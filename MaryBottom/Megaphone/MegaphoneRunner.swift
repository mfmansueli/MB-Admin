import Foundation
import Observation

/// Conduz o megafone: lista todos os produtos da loja e passa por eles quantas rodadas o usuário
/// pedir, publicando o andamento para a tela.
@MainActor
@Observable
final class MegaphoneRunner {
    // `internal(set)` em vez de `private(set)` nas propriedades abaixo — sem isso, os métodos
    // movidos pra `MegaphoneRunner+ProductLoading.swift`/`MegaphoneRunner+ProductActions.swift`
    // (mesmo tipo, arquivos diferentes) não conseguiriam escrever aqui: `private` em Swift vale
    // por arquivo, não por tipo. Continuam só de leitura pra fora do módulo (a UI só lê, nunca
    // atribui direto).
    internal(set) var phase: MegaphonePhase = .idle
    internal(set) var items: [MegaphoneItem] = []
    /// Produto sendo megafonado agora — a lista rola até ele.
    private(set) var currentItemID: Int?
    /// Rodada em andamento e quantas foram pedidas.
    private(set) var round = 0
    private(set) var rounds: MegaphoneRounds = .once
    /// Por que está parado, quando está. Uma pausa do usuário não é desfeita pela volta do app.
    private(set) var pauseReason: MegaphonePauseReason?
    /// Somatórios de todas as rodadas (os status em `items` valem só para a rodada atual).
    internal(set) var totalSucceeded = 0
    internal(set) var totalFailed = 0
    /// Andamento de apagar cada produto, por id — separado de `items[].status` de propósito:
    /// apagar não é megafonar, e reaproveitar o mesmo campo faria o laço automático pular um
    /// produto só porque ele está sendo apagado.
    internal(set) var deleteStatuses: [Int: MegaphoneStatus] = [:]
    /// Andamento de inativar cada produto, por id — mesmo raciocínio de `deleteStatuses`: inativar
    /// não é megafonar, e reaproveitar `items[].status` faria o laço automático pular o produto só
    /// por causa disso.
    internal(set) var inactivateStatuses: [Int: MegaphoneStatus] = [:]
    /// Andamento de ativar cada produto, por id — separado de `inactivateStatuses` porque essa
    /// ação parte da aba "inativos" (produtos fora de `items`), não da lista de publicados.
    internal(set) var activateStatuses: [Int: MegaphoneStatus] = [:]
    /// Diagnóstico completo da última falha de cada produto, qualquer que seja a ação (megafonar,
    /// aplicar desconto, apagar, inativar ou ativar) — só em memória, ao contrário do que os
    /// quatro dicionários de status acima guardam. Um produto só tem uma falha "visível" por vez
    /// na tela (a row prioriza apagado > inativado > mensagem de erro do megafone), então um
    /// dicionário só, sobrescrito a cada falha nova, já basta.
    internal(set) var failureDetails: [Int: MegaphoneFailureDetail] = [:]

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

    // Também sem `private` — usado pelos métodos movidos pros arquivos de extensão (ver
    // comentário acima, nas propriedades).
    let client: EnjoeiClientProtocol
    private let itemsPersistence: MegaphoneItemsPersisting
    /// Compartilhada entre todas as contas — decide quando `start()` pode de fato começar a rodar
    /// (ver `MegaphoneQueue`). Uma fila só pra este runner por padrão: sozinho nela, nunca espera —
    /// testes/previews não precisam pensar em concorrência entre contas pra funcionar.
    private let megaphoneQueue: MegaphoneQueue
    private var task: Task<Void, Never>?
    private var pauseGate: CheckedContinuation<Void, Never>?

    /// - Parameter itemsPersistence: em memória por padrão, pra um runner criado sem pensar em
    ///   disco (testes, previews) nunca escrever em disco por acidente — a produção passa
    ///   `SwiftDataMegaphoneItemsPersistence` explicitamente.
    /// - Parameter megaphoneQueue: a fila compartilhada de verdade vem de `AccountsStore` — a
    ///   produção sempre passa a mesma instância pras contas restantes; testes/previews recebem
    ///   uma fila só sua por padrão.
    init(
        client: EnjoeiClientProtocol,
        itemsPersistence: MegaphoneItemsPersisting = InMemoryMegaphoneItemsPersistence(),
        megaphoneQueue: MegaphoneQueue = MegaphoneQueue()
    ) {
        self.client = client
        self.itemsPersistence = itemsPersistence
        self.megaphoneQueue = megaphoneQueue
        items = itemsPersistence.loadItems()
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
        // Sempre passa por `.waitingInQueue` primeiro, mesmo quando a vaga está livre na hora (o
        // `Task` abaixo sempre tem pelo menos um agendamento antes de rodar de verdade) — troca pra
        // `.loadingProducts`/o que já estava rodando assim que `megaphoneQueue.acquire` devolver.
        phase = .waitingInQueue
        task = Task { [weak self] in
            guard let self else { return }
            await self.megaphoneQueue.acquire(self)
            defer { self.megaphoneQueue.release(self) }
            guard !Task.isCancelled else {
                // Mesmo tratamento de `run()` quando cancelado em pleno andamento — sem isso,
                // `phase` ficaria travada em `.waitingInQueue` pra sempre (o `cancel()` que
                // interrompeu a espera não passa por `run()`, que é quem normalmente cuida disso).
                self.finish(.cancelled)
                self.task = nil
                return
            }
            if self.items.isEmpty { self.phase = .loadingProducts(loaded: 0, total: 0) }
            await self.run(sellerID: sellerID)
            self.task = nil
        }
    }

    /// Busca por título direto na persistência (SwiftData em produção — ver
    /// `SwiftDataMegaphoneItemsPersistence.searchProductIDs(matching:)`), devolvendo só os ids que
    /// batem. Quem chama cruza esses ids com `items` (a lista ao vivo, com status/exposição
    /// corretos — o que fica persistido nunca reflete uma megafonagem em andamento) — ver
    /// `AccountPublishedTabView.recomputeFilteredItems()`.
    func searchProductIDs(matching query: String, limit: Int = 500) -> [Int] {
        itemsPersistence.searchProductIDs(matching: query, limit: limit)
    }

    /// Descarta a lista carregada e busca a loja de novo do zero — pro botão de recarregar, quando
    /// o usuário quer garantir que está vendo o catálogo atual. Só carrega (igual a `load`), nunca
    /// começa a megafonar sozinho: em nenhuma hipótese o app dispara isso sem o toque explícito no
    /// botão "megafonar".
    func reload(sellerID: Int) {
        guard task == nil else { return }
        items = []
        // Descartada aqui mesmo, sem esperar a busca nova: se o app fechar no meio do reload, a
        // próxima abertura não deve voltar a mostrar a lista antiga como se nada tivesse pedido.
        itemsPersistence.clearItems()
        load(sellerID: sellerID)
    }

    /// Guarda a lista recém-carregada (produtos + exposição) tanto na tela quanto em disco, pra
    /// não precisar buscar a loja de novo na próxima abertura do app.
    private func setLoadedItems(_ items: [MegaphoneItem]) {
        self.items = items
        itemsPersistence.saveItems(items)
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
            let items = try await loadProductsWithExposure(sellerID: sellerID)
            guard !items.isEmpty else {
                phase = .idle
                return
            }
            setLoadedItems(items)
            phase = .idle
        } catch {
            // Falha ou cancelamento na busca automática não vira alarme — o usuário ainda pode
            // tocar em "megafonar" pra tentar de propósito e ver o erro de verdade.
            phase = .idle
        }
    }

    /// Busca a loja inteira e, na sequência, a exposição de cada produto — usado tanto pelo
    /// carregamento sozinho (`loadOnly`) quanto pela primeira busca de uma rodada (`run`), pra não
    /// duplicar os dois passos nos dois lugares.
    private func loadProductsWithExposure(sellerID: Int) async throws -> [MegaphoneItem] {
        let products = try await loadAllProducts(sellerID: sellerID)
        guard !products.isEmpty else { return [] }
        phase = .checkingExposure(checked: 0, total: products.count)
        let exposures = try await loadExposures(productIDs: products.map(\.id))
        return products.map { MegaphoneItem(product: $0, exposure: exposures[$0.id]) }
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
                let loadedItems = try await loadProductsWithExposure(sellerID: sellerID)
                guard !loadedItems.isEmpty else {
                    finish(.finished)
                    return
                }
                setLoadedItems(loadedItems)
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
            if inactivateStatuses[items[index].id] == .succeeded { continue }
            items[index].status = .megaphoning
            currentItemID = items[index].id

            do {
                token = try await megaphone(productID: items[index].id, newPrice: nil, token: token)
                items[index].status = .succeeded
                totalSucceeded += 1
            } catch EnjoeiError.notAuthenticated {
                items[index].status = .failed(EnjoeiError.notAuthenticated.localizedDescription)
                failureDetails[items[index].id] = MegaphoneFailureDetail(action: .megaphone, error: EnjoeiError.notAuthenticated)
                totalFailed += 1
                throw EnjoeiError.notAuthenticated
            } catch {
                items[index].status = .failed(error.localizedDescription)
                failureDetails[items[index].id] = MegaphoneFailureDetail(action: .megaphone, error: error)
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
    /// token — ele roda junto com a sessão. `newPrice` aplica o desconto sugerido junto. Sem
    /// `private`: reaproveitado por `performApplyDiscount`, em `MegaphoneRunner+ProductActions.swift`.
    func megaphone(productID: Int, newPrice: Double?, token: String) async throws -> String {
        do {
            try await client.megaphone(productID: productID, csrfToken: token, newPrice: newPrice)
            return token
        } catch let error as EnjoeiError where error.isCSRFRejection {
            let refreshed = try await client.csrfToken()
            try await client.megaphone(productID: productID, csrfToken: refreshed, newPrice: newPrice)
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
