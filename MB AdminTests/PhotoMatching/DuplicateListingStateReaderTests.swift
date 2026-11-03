import Foundation
import Testing
@testable import MB_Admin

/// O estado dos anúncios repetidos lido da fila de ações de verdade — com um client falso, nunca
/// uma loja real.
@Suite("estado dos anúncios repetidos na fila de ações")
struct DuplicateListingStateReaderTests {
    typealias Fixtures = ComparisonFixtures

    private func makeAccount(_ client: StubEnjoeiClient) -> AccountSession {
        AccountSession(
            id: EnjoeiAccountID(),
            user: EnjoeiUser(id: Fixtures.sellerA, nickname: "antonia", name: "antonia", avatarPublicID: nil, availableProductsCount: nil),
            dependencies: AccountDependencies(client: client, sessionClearer: FakeSessionClearer(), webView: nil)
        )
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<10_000 where !condition() {
            await Task.yield()
        }
    }

    @Test("o primeiro sai da fila e é apagado; o segundo espera a vez; o histórico lembra os apagados")
    func filaEHistorico() async {
        let client = StubEnjoeiClient()
        let account = makeAccount(client)
        let products = [1, 2, 3, 4].map { Fixtures.product($0, title: "anel", cover: "a\($0)") }
        let group = Fixtures.duplicates(Fixtures.sellerA, products)
        let history = InMemoryPostHistoryPersistence()
        // Apagado numa abertura anterior do app.
        history.insert(PostHistoryEntry(
            id: UUID(), product: products[3], kind: .delete,
            sourceAccountID: account.id, sourceAccountName: "antonia",
            destinationAccountID: account.id, destinationAccountName: "antonia",
            outcome: .succeeded, completedAt: .now
        ))
        // Intervalo bem maior que o teste: o segundo item fica esperando a vez.
        let queue = PostQueue(poster: CrossAccountPoster(), accountsProvider: { [account] }, interval: 60, historyPersistence: history)

        queue.enqueueDelete(product: products[1], account: account)
        queue.enqueueDelete(product: products[2], account: account)
        await waitUntil { account.runner.deleteStatuses[2] == .succeeded }

        var reader = DuplicateListingStateReader(queue: queue)
        let states = reader.states(of: [group], account: account)
        #expect(states == [1: .listed, 2: .deleted, 3: .queued, 4: .deleted])
        #expect(await client.deleteProductCalls.map(\.productID) == [2])
        // Sobra um na loja: nada mais pra apagar neste grupo.
        #expect(!DuplicateCleanup.isSelectable(group, states: states))
    }

    @Test("sem grupo nenhum, nem lê a fila")
    func semGrupo() {
        let account = makeAccount(StubEnjoeiClient())
        var reader = DuplicateListingStateReader(queue: PostQueue(poster: CrossAccountPoster(), accountsProvider: { [account] }))
        #expect(reader.states(of: [], account: account).isEmpty)
    }
}
