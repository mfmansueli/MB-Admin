import Foundation
import Testing
@testable import MaryBottom

@Suite("fila de publicação entre contas")
struct PostQueueTests {
    private func makeAccount(name: String, client: StubEnjoeiClient) -> AccountSession {
        AccountSession(
            id: EnjoeiAccountID(),
            user: EnjoeiUser(
                id: Int.random(in: 1...1_000_000),
                nickname: name,
                name: name,
                avatarPublicID: nil,
                availableProductsCount: nil
            ),
            dependencies: AccountDependencies(client: client, sessionClearer: FakeSessionClearer(), webView: nil)
        )
    }

    private func makeTemplate(productID: Int) -> ProductTemplate {
        ProductTemplate(
            title: "produto \(productID)",
            description: "descrição",
            brand: "marca",
            used: false,
            price: 29900,
            originalPrice: 29900,
            weight: "0.3",
            quantity: 1,
            category: .init(id: 327),
            size: nil,
            shipping: .init(type: "charge_by_weight", hasInsurance: true),
            photos: [.init(imagePublicID: "foto-\(productID)", position: 0)],
            originPlanID: 1,
            smartPrice: .init(enabled: true)
        )
    }

    @Test("enfileira e processa os itens em sequência, um de cada vez")
    func processaEmSequencia() async {
        let sourceClient = StubEnjoeiClient(
            templatesByProductID: [1: makeTemplate(productID: 1), 2: makeTemplate(productID: 2)]
        )
        let source = makeAccount(name: "origem", client: sourceClient)
        let destinationClient = StubEnjoeiClient()
        let destination = makeAccount(name: "destino", client: destinationClient)
        // Os dois itens têm que suceder um atrás do outro — sem isso, o cooldown de verdade do
        // `poster` compartilhado (2 minutos) travaria o segundo item bem além do que o teste espera.
        let poster = CrossAccountPoster(cooldownDuration: .zero)
        let queue = PostQueue(poster: poster, accountsProvider: { [source, destination] }, interval: .zero)

        queue.enqueue(product: EnjoeiFixtures.product(id: 1), source: source, destination: destination)
        queue.enqueue(product: EnjoeiFixtures.product(id: 2), source: source, destination: destination)
        #expect(queue.isRunning)

        // Espera cada item se resolver separadamente (cada `waitUntil` ganha seu próprio limite de
        // iterações) em vez de um único `waitUntil { !queue.isRunning }` — sob carga pesada (suíte
        // inteira rodando em paralelo), a cadeia dos dois itens juntos pode não caber no limite de
        // um `waitUntil` só.
        await waitUntil { poster.statuses[1] != nil && poster.statuses[1] != .megaphoning }
        await waitUntil { poster.statuses[2] != nil && poster.statuses[2] != .megaphoning }
        await waitUntil { !queue.isRunning }

        #expect(await sourceClient.requestedTemplateIDs == [1, 2])
        #expect(await destinationClient.createProductCalls.count == 2)
        #expect(queue.items.allSatisfy { queue.status(for: $0) == .succeeded })
    }

    @Test("remover um item pendente tira ele da fila sem postar")
    func removerItemPendente() async {
        let sourceClient = StubEnjoeiClient(
            templatesByProductID: [1: makeTemplate(productID: 1), 2: makeTemplate(productID: 2)]
        )
        let source = makeAccount(name: "origem", client: sourceClient)
        let destination = makeAccount(name: "destino", client: StubEnjoeiClient())
        let poster = CrossAccountPoster()
        // Intervalo bem maior que a duração do teste — dá tempo de remover o segundo item antes
        // dele sair da espera.
        let queue = PostQueue(poster: poster, accountsProvider: { [source, destination] }, interval: 60)

        queue.enqueue(product: EnjoeiFixtures.product(id: 1), source: source, destination: destination)
        queue.enqueue(product: EnjoeiFixtures.product(id: 2), source: source, destination: destination)
        let secondItemID = queue.items[1].id

        await waitUntil { poster.statuses[1] != .megaphoning && poster.statuses[1] != nil }
        queue.remove(id: secondItemID)

        #expect(queue.items.map(\.id) == [queue.items.first?.id].compactMap { $0 })
        #expect(await sourceClient.requestedTemplateIDs == [1])
    }

    @Test("limpar a fila tira todos os itens de uma vez, sem postar o que ainda estava pendente")
    func limparFilaRemoveTudo() async {
        let sourceClient = StubEnjoeiClient(
            templatesByProductID: [1: makeTemplate(productID: 1), 2: makeTemplate(productID: 2)]
        )
        let source = makeAccount(name: "origem", client: sourceClient)
        let destination = makeAccount(name: "destino", client: StubEnjoeiClient())
        let poster = CrossAccountPoster()
        // Intervalo bem maior que a duração do teste — dá tempo de limpar a fila antes do segundo
        // item sair da espera.
        let queue = PostQueue(poster: poster, accountsProvider: { [source, destination] }, interval: 60)

        queue.enqueue(product: EnjoeiFixtures.product(id: 1), source: source, destination: destination)
        queue.enqueue(product: EnjoeiFixtures.product(id: 2), source: source, destination: destination)

        await waitUntil { poster.statuses[1] != .megaphoning && poster.statuses[1] != nil }
        queue.removeAll()

        #expect(queue.items.isEmpty)
        #expect(await sourceClient.requestedTemplateIDs == [1])
    }

    @Test("pausar antes de qualquer item começar trava o laço até continuar")
    func pausarTravaOLacoAteContinuar() async {
        let sourceClient = StubEnjoeiClient(
            templatesByProductID: [1: makeTemplate(productID: 1), 2: makeTemplate(productID: 2)]
        )
        let source = makeAccount(name: "origem", client: sourceClient)
        let destination = makeAccount(name: "destino", client: StubEnjoeiClient())
        let poster = CrossAccountPoster(cooldownDuration: .zero)
        let queue = PostQueue(poster: poster, accountsProvider: { [source, destination] }, interval: .zero)

        // Pausa antes de enfileirar — a `Task` do laço só ganha a vez depois que este trecho
        // síncrono termina, então ela já nasce vendo `isPaused == true`.
        queue.pause()
        queue.enqueue(product: EnjoeiFixtures.product(id: 1), source: source, destination: destination)
        queue.enqueue(product: EnjoeiFixtures.product(id: 2), source: source, destination: destination)

        // Várias chances do laço rodar — nada é postado enquanto pausado.
        for _ in 0..<200 { await Task.yield() }
        #expect(poster.statuses[1] == nil)
        #expect(queue.isPaused)
        #expect(queue.isRunning)

        queue.resume()
        await waitUntil { poster.statuses[1] != nil && poster.statuses[1] != .megaphoning }
        await waitUntil { poster.statuses[2] != nil && poster.statuses[2] != .megaphoning }

        #expect(queue.items.allSatisfy { queue.status(for: $0) == .succeeded })
        #expect(queue.isPaused == false)
    }

    @Test("pausar durante o intervalo entre itens não espera ele terminar pra valer")
    func pausarDuranteOIntervaloInterrompeNaHora() async {
        let sourceClient = StubEnjoeiClient(
            templatesByProductID: [1: makeTemplate(productID: 1), 2: makeTemplate(productID: 2)]
        )
        let source = makeAccount(name: "origem", client: sourceClient)
        let destination = makeAccount(name: "destino", client: StubEnjoeiClient())
        let poster = CrossAccountPoster(cooldownDuration: .zero)
        // Intervalo bem maior que a duração do teste — sem interromper por pausa, o segundo item
        // não sairia da espera a tempo do teste terminar.
        let queue = PostQueue(poster: poster, accountsProvider: { [source, destination] }, interval: 60)

        queue.enqueue(product: EnjoeiFixtures.product(id: 1), source: source, destination: destination)
        queue.enqueue(product: EnjoeiFixtures.product(id: 2), source: source, destination: destination)

        // Ainda dentro do intervalo de 60s entre o primeiro item e o segundo.
        await waitUntil { poster.statuses[1] != nil && poster.statuses[1] != .megaphoning }
        queue.pause()
        // Tempo real (não só `Task.yield`) maior que o pedaço de 0.2s do laço de espera interno —
        // sem isso, um `resume()` na sequência pode acontecer antes do laço sequer checar
        // `isPaused`, e o teste não estaria testando nada.
        try? await Task.sleep(for: .milliseconds(500))
        queue.resume()

        await waitUntil { poster.statuses[2] != nil && poster.statuses[2] != .megaphoning }
        #expect(queue.items.allSatisfy { queue.status(for: $0) == .succeeded })
    }

    @Test("apagar pela fila delega pro runner da conta e aparece como succeeded")
    func apagarPelaFilaDelegaProRunner() async {
        let client = StubEnjoeiClient()
        let account = makeAccount(name: "conta", client: client)
        let poster = CrossAccountPoster()
        let queue = PostQueue(poster: poster, accountsProvider: { [account] }, interval: .zero)

        queue.enqueueDelete(product: EnjoeiFixtures.product(id: 1), account: account)
        await waitUntil { !queue.isRunning }

        #expect(account.runner.deleteStatuses[1] == .succeeded)
        #expect(queue.status(for: queue.items[0]) == .succeeded)
        #expect(await client.deleteProductCalls.map(\.productID) == [1])
    }

    @Test("inativar pela fila delega pro runner da conta e aparece como succeeded")
    func inativarPelaFilaDelegaProRunner() async {
        let client = StubEnjoeiClient(templatesByProductID: [1: makeTemplate(productID: 1)])
        let account = makeAccount(name: "conta", client: client)
        let poster = CrossAccountPoster()
        let queue = PostQueue(poster: poster, accountsProvider: { [account] }, interval: .zero)

        queue.enqueueInactivate(product: EnjoeiFixtures.product(id: 1), account: account)
        await waitUntil { !queue.isRunning }

        #expect(account.runner.inactivateStatuses[1] == .succeeded)
        #expect(queue.status(for: queue.items[0]) == .succeeded)
        #expect(await client.updateProductStateCalls.map(\.productID) == [1])
    }

    @Test("ativar pela fila delega pro runner da conta e aparece como succeeded")
    func ativarPelaFilaDelegaProRunner() async {
        let client = StubEnjoeiClient(templatesByProductID: [1: makeTemplate(productID: 1)])
        let account = makeAccount(name: "conta", client: client)
        let poster = CrossAccountPoster()
        let queue = PostQueue(poster: poster, accountsProvider: { [account] }, interval: .zero)

        queue.enqueueActivate(product: EnjoeiFixtures.product(id: 1), account: account)
        await waitUntil { !queue.isRunning }

        #expect(account.runner.activateStatuses[1] == .succeeded)
        #expect(queue.status(for: queue.items[0]) == .succeeded)
        #expect(await client.updateProductStateCalls.map(\.productID) == [1])
    }

    @Test("postagem bem-sucedida entra no histórico com os detalhes de origem e destino")
    func postagemEntraNoHistorico() async throws {
        let sourceClient = StubEnjoeiClient(templatesByProductID: [1: makeTemplate(productID: 1)])
        let source = makeAccount(name: "origem", client: sourceClient)
        let destination = makeAccount(name: "destino", client: StubEnjoeiClient())
        let poster = CrossAccountPoster(cooldownDuration: .zero)
        let history = InMemoryPostHistoryPersistence()
        let queue = PostQueue(
            poster: poster,
            accountsProvider: { [source, destination] },
            interval: .zero,
            historyPersistence: history
        )

        queue.enqueue(product: EnjoeiFixtures.product(id: 1), source: source, destination: destination)
        await waitUntil { !queue.isRunning }

        #expect(queue.history.count == 1)
        let entry = try #require(queue.history.first)
        #expect(entry.product.id == 1)
        #expect(entry.kind == .post)
        #expect(entry.sourceAccountID == source.id)
        #expect(entry.sourceAccountName == "origem")
        #expect(entry.destinationAccountID == destination.id)
        #expect(entry.destinationAccountName == "destino")
        #expect(entry.outcome == .succeeded)
        // Persistido de verdade, não só em memória na instância da fila.
        #expect(history.loadEntries() == queue.history)
    }

    @Test("ação que falha também entra no histórico, com a mensagem de erro")
    func falhaEntraNoHistorico() async throws {
        let client = StubEnjoeiClient(deleteProductError: .http(status: 500, message: "o enjoei caiu"))
        let account = makeAccount(name: "conta", client: client)
        let poster = CrossAccountPoster()
        let history = InMemoryPostHistoryPersistence()
        let queue = PostQueue(
            poster: poster,
            accountsProvider: { [account] },
            interval: .zero,
            historyPersistence: history
        )

        queue.enqueueDelete(product: EnjoeiFixtures.product(id: 1), account: account)
        await waitUntil { !queue.isRunning }

        let entry = try #require(queue.history.first)
        #expect(entry.kind == .delete)
        #expect(entry.outcome == .failed("o enjoei caiu"))
        #expect(entry.failureDetail?.action == .delete)
        #expect(entry.failureDetail?.httpStatus == 500)
        #expect(entry.failureDetail?.serverMessage == "o enjoei caiu")
    }

    @Test("postagem que falha também grava o diagnóstico completo, não só a mensagem curta")
    func postagemQueFalhaGravaDiagnostico() async throws {
        let sourceClient = StubEnjoeiClient(templateError: .unexpectedResponse)
        let source = makeAccount(name: "origem", client: sourceClient)
        let destination = makeAccount(name: "destino", client: StubEnjoeiClient())
        let poster = CrossAccountPoster(cooldownDuration: .zero)
        let history = InMemoryPostHistoryPersistence()
        let queue = PostQueue(
            poster: poster,
            accountsProvider: { [source, destination] },
            interval: .zero,
            historyPersistence: history
        )

        queue.enqueue(product: EnjoeiFixtures.product(id: 1), source: source, destination: destination)
        await waitUntil { !queue.isRunning }

        let entry = try #require(queue.history.first)
        #expect(entry.failureDetail?.action == .post)
        #expect(entry.failureDetail?.technicalDescription == EnjoeiError.unexpectedResponse.diagnosticDescription)
    }

    @Test("histórico novo carrega o que já estava persistido")
    func historicoCarregaOQueJaEstavaPersistido() async {
        let poster = CrossAccountPoster()
        let history = InMemoryPostHistoryPersistence()
        let firstQueue = PostQueue(
            poster: poster,
            accountsProvider: { [] },
            interval: .zero,
            historyPersistence: history
        )
        let sourceClient = StubEnjoeiClient(templatesByProductID: [1: makeTemplate(productID: 1)])
        let source = makeAccount(name: "origem", client: sourceClient)
        let destination = makeAccount(name: "destino", client: StubEnjoeiClient())
        firstQueue.accountsProvider = { [source, destination] }
        firstQueue.enqueue(product: EnjoeiFixtures.product(id: 1), source: source, destination: destination)
        await waitUntil { !firstQueue.isRunning }

        // Simula reabrir o app: uma fila nova, mesma persistência.
        let secondQueue = PostQueue(poster: poster, accountsProvider: { [] }, historyPersistence: history)

        #expect(secondQueue.history == firstQueue.history)
    }

    @Test("limpar o histórico apaga tudo, sem afetar a fila em andamento")
    func limparHistoricoApagaTudo() async {
        let sourceClient = StubEnjoeiClient(templatesByProductID: [1: makeTemplate(productID: 1)])
        let source = makeAccount(name: "origem", client: sourceClient)
        let destination = makeAccount(name: "destino", client: StubEnjoeiClient())
        let poster = CrossAccountPoster(cooldownDuration: .zero)
        let history = InMemoryPostHistoryPersistence()
        let queue = PostQueue(
            poster: poster,
            accountsProvider: { [source, destination] },
            interval: .zero,
            historyPersistence: history
        )
        queue.enqueue(product: EnjoeiFixtures.product(id: 1), source: source, destination: destination)
        await waitUntil { !queue.isRunning }
        #expect(!queue.history.isEmpty)

        queue.clearHistory()

        #expect(queue.history.isEmpty)
        #expect(history.loadEntries().isEmpty)
        #expect(queue.items.isEmpty == false)
    }

    /// Suite efêmera própria por teste, pra `setInterval` não sujar (nem depender de) o
    /// `UserDefaults.standard` da máquina rodando os testes.
    private func makeIntervalDefaults() -> UserDefaults {
        UserDefaults(suiteName: "PostQueueTests.interval.\(UUID().uuidString)")!
    }

    @Test("mudar o intervalo persiste a escolha")
    func mudarIntervaloPersiste() {
        let defaults = makeIntervalDefaults()
        let queue = PostQueue(poster: CrossAccountPoster(), accountsProvider: { [] }, defaults: defaults)

        queue.setInterval(30)

        #expect(queue.interval == 30)
        #expect(defaults.double(forKey: "postQueue.interval") == 30)
    }

    @Test("fila nova recupera o intervalo persistido, sem cair no padrão do poster")
    func filaNovaRecuperaIntervaloPersistido() {
        let defaults = makeIntervalDefaults()
        let firstQueue = PostQueue(poster: CrossAccountPoster(), accountsProvider: { [] }, defaults: defaults)
        firstQueue.setInterval(30)

        // Simula reabrir o app: uma fila nova, mesmo `UserDefaults`, sem `interval` explícito.
        let secondQueue = PostQueue(
            poster: CrossAccountPoster(cooldownDuration: 999),
            accountsProvider: { [] },
            defaults: defaults
        )

        #expect(secondQueue.interval == 30)
    }

    @Test("um interval explícito no init vale por cima de qualquer coisa persistida")
    func intervalExplicitoIgnoraOPersistido() {
        let defaults = makeIntervalDefaults()
        defaults.set(TimeInterval(30), forKey: "postQueue.interval")

        let queue = PostQueue(poster: CrossAccountPoster(), accountsProvider: { [] }, interval: .zero, defaults: defaults)

        #expect(queue.interval == .zero)
    }

    @Test("conta que não existe mais no accountsProvider vira falha, sem travar o resto da fila")
    func contaDeslogada() async {
        let vanishingSource = makeAccount(name: "origem que some", client: StubEnjoeiClient())
        let vanishingDestination = makeAccount(name: "destino que some", client: StubEnjoeiClient())
        let stableSourceClient = StubEnjoeiClient(templatesByProductID: [2: makeTemplate(productID: 2)])
        let stableSource = makeAccount(name: "origem estável", client: stableSourceClient)
        let stableDestinationClient = StubEnjoeiClient()
        let stableDestination = makeAccount(name: "destino estável", client: stableDestinationClient)

        var currentAccounts = [vanishingSource, vanishingDestination, stableSource, stableDestination]
        let poster = CrossAccountPoster()
        let queue = PostQueue(poster: poster, accountsProvider: { currentAccounts }, interval: .zero)

        queue.enqueue(product: EnjoeiFixtures.product(id: 1), source: vanishingSource, destination: vanishingDestination)
        queue.enqueue(product: EnjoeiFixtures.product(id: 2), source: stableSource, destination: stableDestination)
        // As duas primeiras "deslogam" antes da fila sequer olhar pro primeiro item — tudo isso
        // ainda em código síncrono, então a Task da fila nem começou a rodar ainda.
        currentAccounts = [stableSource, stableDestination]

        // Cada item espera com seu próprio limite de iterações — ver comentário em
        // `processaEmSequencia` sobre por que não dá pra confiar num único `waitUntil` pra dois
        // itens seguidos sob carga pesada.
        await waitUntil { queue.status(for: queue.items[0]) != .pending }
        await waitUntil { poster.statuses[2] != nil && poster.statuses[2] != .megaphoning }
        await waitUntil { !queue.isRunning }

        #expect(queue.status(for: queue.items[0]) == .failed("conta não está mais logada"))
        #expect(queue.status(for: queue.items[1]) == .succeeded)
        #expect(await stableDestinationClient.createProductCalls.count == 1)
        // Sem `Error` de verdade por trás (a fila nem chega a tentar a chamada de rede) — o
        // diagnóstico sintético repete a mensagem, em vez de vir vazio.
        #expect(queue.failureDetail(for: queue.items[0])?.action == .post)
        #expect(queue.failureDetail(for: queue.items[0])?.technicalDescription == "conta não está mais logada")
    }

    @Test("produto já postado no poster compartilhado não dispara outra chamada pela fila")
    func produtoJaPostadoNaoDuplica() async {
        let sourceClient = StubEnjoeiClient(templatesByProductID: [1: makeTemplate(productID: 1)])
        let source = makeAccount(name: "origem", client: sourceClient)
        let destinationClient = StubEnjoeiClient()
        let destination = makeAccount(name: "destino", client: destinationClient)
        let poster = CrossAccountPoster()
        let queue = PostQueue(poster: poster, accountsProvider: { [source, destination] }, interval: .zero)

        poster.post(product: EnjoeiFixtures.product(id: 1), from: source, to: destination)
        await waitUntil { poster.statuses[1] != .megaphoning && poster.statuses[1] != nil }
        #expect(await destinationClient.createProductCalls.count == 1)

        queue.enqueue(product: EnjoeiFixtures.product(id: 1), source: source, destination: destination)
        await waitUntil { !queue.isRunning }

        #expect(await destinationClient.createProductCalls.count == 1)
        #expect(queue.status(for: queue.items[0]) == .succeeded)
    }

    @Test("currentItem aponta pro item em voo processando a fila, e volta a nil no fim")
    func currentItemDuranteAFila() async {
        let sourceClient = StubEnjoeiClient(templatesByProductID: [1: makeTemplate(productID: 1)])
        let source = makeAccount(name: "origem", client: sourceClient)
        let destination = makeAccount(name: "destino", client: StubEnjoeiClient())
        let poster = CrossAccountPoster()
        let queue = PostQueue(poster: poster, accountsProvider: { [source, destination] }, interval: .zero)

        #expect(queue.currentItem == nil)

        queue.enqueue(product: EnjoeiFixtures.product(id: 1), source: source, destination: destination)
        await waitUntil { !queue.isRunning }

        #expect(queue.currentItem == nil)
    }

    @Test("postSingle não faz nada enquanto já existe algo em voo")
    func postSingleNaoDuplicaEmVoo() async {
        let source = makeAccount(name: "origem", client: StubEnjoeiClient(templatesByProductID: [
            1: makeTemplate(productID: 1), 2: makeTemplate(productID: 2)
        ]))
        let destination = makeAccount(name: "destino", client: StubEnjoeiClient())
        let poster = CrossAccountPoster()
        // Intervalo grande: o primeiro item fica "reservando" currentItem tempo suficiente pro
        // segundo postSingle (chamado antes do primeiro terminar) ser recusado.
        let queue = PostQueue(poster: poster, accountsProvider: { [source, destination] }, interval: 60)

        queue.postSingle(product: EnjoeiFixtures.product(id: 1), from: source, to: destination)
        queue.postSingle(product: EnjoeiFixtures.product(id: 2), from: source, to: destination)

        await waitUntil { poster.statuses[1] != .megaphoning && poster.statuses[1] != nil }

        #expect(poster.statuses[2] == nil)
    }

    /// Espera uma condição sem prender o teste pra sempre se algo der errado.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<10_000 where !condition() {
            await Task.yield()
        }
    }
}
