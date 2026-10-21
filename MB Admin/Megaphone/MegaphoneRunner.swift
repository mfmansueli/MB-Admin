import Foundation
import Observation

/// Conduz o megafone: lista todos os produtos da loja e passa por eles quantas rodadas o usuário
/// pedir, publicando o andamento para a tela.
@MainActor
@Observable
final class MegaphoneRunner {
    /// Só muda por `setPhase(_:)`, mesmo dentro deste tipo — é o único jeito de garantir que toda
    /// transição force uma publicação de `progressSnapshot` na hora (ver esse método), inclusive
    /// as que acontecem em `MegaphoneRunner+ProductLoading.swift`.
    private(set) var phase: MegaphonePhase = .idle
    // Sem `private(set)` nesta e nas propriedades de status/totais abaixo — sem isso, os métodos
    // movidos pra `MegaphoneRunner+ProductLoading.swift`/`MegaphoneRunner+ProductActions.swift`
    // (mesmo tipo, arquivos diferentes) não conseguiriam escrever aqui: `private` em Swift vale
    // por arquivo, não por tipo. A UI só lê, nunca atribui direto.
    var items: [MegaphoneItem] = []
    /// Resumo pra quem só mostra visão geral — ver `MegaphoneProgressSnapshot` e
    /// `refreshProgressSnapshot(force:)`. Só muda por esse método (mesmo de arquivos diferentes,
    /// que só conseguem chamá-lo — a atribuição em si mora dentro dele, neste arquivo).
    private(set) var progressSnapshot = MegaphoneProgressSnapshot()
    /// Último produto que o laço terminou de megafonar (sucesso ou falha).
    private(set) var currentItemID: Int?
    /// Produto que o laço em JS está megafonando agora — o próximo do pedaço em voo depois de
    /// `currentItemID`. Diferente de `items[].status == .megaphoning`, que marca o pedaço inteiro
    /// (até `megaphoneBatchChunkSize` produtos) de uma vez: só este é "o da vez" na tela, e é até ele
    /// que a lista rola acompanhando. `nil` entre um pedaço e o próximo, e com a rodada parada.
    private(set) var activeItemID: Int?
    /// Rodada em andamento e quantas foram pedidas.
    private(set) var round = 0
    private(set) var rounds: MegaphoneRounds = .once
    /// Por que está parado, quando está. Uma pausa do usuário não é desfeita pela volta do app.
    private(set) var pauseReason: MegaphonePauseReason?
    /// Somatórios de todas as rodadas (os status em `items` valem só para a rodada atual).
    var totalSucceeded = 0
    var totalFailed = 0
    /// Andamento de apagar cada produto, por id — separado de `items[].status` de propósito:
    /// apagar não é megafonar, e reaproveitar o mesmo campo faria o laço automático pular um
    /// produto só porque ele está sendo apagado.
    var deleteStatuses: [Int: MegaphoneStatus] = [:]
    /// Andamento de inativar cada produto, por id — mesmo raciocínio de `deleteStatuses`: inativar
    /// não é megafonar, e reaproveitar `items[].status` faria o laço automático pular o produto só
    /// por causa disso.
    var inactivateStatuses: [Int: MegaphoneStatus] = [:]
    /// Andamento de ativar cada produto, por id — separado de `inactivateStatuses` porque essa
    /// ação parte da aba "inativos" (produtos fora de `items`), não da lista de publicados.
    var activateStatuses: [Int: MegaphoneStatus] = [:]
    /// Diagnóstico completo da última falha de cada produto, qualquer que seja a ação (megafonar,
    /// aplicar desconto, apagar, inativar ou ativar) — só em memória, ao contrário do que os
    /// quatro dicionários de status acima guardam. Um produto só tem uma falha "visível" por vez
    /// na tela (a row prioriza apagado > inativado > mensagem de erro do megafone), então um
    /// dicionário só, sobrescrito a cada falha nova, já basta.
    var failureDetails: [Int: MegaphoneFailureDetail] = [:]

    /// Intervalo entre um megafone e o próximo, para não martelar o Enjoei. `megaphoneAll` manda
    /// esse valor para dentro do laço em JS (ver `delayBetweenProductsMilliseconds`) — não dá mais
    /// pra usar `Task.sleep` aqui, já que o laço item a item saiu do Swift.
    var delayBetweenProducts: Duration = .milliseconds(900)
    /// Quantos ids pedir por chamada ao endpoint de exposição — o Enjoei aceita vários de uma vez,
    /// mas evitamos mandar a loja inteira numa URL só.
    var exposureBatchSize = 80
    /// Quantos produtos manda por chamada ao lote em JS (`EnjoeiJavaScript.megaphoneBatch`) — ver
    /// `megaphoneAll()`. Um pedaço só com a loja inteira reduziria IPC ao máximo, mas
    /// `callAsyncJavaScript` não é sensível a `Task.cancel()`: um pedaço já disparado roda até o
    /// fim não importa o que o Swift decida nesse meio tempo, então esse valor é também o quanto
    /// pausar/cancelar demora a fazer efeito de verdade (pior caso: tempo de terminar o pedaço
    /// atual). `var`, não `let`, pelo mesmo motivo de `progressSnapshotBatchSize` — testes usam um
    /// valor pequeno sem precisar de centenas de itens.
    var megaphoneBatchChunkSize = 10
    /// A cada quantos itens megafonados (no mínimo) `progressSnapshot` se atualiza durante o laço
    /// automático — ver `refreshProgressSnapshot(force:)`. `var`, não `let`: os testes usam um
    /// valor pequeno pra provar o lote sem precisar rodar centenas de itens. Em produção, numa loja
    /// de 1500 produtos isso publica ~50 atualizações de resumo por rodada em vez de 1500.
    ///
    /// Cada publicação reatribui `filteredItems` em `AccountPublishedTabView`, e o `ForEach` sobre
    /// esse array força o SwiftUI a comparar `MegaphoneItem` (structs com `EnjoeiProduct`/
    /// `MegaphoneExposure` aninhados, incluindo strings) pra decidir quais linhas mudaram de
    /// verdade — um trace de CPU num iPad real (Time Profiler) mostrou essa comparação como o maior
    /// custo de CPU da tela durante uma rodada, mesmo já em lote de 10. Subir esse número reduz
    /// proporcionalmente quantas vezes isso acontece por rodada — trade-off aceito: a lista demora
    /// um pouco mais pra refletir um produto recém-megafonado, nunca mais que 30 produtos de atraso
    /// (ver `MegaphoneRowView.==` pro outro lado desse mesmo fix, que reduz o custo de CADA
    /// comparação em vez da frequência).
    var progressSnapshotBatchSize = 30
    /// Quantos itens já passaram desde a última publicação de `progressSnapshot` — zera a cada
    /// publicação, forçada ou não.
    private var itemsSinceSnapshot = 0
    /// Quantos produtos processar (sucesso ou falha) antes de recarregar a página de bastidores
    /// proativamente, entre um pedaço e o próximo — ver `EnjoeiClientProtocol.reloadPage()`. Não é
    /// recuperação de erro (isso já existe em `EnjoeiWebSession.run`): é suspeita de que, numa
    /// sessão muito longa (centenas de rodadas seguidas, a mesma página desde o login), o heap
    /// JS/DOM da própria página do Enjoei só cresce, nunca reseta — pressão de memória grande o
    /// bastante explicaria o app inteiro (não só a WebView) ficando lento/travando o scroll depois
    /// de muitas rodadas. `var`, não `let`: dá pra baixar num teste sem esperar centenas de
    /// produtos de verdade.
    var pageReloadThreshold = 250
    /// Quantos produtos já foram processados (em qualquer rodada) desde o último reload — zera a
    /// cada reload, rolando por cima de fronteira de rodada (a contagem é da sessão toda, não por
    /// rodada).
    private var itemsSinceLastPageReload = 0

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
        // Sem isso, uma lista restaurada do disco ficava invisível pra quem lê só o resumo (a aba
        // de publicados mostrava "nenhum produto", a lista de contas não sabia quantos pedem
        // desconto) até a primeira troca de fase — que nunca vem sem um toque em megafonar.
        refreshProgressSnapshot()
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
        activeItemID = nil
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
        setPhase(.waitingInQueue)
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
            if self.items.isEmpty { self.setPhase(.loadingProducts(loaded: 0, total: 0)) }
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
        setPhase(.loadingProducts(loaded: 0, total: 0))
        do {
            let items = try await loadProductsWithExposure(sellerID: sellerID)
            guard !items.isEmpty else {
                setPhase(.idle)
                return
            }
            setLoadedItems(items)
            setPhase(.idle)
        } catch {
            // Falha ou cancelamento na busca automática não vira alarme — o usuário ainda pode
            // tocar em "megafonar" pra tentar de propósito e ver o erro de verdade.
            setPhase(.idle)
        }
    }

    /// Busca a loja inteira e, na sequência, a exposição de cada produto — usado tanto pelo
    /// carregamento sozinho (`loadOnly`) quanto pela primeira busca de uma rodada (`run`), pra não
    /// duplicar os dois passos nos dois lugares.
    private func loadProductsWithExposure(sellerID: Int) async throws -> [MegaphoneItem] {
        let products = try await loadAllProducts(sellerID: sellerID)
        guard !products.isEmpty else { return [] }
        setPhase(.checkingExposure(checked: 0, total: products.count))
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
            setPhase(.paused(round: round, of: rounds, reason: reason))
        }
    }

    private func resume(ifPausedBy reason: MegaphonePauseReason?) {
        guard let currentReason = pauseReason else { return }
        guard reason == nil || reason == currentReason else { return }
        pauseReason = nil
        if case .paused(let round, let rounds, _) = phase {
            setPhase(.megaphoning(round: round, of: rounds))
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
                setPhase(.megaphoning(round: currentRound, of: rounds))
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
        setPhase(phase)
        onRoundFinished?(
            MegaphoneRoundSummary(succeeded: totalSucceeded, failed: totalFailed, finishedAt: .now)
        )
    }

    /// Único ponto que muda `phase` — publica `progressSnapshot` junto, sempre, pra transições de
    /// fase (raras) nunca ficarem escondidas atrás do lote usado pelas atualizações item a item
    /// (ver `refreshProgressSnapshot(force:)`). Sem `private`: chamado também pelos métodos de
    /// carregamento movidos pra `MegaphoneRunner+ProductLoading.swift` (mesmo raciocínio das
    /// propriedades sem `private(set)` no topo deste arquivo).
    func setPhase(_ newPhase: MegaphonePhase) {
        phase = newPhase
        refreshProgressSnapshot()
    }

    /// Publica `progressSnapshot` a partir do estado atual. `force: true` (o padrão) publica sempre
    /// — usado em toda transição de fase, que é rara e precisa aparecer na hora. `force: false` só
    /// publica de fato a cada `progressSnapshotBatchSize` itens — usado dentro do laço de
    /// `megaphoneAll`/`performApplyDiscount`, onde cada item mudando `items` não pode custar um
    /// recálculo de tela por conta rodando ao mesmo tempo (ver `MegaphoneProgressSnapshot`).
    func refreshProgressSnapshot(force: Bool = true) {
        if !force {
            itemsSinceSnapshot += 1
            guard itemsSinceSnapshot >= progressSnapshotBatchSize else { return }
        }
        itemsSinceSnapshot = 0
        progressSnapshot = MegaphoneProgressSnapshot(
            phase: phase,
            itemsCount: items.count,
            processedCount: processedCount,
            totalSucceeded: totalSucceeded,
            totalFailed: totalFailed,
            round: round,
            discountDecisionCount: discountDecisionCount
        )
    }

    /// Mesmo O(catálogo) de `processedCount` — só roda quando o snapshot é publicado de fato (em
    /// lote, ver acima), nunca a cada produto.
    private var discountDecisionCount: Int {
        items.filter {
            $0.needsDiscountDecision && deleteStatuses[$0.id] != .succeeded && inactivateStatuses[$0.id] != .succeeded
        }.count
    }

    /// Quantos milissegundos `delayBetweenProducts` representa — é o que `megaphoneAll` manda pro
    /// laço em JS (`EnjoeiJavaScript.megaphoneBatch`), que não entende `Duration`.
    private var delayBetweenProductsMilliseconds: Int {
        let components = delayBetweenProducts.components
        let milliseconds = Double(components.seconds) * 1000
            + Double(components.attoseconds) / 1_000_000_000_000_000
        return Int(milliseconds.rounded())
    }

    /// Megafona a fila inteira em pedaços de `megaphoneBatchChunkSize`, cada um num lote só dentro
    /// da própria WebView (ver `EnjoeiClientProtocol.megaphoneBatch`/`EnjoeiJavaScript.megaphoneBatch`)
    /// — evita o round-trip de IPC por produto que o laço item a item em Swift custava antes, sem
    /// abrir mão de pausar/cancelar entre um pedaço e o próximo (ver `megaphoneBatchChunkSize` pro
    /// porquê de não ser um lote só com a loja inteira). Pula produtos já concluídos ou em andamento
    /// por fora — um desconto aplicado na mão (`applyDiscount`) enquanto a rodada corria não pode
    /// ser megafonado de novo por cima, ou os dois chamariam a rota ao mesmo tempo pro mesmo
    /// produto; essa checagem roda de novo a cada pedaço nesse conjunto de pendentes já calculado,
    /// então uma ação manual num produto ainda não alcançado é vista quando o pedaço dele chegar (ao
    /// contrário do laço antigo, que revia o pulo item a item, ela ainda não é vista dentro do
    /// pedaço já disparado — só no próximo). Erro num produto não para os demais — só sessão caída
    /// (`notAuthenticated`) interrompe a rodada de verdade.
    private func megaphoneAll(token: String) async throws -> String {
        var token = token

        let chunks = pendingMegaphoneChunks()
        guard !chunks.isEmpty else { return token }

        for (chunkIndex, chunk) in chunks.enumerated() {
            // Único ponto em que dá pra interromper um lote em andamento — o `callAsyncJavaScript`
            // de um pedaço já disparado roda até o fim não importa o que decidirmos nesse meio
            // tempo (ver doc de `megaphoneBatchChunkSize`), daí checar antes de cada pedaço, não
            // dentro dele.
            await waitWhilePaused()
            try Task.checkCancellation()

            // Recheca apagado/inativado aqui, não só quando `pendingIDs` foi montada: uma ação
            // manual pode ter acontecido enquanto pedaços anteriores rodavam.
            let liveChunk = chunk.filter { deleteStatuses[$0] != .succeeded && inactivateStatuses[$0] != .succeeded }
            guard !liveChunk.isEmpty else { continue }
            for id in liveChunk {
                setStatus(.megaphoning, for: id)
            }
            activeItemID = liveChunk.first

            var sessionExpired = false
            token = try await client.megaphoneBatch(
                productIDs: liveChunk,
                csrfToken: token,
                delayMilliseconds: delayBetweenProductsMilliseconds
            ) { [weak self] productID, response in
                guard let self else { return }
                self.currentItemID = productID
                self.activeItemID = Self.activeItemID(after: productID, in: liveChunk)
                if let error = response.failure {
                    self.setStatus(.failed(error.localizedDescription), for: productID)
                    self.failureDetails[productID] = MegaphoneFailureDetail(action: .megaphone, error: error)
                    self.totalFailed += 1
                    if case .notAuthenticated = error { sessionExpired = true }
                } else {
                    self.setStatus(.succeeded, for: productID)
                    self.totalSucceeded += 1
                }
                self.itemsSinceLastPageReload += 1
                self.refreshProgressSnapshot(force: false)
            }

            if sessionExpired {
                currentItemID = nil
                activeItemID = nil
                throw EnjoeiError.notAuthenticated
            }

            // Mesma cadência que já existia entre um produto e o seguinte — sem isso, o último
            // produto de um pedaço e o primeiro do próximo sairiam sem o intervalo que o resto do
            // laço respeita (o script em JS só espera *dentro* do próprio pedaço).
            if chunkIndex < chunks.count - 1, delayBetweenProducts > .zero {
                try await Task.sleep(for: delayBetweenProducts)
            }

            // Reload proativo entre pedaços — ver `pageReloadThreshold`. Cancelamento já é
            // checado no topo do laço, antes do próximo pedaço; não precisa checar de novo aqui.
            if itemsSinceLastPageReload >= pageReloadThreshold {
                itemsSinceLastPageReload = 0
                await client.reloadPage()
            }
        }

        currentItemID = nil
        activeItemID = nil
        return token
    }

    /// O laço em JS passa pelo pedaço em ordem, um de cada vez — terminado `productID`, o da vez
    /// passa a ser o seguinte dele no pedaço; depois do último, nenhum (até o próximo pedaço).
    nonisolated static func activeItemID(after productID: Int, in chunk: [Int]) -> Int? {
        guard let index = chunk.firstIndex(of: productID), chunk.indices.contains(index + 1) else { return nil }
        return chunk[index + 1]
    }

    /// Ids que `megaphoneAll` ainda tem que megafonar nesta rodada — nem já megafonados (ou em
    /// andamento), nem apagados/inativados — em pedaços de `megaphoneBatchChunkSize`.
    private func pendingMegaphoneChunks() -> [[Int]] {
        let pendingIDs = items
            .filter { $0.status != .succeeded && $0.status != .megaphoning }
            .filter { deleteStatuses[$0.id] != .succeeded }
            .filter { inactivateStatuses[$0.id] != .succeeded }
            .map(\.id)
        return stride(from: 0, to: pendingIDs.count, by: megaphoneBatchChunkSize).map {
            Array(pendingIDs[$0..<Swift.min($0 + megaphoneBatchChunkSize, pendingIDs.count)])
        }
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
        activeItemID = nil
    }
}
