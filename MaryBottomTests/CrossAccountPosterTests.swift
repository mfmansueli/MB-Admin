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

    /// Atalho pra chave de `CrossAccountPoster.statuses`/`postedProductURLs`/`failureDetails` nos
    /// testes — todos aqui têm um único `destination` por cenário, exceto o teste de colisão.
    private func target(_ productID: Int, destination: AccountSession) -> PostTarget {
        PostTarget(productID: productID, destinationAccountID: destination.id)
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
        await waitUntil { poster.statuses[target(1, destination: destination)] != .megaphoning && poster.statuses[target(1, destination: destination)] != nil }

        #expect(poster.statuses[target(1, destination: destination)] == .succeeded)
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
        await waitUntil { poster.statuses[target(1, destination: destination)] != .megaphoning && poster.statuses[target(1, destination: destination)] != nil }

        #expect(poster.postedProductURLs[target(1, destination: destination)]?.absoluteString == "https://www.enjoei.com.br/p/colar-curto-149812846")
    }

    @Test("erro ao ler o template na origem vira falha, sem tentar criar no destino")
    func falhaAoLerTemplate() async {
        let source = makeAccount(client: StubEnjoeiClient(templateError: .http(status: 500, message: "o enjoei caiu")))
        let destinationClient = StubEnjoeiClient()
        let destination = makeAccount(client: destinationClient)
        let poster = CrossAccountPoster()

        poster.post(product: EnjoeiFixtures.product(id: 1), from: source, to: destination)
        await waitUntil { poster.statuses[target(1, destination: destination)] != .megaphoning && poster.statuses[target(1, destination: destination)] != nil }

        #expect(poster.statuses[target(1, destination: destination)] == .failed("o enjoei caiu"))
        #expect(await destinationClient.createProductCalls.isEmpty)
        #expect(poster.failureDetails[target(1, destination: destination)]?.action == .post)
        #expect(poster.failureDetails[target(1, destination: destination)]?.httpStatus == 500)
        #expect(poster.failureDetails[target(1, destination: destination)]?.serverMessage == "o enjoei caiu")
    }

    @Test("erro ao criar no destino vira falha")
    func falhaAoCriar() async {
        let source = makeAccount(client: StubEnjoeiClient(templatesByProductID: [1: makeTemplate(productID: 1)]))
        let destination = makeAccount(
            client: StubEnjoeiClient(createProductError: .http(status: 422, message: "preço mínimo não atingido"))
        )
        let poster = CrossAccountPoster()

        poster.post(product: EnjoeiFixtures.product(id: 1), from: source, to: destination)
        await waitUntil { poster.statuses[target(1, destination: destination)] != .megaphoning && poster.statuses[target(1, destination: destination)] != nil }

        #expect(poster.statuses[target(1, destination: destination)] == .failed("preço mínimo não atingido"))
        #expect(poster.failureDetails[target(1, destination: destination)]?.action == .post)
        #expect(poster.failureDetails[target(1, destination: destination)]?.httpStatus == 422)
    }

    @Test("token CSRF recusado no destino é renovado e a criação sai do mesmo jeito")
    func renovaTokenRecusado() async {
        let source = makeAccount(client: StubEnjoeiClient(templatesByProductID: [1: makeTemplate(productID: 1)]))
        let destinationClient = StubEnjoeiClient(csrfRejectionsRemaining: 1)
        let destination = makeAccount(client: destinationClient)
        let poster = CrossAccountPoster()

        poster.post(product: EnjoeiFixtures.product(id: 1), from: source, to: destination)
        await waitUntil { poster.statuses[target(1, destination: destination)] != .megaphoning && poster.statuses[target(1, destination: destination)] != nil }

        #expect(poster.statuses[target(1, destination: destination)] == .succeeded)
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
        await waitUntil { poster.statuses[target(1, destination: destination)] != .megaphoning && poster.statuses[target(1, destination: destination)] != nil }

        #expect(await sourceClient.requestedTemplateIDs.count == 1)
    }

    @Test("postar com sucesso ativa isInCooldown, mas isso não bloqueia mais post(...) de outro produto")
    func sucessoAtivaIsInCooldownSemBloquear() async throws {
        // `isInCooldown` virou só um sinal pra UI (o botão "postar em X" da tela de comparação) —
        // quem manda na pacing de verdade agora é só `PostQueue.interval`. Ver comentário em
        // `CrossAccountPoster.cooldownDuration`.
        let source = makeAccount(client: StubEnjoeiClient(
            templatesByProductID: [1: makeTemplate(productID: 1), 2: makeTemplate(productID: 2)]
        ))
        let destinationClient = StubEnjoeiClient()
        let destination = makeAccount(client: destinationClient)
        let poster = CrossAccountPoster()

        #expect(poster.isInCooldown == false)

        poster.post(product: EnjoeiFixtures.product(id: 1), from: source, to: destination)
        await waitUntil { poster.statuses[target(1, destination: destination)] != .megaphoning && poster.statuses[target(1, destination: destination)] != nil }

        #expect(poster.isInCooldown)
        let cooldownUntil = try #require(poster.cooldownUntil)
        #expect(cooldownUntil.timeIntervalSinceNow > poster.cooldownDuration - 5)
        #expect(cooldownUntil.timeIntervalSinceNow <= poster.cooldownDuration)

        // Um segundo produto, mesmo com `isInCooldown` ainda ativo, posta normalmente.
        poster.post(product: EnjoeiFixtures.product(id: 2), from: source, to: destination)
        await waitUntil { poster.statuses[target(2, destination: destination)] != .megaphoning && poster.statuses[target(2, destination: destination)] != nil }
        #expect(poster.statuses[target(2, destination: destination)] == .succeeded)
        #expect(await destinationClient.createProductCalls.count == 2)
    }

    @Test("cooldown expira sozinho, sem precisar de mais nenhuma mudança de estado pra notar")
    func cooldownExpiraSozinho() async throws {
        let source = makeAccount(client: StubEnjoeiClient(templatesByProductID: [1: makeTemplate(productID: 1)]))
        let destination = makeAccount(client: StubEnjoeiClient())
        // Duração bem curta — sem esperar o minuto real do padrão, o teste ainda cobre o
        // comportamento (`cooldownUntil` zera sozinho, sem precisar de outro `post`/leitura pra
        // "notar" a expiração).
        let poster = CrossAccountPoster(cooldownDuration: 0.05)

        poster.post(product: EnjoeiFixtures.product(id: 1), from: source, to: destination)
        await waitUntil { poster.statuses[target(1, destination: destination)] != .megaphoning && poster.statuses[target(1, destination: destination)] != nil }

        #expect(poster.isInCooldown)
        // Sleep de verdade, com margem folgada (10x a duração) — `waitUntil` (só `Task.yield` em
        // laço) não serve aqui: sem nenhum outro trabalho pra ceder vez, as 10 mil iterações podem
        // esgotar bem antes dos 50ms reais do timer interno, então o teste "desistiria" cedo demais.
        try await Task.sleep(for: .milliseconds(500))
        #expect(poster.isInCooldown == false)
        #expect(poster.cooldownUntil == nil)
    }

    @Test("uma postagem nova estica cooldownUntil em vez de deixar a expiração antiga zerar por cima")
    func postagemNovaEsticaOCooldown() async throws {
        let source = makeAccount(client: StubEnjoeiClient(
            templatesByProductID: [1: makeTemplate(productID: 1), 2: makeTemplate(productID: 2)]
        ))
        let destination = makeAccount(client: StubEnjoeiClient())
        let poster = CrossAccountPoster(cooldownDuration: 0.3)

        poster.post(product: EnjoeiFixtures.product(id: 1), from: source, to: destination)
        await waitUntil { poster.statuses[target(1, destination: destination)] != .megaphoning && poster.statuses[target(1, destination: destination)] != nil }
        let firstCooldownUntil = try #require(poster.cooldownUntil)

        try await Task.sleep(for: .milliseconds(50))
        poster.post(product: EnjoeiFixtures.product(id: 2), from: source, to: destination)
        await waitUntil { poster.statuses[target(2, destination: destination)] != .megaphoning && poster.statuses[target(2, destination: destination)] != nil }
        let secondCooldownUntil = try #require(poster.cooldownUntil)

        // Comparação de valor, não corrida contra relógio de verdade: a segunda postagem estica o
        // prazo pra mais longe do que a primeira sozinha deixaria. `scheduleCooldownExpiry` cancela
        // a tarefa antiga na hora (síncrono, dentro de `run()`), então não existe janela de corrida
        // pra testar aqui — só confirmar que o valor não regrediu.
        #expect(secondCooldownUntil > firstCooldownUntil)

        // Sleep de verdade, folgado o bastante pra passar dos dois prazos (o antigo, que a tarefa
        // cancelada não deveria mais tocar, e o novo, estendido) — mesmo raciocínio de
        // `cooldownExpiraSozinho` sobre não usar `waitUntil` aqui.
        try await Task.sleep(for: .milliseconds(500))
        #expect(poster.isInCooldown == false)
        #expect(poster.cooldownUntil == nil)
    }

    @Test("o mesmo produto postado pra dois destinos diferentes não colide: os dois rodam de verdade")
    func mesmoProdutoDoisDestinosNaoColide() async {
        let sourceClient = StubEnjoeiClient(templatesByProductID: [1: makeTemplate(productID: 1)])
        let source = makeAccount(client: sourceClient)
        let destinationBClient = StubEnjoeiClient()
        let destinationB = makeAccount(client: destinationBClient)
        let destinationCClient = StubEnjoeiClient()
        let destinationC = makeAccount(client: destinationCClient)
        // Sem cooldown: o que este teste verifica é a chave do dicionário, não o bloqueio de 3 min.
        let poster = CrossAccountPoster(cooldownDuration: .zero)

        poster.post(product: EnjoeiFixtures.product(id: 1), from: source, to: destinationB)
        await waitUntil { poster.statuses[target(1, destination: destinationB)] != .megaphoning && poster.statuses[target(1, destination: destinationB)] != nil }
        // Sem isso, `post` pra C via a mesma chave (só `product.id`) veria `.succeeded` da postagem
        // em B e nunca chamaria `run` de verdade — reproduz o bug antes da correção.
        poster.post(product: EnjoeiFixtures.product(id: 1), from: source, to: destinationC)
        await waitUntil { poster.statuses[target(1, destination: destinationC)] != .megaphoning && poster.statuses[target(1, destination: destinationC)] != nil }

        #expect(poster.statuses[target(1, destination: destinationB)] == .succeeded)
        #expect(poster.statuses[target(1, destination: destinationC)] == .succeeded)
        #expect(await destinationBClient.createProductCalls.count == 1)
        #expect(await destinationCClient.createProductCalls.count == 1)
    }

    /// Erro não conta como "postagem bem-sucedida" — não trava a próxima tentativa.
    @Test("falha ao postar não ativa o bloqueio")
    func falhaNaoAtivaOBloqueio() async {
        let source = makeAccount(client: StubEnjoeiClient(templateError: .http(status: 500, message: "o enjoei caiu")))
        let destination = makeAccount(client: StubEnjoeiClient())
        let poster = CrossAccountPoster()

        poster.post(product: EnjoeiFixtures.product(id: 1), from: source, to: destination)
        await waitUntil { poster.statuses[target(1, destination: destination)] != .megaphoning && poster.statuses[target(1, destination: destination)] != nil }

        #expect(poster.isInCooldown == false)
        #expect(poster.cooldownUntil == nil)
    }

    /// `postAndWait` é quem `PostQueue` usa (em vez de um laço checando `statuses`) — precisa
    /// voltar só depois que o status já está resolvido, sucesso ou falha.
    @Test("postAndWait só volta depois que o status já está resolvido, com sucesso")
    func postAndWaitSoVoltaComStatusResolvidoSucesso() async {
        let source = makeAccount(client: StubEnjoeiClient(templatesByProductID: [1: makeTemplate(productID: 1)]))
        let destination = makeAccount(client: StubEnjoeiClient())
        let poster = CrossAccountPoster()

        await poster.postAndWait(product: EnjoeiFixtures.product(id: 1), from: source, to: destination)

        #expect(poster.statuses[target(1, destination: destination)] == .succeeded)
    }

    @Test("postAndWait só volta depois que o status já está resolvido, com falha")
    func postAndWaitSoVoltaComStatusResolvidoFalha() async {
        let source = makeAccount(client: StubEnjoeiClient(templateError: .http(status: 500, message: "o enjoei caiu")))
        let destination = makeAccount(client: StubEnjoeiClient())
        let poster = CrossAccountPoster()

        await poster.postAndWait(product: EnjoeiFixtures.product(id: 1), from: source, to: destination)

        #expect(poster.statuses[target(1, destination: destination)] == .failed("o enjoei caiu"))
    }

    @Test("postAndWait não posta de novo um produto já concluído com sucesso")
    func postAndWaitNaoRepostaProdutoJaConcluido() async {
        let source = makeAccount(client: StubEnjoeiClient(templatesByProductID: [1: makeTemplate(productID: 1)]))
        let destinationClient = StubEnjoeiClient()
        let destination = makeAccount(client: destinationClient)
        let poster = CrossAccountPoster()
        await poster.postAndWait(product: EnjoeiFixtures.product(id: 1), from: source, to: destination)

        await poster.postAndWait(product: EnjoeiFixtures.product(id: 1), from: source, to: destination)

        #expect(await destinationClient.createProductCalls.count == 1)
    }

    /// Espera uma condição sem prender o teste pra sempre se algo der errado.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<10_000 where !condition() {
            await Task.yield()
        }
    }
}
