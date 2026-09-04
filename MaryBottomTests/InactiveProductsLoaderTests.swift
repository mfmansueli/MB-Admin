import Foundation
import Testing
@testable import MaryBottom

@Suite("carregamento de produtos inativos")
struct InactiveProductsLoaderTests {
    /// Sem espera entre páginas, os testes não ficam presos ao ritmo real do app.
    private func makeLoader(
        client: StubEnjoeiClient,
        itemsPersistence: InactiveProductsPersisting = InMemoryInactiveProductsPersistence()
    ) -> InactiveProductsLoader {
        let loader = InactiveProductsLoader(client: client, itemsPersistence: itemsPersistence)
        loader.delayBetweenPages = .zero
        return loader
    }

    private func makeProduct(id: Int) -> InactiveProduct {
        InactiveProduct(
            id: id,
            path: "produto-\(id)",
            title: "produto \(id)",
            price: 100,
            photoPublicID: nil,
            inactiveSince: "01/01/2026"
        )
    }

    @Test("busca todas as páginas em sequência e acumula os itens")
    func buscaTodasAsPaginas() async {
        let client = StubEnjoeiClient(inactivePagesByNumber: [
            1: InactiveProductsPage(products: [makeProduct(id: 1), makeProduct(id: 2)], maxPage: 3),
            2: InactiveProductsPage(products: [makeProduct(id: 3)], maxPage: 3),
            3: InactiveProductsPage(products: [makeProduct(id: 4)], maxPage: 3)
        ])
        let loader = makeLoader(client: client)

        loader.load()
        await waitUntil { loader.phase == .finished }

        #expect(loader.items.map(\.id) == [1, 2, 3, 4])
        #expect(await client.requestedInactivePages == [1, 2, 3])
    }

    @Test("loja sem inativos termina com lista vazia, sem erro")
    func lojaSemInativos() async {
        let client = StubEnjoeiClient(inactivePagesByNumber: [1: InactiveProductsPage(products: [], maxPage: 1)])
        let loader = makeLoader(client: client)

        loader.load()
        await waitUntil { loader.phase == .finished }

        #expect(loader.items.isEmpty)
    }

    @Test("erro numa página vira falha, sem travar")
    func erroViraFalha() async {
        let client = StubEnjoeiClient(inactiveProductsError: .http(status: 500, message: "o enjoei caiu"))
        let loader = makeLoader(client: client)

        loader.load()
        await waitUntil {
            if case .failed = loader.phase { return true }
            return false
        }

        #expect(loader.phase == .failed("o enjoei caiu"))
    }

    @Test("load chamado de novo enquanto já está carregando não dispara outra busca")
    func loadDuploNaoDuplica() async {
        let client = StubEnjoeiClient(inactivePagesByNumber: [1: InactiveProductsPage(products: [], maxPage: 1)])
        let loader = makeLoader(client: client)

        loader.load()
        loader.load()
        await waitUntil { loader.phase == .finished }

        #expect(await client.requestedInactivePages.count == 1)
    }

    @Test("guarda a lista carregada na persistência")
    func guardaListaNaPersistencia() async {
        let persistence = InMemoryInactiveProductsPersistence()
        let client = StubEnjoeiClient(inactivePagesByNumber: [
            1: InactiveProductsPage(products: [makeProduct(id: 1)], maxPage: 1)
        ])
        let loader = makeLoader(client: client, itemsPersistence: persistence)

        loader.load()
        await waitUntil { loader.phase == .finished }

        #expect(persistence.loadItems().map(\.id) == [1])
    }

    @Test("um loader novo com a mesma persistência recupera a lista sem buscar de novo")
    func loaderNovoRecuperaListaPersistida() async {
        let persistence = InMemoryInactiveProductsPersistence()
        let client = StubEnjoeiClient(inactivePagesByNumber: [
            1: InactiveProductsPage(products: [makeProduct(id: 1)], maxPage: 1)
        ])
        let firstLoader = makeLoader(client: client, itemsPersistence: persistence)
        firstLoader.load()
        await waitUntil { firstLoader.phase == .finished }

        let secondLoader = makeLoader(client: client, itemsPersistence: persistence)

        #expect(secondLoader.items.map(\.id) == [1])
        #expect(await client.requestedInactivePages.count == 1)
    }

    @Test("grava cada página assim que ela chega, não só no final")
    func gravaCadaPaginaAssimQueChega() async {
        let persistence = InMemoryInactiveProductsPersistence()
        let client = StubEnjoeiClient(inactivePagesByNumber: [
            1: InactiveProductsPage(products: [makeProduct(id: 1)], maxPage: 2),
            2: InactiveProductsPage(products: [makeProduct(id: 2)], maxPage: 2)
        ])
        let loader = makeLoader(client: client, itemsPersistence: persistence)

        loader.load()
        await waitUntil { persistence.loadItems().map(\.id) == [1] }
        await waitUntil { loader.phase == .finished }

        #expect(persistence.loadItems().map(\.id) == [1, 2])
    }

    @Test("falha logo na primeira página não apaga o cache persistido de um carregamento anterior")
    func falhaNaPrimeiraPaginaNaoApagaCacheAntigo() async {
        let persistence = InMemoryInactiveProductsPersistence()
        persistence.saveItems([makeProduct(id: 1)])
        let client = StubEnjoeiClient(inactiveProductsError: .http(status: 500, message: "o enjoei caiu"))
        let loader = makeLoader(client: client, itemsPersistence: persistence)

        loader.load()
        await waitUntil {
            if case .failed = loader.phase { return true }
            return false
        }

        #expect(persistence.loadItems().map(\.id) == [1])
    }

    @Test("search delega pra persistência")
    func searchDelegaParaPersistencia() async {
        let persistence = InMemoryInactiveProductsPersistence()
        let client = StubEnjoeiClient(inactivePagesByNumber: [
            1: InactiveProductsPage(products: [makeProduct(id: 1), makeProduct(id: 2)], maxPage: 1)
        ])
        let loader = makeLoader(client: client, itemsPersistence: persistence)

        loader.load()
        await waitUntil { loader.phase == .finished }

        #expect(loader.search(matching: "produto 1").map(\.id) == [1])
    }

    /// Espera uma condição sem prender o teste pra sempre se algo der errado.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<10_000 where !condition() {
            await Task.yield()
        }
    }
}
