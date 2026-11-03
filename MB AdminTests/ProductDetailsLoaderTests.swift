import Foundation
import Testing
@testable import MB_Admin

@Suite("busca de detalhes completos (descrição) de cada produto")
struct ProductDetailsLoaderTests {
    /// Sem espera entre produtos, os testes não ficam presos ao ritmo real do app.
    private func makeLoader(client: StubEnjoeiClient, itemsPersistence: MegaphoneItemsPersisting) -> ProductDetailsLoader {
        let loader = ProductDetailsLoader(client: client, itemsPersistence: itemsPersistence)
        loader.delayBetweenProducts = .zero
        loader.retryDelay = .zero
        return loader
    }

    private func makeProduct(id: Int) -> EnjoeiProduct {
        EnjoeiProduct(
            id: id,
            title: "produto \(id)",
            path: "produto-\(id)",
            photoPublicID: nil,
            currentPrice: 100,
            originalPrice: 100
        )
    }

    private func makeTemplate(description: String) -> ProductTemplate {
        EnjoeiFixtures.productTemplate(description: description)
    }

    @Test("busca a descrição de cada produto, persiste e guarda em fetchedDescriptions")
    func buscaADescricaoDeCadaProduto() async {
        let client = StubEnjoeiClient(templatesByProductID: [
            1: makeTemplate(description: "descrição do produto 1"),
            2: makeTemplate(description: "descrição do produto 2")
        ])
        let persistence = InMemoryMegaphoneItemsPersistence()
        let loader = makeLoader(client: client, itemsPersistence: persistence)

        loader.fetchAll(products: [makeProduct(id: 1), makeProduct(id: 2)])
        await waitUntil { loader.phase == .finished }

        #expect(persistence.loadItems().first { $0.id == 1 }?.product.description == "descrição do produto 1")
        #expect(persistence.loadItems().first { $0.id == 2 }?.product.description == "descrição do produto 2")
        #expect(loader.fetchedDescriptions == [1: "descrição do produto 1", 2: "descrição do produto 2"])
        #expect(await client.requestedTemplateIDs == [1, 2])
    }

    /// Diferente do fluxo antigo (botão na tela de detalhe, que exigia a lista já carregada): a
    /// tela de comparação busca produtos frescos direto da rede, então o produto pode não ter
    /// registro nenhum persistido ainda — `upsertDescription` (ver
    /// `SwiftDataMegaphoneItemsPersistenceTests`) cria o registro nesse caso.
    @Test("persiste mesmo sem nenhum produto salvo antes — cria o registro (upsert)")
    func persisteSemProdutoSalvoAntes() async {
        let client = StubEnjoeiClient(templatesByProductID: [1: makeTemplate(description: "descrição 1")])
        let persistence = InMemoryMegaphoneItemsPersistence()
        #expect(persistence.loadItems().isEmpty)
        let loader = makeLoader(client: client, itemsPersistence: persistence)

        loader.fetchAll(products: [makeProduct(id: 1)])
        await waitUntil { loader.phase == .finished }

        #expect(persistence.loadItems().count == 1)
        #expect(persistence.loadItems().first?.product.description == "descrição 1")
    }

    @Test("avisa onDescriptionFetched a cada produto que responde")
    func avisaOnDescriptionFetched() async {
        let client = StubEnjoeiClient(templatesByProductID: [1: makeTemplate(description: "descrição 1")])
        let persistence = InMemoryMegaphoneItemsPersistence()
        let loader = makeLoader(client: client, itemsPersistence: persistence)
        var fetched: [(productID: Int, description: String)] = []
        loader.onDescriptionFetched = { fetched.append(($0, $1)) }

        loader.fetchAll(products: [makeProduct(id: 1)])
        await waitUntil { loader.phase == .finished }

        #expect(fetched.count == 1)
        #expect(fetched.first?.productID == 1)
        #expect(fetched.first?.description == "descrição 1")
    }

    @Test("produto sem template configurado falha isolado — não trava os demais")
    func produtoSemTemplateNaoTravaOsDemais() async {
        // Só o produto 2 tem template combinado — o 1 (sem entrada) falha com `.unexpectedResponse`.
        let client = StubEnjoeiClient(templatesByProductID: [2: makeTemplate(description: "descrição 2")])
        let persistence = InMemoryMegaphoneItemsPersistence()
        let loader = makeLoader(client: client, itemsPersistence: persistence)

        loader.fetchAll(products: [makeProduct(id: 1), makeProduct(id: 2)])
        await waitUntil { loader.phase == .finished }

        #expect(persistence.loadItems().first { $0.id == 1 }?.product.description == nil)
        #expect(persistence.loadItems().first { $0.id == 2 }?.product.description == "descrição 2")
        // O 1 é tentado de novo uma vez antes de desistir.
        #expect(await client.requestedTemplateIDs == [1, 1, 2])
    }

    @Test("pula produtos que já têm descrição salva localmente")
    func pulaProdutosQueJaTemDescricao() async {
        let client = StubEnjoeiClient(templatesByProductID: [2: makeTemplate(description: "descrição 2 nova")])
        let persistence = InMemoryMegaphoneItemsPersistence()
        persistence.upsertDescription(for: makeProduct(id: 1), description: "descrição 1 já salva")
        let loader = makeLoader(client: client, itemsPersistence: persistence)

        loader.fetchAll(products: [makeProduct(id: 1), makeProduct(id: 2)])
        await waitUntil { loader.phase == .finished }

        #expect(await client.requestedTemplateIDs == [2])
        // A descrição do 1 (que nem foi pedida de novo) continua a que já estava salva.
        #expect(persistence.loadItems().first { $0.id == 1 }?.product.description == "descrição 1 já salva")
    }

    @Test("todos já têm descrição: termina na hora, sem pedir nada")
    func todosJaTemDescricaoTerminaNaHora() async {
        let client = StubEnjoeiClient()
        let persistence = InMemoryMegaphoneItemsPersistence()
        persistence.upsertDescription(for: makeProduct(id: 1), description: "já salva")
        let loader = makeLoader(client: client, itemsPersistence: persistence)

        loader.fetchAll(products: [makeProduct(id: 1)])

        #expect(loader.phase == .finished)
        #expect(await client.requestedTemplateIDs.isEmpty)
    }

    @Test("fetchAll chamado de novo enquanto já está buscando não dispara outra busca")
    func fetchAllDuploNaoDuplica() async {
        let client = StubEnjoeiClient(templatesByProductID: [1: makeTemplate(description: "descrição 1")])
        let persistence = InMemoryMegaphoneItemsPersistence()
        let loader = makeLoader(client: client, itemsPersistence: persistence)

        loader.fetchAll(products: [makeProduct(id: 1)])
        loader.fetchAll(products: [makeProduct(id: 1)])
        await waitUntil { loader.phase == .finished }

        #expect(await client.requestedTemplateIDs.count == 1)
    }

    @Test("phase reporta quantos já foram buscados, conforme avança")
    func phaseReportaProgresso() async {
        let client = StubEnjoeiClient(templatesByProductID: [
            1: makeTemplate(description: "descrição 1"),
            2: makeTemplate(description: "descrição 2")
        ])
        let persistence = InMemoryMegaphoneItemsPersistence()
        let loader = makeLoader(client: client, itemsPersistence: persistence)

        loader.fetchAll(products: [makeProduct(id: 1), makeProduct(id: 2)])

        #expect(loader.phase == .fetching(fetched: 0, total: 2))
        await waitUntil { loader.phase == .finished }
    }

    @Test("detailedCount/totalCount refletem o que está persistido, atualizados depois de cada busca")
    func detailedCountETotalCountRefletemPersistencia() async {
        let client = StubEnjoeiClient(templatesByProductID: [2: makeTemplate(description: "descrição 2")])
        let persistence = InMemoryMegaphoneItemsPersistence()
        persistence.upsertDescription(for: makeProduct(id: 1), description: "já salva")
        let loader = makeLoader(client: client, itemsPersistence: persistence)

        #expect(loader.detailedCount == 1)
        #expect(loader.totalCount == 1)

        loader.fetchAll(products: [makeProduct(id: 1), makeProduct(id: 2)])
        await waitUntil { loader.phase == .finished }

        #expect(loader.detailedCount == 2)
        #expect(loader.totalCount == 2)
    }

    /// Espera uma condição sem prender o teste pra sempre se algo der errado.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<10_000 where !condition() {
            await Task.yield()
        }
    }

    // MARK: - fetchDetails (comparação)

    private func photoTemplate(photos: [(id: String, position: Int)], size: String? = "17") -> ProductTemplate {
        ProductTemplate(
            title: "anel", description: "anel prata", brand: "vivara", used: false, price: 10_000, originalPrice: 10_000,
            weight: "0.3", quantity: 1, category: .init(id: 327), size: size,
            shipping: .init(type: "charge_by_weight", hasInsurance: true),
            photos: photos.map { ProductTemplate.Photo(imagePublicID: $0.id, position: $0.position) },
            originPlanID: 1, smartPrice: nil
        )
    }

    private func makeDetailsLoader(client: StubEnjoeiClient, details: InMemoryProductListingDetailsPersistence) -> ProductDetailsLoader {
        let loader = ProductDetailsLoader(client: client, itemsPersistence: InMemoryMegaphoneItemsPersistence(), detailsPersistence: details)
        loader.delayBetweenProducts = .zero
        loader.retryDelay = .zero
        return loader
    }

    @Test("fetchDetails ordena as fotos pela posição do template e guarda tudo (capa, categoria, tamanho, descrição)")
    func fetchDetailsOrdenaEGuarda() async {
        let client = StubEnjoeiClient(templatesByProductID: [
            1: photoTemplate(photos: [("terceira", 2), ("capa", 0), ("segunda", 1)])
        ])
        let persistence = InMemoryProductListingDetailsPersistence()
        let loader = makeDetailsLoader(client: client, details: persistence)
        let product = EnjoeiProduct(id: 1, title: "anel", path: "anel-1", photoPublicID: "capa", currentPrice: 100, originalPrice: 100)
        let fetchedAt = Date(timeIntervalSince1970: 1_000)

        let report = await loader.fetchDetails(for: [product], now: { fetchedAt })

        let details = report.details[1]
        #expect(details?.photoPublicIDs == ["capa", "segunda", "terceira"])
        #expect(details?.coverPublicID == "capa")
        #expect(details?.categoryID == 327)
        #expect(details?.size == "17")
        #expect(details?.description == "anel prata")
        #expect(details?.fetchedAt == fetchedAt)
        #expect(report.failures.isEmpty)
        #expect(!report.wasCancelled)
        #expect(persistence.stored[1] == details)
        #expect(loader.storedDetails(for: [1, 2]) == [1: details].compactMapValues { $0 })
        #expect(loader.fetchedDescriptions[1] == "anel prata")
    }

    @Test("fetchDetails tenta de novo um template que falhou e segue quando responde")
    func fetchDetailsTentaDeNovo() async {
        let client = StubEnjoeiClient(templatesByProductID: [1: photoTemplate(photos: [("capa", 0)])])
        await client.setTemplateFailures(1)
        let loader = makeDetailsLoader(client: client, details: InMemoryProductListingDetailsPersistence())

        let report = await loader.fetchDetails(for: [makeProduct(id: 1)])

        #expect(report.details[1] != nil)
        #expect(report.failures.isEmpty)
        #expect(await client.requestedTemplateIDs == [1, 1])
    }

    @Test("fetchDetails não insiste com sessão caída: falha na primeira e diz por quê")
    func fetchDetailsSessaoCaida() async {
        let client = StubEnjoeiClient(templateError: .notAuthenticated)
        let loader = makeDetailsLoader(client: client, details: InMemoryProductListingDetailsPersistence())

        let report = await loader.fetchDetails(for: [makeProduct(id: 1), makeProduct(id: 2)])

        #expect(report.details.isEmpty)
        #expect(Set(report.failures.keys) == [1, 2])
        #expect(await client.requestedTemplateIDs == [1, 2])
    }

    @Test("fetchDetails cancelado no meio devolve o que já chegou e marca como cancelado")
    func fetchDetailsCancelado() async throws {
        let client = StubEnjoeiClient(templatesByProductID: [
            1: photoTemplate(photos: [("um", 0)]),
            2: photoTemplate(photos: [("dois", 0)]),
            3: photoTemplate(photos: [("três", 0)])
        ])
        let persistence = InMemoryProductListingDetailsPersistence()
        let loader = makeDetailsLoader(client: client, details: persistence)
        loader.delayBetweenProducts = .milliseconds(300)
        let products = [makeProduct(id: 1), makeProduct(id: 2), makeProduct(id: 3)]

        let task = Task { await loader.fetchDetails(for: products) }
        while await client.requestedTemplateIDs.isEmpty {
            try await Task.sleep(for: .milliseconds(5))
        }
        task.cancel()
        let report = await task.value

        #expect(report.wasCancelled)
        #expect(report.details.keys.sorted() == [1])
        // O que chegou antes de parar ficou salvo — continuar não pede de novo.
        #expect(persistence.stored.keys.sorted() == [1])
        #expect(report.failures.isEmpty)
        #expect(!loader.isRunning)
    }
}
