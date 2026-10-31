import Foundation
import Testing
@testable import MB_Admin

@Suite("linha de postar em outra loja na row de publicados")
struct OtherStorePostStateTests {
    private let source = EnjoeiAccountID()
    private let storeB = EnjoeiAccountID()
    private let storeC = EnjoeiAccountID()

    private func item(
        productID: Int = 1,
        kind: PostQueueItem.Kind = .post,
        from sourceID: EnjoeiAccountID? = nil,
        to destinationID: EnjoeiAccountID,
        destinationName: String
    ) -> PostQueueItem {
        PostQueueItem(
            id: UUID(),
            product: EnjoeiFixtures.product(id: productID),
            kind: kind,
            sourceAccountID: sourceID ?? source,
            sourceAccountName: "antonia",
            destinationAccountID: destinationID,
            destinationAccountName: destinationName
        )
    }

    @Test("sem postagem pra outra loja, não há linha — repostar, apagar e inativar não contam")
    func semPostagemParaOutraLoja() {
        let items = [
            item(to: source, destinationName: "antonia"),
            item(kind: .delete, to: source, destinationName: "antonia"),
            item(kind: .inactivate, to: source, destinationName: "antonia"),
            item(productID: 2, to: storeB, destinationName: "loja B")
        ]

        let state = OtherStorePostState.latest(productID: 1, sourceAccountID: source, in: items) { _ in .pending }

        #expect(state == nil)
    }

    @Test("vale a postagem mais recente do produto")
    func valeAMaisRecente() {
        let items = [
            item(to: storeB, destinationName: "loja B"),
            item(to: storeC, destinationName: "loja C")
        ]

        let state = OtherStorePostState.latest(productID: 1, sourceAccountID: source, in: items) { _ in .pending }

        #expect(state?.storeName == "loja C")
    }

    @Test("o mesmo produto vindo de outra loja não conta como desta")
    func outraOrigemNaoConta() {
        let items = [item(from: storeC, to: storeB, destinationName: "loja B")]

        let state = OtherStorePostState.latest(productID: 1, sourceAccountID: source, in: items) { _ in .pending }

        #expect(state == nil)
    }

    @Test("cada situação da fila vira um texto, um ícone e o que dá pra fazer")
    func cadaSituacao() {
        let items = [item(to: storeB, destinationName: "loja B")]
        func state(_ status: MegaphoneStatus) -> OtherStorePostState? {
            OtherStorePostState.latest(productID: 1, sourceAccountID: source, in: items) { _ in status }
        }

        #expect(state(.pending)?.text == "na fila pra loja B")
        #expect(state(.pending)?.systemImage == "clock")
        #expect(state(.megaphoning)?.text == "postando em loja B…")
        #expect(state(.megaphoning)?.isPosting == true)
        #expect(state(.succeeded)?.text == "postado em loja B")
        #expect(state(.succeeded)?.systemImage == "checkmark.circle.fill")
        #expect(state(.failed("erro 500"))?.text == "não deu pra postar em loja B")
        #expect(state(.failed("erro 500"))?.failureMessage == "erro 500")
        #expect(state(.pending)?.failureMessage == nil)
    }

    @Test("pela fila de verdade: na fila, depois postado na outra loja")
    func pelaFilaDeVerdade() async {
        let template = ProductTemplate(
            title: "produto 1",
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
            photos: [.init(imagePublicID: "foto-1", position: 0)],
            originPlanID: 1,
            smartPrice: .init(enabled: true)
        )
        let sourceAccount = makeAccount(name: "antonia", client: StubEnjoeiClient(templatesByProductID: [1: template]))
        let destination = makeAccount(name: "loja B", client: StubEnjoeiClient())
        let queue = PostQueue(
            poster: CrossAccountPoster(cooldownDuration: .zero),
            accountsProvider: { [sourceAccount, destination] },
            interval: .zero
        )
        queue.pause()

        queue.enqueue(product: EnjoeiFixtures.product(id: 1), source: sourceAccount, destination: destination)
        let queued = OtherStorePostState.latest(productID: 1, sourceAccountID: sourceAccount.id, in: queue.items, status: queue.status(for:))
        #expect(queued?.text == "na fila pra loja B")

        queue.resume()
        for _ in 0..<10_000 where queue.isRunning {
            await Task.yield()
        }
        let posted = OtherStorePostState.latest(productID: 1, sourceAccountID: sourceAccount.id, in: queue.items, status: queue.status(for:))
        #expect(posted?.text == "postado em loja B")
    }

    private func makeAccount(name: String, client: StubEnjoeiClient) -> AccountSession {
        AccountSession(
            id: EnjoeiAccountID(),
            user: EnjoeiUser(id: Int.random(in: 1...1_000_000), nickname: name, name: name, avatarPublicID: nil, availableProductsCount: nil),
            dependencies: AccountDependencies(client: client, sessionClearer: FakeSessionClearer(), webView: nil)
        )
    }
}
