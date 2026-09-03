import Foundation
import Testing
@testable import MaryBottom

@Suite("carregamento e ativação de produtos sem preço esperto")
struct SmartPriceProductsLoaderTests {
    /// Sem espera entre páginas nem entre ativações, os testes não ficam presos ao ritmo real do app.
    private func makeLoader(
        client: StubEnjoeiClient,
        accountID: EnjoeiAccountID = UUID(),
        itemsPersistence: SmartPriceProductsPersisting = InMemorySmartPriceProductsPersistence()
    ) -> SmartPriceProductsLoader {
        let loader = SmartPriceProductsLoader(client: client, accountID: accountID, itemsPersistence: itemsPersistence)
        loader.delayBetweenPages = .zero
        loader.delayBetweenActivations = .zero
        return loader
    }

    private func makeProduct(id: Int, blocked: Bool = false) -> SmartPriceProduct {
        SmartPriceProduct(
            id: id, price: 100, minPrice: 70, maxPrice: 150, blocked: blocked, smartPriceEnabled: false,
            statusText: "preço atual", statusColor: "#8F8F8F", photoPublicID: nil
        )
    }

    // MARK: - carregamento

    @Test("busca todas as páginas em sequência e acumula os itens, sempre pela aba tab=false")
    func buscaTodasAsPaginas() async {
        let client = StubEnjoeiClient(smartPricePagesByNumber: [
            1: SmartPriceProductsPage(products: [makeProduct(id: 1), makeProduct(id: 2)], currentPage: 1, totalPages: 3),
            2: SmartPriceProductsPage(products: [makeProduct(id: 3)], currentPage: 2, totalPages: 3),
            3: SmartPriceProductsPage(products: [makeProduct(id: 4)], currentPage: 3, totalPages: 3)
        ])
        let loader = makeLoader(client: client)

        loader.load()
        await waitUntil { loader.phase == .finished }

        #expect(loader.items.map(\.id) == [1, 2, 3, 4])
        #expect(await client.requestedSmartPricePages.map(\.page) == [1, 2, 3])
        #expect(await client.requestedSmartPricePages.allSatisfy { $0.tab == false })
    }

    @Test("loja toda com preço esperto termina com lista vazia, sem erro")
    func lojaSemItens() async {
        let client = StubEnjoeiClient(smartPricePagesByNumber: [
            1: SmartPriceProductsPage(products: [], currentPage: 1, totalPages: 1)
        ])
        let loader = makeLoader(client: client)

        loader.load()
        await waitUntil { loader.phase == .finished }

        #expect(loader.items.isEmpty)
    }

    @Test("erro numa página vira falha, sem travar")
    func erroViraFalha() async {
        let client = StubEnjoeiClient(smartPriceProductsError: .http(status: 500, message: "o enjoei caiu"))
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
        let client = StubEnjoeiClient(smartPricePagesByNumber: [
            1: SmartPriceProductsPage(products: [], currentPage: 1, totalPages: 1)
        ])
        let loader = makeLoader(client: client)

        loader.load()
        loader.load()
        await waitUntil { loader.phase == .finished }

        #expect(await client.requestedSmartPricePages.count == 1)
    }

    @Test("guarda a lista carregada na persistência, e um loader novo recupera sem buscar de novo")
    func guardaEPersisteEntreAberturas() async {
        let accountID = EnjoeiAccountID()
        let persistence = InMemorySmartPriceProductsPersistence()
        let client = StubEnjoeiClient(smartPricePagesByNumber: [
            1: SmartPriceProductsPage(products: [makeProduct(id: 1)], currentPage: 1, totalPages: 1)
        ])
        let firstLoader = makeLoader(client: client, accountID: accountID, itemsPersistence: persistence)
        firstLoader.load()
        await waitUntil { firstLoader.phase == .finished }

        #expect(persistence.loadItems(accountID: accountID).map(\.id) == [1])

        let secondLoader = makeLoader(client: client, accountID: accountID, itemsPersistence: persistence)

        #expect(secondLoader.items.map(\.id) == [1])
        #expect(await client.requestedSmartPricePages.count == 1)
    }

    // MARK: - ativação

    @Test("ativa um produto avulso e marca sucesso")
    func ativaUmProdutoAvulso() async {
        let client = StubEnjoeiClient()
        let loader = makeLoader(client: client)

        loader.activate(productIDs: [1])
        await waitUntil { loader.activationStatuses[1] == .succeeded }

        #expect(await client.setSmartPriceCalls.map(\.productID) == [1])
        #expect(await client.setSmartPriceCalls.map(\.activate) == [true])
    }

    @Test("ativa vários produtos em sequência, respeitando o intervalo entre um e o próximo")
    func ativaVariosEmSequencia() async {
        let client = StubEnjoeiClient()
        let loader = makeLoader(client: client)

        loader.activate(productIDs: [1, 2, 3])
        await waitUntil {
            loader.activationStatuses[1] == .succeeded
                && loader.activationStatuses[2] == .succeeded
                && loader.activationStatuses[3] == .succeeded
        }

        #expect(await client.setSmartPriceCalls.map(\.productID) == [1, 2, 3])
    }

    @Test("erro num produto vira falha, sem travar os outros da mesma leva")
    func erroNumProdutoNaoTravaOsOutros() async {
        let client = StubEnjoeiClient(setSmartPriceFailuresByProductID: [
            2: .http(status: 422, message: "bloqueado")
        ])
        let loader = makeLoader(client: client)

        loader.activate(productIDs: [1, 2, 3])
        await waitUntil {
            loader.activationStatuses[1] == .succeeded
                && loader.activationStatuses[3] == .succeeded
                && loader.activationStatuses[2] != .pending
                && loader.activationStatuses[2] != .megaphoning
        }

        #expect(loader.activationStatuses[2] == .failed("bloqueado"))
    }

    @Test("token CSRF recusado é renovado e a ativação tenta de novo com o token novo")
    func tokenRecusadoRenovaEETentaDeNovo() async {
        let client = StubEnjoeiClient(csrfRejectionsRemaining: 1)
        let loader = makeLoader(client: client)

        loader.activate(productIDs: [1])
        await waitUntil { loader.activationStatuses[1] == .succeeded }

        #expect(await client.setSmartPriceCalls.map(\.productID) == [1, 1])
        #expect(await client.csrfCallCount == 2)
    }

    @Test("ativar um produto já concluído com sucesso não chama a rota de novo")
    func naoReativaProdutoJaConcluido() async {
        let client = StubEnjoeiClient()
        let loader = makeLoader(client: client)

        loader.activate(productIDs: [1])
        await waitUntil { loader.activationStatuses[1] == .succeeded }

        loader.activate(productIDs: [1])
        // Sem outra chamada disparada, não tem o que esperar além de deixar o loop de eventos
        // rodar uma vez — se tivesse enfileirado de novo, isso já teria acontecido.
        await Task.yield()

        #expect(await client.setSmartPriceCalls.count == 1)
    }

    @Test("uma segunda leva chamada enquanto a primeira ainda está ativando entra na mesma fila")
    func segundaLevaEntraNaFila() async {
        let client = StubEnjoeiClient()
        let loader = makeLoader(client: client)

        loader.activate(productIDs: [1])
        loader.activate(productIDs: [2])
        await waitUntil {
            loader.activationStatuses[1] == .succeeded && loader.activationStatuses[2] == .succeeded
        }

        #expect(await client.setSmartPriceCalls.map(\.productID) == [1, 2])
    }

    /// Espera uma condição sem prender o teste pra sempre se algo der errado.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<10_000 where !condition() {
            await Task.yield()
        }
    }
}
