import Foundation
import Testing
@testable import MB_Admin

@Suite("carregador da comparação entre duas contas")
struct AccountComparisonLoaderTests {
    typealias Fixtures = ComparisonFixtures

    private static let sellerA = 1001
    private static let sellerB = 2002

    private static let ringWhiteA = DemoPhotoRenderer.jpeg(Fixtures.ring(1), side: 300, quality: 0.9)
    private static let ringWhiteB = DemoPhotoRenderer.jpeg(Fixtures.ring(1), side: 300, quality: 0.6)
    private static let otherRing = DemoPhotoRenderer.jpeg(Fixtures.ring(2), side: 300, quality: 0.6)
    private static let pendant = DemoPhotoRenderer.jpeg(DemoPhotoRenderer.Spec(shape: .pendant, seed: 5), side: 300)
    private static let ambient: Data? = {
        var spec = Fixtures.ring(50)
        spec.background = .init(red: 0.6, green: 0.5, blue: 0.45)
        spec.backgroundGradient = 0.4
        spec.rotation = 0.3
        return DemoPhotoRenderer.jpeg(spec, side: 300)
    }()

    private func makeAccount(seller: Int, client: StubEnjoeiClient) -> AccountSession {
        let account = AccountSession(
            id: EnjoeiAccountID(),
            user: EnjoeiUser(
                id: seller,
                nickname: "loja-\(seller)",
                name: seller == Self.sellerA ? "antonia" : "loja B",
                avatarPublicID: nil,
                availableProductsCount: nil
            ),
            dependencies: AccountDependencies(client: client, sessionClearer: FakeSessionClearer(), webView: nil)
        )
        account.productDetailsLoader.delayBetweenProducts = .zero
        account.productDetailsLoader.retryDelay = .zero
        return account
    }

    /// Compara duas contas novas (A = antonia, B = loja B) feitas em cima dos clients dados.
    private func compare(_ loader: AccountComparisonLoader, _ clientA: StubEnjoeiClient, _ clientB: StubEnjoeiClient, services: ComparisonServices? = nil) {
        loader.compare(
            accountA: makeAccount(seller: Self.sellerA, client: clientA),
            accountB: makeAccount(seller: Self.sellerB, client: clientB),
            services: services ?? .inMemory(fetcher: photos())
        )
    }

    private func template(photos: [String], size: String? = nil, description: String = "") -> ProductTemplate {
        ProductTemplate(
            title: "produto", description: description, brand: nil, used: false, price: 10_000, originalPrice: 10_000,
            weight: "0.3", quantity: 1, category: .init(id: 327), size: size,
            shipping: .init(type: "charge_by_weight", hasInsurance: true),
            photos: photos.enumerated().map { ProductTemplate.Photo(imagePublicID: $1, position: $0) },
            originPlanID: 1, smartPrice: nil
        )
    }

    private func page(_ products: [EnjoeiProduct], total: Int? = nil) -> StoreProductsPage {
        StoreProductsPage(products: products, total: total ?? products.count, endCursor: nil)
    }

    private func finishedResult(_ loader: AccountComparisonLoader) -> AccountComparisonResult? {
        guard case .finished(let result) = loader.phase else {
            Issue.record("esperava .finished, veio \(loader.phase)")
            return nil
        }
        return result
    }

    private func photos() -> StubPhotoFetcher {
        StubPhotoFetcher(photos: [
            "a1": Self.ringWhiteA ?? Data(),
            "b1": Self.ringWhiteB ?? Data(),
            "b1-ambiente": Self.ambient ?? Data(),
            "a2": Self.pendant ?? Data(),
            "a1-outra-versao": Self.ringWhiteA ?? Data(),
            "b2-outro": Self.otherRing ?? Data()
        ])
    }

    // MARK: - Listagem

    @Test("mesmo com o runner já carregado, comparar busca de novo — não reaproveita a lista, que pode estar desatualizada")
    func buscaDeNovoMesmoJaCarregado() async {
        let clientA = StubEnjoeiClient(pages: [
            page([Fixtures.product(1, title: "anel", cover: "velha")]),
            page([Fixtures.product(99, title: "anel", cover: "a1")])
        ])
        let accountA = makeAccount(seller: Self.sellerA, client: clientA)
        accountA.runner.load(sellerID: Self.sellerA)
        await accountA.runner.waitUntilFinished()
        let clientB = StubEnjoeiClient(pages: [page([Fixtures.product(2, title: "anel", cover: "b1")])])
        let accountB = makeAccount(seller: Self.sellerB, client: clientB)

        let loader = AccountComparisonLoader()
        loader.compare(accountA: accountA, accountB: accountB, services: .inMemory(fetcher: photos()))
        await loader.waitUntilFinished()

        #expect(await clientA.requestedCursors.count == 2)
        #expect(finishedResult(loader)?.matches.map(\.productA.id) == [99])
    }

    @Test("comparar não consulta exposição — isso é coisa do megafone e deixaria a comparação lenta à toa")
    func naoConsultaExposicao() async {
        let clientA = StubEnjoeiClient(pages: [page([Fixtures.product(1, title: "anel", cover: "a1")])])
        let clientB = StubEnjoeiClient(pages: [page([Fixtures.product(2, title: "anel", cover: "b1")])])
        let loader = AccountComparisonLoader()
        compare(loader, clientA, clientB)
        await loader.waitUntilFinished()
        #expect(await clientA.requestedExposureBatches.isEmpty)
        #expect(await clientB.requestedExposureBatches.isEmpty)
    }

    @Test("uma página que falha não vira lista vazia: nada da outra loja é dado como ausente, e tentar de novo resolve")
    func listagemQueFalha() async {
        let clientA = StubEnjoeiClient(
            pages: [page([Fixtures.product(1, title: "anel", cover: "a1")])],
            templatesByProductID: [1: template(photos: ["a1"])]
        )
        let clientB = StubEnjoeiClient()
        await clientB.setPageError(.http(status: 503, message: nil), onCall: 0)
        let loader = AccountComparisonLoader()
        let services = ComparisonServices.inMemory(fetcher: photos())
        compare(loader, clientA, clientB, services: services)
        await loader.waitUntilFinished()

        let failed = finishedResult(loader)
        #expect(failed?.possiblyMissingInB.isEmpty == true)
        #expect(failed?.unverifiedA.first?.reasons.contains(.otherStoreListingIncomplete(storeName: "loja B")) == true)
        if case .failed(let loaded, _) = failed?.storeB.status {
            #expect(loaded == 0)
        } else {
            Issue.record("esperava a lista de B como falha")
        }

        await clientA.setPages([page([Fixtures.product(1, title: "anel", cover: "a1")])])
        await clientB.setPageError(nil, onCall: nil)
        await clientB.setPages([page([Fixtures.product(2, title: "anel", cover: "b1")])])
        loader.retry()
        await loader.waitUntilFinished()
        #expect(finishedResult(loader)?.matches.map(\.id) == ["1-2"])
    }

    @Test("lista com menos produtos que o total informado fica marcada como incompleta")
    func listaIncompleta() async {
        let clientA = StubEnjoeiClient(pages: [page([Fixtures.product(1, title: "anel", cover: "a1")], total: 3)])
        let clientB = StubEnjoeiClient(pages: [page([Fixtures.product(2, title: "pingente", cover: "a2")])])
        let loader = AccountComparisonLoader()
        compare(loader, clientA, clientB)
        await loader.waitUntilFinished()
        let result = finishedResult(loader)
        #expect(result?.storeA.status == .incomplete(loaded: 1, expected: 3))
        #expect(result?.possiblyMissingInA.isEmpty == true)
    }

    // MARK: - Duas etapas

    @Test("capa igual nas duas lojas: par forte sem buscar template nenhum")
    func capaResolveSemTemplate() async {
        let clientA = StubEnjoeiClient(pages: [page([Fixtures.product(1, title: "anel aro 17", cover: "a1")])])
        let clientB = StubEnjoeiClient(pages: [page([Fixtures.product(2, title: "joia linda", cover: "b1")])])
        let memory = ComparisonMatchMemory()
        let accountA = makeAccount(seller: Self.sellerA, client: clientA)
        let accountB = makeAccount(seller: Self.sellerB, client: clientB)
        let loader = AccountComparisonLoader()
        loader.compare(accountA: accountA, accountB: accountB, services: .inMemory(fetcher: photos()), matchMemory: memory)
        await loader.waitUntilFinished()

        #expect(finishedResult(loader)?.matches.first?.status == .strong)
        #expect(await clientA.requestedTemplateIDs.isEmpty)
        #expect(await clientB.requestedTemplateIDs.isEmpty)
        #expect(memory.presence(of: 1, from: accountA.id, to: accountB.id) == .present)
        #expect(memory.presence(of: 2, from: accountB.id, to: accountA.id) == .present)
    }

    @Test("capa diferente: busca o template só de quem ficou sem par e acha a mesma foto na segunda posição")
    func templateSoDeQuemFicouSemPar() async {
        let clientA = StubEnjoeiClient(
            pages: [page([Fixtures.product(1, title: "anel aro 17", cover: "a1"), Fixtures.product(3, title: "pingente", cover: "a2")])],
            templatesByProductID: [1: template(photos: ["a1"]), 3: template(photos: ["a2"])]
        )
        let clientB = StubEnjoeiClient(
            pages: [page([Fixtures.product(2, title: "joia linda", cover: "b1-ambiente")])],
            templatesByProductID: [2: template(photos: ["b1-ambiente", "b1"])]
        )
        let fetcher = photos()
        let services = ComparisonServices.inMemory(fetcher: fetcher)
        let accountA = makeAccount(seller: Self.sellerA, client: clientA)
        let accountB = makeAccount(seller: Self.sellerB, client: clientB)
        let loader = AccountComparisonLoader()
        loader.compare(accountA: accountA, accountB: accountB, services: services)
        await loader.waitUntilFinished()

        let result = finishedResult(loader)
        #expect(result?.matches.map(\.id) == ["1-2"])
        #expect(result?.matches.first?.photoB == "b1")
        #expect(result?.possiblyMissingInB.map(\.id) == [3])
        #expect(await clientA.requestedTemplateIDs == [1, 3])
        #expect(await clientB.requestedTemplateIDs == [2])

        // Comparar de novo: template salvo e assinatura em cache — nada é pedido outra vez.
        await clientA.setPages([page([Fixtures.product(1, title: "anel aro 17", cover: "a1"), Fixtures.product(3, title: "pingente", cover: "a2")])])
        await clientB.setPages([page([Fixtures.product(2, title: "joia linda", cover: "b1-ambiente")])])
        loader.reset()
        loader.compare(accountA: accountA, accountB: accountB, services: services)
        await loader.waitUntilFinished()
        #expect(finishedResult(loader)?.matches.map(\.id) == ["1-2"])
        #expect(await clientA.requestedTemplateIDs == [1, 3])
        #expect(await clientB.requestedTemplateIDs == [2])
        #expect(await fetcher.requestCount(for: "b1") == 1)
    }

    @Test("versões com a mesma capa: busca o template até de quem já tem par, e a descrição separa as versões")
    func templateDasVersoes() async {
        // Títulos iguais: só a descrição diz o banho. Na etapa 1 (só capas), tudo empata.
        let clientA = StubEnjoeiClient(
            pages: [page([Fixtures.product(1, title: "anel coração", cover: "a1"), Fixtures.product(3, title: "anel coração", cover: "a1-outra-versao")])],
            templatesByProductID: [
                1: template(photos: ["a1"], description: "banho de ródio"),
                3: template(photos: ["a1-outra-versao"], description: "banho de ouro")
            ]
        )
        let clientB = StubEnjoeiClient(
            pages: [page([Fixtures.product(2, title: "anel coração", cover: "b1")])],
            templatesByProductID: [2: template(photos: ["b1"], description: "banho de ródio")]
        )
        let loader = AccountComparisonLoader()
        compare(loader, clientA, clientB)
        await loader.waitUntilFinished()

        let result = finishedResult(loader)
        #expect(result?.matches.map(\.id) == ["1-2"])
        #expect(result?.reviews.isEmpty == true)
        #expect(result?.possiblyMissingInB.map(\.id) == [3])
        #expect(result?.otherVersions[ListingKey(sellerID: Self.sellerA, productID: 3)]?.first?.label == "ródio")
        #expect(result?.families.count == 1)
        #expect(Set(await clientA.requestedTemplateIDs) == [1, 3])
        #expect(await clientB.requestedTemplateIDs == [2])
    }

    @Test("par 1:1 pela capa não busca template — a não ser com 'conferir a descrição de todos'")
    func conferirTodos() async {
        let products = (a: [Fixtures.product(1, title: "anel", cover: "a1")], b: [Fixtures.product(2, title: "anel", cover: "b1")])
        let clientA = StubEnjoeiClient(pages: [page(products.a)], templatesByProductID: [1: template(photos: ["a1"], description: "aro 16")])
        let clientB = StubEnjoeiClient(pages: [page(products.b)], templatesByProductID: [2: template(photos: ["b1"], description: "aro 18")])
        let loader = AccountComparisonLoader()
        compare(loader, clientA, clientB)
        await loader.waitUntilFinished()
        #expect(finishedResult(loader)?.matches.map(\.id) == ["1-2"])
        #expect(await clientA.requestedTemplateIDs.isEmpty)

        // O stub entrega cada página uma vez só: a listagem da segunda rodada vai de novo.
        await clientA.setPages([page(products.a)])
        await clientB.setPages([page(products.b)])
        loader.reset()
        loader.compare(
            accountA: makeAccount(seller: Self.sellerA, client: clientA),
            accountB: makeAccount(seller: Self.sellerB, client: clientB),
            services: .inMemory(fetcher: photos()),
            checkAllDetails: true
        )
        await loader.waitUntilFinished()
        // Com a descrição, o aro diferente aparece: outra versão, não o mesmo produto.
        let result = finishedResult(loader)
        #expect(result?.matches.isEmpty == true)
        #expect(result?.possiblyMissingInB.map(\.id) == [1])
        #expect(await clientA.requestedTemplateIDs == [1])
        #expect(await clientB.requestedTemplateIDs == [2])
    }

    @Test("template que falha deixa o anúncio como não verificado, nunca ausente")
    func templateQueFalha() async {
        let clientA = StubEnjoeiClient(pages: [page([Fixtures.product(3, title: "pingente", cover: "a2")])], templateError: .http(status: 500, message: nil))
        let clientB = StubEnjoeiClient(
            pages: [page([Fixtures.product(4, title: "anel", cover: "b2-outro")])],
            templatesByProductID: [4: template(photos: ["b2-outro"])]
        )
        let loader = AccountComparisonLoader()
        compare(loader, clientA, clientB)
        await loader.waitUntilFinished()
        let result = finishedResult(loader)
        #expect(result?.possiblyMissingInB.isEmpty == true)
        #expect(result?.unverifiedA.first?.reasons.contains(.detailsUnavailable) == true)
        #expect(result?.storeA.listingsWithDetailsFailures == 1)
        // Tentou de novo uma vez antes de desistir.
        #expect(await clientA.requestedTemplateIDs == [3, 3])
    }

    // MARK: - Cancelar e continuar

    @Test("parar no meio deixa a comparação interrompida (nunca terminada) e continuar retoma de onde parou")
    func cancelarEContinuar() async throws {
        let products = [
            Fixtures.product(1, title: "anel um", cover: "a2"),
            Fixtures.product(3, title: "anel três", cover: "a2"),
            Fixtures.product(5, title: "anel cinco", cover: "a2")
        ]
        let clientA = StubEnjoeiClient(
            pages: [page(products)],
            templatesByProductID: [1: template(photos: ["a2"]), 3: template(photos: ["a2"]), 5: template(photos: ["a2"])]
        )
        await clientA.setTemplateDelay(.milliseconds(300))
        let clientB = StubEnjoeiClient(
            pages: [page([Fixtures.product(2, title: "outro", cover: "b2-outro")])],
            templatesByProductID: [2: template(photos: ["b2-outro"])]
        )
        let loader = AccountComparisonLoader()
        compare(loader, clientA, clientB)
        while await clientA.requestedTemplateIDs.count < 2 {
            try await Task.sleep(for: .milliseconds(10))
        }
        loader.cancel()
        await loader.waitUntilFinished()
        #expect(loader.phase == .interrupted)

        await clientA.setTemplateDelay(.zero)
        let cursorsBefore = await clientA.requestedCursors.count
        loader.resume()
        await loader.waitUntilFinished()
        #expect(finishedResult(loader) != nil)
        // A listagem não foi buscada de novo, e o template que já tinha chegado não foi pedido outra vez.
        #expect(await clientA.requestedCursors.count == cursorsBefore)
        #expect(await clientA.requestedTemplateIDs.count { $0 == 1 } == 1)
    }

    // MARK: - Revisão manual

    @Test("confirmar e desfazer recalculam na hora, sem rede, com o mesmo id de comparação")
    func confirmarEDesfazer() async throws {
        let clientA = StubEnjoeiClient(
            pages: [page([Fixtures.product(1, title: "anel solitário zircônia rosa", cover: "a1")])],
            templatesByProductID: [1: template(photos: ["a1"])]
        )
        let clientB = StubEnjoeiClient(
            pages: [page([Fixtures.product(2, title: "anel solitário zircônia rosa", cover: "b2-outro")])],
            templatesByProductID: [2: template(photos: ["b2-outro"])]
        )
        let decisions = InMemoryComparisonDecisionStore()
        let services = ComparisonServices.inMemory(fetcher: photos(), decisions: decisions)
        let accountA = makeAccount(seller: Self.sellerA, client: clientA)
        let accountB = makeAccount(seller: Self.sellerB, client: clientB)
        let memory = ComparisonMatchMemory()
        let loader = AccountComparisonLoader()
        loader.compare(accountA: accountA, accountB: accountB, services: services, matchMemory: memory)
        await loader.waitUntilFinished()
        let review = try #require(finishedResult(loader)?.reviews.first)
        #expect(memory.presence(of: 1, from: accountA.id, to: accountB.id) == .possible)
        let cursors = await clientA.requestedCursors.count

        await loader.decide(.sameProduct, for: review)
        let confirmed = finishedResult(loader)
        #expect(confirmed?.matches.first?.status == .confirmed)
        #expect(confirmed?.id == finishedResult(loader)?.id)
        #expect(confirmed?.revision == 1)
        #expect(decisions.stored.count == 1)
        #expect(memory.presence(of: 1, from: accountA.id, to: accountB.id) == .present)

        await loader.undoDecision(for: try #require(confirmed?.matches.first))
        #expect(finishedResult(loader)?.reviews.map(\.id) == ["1-2"])
        #expect(finishedResult(loader)?.revision == 2)
        #expect(decisions.stored.isEmpty)
        #expect(await clientA.requestedCursors.count == cursors)
    }

    @Test("revisão salva vale na comparação seguinte")
    func revisaoValeNaProxima() async throws {
        let clientA = StubEnjoeiClient(templatesByProductID: [1: template(photos: ["a1"])])
        let clientB = StubEnjoeiClient(templatesByProductID: [2: template(photos: ["b2-outro"])])
        let pagesA = [page([Fixtures.product(1, title: "anel solitário zircônia rosa", cover: "a1")])]
        let pagesB = [page([Fixtures.product(2, title: "anel solitário zircônia rosa", cover: "b2-outro")])]
        await clientA.setPages(pagesA)
        await clientB.setPages(pagesB)
        let services = ComparisonServices.inMemory(fetcher: photos())
        let accountA = makeAccount(seller: Self.sellerA, client: clientA)
        let accountB = makeAccount(seller: Self.sellerB, client: clientB)
        let loader = AccountComparisonLoader()
        loader.compare(accountA: accountA, accountB: accountB, services: services)
        await loader.waitUntilFinished()
        await loader.decide(.differentProducts, for: try #require(finishedResult(loader)?.reviews.first))

        await clientA.setPages(pagesA)
        await clientB.setPages(pagesB)
        loader.reset()
        loader.compare(accountA: accountB, accountB: accountA, services: services)
        await loader.waitUntilFinished()
        // Mesmo com as lojas na ordem inversa.
        #expect(finishedResult(loader)?.rejected.map(\.id) == ["2-1"])
        #expect(finishedResult(loader)?.reviews.isEmpty == true)
    }

    // MARK: - Fases

    @Test("nova comparação volta pra escolha das contas; não larga uma comparação em andamento")
    func novaComparacao() async {
        let clientA = StubEnjoeiClient(pages: [page([Fixtures.product(1, title: "anel", cover: "a1")])])
        let clientB = StubEnjoeiClient(pages: [page([Fixtures.product(2, title: "anel", cover: "b1")])])
        let loader = AccountComparisonLoader()
        compare(loader, clientA, clientB)
        loader.reset()
        #expect(loader.phase != .idle)
        await loader.waitUntilFinished()
        loader.reset()
        #expect(loader.phase == .idle)
    }

    @Test("cada comparação tem um id diferente, mesmo comparando o mesmo par de contas de novo")
    func idNovoACadaComparacao() async {
        let clientA = StubEnjoeiClient()
        let clientB = StubEnjoeiClient()
        let accountA = makeAccount(seller: Self.sellerA, client: clientA)
        let accountB = makeAccount(seller: Self.sellerB, client: clientB)
        let services = ComparisonServices.inMemory(fetcher: photos())
        let loader = AccountComparisonLoader()
        var ids: [UUID] = []
        for _ in 0..<2 {
            await clientA.setPages([page([Fixtures.product(1, title: "anel", cover: "a1")])])
            await clientB.setPages([page([Fixtures.product(2, title: "anel", cover: "b1")])])
            loader.reset()
            loader.compare(accountA: accountA, accountB: accountB, services: services)
            await loader.waitUntilFinished()
            if let result = finishedResult(loader) { ids.append(result.id) }
        }
        #expect(ids.count == 2)
        #expect(Set(ids).count == 2)
    }
}
