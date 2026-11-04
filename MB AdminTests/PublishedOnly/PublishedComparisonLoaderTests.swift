import Foundation
import Testing
@testable import MB_Admin

/// A comparação de verdade (listagem, fotos, templates) só com o que está publicado — numa comparação
/// nova, no resultado já na tela, na comparação reaberta do disco e pela fila de ações de verdade.
@Suite("comparação só com anúncios publicados")
struct PublishedComparisonLoaderTests {
    typealias Fixtures = ComparisonFixtures

    private static let sellerA = 1001
    private static let sellerB = 2002
    private static let listedAt = Date(timeIntervalSince1970: 1_800_000_000)
    private static let ringA = DemoPhotoRenderer.jpeg(Fixtures.ring(1), side: 300, quality: 0.9)
    private static let ringB = DemoPhotoRenderer.jpeg(Fixtures.ring(1), side: 300, quality: 0.6)
    private static let pendant = DemoPhotoRenderer.jpeg(DemoPhotoRenderer.Spec(shape: .pendant, seed: 5), side: 300)

    /// O que "a fila e a aba inativos" sabem, mudável no meio do teste.
    @MainActor
    private final class KnownChanges {
        var byAccount: [EnjoeiAccountID: [ListingStateChange]] = [:]
    }

    private struct Setup {
        let accountA: AccountSession
        let accountB: AccountSession
        let clientA: StubEnjoeiClient
        let clientB: StubEnjoeiClient
        let photoStore = InMemoryPhotoSignatureStore()
        let decisions = InMemoryComparisonDecisionStore()

        var accounts: [AccountSession] { [accountA, accountB] }
    }

    private func makeAccount(seller: Int, client: StubEnjoeiClient) -> AccountSession {
        let account = AccountSession(
            id: EnjoeiAccountID(),
            user: EnjoeiUser(
                id: seller, nickname: "loja-\(seller)", name: seller == Self.sellerA ? "antonia" : "loja B",
                avatarPublicID: nil, availableProductsCount: nil
            ),
            dependencies: AccountDependencies(client: client, sessionClearer: FakeSessionClearer(), webView: nil)
        )
        account.productDetailsLoader.delayBetweenProducts = .zero
        account.productDetailsLoader.retryDelay = .zero
        return account
    }

    private func template(photos: [String]) -> ProductTemplate {
        ProductTemplate(
            title: "produto", description: "", brand: nil, used: false, price: 10_000, originalPrice: 10_000,
            weight: "0.3", quantity: 1, category: .init(id: 327), size: nil,
            shipping: .init(type: "charge_by_weight", hasInsurance: true),
            photos: photos.enumerated().map { ProductTemplate.Photo(imagePublicID: $1, position: $0) },
            originPlanID: 1, smartPrice: nil
        )
    }

    private func page(_ products: [EnjoeiProduct]) -> StoreProductsPage {
        StoreProductsPage(products: products, total: products.count, endCursor: nil)
    }

    private func makeClientA(user: EnjoeiUser = .stub) -> StubEnjoeiClient {
        StubEnjoeiClient(
            user: user,
            pages: [page([Fixtures.product(1, title: "anel", cover: "a1"), Fixtures.product(3, title: "pingente gota", cover: "a2")])],
            templatesByProductID: [1: template(photos: ["a1"]), 3: template(photos: ["a2"])]
        )
    }

    private func makeClientB(user: EnjoeiUser = .stub) -> StubEnjoeiClient {
        StubEnjoeiClient(user: user, pages: [page([Fixtures.product(2, title: "anel", cover: "b1")])], templatesByProductID: [2: template(photos: ["b1"])])
    }

    /// A tem o anel (1, par com o 2 de B) e o pingente (3, só em A).
    private func makeSetup() -> Setup {
        let clientA = makeClientA()
        let clientB = makeClientB()
        return Setup(
            accountA: makeAccount(seller: Self.sellerA, client: clientA),
            accountB: makeAccount(seller: Self.sellerB, client: clientB),
            clientA: clientA,
            clientB: clientB
        )
    }

    private func services(_ setup: Setup) -> ComparisonServices {
        .inMemory(
            fetcher: StubPhotoFetcher(photos: ["a1": Self.ringA ?? Data(), "b1": Self.ringB ?? Data(), "a2": Self.pendant ?? Data()]),
            store: setup.photoStore,
            decisions: setup.decisions
        )
    }

    @MainActor
    private func makeLoader(_ known: KnownChanges, snapshots: ComparisonSnapshotStoring = InMemoryComparisonSnapshotStore()) -> AccountComparisonLoader {
        let loader = AccountComparisonLoader(snapshots: snapshots)
        loader.now = { Self.listedAt }
        loader.listingStateChanges = { account in known.byAccount[account.id] ?? [] }
        return loader
    }

    private func finished(_ loader: AccountComparisonLoader) -> AccountComparisonResult? {
        guard case .finished(let result) = loader.phase else {
            Issue.record("esperava .finished, veio \(loader.phase)")
            return nil
        }
        return result
    }

    private func change(_ id: Int, _ state: ListingStateChange.State, minutes: Double) -> ListingStateChange {
        ListingStateChange(productID: id, state: state, date: Self.listedAt.addingTimeInterval(minutes * 60))
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<2_000 where !condition() {
            try? await Task.sleep(for: .milliseconds(2))
        }
    }

    // MARK: - Comparação nova

    @Test("produto inativado pouco antes de comparar não entra: nem como ausente, nem o template dele é buscado")
    @MainActor
    func inativadoAntesNaoEntra() async {
        let setup = makeSetup()
        let known = KnownChanges()
        // A busca da loja ainda mostra o pingente, mas a fila acabou de inativar.
        known.byAccount[setup.accountA.id] = [change(3, .inactive, minutes: -2)]
        let loader = makeLoader(known)

        loader.compare(accountA: setup.accountA, accountB: setup.accountB, services: services(setup))
        await loader.waitUntilFinished()

        let result = finished(loader)
        #expect(result?.matches.map(\.id) == ["1-2"])
        #expect(result?.possiblyMissingInB.isEmpty == true)
        #expect(result?.unverifiedA.isEmpty == true)
        #expect(result?.storeA.listingCount == 1)
        #expect(await setup.clientA.requestedTemplateIDs.contains(3) == false)
    }

    // MARK: - Resultado já na tela

    @Test("o par da outra loja foi inativado depois: sem rede, o produto vira possivelmente ausente lá")
    @MainActor
    func parInativadoDepois() async {
        let setup = makeSetup()
        let known = KnownChanges()
        let loader = makeLoader(known)
        let memory = ComparisonMatchMemory()
        loader.compare(accountA: setup.accountA, accountB: setup.accountB, services: services(setup), matchMemory: memory, checkAllDetails: true)
        await loader.waitUntilFinished()
        let original = finished(loader)
        #expect(original?.matches.map(\.id) == ["1-2"])
        let cursors = await setup.clientB.requestedCursors.count

        known.byAccount[setup.accountB.id] = [change(2, .inactive, minutes: 30)]
        await loader.refreshPublished()

        let refreshed = finished(loader)
        #expect(refreshed?.id == original?.id)
        #expect(refreshed?.revision == 1)
        #expect(refreshed?.matches.isEmpty == true)
        #expect(Set(refreshed?.possiblyMissingInB.map(\.id) ?? []) == [1, 3])
        #expect(refreshed?.possiblyMissingInA.isEmpty == true)
        #expect(refreshed?.storeB.listingCount == 0)
        // "Postar em outra loja" deixa de avisar que o anel já existe em B.
        #expect(memory.presence(of: 1, from: setup.accountA.id, to: setup.accountB.id) == .possiblyMissing)
        #expect(memory.presence(of: 2, from: setup.accountB.id, to: setup.accountA.id) == nil)
        #expect(await setup.clientB.requestedCursors.count == cursors)
    }

    @Test("sem o template do produto, perder o par vira 'não verificado' — nunca ausente sem conferir todas as fotos")
    @MainActor
    func semTemplateViraNaoVerificado() async {
        let setup = makeSetup()
        let known = KnownChanges()
        let loader = makeLoader(known)
        loader.compare(accountA: setup.accountA, accountB: setup.accountB, services: services(setup))
        await loader.waitUntilFinished()

        known.byAccount[setup.accountB.id] = [change(2, .deleted, minutes: 30)]
        await loader.refreshPublished()

        let refreshed = finished(loader)
        #expect(refreshed?.matches.isEmpty == true)
        #expect(refreshed?.possiblyMissingInB.map(\.id) == [3])
        #expect(refreshed?.unverifiedA.map(\.product.id) == [1])
    }

    @Test("nada mudou no recorte: não recalcula à toa")
    @MainActor
    func semMudancaNaoRecalcula() async {
        let setup = makeSetup()
        let known = KnownChanges()
        let loader = makeLoader(known)
        loader.compare(accountA: setup.accountA, accountB: setup.accountB, services: services(setup))
        await loader.waitUntilFinished()

        // Produto que nem estava na comparação.
        known.byAccount[setup.accountA.id] = [change(99, .inactive, minutes: 30)]
        await loader.refreshPublished()

        #expect(finished(loader)?.revision == 0)
    }

    // MARK: - Comparação reaberta do disco

    @Test("reabrir a última comparação deixa de fora o que foi apagado depois dela")
    @MainActor
    func reabrirSemOApagado() async {
        let setup = makeSetup()
        let snapshots = InMemoryComparisonSnapshotStore()
        let known = KnownChanges()
        let first = makeLoader(known, snapshots: snapshots)
        first.compare(accountA: setup.accountA, accountB: setup.accountB, services: services(setup))
        await first.waitUntilFinished()
        #expect(finished(first)?.possiblyMissingInB.map(\.id) == [3])
        await waitUntil { snapshots.snapshot != nil }
        #expect(snapshots.snapshot?.storeA.listedAt == Self.listedAt)

        known.byAccount[setup.accountA.id] = [change(3, .deleted, minutes: 60)]
        let reopened = makeLoader(known, snapshots: snapshots)
        reopened.showLastComparison(accounts: setup.accounts, services: { services(setup) })
        await reopened.waitUntilFinished()

        let restored = finished(reopened)
        #expect(restored?.matches.map(\.id) == ["1-2"])
        #expect(restored?.possiblyMissingInB.isEmpty == true)
        #expect(restored?.storeA.listingCount == 1)
    }

    // MARK: - Fila de ações de verdade

    @Test("inativar pela fila tira o anúncio da comparação na hora e do aviso de 'postar em outra loja'")
    @MainActor
    func inativarPelaFila() async {
        let idA = EnjoeiAccountID()
        let idB = EnjoeiAccountID()
        let userA = EnjoeiUser(id: Self.sellerA, nickname: "antonia", name: "antonia", avatarPublicID: nil, availableProductsCount: nil)
        let userB = EnjoeiUser(id: Self.sellerB, nickname: "loja-b", name: "loja B", avatarPublicID: nil, availableProductsCount: nil)
        let clients = [idA: makeClientA(user: userA), idB: makeClientB(user: userB)]
        let photoStore = InMemoryPhotoSignatureStore()
        let fetcher = StubPhotoFetcher(photos: ["a1": Self.ringA ?? Data(), "b1": Self.ringB ?? Data(), "a2": Self.pendant ?? Data()])
        let store = AccountsStore(
            dependenciesFactory: { id in
                AccountDependencies(client: clients[id] ?? StubEnjoeiClient(), sessionClearer: FakeSessionClearer(), webView: nil)
            },
            persistence: InMemoryAccountsPersistence(stored: [
                AccountRecord(id: idA, user: userA, lastRoundSummary: nil),
                AccountRecord(id: idB, user: userB, lastRoundSummary: nil)
            ]),
            postHistoryPersistence: InMemoryPostHistoryPersistence(),
            postQueueItemsPersistence: InMemoryPostQueueItemsPersistence(),
            memoryPressureObserver: FakeMemoryPressureObserver(),
            comparisonServices: { .inMemory(fetcher: fetcher, store: photoStore) },
            comparisonSnapshots: InMemoryComparisonSnapshotStore()
        )
        await store.restoreAccounts()
        guard let accountA = store.accounts.first(where: { $0.id == idA }),
              let accountB = store.accounts.first(where: { $0.id == idB }) else {
            Issue.record("as duas contas deviam ter sido restauradas")
            return
        }
        for account in store.accounts {
            account.productDetailsLoader.delayBetweenProducts = .zero
            account.productDetailsLoader.retryDelay = .zero
        }
        let loader = store.comparisonLoader
        loader.compare(
            accountA: accountA, accountB: accountB, services: store.comparisonServices, matchMemory: store.comparisonMatches, checkAllDetails: true
        )
        await loader.waitUntilFinished()
        #expect(finished(loader)?.matches.map(\.id) == ["1-2"])
        #expect(store.comparisonMatches.presence(of: 1, from: idA, to: idB) == .present)

        store.postQueue.enqueueInactivate(product: Fixtures.product(2, title: "anel", cover: "b1"), account: accountB)
        await waitUntil {
            if case .finished(let result) = loader.phase { return result.matches.isEmpty }
            return false
        }

        let refreshed = finished(loader)
        #expect(refreshed?.matches.isEmpty == true)
        #expect(Set(refreshed?.possiblyMissingInB.map(\.id) ?? []) == [1, 3])
        #expect(store.comparisonMatches.presence(of: 1, from: idA, to: idB) == .possiblyMissing)
        #expect(store.comparisonMatches.presence(of: 2, from: idB, to: idA) == nil)
    }
}
