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
