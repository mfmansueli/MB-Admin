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

    /// - Parameter rounds: quantas vezes a lista inteira será percorrida.
    func start(sellerID: Int, rounds: MegaphoneRounds = .once) {
        guard task == nil else { return }
        items = []
        currentItemID = nil
        round = 0
        self.rounds = rounds
        pauseReason = nil
        totalSucceeded = 0
        totalFailed = 0
        phase = .loadingProducts(loaded: 0, total: 0)
        task = Task { [weak self] in
            await self?.run(sellerID: sellerID)
            self?.task = nil
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
            let products = try await loadAllProducts(sellerID: sellerID)
            guard !products.isEmpty else {
                phase = .finished
                return
            }
            items = products.map { MegaphoneItem(product: $0) }

            var token = try await client.csrfToken()
            var currentRound = 1
            while rounds.includes(round: currentRound) {
                round = currentRound
                if currentRound > 1 { resetItemsForNewRound() }
                phase = .megaphoning(round: currentRound, of: rounds)
                token = try await megaphoneAll(token: token)
                currentRound += 1
            }
            phase = .finished
        } catch is CancellationError {
            stopInFlight()
            phase = .cancelled
        } catch Stop.tooManyFailures(let message) {
            stopInFlight()
            phase = .failed(message)
        } catch {
            stopInFlight()
            phase = .failed(error.localizedDescription)
        }
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

    /// Megafona a fila inteira uma vez. Devolve o token em uso ao final — ele pode ter sido
    /// renovado no caminho.
    private func megaphoneAll(token: String) async throws -> String {
        var token = token
        var consecutiveFailures = 0

        for index in items.indices {
            await waitWhilePaused()
            try Task.checkCancellation()
            items[index].status = .megaphoning
            currentItemID = items[index].id

            do {
                token = try await megaphone(productID: items[index].id, token: token)
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
    /// token — ele roda junto com a sessão.
    private func megaphone(productID: Int, token: String) async throws -> String {
        do {
            try await client.megaphone(productID: productID, csrfToken: token)
            return token
        } catch let error as EnjoeiError where error.isCSRFRejection {
            let refreshed = try await client.csrfToken()
            try await client.megaphone(productID: productID, csrfToken: refreshed)
            return refreshed
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
