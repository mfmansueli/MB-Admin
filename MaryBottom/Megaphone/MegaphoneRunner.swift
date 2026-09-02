import Foundation
import Observation

/// Conduz o megafone: lista todos os produtos da loja e passa por eles quantas rodadas o usuário
/// pedir, publicando o andamento para a tela.
@MainActor
@Observable
final class MegaphoneRunner {
    private(set) var phase: MegaphonePhase = .idle
    private(set) var items: [MegaphoneItem] = []
    /// Produto sendo megafonado agora — a lista rola até ele.
    private(set) var currentItemID: Int?
    /// Rodada em andamento e quantas foram pedidas.
    private(set) var round = 0
    private(set) var rounds: MegaphoneRounds = .once
    /// Por que está parado, quando está. Uma pausa do usuário não é desfeita pela volta do app.
    private(set) var pauseReason: MegaphonePauseReason?
    /// Somatórios de todas as rodadas (os status em `items` valem só para a rodada atual).
    private(set) var totalSucceeded = 0
    private(set) var totalFailed = 0
    /// Andamento de apagar cada produto, por id — separado de `items[].status` de propósito:
    /// apagar não é megafonar, e reaproveitar o mesmo campo faria o laço automático pular um
    /// produto só porque ele está sendo apagado.
    private(set) var deleteStatuses: [Int: MegaphoneStatus] = [:]
    /// Já conferiu a exposição da lista atual — sem isso, reabrir o filtro "pede desconto" chamaria
    /// a rota de novo a cada toque.
    private(set) var hasCheckedExposures = false

    /// Intervalo entre um megafone e o próximo, para não martelar o Enjoei.
    var delayBetweenProducts: Duration = .milliseconds(900)
    /// Quantos ids pedir por chamada ao endpoint de exposição — o Enjoei aceita vários de uma vez,
    /// mas evitamos mandar a loja inteira numa URL só.
    var exposureBatchSize = 80

    /// Chamado ao fim de uma rodada (concluída, cancelada ou interrompida por falha), para quem
    /// guarda o resumo entre execuções — a tela só observa `phase`, que reseta a cada novo `start`.
    var onRoundFinished: ((MegaphoneRoundSummary) -> Void)?
    /// Chamado quando a sessão do Enjoei caiu no meio da rodada, para sinalizar a conta como
    /// precisando logar de novo sem depender de a tela estar aberta observando `phase`.
    var onSessionExpired: (() -> Void)?

    private let client: EnjoeiClientProtocol
    private let accountID: EnjoeiAccountID
    private let itemsPersistence: MegaphoneItemsPersisting
    private var task: Task<Void, Never>?
    private var pauseGate: CheckedContinuation<Void, Never>?

    /// - Parameter itemsPersistence: em memória por padrão, pra um runner criado sem pensar em
    ///   disco (testes, previews) nunca escrever em `UserDefaults` por acidente — a produção passa
    ///   `UserDefaultsMegaphoneItemsPersistence` explicitamente.
    init(
        client: EnjoeiClientProtocol,
        accountID: EnjoeiAccountID = UUID(),
        itemsPersistence: MegaphoneItemsPersisting = InMemoryMegaphoneItemsPersistence()
    ) {
        self.client = client
        self.accountID = accountID
        self.itemsPersistence = itemsPersistence
        items = itemsPersistence.loadItems(accountID: accountID)
    }

    var isRunning: Bool { task != nil }
    var isPaused: Bool { pauseReason != nil }
    var succeededCount: Int { items.filter { $0.status == .succeeded }.count }
    var failedCount: Int { items.filter { $0.status.failureMessage != nil }.count }
    var processedCount: Int { items.filter { $0.status.isFinished }.count }

    /// Começa a megafonar. Reaproveita os produtos já carregados (por `load` ou por uma rodada
    /// anterior) quando a lista não está vazia — só busca a loja de novo quando não tem nada
    /// carregado ainda. Use `reload` pra forçar uma busca nova mesmo com lista carregada.
    ///
    /// - Parameter rounds: quantas vezes a lista inteira será percorrida.
    func start(sellerID: Int, rounds: MegaphoneRounds = .once) {
        guard task == nil else { return }
        currentItemID = nil
        round = 0
        self.rounds = rounds
        pauseReason = nil
        // Reaproveitando a lista, os somatórios partem do que ela já mostra (ex.: desconto
        // aplicado na mão antes de tocar em megafonar) em vez de zerar e subcontar.
        totalSucceeded = items.filter { $0.status == .succeeded }.count
        totalFailed = items.filter { $0.status.failureMessage != nil }.count
        if items.isEmpty { phase = .loadingProducts(loaded: 0, total: 0) }
        task = Task { [weak self] in
            await self?.run(sellerID: sellerID)
            self?.task = nil
        }
    }

    /// Descarta a lista carregada e busca a loja de novo do zero antes de megafonar — pro botão de
    /// recarregar, quando o usuário quer garantir que está vendo o catálogo atual.
    func reload(sellerID: Int, rounds: MegaphoneRounds = .once) {
        guard task == nil else { return }
        items = []
        // Descartada aqui mesmo, sem esperar a busca nova: se o app fechar no meio do reload, a
        // próxima abertura não deve voltar a mostrar a lista antiga como se nada tivesse pedido.
        itemsPersistence.clearItems(accountID: accountID)
        start(sellerID: sellerID, rounds: rounds)
    }

    /// Guarda a lista recém-carregada (só produtos — exposição vem depois, sob demanda) tanto na
    /// tela quanto em disco, pra não precisar buscar a loja de novo na próxima abertura do app.
    private func setLoadedItems(_ items: [MegaphoneItem]) {
        self.items = items
        // Lista nova: qualquer exposição conferida antes era pra outros produtos.
        hasCheckedExposures = false
        itemsPersistence.saveItems(items, accountID: accountID)
    }

    /// Só carrega os produtos da loja — não confere exposição nem começa a megafonar. Serve pra
    /// popular a lista sozinho ao abrir a tela, sem disparar boost nenhum sem o usuário pedir
    /// (isso continua exigindo o toque em "megafonar", que sempre busca tudo de novo).
    func load(sellerID: Int) {
        guard task == nil else { return }
        task = Task { [weak self] in
            await self?.loadOnly(sellerID: sellerID)
            self?.task = nil
        }
    }

    private func loadOnly(sellerID: Int) async {
        phase = .loadingProducts(loaded: 0, total: 0)
        do {
            let products = try await loadAllProducts(sellerID: sellerID)
            guard !products.isEmpty else {
                phase = .idle
                return
            }
            setLoadedItems(products.map { MegaphoneItem(product: $0) })
            phase = .idle
        } catch {
            // Falha ou cancelamento na busca automática não vira alarme — o usuário ainda pode
            // tocar em "megafonar" pra tentar de propósito e ver o erro de verdade.
            phase = .idle
        }
    }

    /// Confere quais produtos já carregados pedem decisão de desconto — só quando o filtro "pede
    /// desconto" é aberto pela primeira vez. Antes disso, carregar a lista não passa por essa rota
    /// (WebView, em lotes) — ela é bem mais lenta que a busca dos produtos em si, e a maior parte
    /// das aberturas de tela nem chega a usar o filtro.
    func checkExposuresIfNeeded() {
        guard !items.isEmpty, !hasCheckedExposures, task == nil else { return }
        task = Task { [weak self] in
            await self?.checkExposures()
            self?.task = nil
        }
    }

    private func checkExposures() async {
        phase = .checkingExposure(checked: 0, total: items.count)
        do {
            let exposures = try await loadExposures(productIDs: items.map(\.id))
            for index in items.indices {
                items[index].exposure = exposures[items[index].id]
            }
            hasCheckedExposures = true
            itemsPersistence.saveItems(items, accountID: accountID)
        } catch {
            // Falha aqui não é fatal — o filtro fica vazio e o usuário pode tentar de novo.
        }
        phase = .idle
    }

    func cancel() {
        pauseReason = nil
        openPauseGate()
        task?.cancel()
    }

    /// Pausa pedida pelo usuário. Só o botão continuar desfaz.
    func pause() {
        pause(reason: .user)
    }

    /// Retomada pedida pelo usuário — vale inclusive para uma pausa feita pelo segundo plano.
    func resume() {
        resume(ifPausedBy: nil)
    }

    /// O app saiu de vista: o iOS suspende a WebView de onde as chamadas saem, então paramos no
    /// lugar em vez de acumular erro.
    func pauseForBackground() {
        pause(reason: .background)
    }

    /// O app voltou. Se a pausa foi do usuário, ela continua de pé.
    func resumeFromBackground() {
        resume(ifPausedBy: .background)
    }

    private func pause(reason: MegaphonePauseReason) {
        guard isRunning, pauseReason == nil else { return }
        pauseReason = reason
        if case .megaphoning(let round, let rounds) = phase {
            phase = .paused(round: round, of: rounds, reason: reason)
        }
    }

    private func resume(ifPausedBy reason: MegaphonePauseReason?) {
        guard let currentReason = pauseReason else { return }
        guard reason == nil || reason == currentReason else { return }
        pauseReason = nil
        if case .paused(let round, let rounds, _) = phase {
            phase = .megaphoning(round: round, of: rounds)
        }
        openPauseGate()
    }

    /// Espera a rodada terminar. Serve aos testes; a tela só observa `phase`.
    func waitUntilFinished() async {
        await task?.value
    }

    private func run(sellerID: Int) async {
        do {
            if items.isEmpty {
                let products = try await loadAllProducts(sellerID: sellerID)
                guard !products.isEmpty else {
                    finish(.finished)
                    return
                }
                setLoadedItems(products.map { MegaphoneItem(product: $0) })
            }

            var token = try await client.csrfToken()
            var currentRound = 1
            while rounds.includes(round: currentRound) {
                round = currentRound
                if currentRound > 1 { resetItemsForNewRound() }
                phase = .megaphoning(round: currentRound, of: rounds)
                token = try await megaphoneAll(token: token)
                currentRound += 1
            }
            finish(.finished)
        } catch is CancellationError {
            stopInFlight()
            finish(.cancelled)
        } catch {
            stopInFlight()
            if case EnjoeiError.notAuthenticated = error {
                onSessionExpired?()
            }
            finish(.failed(error.localizedDescription))
        }
    }

    private func finish(_ phase: MegaphonePhase) {
        self.phase = phase
        onRoundFinished?(
            MegaphoneRoundSummary(succeeded: totalSucceeded, failed: totalFailed, finishedAt: .now)
        )
    }

    private func loadAllProducts(sellerID: Int) async throws -> [EnjoeiProduct] {
        var products: [EnjoeiProduct] = []
        var seenIDs: Set<Int> = []
        var cursor: String?

        while true {
            try Task.checkCancellation()
            let page = try await client.storeProductsPage(sellerID: sellerID, after: cursor)
            let newProducts = page.products.filter { seenIDs.insert($0.id).inserted }
            products.append(contentsOf: newProducts)
            phase = .loadingProducts(loaded: products.count, total: max(page.total, products.count))

            // Sem cursor novo, sem produto inédito, ou cursor repetido: acabou a loja.
            guard let endCursor = page.endCursor, !newProducts.isEmpty, endCursor != cursor else {
                return products
            }
            cursor = endCursor
        }
    }

    private func loadExposures(productIDs: [Int]) async throws -> [Int: MegaphoneExposure] {
        var exposuresByProductID: [Int: MegaphoneExposure] = [:]
        var checked = 0

        for batch in chunks(of: productIDs, size: exposureBatchSize) {
            try Task.checkCancellation()
            let exposures = try await client.megaphoneExposures(productIDs: batch)
            for exposure in exposures { exposuresByProductID[exposure.productID] = exposure }
            checked += batch.count
            phase = .checkingExposure(checked: checked, total: productIDs.count)
        }
        return exposuresByProductID
    }

    private func chunks(of ids: [Int], size: Int) -> [[Int]] {
        stride(from: 0, to: ids.count, by: size).map {
            Array(ids[$0..<min($0 + size, ids.count)])
        }
    }

    /// Megafona a fila inteira uma vez. Devolve o token em uso ao final — ele pode ter sido
    /// renovado no caminho. Pula produtos já concluídos ou em andamento por fora — um desconto
    /// aplicado na mão (`applyDiscount`) enquanto a rodada corria não pode ser megafonado de novo
    /// por cima, ou os dois chamariam a rota ao mesmo tempo pro mesmo produto. Erro num produto não
    /// para os demais — só sessão caída (`notAuthenticated`) interrompe a rodada de verdade.
    private func megaphoneAll(token: String) async throws -> String {
        var token = token

        for index in items.indices {
            // A pausa vem antes das checagens de pular: uma decisão tomada enquanto o laço estava
            // parado nesse mesmo item (aplicar desconto manualmente, repostar, apagar) só é vista
            // se a gente reavaliar o item depois de acordar — checar antes de esperar deixaria a
            // decisão passar batido quando ela chega durante a pausa.
            await waitWhilePaused()
            try Task.checkCancellation()
            if items[index].status == .succeeded || items[index].status == .megaphoning { continue }
            if deleteStatuses[items[index].id] == .succeeded { continue }
            items[index].status = .megaphoning
            currentItemID = items[index].id

            do {
                token = try await megaphone(productID: items[index].id, newPrice: nil, token: token)
                items[index].status = .succeeded
                totalSucceeded += 1
            } catch EnjoeiError.notAuthenticated {
                items[index].status = .failed(EnjoeiError.notAuthenticated.localizedDescription)
                totalFailed += 1
                throw EnjoeiError.notAuthenticated
            } catch {
                items[index].status = .failed(error.localizedDescription)
                totalFailed += 1
            }

            // A pausa é entre um produto e o próximo; no fim da rodada não faz sentido esperar.
            if index < items.count - 1, delayBetweenProducts > .zero {
                try await Task.sleep(for: delayBetweenProducts)
            }
        }

        currentItemID = nil
        return token
    }

    /// Megafona um produto, renovando o token CSRF e tentando de novo quando o servidor recusa o
    /// token — ele roda junto com a sessão. `newPrice` aplica o desconto sugerido junto.
    private func megaphone(productID: Int, newPrice: Double?, token: String) async throws -> String {
        do {
            try await client.megaphone(productID: productID, csrfToken: token, newPrice: newPrice)
            return token
        } catch let error as EnjoeiError where error.isCSRFRejection {
            let refreshed = try await client.csrfToken()
            try await client.megaphone(productID: productID, csrfToken: refreshed, newPrice: newPrice)
            return refreshed
        }
    }

    /// Aplica o desconto sugerido pelo megafone num produto específico e o megafona. Funciona
    /// mesmo com a rodada automática rodando — o item marcado `.succeeded` na hora é pulado por
    /// `megaphoneAll` quando o laço chegar nele.
    func applyDiscount(for productID: Int) {
        guard let index = items.firstIndex(where: { $0.id == productID }) else { return }
        guard deleteStatuses[productID] != .succeeded else { return }
        // Pendente ou falhou antes (retry): tudo bem. Já rodando ou já feito: um segundo toque não
        // dispara outra chamada.
        guard items[index].status != .megaphoning, items[index].status != .succeeded else { return }
        let newPrice = items[index].exposure?.priceToIncreaseExposure
        items[index].status = .megaphoning
        Task { [weak self] in
            await self?.performApplyDiscount(productID: productID, newPrice: newPrice)
        }
    }

    private func performApplyDiscount(productID: Int, newPrice: Double?) async {
        do {
            let token = try await client.csrfToken()
            _ = try await megaphone(productID: productID, newPrice: newPrice, token: token)
            setStatus(.succeeded, for: productID)
            totalSucceeded += 1
        } catch {
            setStatus(.failed(error.localizedDescription), for: productID)
            totalFailed += 1
        }
    }

    /// Procura de novo o índice em vez de guardar o de antes do `await`: uma rodada nova
    /// (`start`) recria `items` do zero enquanto isso estava em andamento.
    private func setStatus(_ status: MegaphoneStatus, for productID: Int) {
        guard let index = items.firstIndex(where: { $0.id == productID }) else { return }
        items[index].status = status
    }

    /// Apaga um produto de vez. Ação destrutiva e provavelmente irreversível — a confirmação fica
    /// por conta de quem chama (a tela). O item continua na lista, só marcado como excluído: tirar
    /// ele de `items` na hora derrubaria a linha (e o que estiver mostrando o resultado) da tela.
    func deleteProduct(productID: Int) {
        guard deleteStatuses[productID] != .megaphoning, deleteStatuses[productID] != .succeeded else { return }
        deleteStatuses[productID] = .megaphoning
        Task { [weak self] in
            await self?.performDelete(productID: productID)
        }
    }

    private func performDelete(productID: Int) async {
        do {
            let token = try await client.csrfToken()
            try await deleteProduct(productID: productID, token: token)
            deleteStatuses[productID] = .succeeded
        } catch {
            deleteStatuses[productID] = .failed(error.localizedDescription)
        }
    }

    /// Apaga o produto, renovando o token CSRF e tentando de novo quando o servidor recusa o token
    /// — mesmo laço do `megaphone`.
    private func deleteProduct(productID: Int, token: String) async throws {
        do {
            try await client.deleteProduct(productID: productID, csrfToken: token)
        } catch let error as EnjoeiError where error.isCSRFRejection {
            let refreshed = try await client.csrfToken()
            try await client.deleteProduct(productID: productID, csrfToken: refreshed)
        }
    }

    /// Segura o laço enquanto o app está em segundo plano.
    private func waitWhilePaused() async {
        while pauseReason != nil, !Task.isCancelled {
            await withCheckedContinuation { continuation in
                pauseGate = continuation
            }
        }
    }

    private func openPauseGate() {
        pauseGate?.resume()
        pauseGate = nil
    }

    /// Zera os status para a rodada seguinte, preservando os somatórios.
    private func resetItemsForNewRound() {
        for index in items.indices {
            items[index].status = .pending
        }
    }

    /// Devolve para a fila o produto que estava em andamento quando a rodada parou.
    private func stopInFlight() {
        for index in items.indices where items[index].status == .megaphoning {
            items[index].status = .pending
        }
        currentItemID = nil
    }
}
