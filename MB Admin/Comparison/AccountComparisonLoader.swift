import Foundation
import Observation

/// Conduz a comparação entre duas lojas, em duas etapas pra não pedir template à toa:
///
/// 1. Busca a listagem das duas lojas (rota pública, em paralelo, sem passar pelo megafone) e
///    analisa as fotos já conhecidas — a capa de cada anúncio, mais as fotos dos templates já salvos
///    — e resolve os pares.
/// 2. Só pros anúncios que a etapa 1 não resolveu (sem par forte) e que não têm template válido
///    salvo, busca o template (todas as fotos, uma chamada por produto, no ritmo do
///    `ProductDetailsLoader`), analisa as fotos novas e resolve de novo com tudo.
///
/// Falha de rede nunca vira lista vazia: a listagem que falhou (ou veio faltando) fica marcada
/// (`StoreListingStatus`) e nada da outra loja é dado como ausente nela. Cancelar deixa a fase em
/// `.interrupted` — nunca em `.finished` — e "continuar" retoma de onde parou (templates e
/// assinaturas já ficaram salvos).
@MainActor
@Observable
final class AccountComparisonLoader {
    enum Phase: Equatable, Sendable {
        case idle
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
    }

    /// O que a última rodada completa usou — pra uma revisão manual recalcular sem rede nenhuma.
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

    var isRunning: Bool { task != nil }

    /// Hora atual — `var` pros testes fixarem.
    var now: () -> Date = { Date() }

    func compare(
        accountA: AccountSession,
        accountB: AccountSession,
        services: ComparisonServices,
        matchMemory: ComparisonMatchMemory? = nil
    ) {
        guard task == nil else { return }
        cachedListings = nil
        session = Session(accountA: accountA, accountB: accountB, services: services, matchMemory: matchMemory)
        start(reusingListings: false)
    }

    /// Para no meio — a fase vai pra `.interrupted`, nunca pra `.finished`.
    func cancel() {
        task?.cancel()
    }

    /// Continua uma comparação interrompida, sem buscar a listagem de novo.
    func resume() {
        guard task == nil, session != nil else { return }
        start(reusingListings: true)
    }

    /// Roda tudo de novo (listagem incluída) — o "tentar de novo" de uma comparação com problemas.
    func retry() {
        guard task == nil, session != nil else { return }
        cachedListings = nil
        start(reusingListings: false)
    }

    /// Volta pra escolha das contas. Sem efeito com uma comparação em andamento.
    func reset() {
        guard task == nil else { return }
        phase = .idle
        session = nil
        lastInputs = nil
        cachedListings = nil
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

    private func reresolve() async {
        guard let session, var inputs = lastInputs, task == nil else { return }
        inputs.revision += 1
        lastInputs = inputs
        let decisions = session.services.decisions.decisions(
            betweenSeller: inputs.sideA.sellerID, andSeller: inputs.sideB.sellerID
        )
        let result = await AccountProductMatcher.resolveOffMain(
            inputs.sideA, inputs.sideB,
            evidence: inputs.evidence, decisions: decisions,
            runID: inputs.runID, revision: inputs.revision
        )
        // Outra rodada pode ter começado enquanto recalculava.
        guard lastInputs?.revision == inputs.revision, task == nil else { return }
        session.matchMemory?.record(result, accountA: session.accountA.id, accountB: session.accountB.id)
        phase = .finished(result)
    }

    // MARK: - Rodada

    private func start(reusingListings: Bool) {
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
            await self?.run(session, reusingListings: reusingListings)
            self?.task = nil
        }
    }

    private func run(_ session: Session, reusingListings: Bool) async {
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

        // Etapa 2: template só de quem ainda não tem par forte nem template válido.
        let currentDate = now()
        let pendingA = Self.pending(listings.a.products, details: detailsA, sellerID: accountA.user.id, resolved: outcome.matchedKeys, now: currentDate)
        let pendingB = Self.pending(listings.b.products, details: detailsB, sellerID: accountB.user.id, resolved: outcome.matchedKeys, now: currentDate)
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
        cachedListings = nil
        session.matchMemory?.record(outcome.result, accountA: accountA.id, accountB: accountB.id)
        phase = .finished(outcome.result)
    }

    private func interrupt() {
        phase = .interrupted
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
        let sideA = Self.side(session.accountA, listings.a, detailsA, failures.storeA, photos)
        let sideB = Self.side(session.accountB, listings.b, detailsB, failures.storeB, photos)
        let decisions = session.services.decisions.decisions(betweenSeller: sideA.sellerID, andSeller: sideB.sellerID)
        let evidence = await AccountProductMatcher.buildEvidenceOffMain(sideA, sideB)
        let result = await AccountProductMatcher.resolveOffMain(
            sideA, sideB, evidence: evidence, decisions: decisions, runID: runID, revision: 0
        )
        let matchedKeys = Set(result.matches.flatMap { [$0.keyA, $0.keyB] })
        return Outcome(
            inputs: ResolvedInputs(sideA: sideA, sideB: sideB, evidence: evidence, runID: runID, revision: 0),
            result: result,
            matchedKeys: matchedKeys
        )
    }

    private static func side(
        _ account: AccountSession,
        _ listing: StoreListing,
        _ details: [Int: ProductListingDetails],
        _ failures: [Int: String],
        _ photos: PhotoAnalysisBatch
    ) -> ComparisonSide {
        ComparisonSide(
            sellerID: account.user.id,
            name: account.user.name,
            listings: listing.products.map { product in
                ComparableListing(
                    sellerID: account.user.id,
                    product: product,
                    details: details[product.id],
                    detailsFailure: failures[product.id],
                    signatures: photos.signatures,
                    failures: photos.failures
                )
            },
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
        async let listingA = loadListing(sellerID: session.accountA.user.id, client: session.accountA.client) { [weak self] loaded, total in
            self?.loadedA = loaded
            self?.totalA = total
            self?.updateLoadingPhase()
        }
        async let listingB = loadListing(sellerID: session.accountB.user.id, client: session.accountB.client) { [weak self] loaded, total in
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

    /// Busca sempre fresco (nunca reaproveita `runner.items`, que pode estar desatualizado) e sem
    /// consultar exposição — a comparação não usa. Uma página que falha encerra a listagem como
    /// `.failed` com o que veio até ali; menos produtos que o `total` informado vira `.incomplete`.
    private func loadListing(
        sellerID: Int,
        client: EnjoeiClientProtocol,
        onProgress: @MainActor (_ loaded: Int, _ total: Int) -> Void
    ) async -> StoreListing {
        var products: [EnjoeiProduct] = []
        var seenIDs: Set<Int> = []
        var cursor: String?
        var expected = 0

        while true {
            if Task.isCancelled { return StoreListing(products: products, status: .failed(loaded: products.count, message: "cancelado")) }
            let page: StoreProductsPage
            do {
                page = try await client.storeProductsPage(sellerID: sellerID, after: cursor)
            } catch {
                return StoreListing(products: products, status: .failed(loaded: products.count, message: Self.describe(error)))
            }
            let newProducts = page.products.filter { seenIDs.insert($0.id).inserted }
            products.append(contentsOf: newProducts)
            expected = max(expected, page.total)
            onProgress(products.count, max(expected, products.count))

            // Sem cursor novo, sem produto inédito, ou cursor repetido: acabou a loja.
            guard let endCursor = page.endCursor, !newProducts.isEmpty, endCursor != cursor else { break }
            cursor = endCursor
        }
        let shortfall = expected - products.count
        let status: StoreListingStatus = shortfall > PhotoMatchingParameters.listingShortfallTolerance
            ? .incomplete(loaded: products.count, expected: expected)
            : .complete
        return StoreListing(products: products, status: status)
    }

    private static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
