import Foundation
import Testing
@testable import MB_Admin

/// A última comparação continua valendo depois de fechar a tela ou reabrir o app, até outra começar.
@Suite("última comparação guardada")
struct ComparisonLastResultTests {
    typealias Fixtures = ComparisonFixtures

    private static let sellerA = 1001
    private static let sellerB = 2002
    private static let ringA = DemoPhotoRenderer.jpeg(Fixtures.ring(1), side: 300, quality: 0.9)
    private static let ringB = DemoPhotoRenderer.jpeg(Fixtures.ring(1), side: 300, quality: 0.6)
    private static let pendant = DemoPhotoRenderer.jpeg(DemoPhotoRenderer.Spec(shape: .pendant, seed: 5), side: 300)

    /// Duas contas, os clients delas e os serviços (cache de fotos e revisões em memória, compartilhados
    /// entre "aberturas" do app).
    private struct Setup {
        let accountA: AccountSession
        let accountB: AccountSession
        let clientA: StubEnjoeiClient
        let clientB: StubEnjoeiClient
        let photoStore = InMemoryPhotoSignatureStore()
        let decisions = InMemoryComparisonDecisionStore()

        var accounts: [AccountSession] { [accountA, accountB] }

        /// Serviços com um fetcher que nunca responde nada — pra provar que reabrir não baixa foto.
        var offlineServices: ComparisonServices {
            .inMemory(fetcher: StubPhotoFetcher(), store: photoStore, decisions: decisions)
        }
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

    /// A tem o anel (par com B) e o pingente (só em A).
    private func makeSetup() -> Setup {
        let clientA = StubEnjoeiClient(
            pages: [page([Fixtures.product(1, title: "anel", cover: "a1"), Fixtures.product(3, title: "pingente gota", cover: "a2")])],
            templatesByProductID: [1: template(photos: ["a1"]), 3: template(photos: ["a2"])]
        )
        let clientB = StubEnjoeiClient(
            pages: [page([Fixtures.product(2, title: "anel", cover: "b1")])],
            templatesByProductID: [2: template(photos: ["b1"])]
        )
        return Setup(
            accountA: makeAccount(seller: Self.sellerA, client: clientA),
            accountB: makeAccount(seller: Self.sellerB, client: clientB),
            clientA: clientA,
            clientB: clientB
        )
    }

    private func onlineServices(_ setup: Setup) -> ComparisonServices {
        .inMemory(
            fetcher: StubPhotoFetcher(photos: ["a1": Self.ringA ?? Data(), "b1": Self.ringB ?? Data(), "a2": Self.pendant ?? Data()]),
            store: setup.photoStore,
            decisions: setup.decisions
        )
    }

    private func finished(_ loader: AccountComparisonLoader) -> AccountComparisonResult? {
        guard case .finished(let result) = loader.phase else {
            Issue.record("esperava .finished, veio \(loader.phase)")
            return nil
        }
        return result
    }

    /// Compara e espera a gravação da última comparação terminar (ela é o fim da mesma tarefa).
    private func compareAndSave(_ loader: AccountComparisonLoader, _ setup: Setup) async -> AccountComparisonResult? {
        loader.compare(accountA: setup.accountA, accountB: setup.accountB, services: onlineServices(setup))
        await loader.waitUntilFinished()
        return finished(loader)
    }

    @Test("ao terminar, guarda as listas das duas lojas e a rodada")
    func guardaAoTerminar() async {
        let setup = makeSetup()
        let snapshots = InMemoryComparisonSnapshotStore()
        let loader = AccountComparisonLoader(snapshots: snapshots)
        let result = await compareAndSave(loader, setup)
        await waitForSnapshot(snapshots)

        #expect(snapshots.snapshot?.runID == result?.id)
        #expect(snapshots.snapshot?.storeA.products.map(\.id) == [1, 3])
        #expect(snapshots.snapshot?.storeB.accountID == setup.accountB.id)
    }

    @Test("reabrir o app refaz o mesmo resultado sem rede: nem listagem, nem foto, nem template")
    func reabreSemRede() async {
        let setup = makeSetup()
        let snapshots = InMemoryComparisonSnapshotStore()
        let first = AccountComparisonLoader(snapshots: snapshots)
        let original = await compareAndSave(first, setup)
        await waitForSnapshot(snapshots)
        let pagesRequested = await setup.clientA.requestedCursors.count

        // Outra "abertura do app": loader novo, mesmo disco e mesmos caches.
        let reopened = AccountComparisonLoader(snapshots: snapshots)
        #expect(reopened.hasLastResult)
        reopened.showLastComparison(accounts: setup.accounts, services: { setup.offlineServices })
        #expect(reopened.phase == .restoring)
        await reopened.waitUntilFinished()

        let restored = finished(reopened)
        #expect(restored?.id == original?.id)
        #expect(restored?.matches.map(\.id) == original?.matches.map(\.id))
        #expect(restored?.possiblyMissingInB.map(\.id) == [3])
        #expect(reopened.accountAID == setup.accountA.id)
        #expect(reopened.accountBID == setup.accountB.id)
        #expect(await setup.clientA.requestedCursors.count == pagesRequested)
    }

    @Test("\"nova comparação\" volta pra escolha das contas sem perder o resultado; reabrir mostra ele de novo")
    func novaComparacaoMantemOResultado() async {
        let setup = makeSetup()
        let loader = AccountComparisonLoader()
        let original = await compareAndSave(loader, setup)

        loader.reset()
        #expect(loader.phase == .idle)
        #expect(loader.hasLastResult)

        loader.showLastComparison(accounts: setup.accounts, services: { setup.offlineServices })
        #expect(loader.phase == .finished(original ?? Fixtures.result()))
        #expect(!loader.isRunning)
    }

    @Test("começar outra comparação descarta a anterior — a guardada passa a ser a nova")
    func outraComparacaoDescarta() async {
        let setup = makeSetup()
        let snapshots = InMemoryComparisonSnapshotStore()
        let loader = AccountComparisonLoader(snapshots: snapshots)
        let first = await compareAndSave(loader, setup)
        await waitForSnapshot(snapshots)

        await setup.clientA.setPages([page([Fixtures.product(1, title: "anel", cover: "a1")])])
        await setup.clientB.setPages([page([Fixtures.product(2, title: "anel", cover: "b1")])])
        let second = await compareAndSave(loader, setup)
        await waitForSnapshot(snapshots)

        #expect(second?.id != first?.id)
        #expect(snapshots.snapshot?.runID == second?.id)
        #expect(snapshots.snapshot?.storeA.products.map(\.id) == [1])
    }

    @Test("uma revisão manual depois de soltar a memória refaz a evidência do disco e vale na hora")
    func revisaoDepoisDeSoltarMemoria() async {
        let setup = makeSetup()
        let snapshots = InMemoryComparisonSnapshotStore()
        let loader = AccountComparisonLoader(snapshots: snapshots)
        let original = await compareAndSave(loader, setup)
        await waitForSnapshot(snapshots)
        guard let match = original?.matches.first else {
            Issue.record("esperava um par")
            return
        }

        loader.releaseMemory()
        await loader.decide(.differentProducts, for: match)

        let revised = finished(loader)
        #expect(revised?.id == original?.id)
        #expect(revised?.revision == 1)
        #expect(revised?.matches.isEmpty == true)
        #expect(revised?.rejected.map(\.id) == [match.id])
    }

    @Test("uma conta que saiu do app leva junto a comparação guardada")
    func contaQueSaiu() async {
        let setup = makeSetup()
        let snapshots = InMemoryComparisonSnapshotStore()
        let loader = AccountComparisonLoader(snapshots: snapshots)
        _ = await compareAndSave(loader, setup)
        await waitForSnapshot(snapshots)

        await loader.forget(accountID: setup.accountB.id)

        #expect(loader.phase == .idle)
        #expect(!loader.hasLastResult)
        #expect(snapshots.snapshot == nil)
        #expect(loader.accountBID == nil)
    }

    @Test("sem as duas contas da comparação guardada logadas, fica na escolha das contas")
    func semAsContas() async {
        let setup = makeSetup()
        let snapshots = InMemoryComparisonSnapshotStore()
        _ = await compareAndSave(AccountComparisonLoader(snapshots: snapshots), setup)
        await waitForSnapshot(snapshots)

        let reopened = AccountComparisonLoader(snapshots: snapshots)
        reopened.showLastComparison(accounts: [setup.accountA], services: { setup.offlineServices })
        await reopened.waitUntilFinished()
        #expect(reopened.phase == .idle)
        #expect(snapshots.snapshot != nil)
    }

    @Test("repetidos: \"não são repetidos\" e desfazer recalculam na hora")
    func revisaoDeRepetidos() async {
        let clientA = StubEnjoeiClient(
            pages: [page([Fixtures.product(1, title: "anel coração", cover: "a1"), Fixtures.product(4, title: "anel coração", cover: "a1-de-novo")])],
            templatesByProductID: [1: template(photos: ["a1"]), 4: template(photos: ["a1-de-novo"])]
        )
        let clientB = StubEnjoeiClient(
            pages: [page([Fixtures.product(2, title: "pingente gota", cover: "b2")])],
            templatesByProductID: [2: template(photos: ["b2"])]
        )
        let accountA = makeAccount(seller: Self.sellerA, client: clientA)
        let accountB = makeAccount(seller: Self.sellerB, client: clientB)
        let services = ComparisonServices.inMemory(fetcher: StubPhotoFetcher(photos: [
            "a1": Self.ringA ?? Data(), "a1-de-novo": Self.ringB ?? Data(), "b2": Self.pendant ?? Data()
        ]))
        let loader = AccountComparisonLoader()
        loader.compare(accountA: accountA, accountB: accountB, services: services)
        await loader.waitUntilFinished()
        guard let group = finished(loader)?.duplicatesA.first else {
            Issue.record("esperava os dois anéis como repetidos")
            return
        }
        #expect(group.status == .repeated)

        await loader.decideDuplicate(.differentProducts, for: group)
        #expect(finished(loader)?.duplicatesA.isEmpty == true)
        guard let dismissed = finished(loader)?.dismissedDuplicates.first else {
            Issue.record("esperava o grupo marcado como não repetidos")
            return
        }

        await loader.undoDuplicateDecision(for: dismissed)
        #expect(finished(loader)?.duplicatesA.first?.status == .repeated)
        #expect(finished(loader)?.dismissedDuplicates.isEmpty == true)
    }

    @Test("o arquivo guarda e devolve a mesma comparação; apagar some com ele")
    func arquivo() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "comparacao-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileComparisonSnapshotStore(url: directory.appending(path: "ultima.json"))
        let snapshot = ComparisonSnapshot(
            savedAt: Date(timeIntervalSince1970: 1_000),
            runID: UUID(),
            checkAllDetails: true,
            storeA: .init(
                accountID: UUID(), sellerID: 1, name: "antonia", status: .complete,
                products: [Fixtures.product(1, title: "anel", cover: "a1")], detailsFailures: [1: "HTTP 503"]
            ),
            storeB: .init(
                accountID: UUID(), sellerID: 2, name: "loja B", status: .failed(loaded: 3, message: "sem rede"),
                products: [], detailsFailures: [:]
            ),
            photoFailures: ["b1": .downloadFailed("HTTP 404"), "b2": .undecodable]
        )
        #expect(!store.hasSnapshot)

        await store.save(snapshot)
        #expect(store.hasSnapshot)
        #expect(await FileComparisonSnapshotStore(url: directory.appending(path: "ultima.json")).load() == snapshot)

        await store.delete()
        #expect(!store.hasSnapshot)
        #expect(await store.load() == nil)
    }

    /// A gravação entra depois de a tarefa da comparação terminar — espera ela chegar no armazenamento.
    private func waitForSnapshot(_ snapshots: InMemoryComparisonSnapshotStore) async {
        for _ in 0..<200 where snapshots.snapshot == nil {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}
