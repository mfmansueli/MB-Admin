import Foundation
import Testing
@testable import MaryBottom

@Suite("postar produto de uma conta em outra")
struct CrossAccountPosterTests {
    private func makeAccount(client: StubEnjoeiClient) -> AccountSession {
        AccountSession(
            id: EnjoeiAccountID(),
            user: .stub,
            dependencies: AccountDependencies(client: client, sessionClearer: FakeSessionClearer(), webView: nil)
        )
    }

    private func makeTemplate(productID: Int) -> ProductTemplate {
        ProductTemplate(
            title: "produto \(productID)",
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
            photos: [.init(imagePublicID: "foto-\(productID)", position: 0)],
            originPlanID: 1,
            smartPrice: .init(enabled: true)
        )
    }

    @Test("lê o template na conta de origem e cria o anúncio na conta de destino")
    func postaComSucesso() async {
        let sourceClient = StubEnjoeiClient(templatesByProductID: [1: makeTemplate(productID: 1)])
        let source = makeAccount(client: sourceClient)
        let destinationClient = StubEnjoeiClient()
        let destination = makeAccount(client: destinationClient)
        let poster = CrossAccountPoster()

        poster.post(product: EnjoeiFixtures.product(id: 1), from: source, to: destination)
        await waitUntil { poster.statuses[1] != .megaphoning && poster.statuses[1] != nil }

        #expect(poster.statuses[1] == .succeeded)
        #expect(await sourceClient.requestedTemplateIDs == [1])
        let call = await destinationClient.createProductCalls.first
        #expect(call?.request.product.title == "produto 1")
        #expect(call?.request.product.price == 299)
        // Nada foi criado na conta de origem.
        #expect(await sourceClient.createProductCalls.isEmpty)
    }

    @Test("com sucesso, guarda o link do anúncio novo quando a resposta traz path")
    func guardaLinkDoAnuncioNovo() async {
        let source = makeAccount(client: StubEnjoeiClient(templatesByProductID: [1: makeTemplate(productID: 1)]))
        let destination = makeAccount(
            client: StubEnjoeiClient(createProductResponse: ProductCreateResponse(path: "colar-curto-149812846"))
        )
        let poster = CrossAccountPoster()

        poster.post(product: EnjoeiFixtures.product(id: 1), from: source, to: destination)
        await waitUntil { poster.statuses[1] != .megaphoning && poster.statuses[1] != nil }

        #expect(poster.postedProductURLs[1]?.absoluteString == "https://www.enjoei.com.br/p/colar-curto-149812846")
    }

    @Test("erro ao ler o template na origem vira falha, sem tentar criar no destino")
    func falhaAoLerTemplate() async {
        let source = makeAccount(client: StubEnjoeiClient(templateError: .http(status: 500, message: "o enjoei caiu")))
        let destinationClient = StubEnjoeiClient()
        let destination = makeAccount(client: destinationClient)
        let poster = CrossAccountPoster()

        poster.post(product: EnjoeiFixtures.product(id: 1), from: source, to: destination)
        await waitUntil { poster.statuses[1] != .megaphoning && poster.statuses[1] != nil }

        #expect(poster.statuses[1] == .failed("o enjoei caiu"))
        #expect(await destinationClient.createProductCalls.isEmpty)
    }

    @Test("erro ao criar no destino vira falha")
    func falhaAoCriar() async {
        let source = makeAccount(client: StubEnjoeiClient(templatesByProductID: [1: makeTemplate(productID: 1)]))
        let destination = makeAccount(
            client: StubEnjoeiClient(createProductError: .http(status: 422, message: "preço mínimo não atingido"))
        )
        let poster = CrossAccountPoster()

        poster.post(product: EnjoeiFixtures.product(id: 1), from: source, to: destination)
        await waitUntil { poster.statuses[1] != .megaphoning && poster.statuses[1] != nil }

        #expect(poster.statuses[1] == .failed("preço mínimo não atingido"))
    }

    @Test("token CSRF recusado no destino é renovado e a criação sai do mesmo jeito")
    func renovaTokenRecusado() async {
        let source = makeAccount(client: StubEnjoeiClient(templatesByProductID: [1: makeTemplate(productID: 1)]))
        let destinationClient = StubEnjoeiClient(csrfRejectionsRemaining: 1)
        let destination = makeAccount(client: destinationClient)
        let poster = CrossAccountPoster()

        poster.post(product: EnjoeiFixtures.product(id: 1), from: source, to: destination)
        await waitUntil { poster.statuses[1] != .megaphoning && poster.statuses[1] != nil }

        #expect(poster.statuses[1] == .succeeded)
        let tokens = await destinationClient.createProductCalls.map(\.token)
        #expect(tokens == ["token-1", "token-2"])
    }

    @Test("um segundo toque enquanto já está postando não dispara outra chamada")
    func duploToqueNaoDuplica() async {
        let sourceClient = StubEnjoeiClient(templatesByProductID: [1: makeTemplate(productID: 1)])
        let source = makeAccount(client: sourceClient)
        let destination = makeAccount(client: StubEnjoeiClient())
        let poster = CrossAccountPoster()

        poster.post(product: EnjoeiFixtures.product(id: 1), from: source, to: destination)
        poster.post(product: EnjoeiFixtures.product(id: 1), from: source, to: destination)
        await waitUntil { poster.statuses[1] != .megaphoning && poster.statuses[1] != nil }

        #expect(await sourceClient.requestedTemplateIDs.count == 1)
    }

    @Test("postar com sucesso trava novas postagens por 3 minutos, mesmo de outro produto")
    func sucessoAtivaOBloqueio() async throws {
        let source = makeAccount(client: StubEnjoeiClient(
            templatesByProductID: [1: makeTemplate(productID: 1), 2: makeTemplate(productID: 2)]
        ))
        let destinationClient = StubEnjoeiClient()
        let destination = makeAccount(client: destinationClient)
        let poster = CrossAccountPoster()

        #expect(poster.isInCooldown == false)

        poster.post(product: EnjoeiFixtures.product(id: 1), from: source, to: destination)
        await waitUntil { poster.statuses[1] != .megaphoning && poster.statuses[1] != nil }

        #expect(poster.isInCooldown)
        let cooldownUntil = try #require(poster.cooldownUntil)
        #expect(cooldownUntil.timeIntervalSinceNow > poster.cooldownDuration - 5)
        #expect(cooldownUntil.timeIntervalSinceNow <= poster.cooldownDuration)

        // Um segundo produto, ainda dentro do bloqueio, nem chega a pedir o template.
        poster.post(product: EnjoeiFixtures.product(id: 2), from: source, to: destination)
        #expect(poster.statuses[2] == nil)
        #expect(await destinationClient.createProductCalls.count == 1)
    }

    /// Erro não conta como "postagem bem-sucedida" — não trava a próxima tentativa.
    @Test("falha ao postar não ativa o bloqueio")
    func falhaNaoAtivaOBloqueio() async {
        let source = makeAccount(client: StubEnjoeiClient(templateError: .http(status: 500, message: "o enjoei caiu")))
        let destination = makeAccount(client: StubEnjoeiClient())
        let poster = CrossAccountPoster()

        poster.post(product: EnjoeiFixtures.product(id: 1), from: source, to: destination)
        await waitUntil { poster.statuses[1] != .megaphoning && poster.statuses[1] != nil }

        #expect(poster.isInCooldown == false)
        #expect(poster.cooldownUntil == nil)
    }

    /// Espera uma condição sem prender o teste pra sempre se algo der errado.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<10_000 where !condition() {
            await Task.yield()
        }
    }
}
