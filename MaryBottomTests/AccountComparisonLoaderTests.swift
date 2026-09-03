import Foundation
import Testing
@testable import MaryBottom

@Suite("carregador da comparação entre duas contas")
struct AccountComparisonLoaderTests {
    private func makeAccount(id: EnjoeiAccountID = EnjoeiAccountID(), client: StubEnjoeiClient) -> AccountSession {
        AccountSession(
            id: id,
            user: .stub,
            dependencies: AccountDependencies(client: client, sessionClearer: FakeSessionClearer(), webView: nil)
        )
    }

    @Test("mesmo com o runner já carregado, comparar busca de novo — não reaproveita a lista, que pode estar desatualizada")
    func buscaDeNovoMesmoJaCarregado() async {
        let title = "colar curto prata 925 zircônia branca"
        let clientA = StubEnjoeiClient(pages: [
            // Primeira página: consumida pelo carregamento manual do runner abaixo, simulando um
            // estado velho na conta (produto id 1).
            StoreProductsPage(products: [EnjoeiFixtures.product(id: 1, title: title)], total: 1, endCursor: nil),
            // Segunda página: o que o servidor devolve agora, com um produto novo (id 99) — como se
            // tivesse sido ativado/editado depois do carregamento manual.
            StoreProductsPage(products: [EnjoeiFixtures.product(id: 99, title: title)], total: 1, endCursor: nil)
        ])
        let accountA = makeAccount(client: clientA)
        accountA.runner.load(sellerID: 1)
        await accountA.runner.waitUntilFinished()
        #expect(accountA.runner.items.map(\.id) == [1])

        let clientB = StubEnjoeiClient(pages: [
            StoreProductsPage(products: [EnjoeiFixtures.product(id: 2, title: title)], total: 1, endCursor: nil)
        ])
        let accountB = makeAccount(client: clientB)

        let loader = AccountComparisonLoader()
        loader.compare(accountA: accountA, accountB: accountB)
        await loader.waitUntilFinished()

        // "comparar" é um pedido explícito de estado atual — precisa buscar de novo, não reaproveitar
        // `runner.items`, senão um produto ativado/editado depois do carregamento anterior nunca
        // apareceria na comparação.
        #expect(await clientA.requestedCursors.count == 2)

        guard case .finished(let result) = loader.phase else {
            Issue.record("esperava .finished, veio \(loader.phase)")
            return
        }
        // Casou com o produto 99 (buscado agora pela comparação), não o 1 (que ficou só na lista
        // velha do runner).
        #expect(result.matches.map(\.productA.id) == [99])
        #expect(result.matches.map(\.productB.id) == [2])
    }

    @Test("comparar não consulta exposição — isso é coisa do megafone e deixaria a comparação lenta à toa")
    func naoConsultaExposicao() async {
        let clientA = StubEnjoeiClient(pages: [EnjoeiFixtures.page(ids: [1], endCursor: nil)])
        let accountA = makeAccount(client: clientA)
        let clientB = StubEnjoeiClient(pages: [EnjoeiFixtures.page(ids: [2], endCursor: nil)])
        let accountB = makeAccount(client: clientB)

        let loader = AccountComparisonLoader()
        loader.compare(accountA: accountA, accountB: accountB)
        await loader.waitUntilFinished()

        #expect(await clientA.requestedExposureBatches.isEmpty)
        #expect(await clientB.requestedExposureBatches.isEmpty)
    }

    @Test("conta sem produtos carregados busca sozinha antes de comparar")
    func buscaSozinhoQuandoVazio() async {
        let clientA = StubEnjoeiClient(pages: [
            EnjoeiFixtures.page(ids: [1], endCursor: nil)
        ])
        let accountA = makeAccount(client: clientA)
        let clientB = StubEnjoeiClient(pages: [
            EnjoeiFixtures.page(ids: [2], endCursor: nil)
        ])
        let accountB = makeAccount(client: clientB)

        #expect(accountA.runner.items.isEmpty)
        #expect(accountB.runner.items.isEmpty)

        let loader = AccountComparisonLoader()
        loader.compare(accountA: accountA, accountB: accountB)
        await loader.waitUntilFinished()

        #expect(await clientA.requestedCursors.count == 1)
        #expect(await clientB.requestedCursors.count == 1)
        guard case .finished = loader.phase else {
            Issue.record("esperava .finished, veio \(loader.phase)")
            return
        }
    }

    @Test("cada comparação tem um id diferente, mesmo comparando o mesmo par de contas de novo")
    func cadaComparacaoTemIDDiferente() async {
        let clientA = StubEnjoeiClient(pages: [
            EnjoeiFixtures.page(ids: [1], endCursor: nil),
            EnjoeiFixtures.page(ids: [1], endCursor: nil)
        ])
        let accountA = makeAccount(client: clientA)
        let clientB = StubEnjoeiClient(pages: [
            EnjoeiFixtures.page(ids: [2], endCursor: nil),
            EnjoeiFixtures.page(ids: [2], endCursor: nil)
        ])
        let accountB = makeAccount(client: clientB)
        let loader = AccountComparisonLoader()

        loader.compare(accountA: accountA, accountB: accountB)
        await loader.waitUntilFinished()
        guard case .finished(let firstResult) = loader.phase else {
            Issue.record("esperava .finished, veio \(loader.phase)")
            return
        }

        // Comparar de novo, mesmo par de contas — a tela usa esse id (`.id(result.id)`) pra saber
        // quando zerar busca/filtro/seleção de `ComparisonResultView`; sem um id novo aqui, uma
        // seleção feita antes de comparar de novo sobreviveria pro resultado novo.
        loader.compare(accountA: accountA, accountB: accountB)
        await loader.waitUntilFinished()
        guard case .finished(let secondResult) = loader.phase else {
            Issue.record("esperava .finished, veio \(loader.phase)")
            return
        }

        #expect(firstResult.id != secondResult.id)
    }

    @Test("phase passa por loadingProducts antes de finished")
    func phasePassaPorLoadingProducts() async {
        let clientA = StubEnjoeiClient(pages: [EnjoeiFixtures.page(ids: [1], endCursor: nil)])
        let accountA = makeAccount(client: clientA)
        let clientB = StubEnjoeiClient(pages: [EnjoeiFixtures.page(ids: [2], endCursor: nil)])
        let accountB = makeAccount(client: clientB)

        let loader = AccountComparisonLoader()
        loader.compare(accountA: accountA, accountB: accountB)

        // O phase muda pra loadingProducts na hora, antes de qualquer await — sincronamente.
        #expect(loader.phase == .loadingProducts(loaded: 0, total: 0))

        await loader.waitUntilFinished()

        guard case .finished = loader.phase else {
            Issue.record("esperava .finished, veio \(loader.phase)")
            return
        }
    }
}
