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

    /// Intervalo entre um megafone e o próximo, para não martelar o Enjoei.
    var delayBetweenProducts: Duration = .milliseconds(900)
    /// Depois desta quantidade de falhas seguidas paramos: sinal de bloqueio ou cota estourada.
    var maxConsecutiveFailures = 5
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
    private var task: Task<Void, Never>?
    private var pauseGate: CheckedContinuation<Void, Never>?

    /// Interrupção decidida pelo próprio runner, para o `run` saber que a rodada não terminou bem.
    private enum Stop: Error {
        case tooManyFailures(String)
    }

    init(client: EnjoeiClientProtocol) {
        self.client = client
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
        start(sellerID: sellerID, rounds: rounds)
    }

    /// Só carrega os produtos da loja e confere a exposição — não começa a megafonar. Serve pra
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
            phase = .checkingExposure(checked: 0, total: products.count)
            let exposures = try await loadExposures(productIDs: products.map(\.id))
            items = products.map { MegaphoneItem(product: $0, exposure: exposures[$0.id]) }
            phase = .idle
        } catch {
            // Falha ou cancelamento na busca automática não vira alarme — o usuário ainda pode
            // tocar em "megafonar" pra tentar de propósito e ver o erro de verdade.
            phase = .idle
        }
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
                phase = .checkingExposure(checked: 0, total: products.count)
                let exposures = try await loadExposures(productIDs: products.map(\.id))
                items = products.map { MegaphoneItem(product: $0, exposure: exposures[$0.id]) }
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
        } catch Stop.tooManyFailures(let message) {
            stopInFlight()
            finish(.failed(message))
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
    /// por cima, ou os dois chamariam a rota ao mesmo tempo pro mesmo produto.
    private func megaphoneAll(token: String) async throws -> String {
        var token = token
        var consecutiveFailures = 0

        for index in items.indices {
            if items[index].status == .succeeded || items[index].status == .megaphoning { continue }
            await waitWhilePaused()
            try Task.checkCancellation()
            items[index].status = .megaphoning
            currentItemID = items[index].id

            do {
                token = try await megaphone(productID: items[index].id, newPrice: nil, token: token)
                items[index].status = .succeeded
                totalSucceeded += 1
                consecutiveFailures = 0
            } catch EnjoeiError.notAuthenticated {
                items[index].status = .failed(EnjoeiError.notAuthenticated.localizedDescription)
                totalFailed += 1
                throw EnjoeiError.notAuthenticated
            } catch {
                items[index].status = .failed(error.localizedDescription)
                totalFailed += 1
                consecutiveFailures += 1
                if consecutiveFailures >= maxConsecutiveFailures {
                    throw Stop.tooManyFailures(
                        "parei depois de \(consecutiveFailures) erros seguidos: \(error.localizedDescription)"
                    )
                }
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
