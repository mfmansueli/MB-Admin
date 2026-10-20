import Foundation
import Testing
@testable import MB_Admin

@Suite("busca de detalhes completos (descrição) de cada produto")
struct ProductDetailsLoaderTests {
    /// Sem espera entre produtos, os testes não ficam presos ao ritmo real do app.
    private func makeLoader(client: StubEnjoeiClient, itemsPersistence: MegaphoneItemsPersisting) -> ProductDetailsLoader {
        let loader = ProductDetailsLoader(client: client, itemsPersistence: itemsPersistence)
        loader.delayBetweenProducts = .zero
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
        #expect(await client.requestedTemplateIDs == [1, 2])
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
}
