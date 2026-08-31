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

    @Test("com as duas contas já carregadas, compara direto sem buscar de novo")
    func naoBuscaDeNovoQuandoJaCarregado() async {
        // Páginas manuais, com títulos controlados, pra confirmar que o casamento saiu certo.
        let clientA = StubEnjoeiClient(pages: [
            StoreProductsPage(
                products: [EnjoeiFixtures.product(id: 1, title: "colar curto prata 925 zircônia branca")],
                total: 1,
                endCursor: nil
            )
        ])
        let accountA = makeAccount(client: clientA)
        accountA.runner.load(sellerID: 1)
        await accountA.runner.waitUntilFinished()

        let clientB = StubEnjoeiClient(pages: [
            StoreProductsPage(
                products: [EnjoeiFixtures.product(id: 2, title: "colar curto prata 925 zircônia")],
                total: 1,
                endCursor: nil
            )
        ])
        let accountB = makeAccount(client: clientB)
        accountB.runner.load(sellerID: 2)
        await accountB.runner.waitUntilFinished()

        #expect(await clientA.requestedCursors.count == 1)
        #expect(await clientB.requestedCursors.count == 1)

        let loader = AccountComparisonLoader()
        loader.compare(accountA: accountA, accountB: accountB)
        await loader.waitUntilFinished()

        // As duas já tinham produto carregado — comparar não deve ter disparado outra busca.
        #expect(await clientA.requestedCursors.count == 1)
        #expect(await clientB.requestedCursors.count == 1)

        guard case .finished(let result) = loader.phase else {
            Issue.record("esperava .finished, veio \(loader.phase)")
            return
        }
        #expect(result.matches.map(\.productA.id) == [1])
        #expect(result.matches.map(\.productB.id) == [2])
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

    @Test("phase passa por loadingProducts antes de finished")
    func phasePassaPorLoadingProducts() async {
        let clientA = StubEnjoeiClient(pages: [EnjoeiFixtures.page(ids: [1], endCursor: nil)])
        let accountA = makeAccount(client: clientA)
        let clientB = StubEnjoeiClient(pages: [EnjoeiFixtures.page(ids: [2], endCursor: nil)])
        let accountB = makeAccount(client: clientB)

        let loader = AccountComparisonLoader()
        loader.compare(accountA: accountA, accountB: accountB)

        // O phase muda pra loadingProducts na hora, antes de qualquer await — sincronamente.
        #expect(loader.phase == .loadingProducts)

        await loader.waitUntilFinished()

        guard case .finished = loader.phase else {
            Issue.record("esperava .finished, veio \(loader.phase)")
            return
        }
    }
}
