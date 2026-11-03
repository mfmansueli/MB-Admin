import Foundation
import Observation

/// Conduz a comparação entre duas lojas, em duas etapas pra não pedir template à toa:
///
/// 1. Busca a listagem das duas lojas (rota pública, em paralelo, sem passar pelo megafone) e
///    analisa as fotos já conhecidas — a capa de cada anúncio, mais as fotos dos templates já salvos
///    — e resolve os pares.
/// 2. Só pros anúncios que a etapa 1 não resolveu (sem par forte) — mais os que têm par mas são de
///    uma família de versões (a mesma foto em vários anúncios, `keysWantingDetails`), pra conferir a
///    versão pela descrição/tamanho/marca, e os repetidos dentro de uma loja ainda sem template — e
///    que não têm template válido salvo, busca o template (todas as fotos, descrição, tamanho, marca;
///    uma chamada por produto, no ritmo do `ProductDetailsLoader`), analisa as fotos novas e resolve
///    de novo com tudo. Com `checkAllDetails`, busca o de todo anúncio (pares 1:1 com a mesma foto
///    inclusive).
///
/// Falha de rede nunca vira lista vazia: a listagem que falhou (ou veio faltando) fica marcada
/// (`StoreListingStatus`) e nada da outra loja é dado como ausente nela. Cancelar deixa a fase em
/// `.interrupted` — nunca em `.finished` — e "continuar" retoma de onde parou (templates e
/// assinaturas já ficaram salvos).
///
/// **O resultado fica.** Um só por app (`AccountsStore.comparisonLoader`), então fechar a tela não
/// perde nada (uma comparação em andamento continua por trás). A última comparação terminada também
/// vai pro disco (`ComparisonSnapshot`): reabrir o app refaz o mesmo resultado sem rede. Só começar
/// outra comparação descarta a anterior — "nova comparação" volta pra escolha das contas, mas o
/// resultado anterior continua a um toque ("ver o último resultado") e volta sozinho ao reabrir a tela.
@MainActor
@Observable
final class AccountComparisonLoader {
    enum Phase: Equatable, Sendable {
        case idle
        /// Refazendo a última comparação salva — sem rede, com as fotos e os templates do cache.
        case restoring
        /// Soma das duas lojas — cada uma informa seu próprio `loaded`/`total` conforme pagina.
        case loadingProducts(loaded: Int, total: Int)
        case analyzingPhotos(done: Int, total: Int)
        /// As duas lojas buscam templates ao mesmo tempo; cada `AccountSession.productDetailsLoader`
        /// tem seu próprio `phase`, que a tela lê direto pra mostrar o progresso de cada uma.
        case fetchingDetails
        case matching
        /// Cancelada antes de terminar — não há resultado. `resume()` continua.
        case interrupted
        case finished(AccountComparisonResult)
    }

    private(set) var phase: Phase = .idle
    /// As contas escolhidas na tela — moram aqui, não na tela, pra fechar e abrir de novo manter a
    /// escolha (e a da última comparação, quando ela é reaberta do disco).
    var accountAID: EnjoeiAccountID?
    var accountBID: EnjoeiAccountID?
    /// A última comparação terminada (com as revisões manuais) — continua valendo depois de "nova
    /// comparação", até outra comparação começar.
    private(set) var lastResult: AccountComparisonResult?
    private var task: Task<Void, Never>?

    private var loadedA = 0
    private var totalA = 0
    private var loadedB = 0
    private var totalB = 0
    private var photosDone = 0

    private struct Session {
        let accountA: AccountSession
        let accountB: AccountSession
        let services: ComparisonServices
        let matchMemory: ComparisonMatchMemory?
        let checkAllDetails: Bool

        func involves(_ accountID: EnjoeiAccountID) -> Bool {
            accountA.id == accountID || accountB.id == accountID
        }
    }

    /// O que a última rodada completa usou — pra uma revisão manual recalcular sem rede nenhuma.
    /// Pode ser solto (`releaseMemory`): é refeito do `ComparisonSnapshot` na próxima revisão.
    private struct ResolvedInputs {
        let sideA: ComparisonSide
        let sideB: ComparisonSide
        let evidence: ComparisonEvidenceBuilder.Output
        let runID: UUID
        var revision: Int
    }

    private var session: Session?
    private var lastInputs: ResolvedInputs?
    /// Listagem da rodada interrompida — `resume()` não pagina a loja de novo.
    private var cachedListings: (a: StoreListing, b: StoreListing)?
    private let snapshots: ComparisonSnapshotStoring

    var isRunning: Bool { task != nil }
    /// Há uma comparação anterior pra voltar ("ver o último resultado").
    var hasLastResult: Bool { lastResult != nil || snapshots.hasSnapshot }

    /// Hora atual — `var` pros testes fixarem.
    var now: () -> Date = { Date() }

    init(snapshots: ComparisonSnapshotStoring = InMemoryComparisonSnapshotStore()) {
        self.snapshots = snapshots
    }

    func compare(
        accountA: AccountSession,
        accountB: AccountSession,
        services: ComparisonServices,
        matchMemory: ComparisonMatchMemory? = nil,
        checkAllDetails: Bool = false
    ) {
        guard task == nil else { return }
        cachedListings = nil
        // Começar outra comparação é o que descarta a anterior (o arquivo é apagado no começo da
        // rodada, antes de qualquer gravação nova).
        lastResult = nil
        lastInputs = nil
        accountAID = accountA.id
        accountBID = accountB.id
        session = Session(
            accountA: accountA, accountB: accountB, services: services, matchMemory: matchMemory, checkAllDetails: checkAllDetails
        )
        start(reusingListings: false, discardingSnapshot: true)
    }

    /// Para no meio — a fase vai pra `.interrupted`, nunca pra `.finished`.
    func cancel() {
        task?.cancel()
    }

    /// Continua uma comparação interrompida, sem buscar a listagem de novo.
    func resume() {
        guard task == nil, session != nil else { return }
        start(reusingListings: true, discardingSnapshot: false)
    }

    /// Roda tudo de novo (listagem incluída) — o "tentar de novo" de uma comparação com problemas.
    func retry() {
        guard task == nil, session != nil else { return }
        cachedListings = nil
        lastResult = nil
        lastInputs = nil
        start(reusingListings: false, discardingSnapshot: true)
    }

    /// Volta pra escolha das contas, sem descartar o resultado — `showLastComparison` volta pra ele.
    /// Sem efeito com uma comparação em andamento.
    func reset() {
        guard task == nil else { return }
        phase = .idle
        cachedListings = nil
    }

    /// Mostra a última comparação: na hora, se ela ainda está na memória; senão, refeita do disco
    /// (`ComparisonSnapshot` + caches de fotos e templates, sem rede), se as duas contas dela ainda
    /// estão logadas. Só sai da escolha das contas (`.idle`) — nunca interrompe nada.
    /// - Parameter services: só chamado se for preciso refazer do disco.
    func showLastComparison(
        accounts: [AccountSession],
        services: () -> ComparisonServices,
        matchMemory: ComparisonMatchMemory? = nil
    ) {
        guard task == nil, phase == .idle else { return }
        if let lastResult, let session {
            accountAID = session.accountA.id
            accountBID = session.accountB.id
            phase = .finished(lastResult)
            return
        }
        guard snapshots.hasSnapshot else { return }
        phase = .restoring
        let services = services()
        task = Task { [weak self] in
            await self?.restore(accounts: accounts, services: services, matchMemory: matchMemory)
            self?.task = nil
        }
    }

    /// Solta o que só serve pra recalcular depois de uma revisão manual (a evidência inteira) — o
    /// resultado continua na tela, e a próxima revisão refaz a evidência do disco. Sem efeito no meio
    /// de uma comparação, ou sem comparação salva pra refazer.
    func releaseMemory() {
        guard task == nil, snapshots.hasSnapshot else { return }
        lastInputs = nil
    }

    /// Esquece a comparação que envolve a conta (ela saiu do app): para a que estiver rodando e
    /// apaga a salva.
    func forget(accountID: EnjoeiAccountID) async {
        if session?.involves(accountID) == true {
            task?.cancel()
            await task?.value
            session = nil
            lastResult = nil
            lastInputs = nil
            cachedListings = nil
            phase = .idle
        }
        if accountAID == accountID { accountAID = nil }
        if accountBID == accountID { accountBID = nil }
        if snapshots.hasSnapshot, await snapshots.load()?.involves(accountID) != false {
            await snapshots.delete()
        }
    }

    /// Serve aos testes; a tela só observa `phase`.
    func waitUntilFinished() async {
        await task?.value
    }

    // MARK: - Revisão manual

    /// Grava "mesmo produto"/"produtos diferentes" pro par e recalcula o resultado na hora, com as
    /// mesmas fotos e listas (sem rede).
    func decide(_ verdict: ComparisonDecision.Verdict, for match: ProductMatch) async {
        guard let session else { return }
        session.services.decisions.save(ComparisonDecision(
            (match.keyA, ListingFingerprint(product: match.productA)),
            (match.keyB, ListingFingerprint(product: match.productB)),
            verdict: verdict,
            decidedAt: now()
        ))
        await reresolve()
    }

    /// Desfaz a revisão do par — volta pra avaliação automática.
    func undoDecision(for match: ProductMatch) async {
        guard let session else { return }
        session.services.decisions.removeDecision(for: match.pairKey)
        await reresolve()
    }

    /// "São repetidos" (`.sameProduct`) / "não são repetidos" (`.differentProducts`) pra todos os pares
    /// do grupo de anúncios da mesma loja.
    func decideDuplicate(_ verdict: ComparisonDecision.Verdict, for group: StoreDuplicateGroup) async {
        guard let session else { return }
        for pair in group.pairKeys {
            guard let first = group.product(for: pair.first), let second = group.product(for: pair.second) else { continue }
            session.services.decisions.save(ComparisonDecision(
                (pair.first, ListingFingerprint(product: first)),
                (pair.second, ListingFingerprint(product: second)),
                verdict: verdict,
                decidedAt: now()
            ))
        }
        await reresolve()
    }

    /// Desfaz a revisão dos pares do grupo — voltam pra avaliação automática.
    func undoDuplicateDecision(for group: StoreDuplicateGroup) async {
        guard let session else { return }
        for pair in group.pairKeys {
            session.services.decisions.removeDecision(for: pair)
        }
        await reresolve()
    }

    private func reresolve() async {
        guard let session, task == nil else { return }
        if lastInputs == nil, let lastResult {
            // Solto por memória: refaz do disco, com a mesma rodada.
            guard let snapshot = await snapshots.load(), snapshot.runID == lastResult.id,
                  var inputs = await rebuildInputs(snapshot, session: session) else { return }
            inputs.revision = lastResult.revision
            if lastInputs == nil { lastInputs = inputs }
        }
        guard var inputs = lastInputs else { return }
        inputs.revision += 1
        lastInputs = inputs
        let result = await AccountProductMatcher.resolveOffMain(
            inputs.sideA, inputs.sideB,
            evidence: inputs.evidence, decisions: Self.decisions(session, inputs.sideA, inputs.sideB),
            runID: inputs.runID, revision: inputs.revision
        )
        // Outra rodada pode ter começado enquanto recalculava.
        guard lastInputs?.revision == inputs.revision, task == nil else { return }
        session.matchMemory?.record(result, accountA: session.accountA.id, accountB: session.accountB.id)
        lastResult = result
        phase = .finished(result)
    }

    /// As revisões entre as duas lojas e as de dentro de cada loja (repetidos), uma por par.
    private static func decisions(_ session: Session, _ sideA: ComparisonSide, _ sideB: ComparisonSide) -> [ComparisonDecision] {
        let store = session.services.decisions
        var byPair: [ListingPairKey: ComparisonDecision] = [:]
        let all = store.decisions(betweenSeller: sideA.sellerID, andSeller: sideB.sellerID)
            + store.decisions(betweenSeller: sideA.sellerID, andSeller: sideA.sellerID)
            + store.decisions(betweenSeller: sideB.sellerID, andSeller: sideB.sellerID)
        for decision in all { byPair[decision.pairKey] = decision }
        return byPair.values.sorted { $0.pairKey.storageID < $1.pairKey.storageID }
    }

    // MARK: - Rodada

    private func start(reusingListings: Bool, discardingSnapshot: Bool) {
        guard let session else { return }
        loadedA = 0
        totalA = 0
        loadedB = 0
        totalB = 0
        photosDone = 0
        // Sai de `.idle`/`.interrupted` na hora — a tela não pode ficar mostrando a escolha das
        // contas (ou o "continuar") até a tarefa começar a rodar.
        phase = .loadingProducts(loaded: 0, total: 0)
        task = Task { [weak self] in
            if discardingSnapshot { await self?.snapshots.delete() }
            let snapshot = await self?.run(session, reusingListings: reusingListings)
            self?.task = nil
            // Depois de soltar a tarefa: revisar o resultado não espera a gravação. A gravação entra na
            // fila do arquivo antes de qualquer outra comparação conseguir começar (e apagar).
            if let snapshot { await self?.snapshots.save(snapshot) }
        }
    }

    /// A comparação salva, quando terminou (`nil` se interrompida).
    private func run(_ session: Session, reusingListings: Bool) async -> ComparisonSnapshot? {
        guard let listings = await listings(for: session, reusing: reusingListings) else { return interrupt() }
        let accountA = session.accountA
        let accountB = session.accountB

        // Etapa 1: o que já se sabe (capas + templates salvos).
        var detailsA = accountA.productDetailsLoader.storedDetails(for: listings.a.products.map(\.id))
        var detailsB = accountB.productDetailsLoader.storedDetails(for: listings.b.products.map(\.id))
        var photos = await analyzePhotos(
            Self.photoIDs(listings.a.products, detailsA) + Self.photoIDs(listings.b.products, detailsB),
            services: session.services
        )
        guard !photos.wasCancelled, !Task.isCancelled else { return interrupt() }

        let runID = UUID()
        var failures = DetailsFailures()
        var outcome = await resolve(session, listings, detailsA, detailsB, failures, photos, runID)

        // Etapa 2: template de quem ainda não tem par forte (ou tem, mas numa família de versões, ou é
        // repetido na própria loja) e não tem template válido.
        let currentDate = now()
        let settled = session.checkAllDetails ? [] : outcome.matchedKeys.subtracting(outcome.result.keysWantingDetails)
        let pendingA = Self.pending(listings.a.products, details: detailsA, sellerID: accountA.user.id, resolved: settled, now: currentDate)
        let pendingB = Self.pending(listings.b.products, details: detailsB, sellerID: accountB.user.id, resolved: settled, now: currentDate)
        if !pendingA.isEmpty || !pendingB.isEmpty {
            phase = .fetchingDetails
            async let reportA = accountA.productDetailsLoader.fetchDetails(for: pendingA, now: now)
            async let reportB = accountB.productDetailsLoader.fetchDetails(for: pendingB, now: now)
            let (fetchedA, fetchedB) = await (reportA, reportB)
            detailsA.merge(fetchedA.details) { $1 }
            detailsB.merge(fetchedB.details) { $1 }
            failures = DetailsFailures(storeA: fetchedA.failures, storeB: fetchedB.failures)
            guard !fetchedA.wasCancelled, !fetchedB.wasCancelled, !Task.isCancelled else { return interrupt() }

            let known = Set(photos.signatures.keys).union(photos.failures.keys)
            let newIDs = (Self.photoIDs(pendingA, detailsA) + Self.photoIDs(pendingB, detailsB)).filter { !known.contains($0) }
            photos.merge(await analyzePhotos(newIDs, services: session.services))
            guard !photos.wasCancelled, !Task.isCancelled else { return interrupt() }
            outcome = await resolve(session, listings, detailsA, detailsB, failures, photos, runID)
        }

        lastInputs = outcome.inputs
        lastResult = outcome.result
        cachedListings = nil
        session.matchMemory?.record(outcome.result, accountA: accountA.id, accountB: accountB.id)
        phase = .finished(outcome.result)
        return ComparisonSnapshot(
            savedAt: now(),
            runID: runID,
            checkAllDetails: session.checkAllDetails,
            storeA: Self.snapshotStore(accountA, listings.a, failures.storeA),
            storeB: Self.snapshotStore(accountB, listings.b, failures.storeB),
            photoFailures: photos.failures
        )
    }

    private func interrupt() -> ComparisonSnapshot? {
        phase = .interrupted
        return nil
    }

    private struct DetailsFailures {
        var storeA: [Int: String] = [:]
        var storeB: [Int: String] = [:]
    }

    private struct Outcome {
        let inputs: ResolvedInputs
        let result: AccountComparisonResult
        let matchedKeys: Set<ListingKey>
    }

    // swiftlint:disable:next function_parameter_count
    private func resolve(
        _ session: Session,
        _ listings: (a: StoreListing, b: StoreListing),
        _ detailsA: [Int: ProductListingDetails],
        _ detailsB: [Int: ProductListingDetails],
        _ failures: DetailsFailures,
        _ photos: PhotoAnalysisBatch,
        _ runID: UUID
    ) async -> Outcome {
        phase = .matching
        let (sideA, sideB) = await ComparisonSideBuilder.build(
            Self.source(session.accountA, listings.a, detailsA, failures.storeA),
            Self.source(session.accountB, listings.b, detailsB, failures.storeB),
            photos: photos
        )
        let evidence = await AccountProductMatcher.buildEvidenceOffMain(sideA, sideB)
        let result = await AccountProductMatcher.resolveOffMain(
            sideA, sideB, evidence: evidence, decisions: Self.decisions(session, sideA, sideB), runID: runID, revision: 0
        )
        let matchedKeys = Set(result.matches.flatMap { [$0.keyA, $0.keyB] })
        return Outcome(
            inputs: ResolvedInputs(sideA: sideA, sideB: sideB, evidence: evidence, runID: runID, revision: 0),
            result: result,
            matchedKeys: matchedKeys
        )
    }

    private static func source(
        _ account: AccountSession,
        _ listing: StoreListing,
        _ details: [Int: ProductListingDetails],
        _ failures: [Int: String]
    ) -> ComparisonSideBuilder.Source {
        ComparisonSideBuilder.Source(
            sellerID: account.user.id,
            name: account.user.name,
            products: listing.products,
            details: details,
            detailsFailures: failures,
            status: listing.status
        )
    }

    private static func photoIDs(_ products: [EnjoeiProduct], _ details: [Int: ProductListingDetails]) -> [String] {
        products.flatMap { ComparableListing.photoIDs(product: $0, details: details[$0.id]) }
    }

    private static func pending(
        _ products: [EnjoeiProduct],
        details: [Int: ProductListingDetails],
        sellerID: Int,
        resolved: Set<ListingKey>,
        now: Date
    ) -> [EnjoeiProduct] {
        products.filter { product in
            !resolved.contains(ListingKey(sellerID: sellerID, productID: product.id))
                && details[product.id]?.isFresh(for: product, now: now) != true
        }
    }

    // MARK: - Última comparação

    private static func snapshotStore(_ account: AccountSession, _ listing: StoreListing, _ failures: [Int: String]) -> ComparisonSnapshot.Store {
        ComparisonSnapshot.Store(
            accountID: account.id,
            sellerID: account.user.id,
            name: account.user.name,
            status: listing.status,
            products: listing.products,
            detailsFailures: failures
        )
    }

    private func restore(accounts: [AccountSession], services: ComparisonServices, matchMemory: ComparisonMatchMemory?) async {
        guard let snapshot = await snapshots.load(),
              let accountA = accounts.first(where: { $0.id == snapshot.storeA.accountID }),
              let accountB = accounts.first(where: { $0.id == snapshot.storeB.accountID }) else {
            phase = .idle
            return
        }
        let session = Session(
            accountA: accountA, accountB: accountB, services: services, matchMemory: matchMemory, checkAllDetails: snapshot.checkAllDetails
        )
        guard let inputs = await rebuildInputs(snapshot, session: session), !Task.isCancelled else {
            phase = .idle
            return
        }
        let result = await AccountProductMatcher.resolveOffMain(
            inputs.sideA, inputs.sideB,
            evidence: inputs.evidence, decisions: Self.decisions(session, inputs.sideA, inputs.sideB),
            runID: inputs.runID, revision: 0
        )
        self.session = session
        lastInputs = inputs
        lastResult = result
        accountAID = accountA.id
        accountBID = accountB.id
        matchMemory?.record(result, accountA: accountA.id, accountB: accountB.id)
        phase = .finished(result)
    }

    /// Os mesmos lados e a mesma evidência da comparação salva: as listas dela, os templates salvos
    /// de cada conta e as assinaturas do cache de fotos — nada da rede.
    private func rebuildInputs(_ snapshot: ComparisonSnapshot, session: Session) async -> ResolvedInputs? {
        let detailsA = session.accountA.productDetailsLoader.storedDetails(for: snapshot.storeA.products.map(\.id))
        let detailsB = session.accountB.productDetailsLoader.storedDetails(for: snapshot.storeB.products.map(\.id))
        let photoIDs = Self.photoIDs(snapshot.storeA.products, detailsA) + Self.photoIDs(snapshot.storeB.products, detailsB)
        let signatures = await session.services.photoSignatures.cachedSignatures(for: photoIDs)
        let photos = PhotoAnalysisBatch(signatures: signatures, failures: snapshot.photoFailures.filter { signatures[$0.key] == nil })
        let (sideA, sideB) = await ComparisonSideBuilder.build(
            Self.source(snapshot.storeA, detailsA),
            Self.source(snapshot.storeB, detailsB),
            photos: photos
        )
        let evidence = await AccountProductMatcher.buildEvidenceOffMain(sideA, sideB)
        return ResolvedInputs(sideA: sideA, sideB: sideB, evidence: evidence, runID: snapshot.runID, revision: 0)
    }

    private static func source(_ store: ComparisonSnapshot.Store, _ details: [Int: ProductListingDetails]) -> ComparisonSideBuilder.Source {
        ComparisonSideBuilder.Source(
            sellerID: store.sellerID,
            name: store.name,
            products: store.products,
            details: details,
            detailsFailures: store.detailsFailures,
            status: store.status
        )
    }

    // MARK: - Fotos

    private func analyzePhotos(_ publicIDs: [String], services: ComparisonServices) async -> PhotoAnalysisBatch {
        guard !publicIDs.isEmpty else { return PhotoAnalysisBatch() }
        phase = .analyzingPhotos(done: 0, total: 0)
        photosDone = 0
        return await services.photoSignatures.analyze(publicIDs) { [weak self] done, total in
            Task { @MainActor [weak self] in
                guard let self, case .analyzingPhotos = phase, done >= photosDone else { return }
                photosDone = done
                phase = .analyzingPhotos(done: done, total: total)
            }
        }
    }

    // MARK: - Listagem

    /// `nil` só se cancelado — falha de rede vira `StoreListingStatus.failed`, nunca lista vazia.
    private func listings(for session: Session, reusing: Bool) async -> (a: StoreListing, b: StoreListing)? {
        if reusing, let cachedListings { return cachedListings }
        phase = .loadingProducts(loaded: 0, total: 0)
        // As duas contas em paralelo — cada uma tem sua própria WebView/sessão.
        async let listingA = StoreListingFetcher.load(sellerID: session.accountA.user.id, client: session.accountA.client) { [weak self] loaded, total in
            self?.loadedA = loaded
            self?.totalA = total
            self?.updateLoadingPhase()
        }
        async let listingB = StoreListingFetcher.load(sellerID: session.accountB.user.id, client: session.accountB.client) { [weak self] loaded, total in
            self?.loadedB = loaded
            self?.totalB = total
            self?.updateLoadingPhase()
        }
        let result = await (a: listingA, b: listingB)
        guard !Task.isCancelled else { return nil }
        cachedListings = result
        return result
    }

    private func updateLoadingPhase() {
        phase = .loadingProducts(loaded: loadedA + loadedB, total: totalA + totalB)
    }
}
