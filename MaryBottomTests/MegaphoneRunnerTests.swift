import Foundation
import Testing
@testable import MaryBottom

@Suite("rodada de megafone")
struct MegaphoneRunnerTests {
    /// Sem espera entre produtos, os testes não ficam presos ao ritmo real do app.
    private func makeRunner(
        client: StubEnjoeiClient,
        accountID: EnjoeiAccountID = UUID(),
        itemsPersistence: MegaphoneItemsPersisting = InMemoryMegaphoneItemsPersistence()
    ) -> MegaphoneRunner {
        let runner = MegaphoneRunner(client: client, accountID: accountID, itemsPersistence: itemsPersistence)
        runner.delayBetweenProducts = .zero
        return runner
    }

    @Test("megafona todos os produtos da loja e termina")
    func megafonaTodosOsProdutos() async {
        let client = StubEnjoeiClient(pages: [
            EnjoeiFixtures.page(ids: [1, 2, 3], total: 3, endCursor: nil)
        ])
        let runner = makeRunner(client: client)

        runner.start(sellerID: 28714888)
        await runner.waitUntilFinished()

        #expect(runner.phase == .finished)
        #expect(await client.megaphonedIDs == [1, 2, 3])
        #expect(runner.succeededCount == 3)
        #expect(runner.failedCount == 0)
        #expect(runner.items.allSatisfy { $0.status == .succeeded })
        #expect(runner.currentItemID == nil)
    }

    @Test("junta as páginas da loja e não repete produto")
    func percorreTodasAsPaginas() async {
        let client = StubEnjoeiClient(pages: [
            EnjoeiFixtures.page(ids: [1, 2], total: 3, endCursor: "cursor-1"),
            EnjoeiFixtures.page(ids: [2, 3], total: 3, endCursor: "cursor-2"),
            EnjoeiFixtures.page(ids: [], total: 3, endCursor: nil)
        ])
        let runner = makeRunner(client: client)

        runner.start(sellerID: 1)
        await runner.waitUntilFinished()

        #expect(runner.items.map(\.id) == [1, 2, 3])
        #expect(await client.requestedCursors == [nil, "cursor-1", "cursor-2"])
    }

    @Test("um produto com erro não interrompe os outros")
    func falhaIsoladaNaoParaARodada() async {
        let client = StubEnjoeiClient(
            pages: [EnjoeiFixtures.page(ids: [1, 2, 3], endCursor: nil)],
            failuresByProductID: [2: .http(status: 429, message: "calma lá")]
        )
        let runner = makeRunner(client: client)

        runner.start(sellerID: 1)
        await runner.waitUntilFinished()

        #expect(runner.phase == .finished)
        #expect(await client.megaphonedIDs == [1, 3])
        #expect(runner.items[1].status == .failed("calma lá"))
        #expect(runner.succeededCount == 2)
        #expect(runner.failedCount == 1)
    }

    @Test("sessão expirada interrompe a rodada na hora")
    func sessaoExpiradaParaTudo() async {
        let client = StubEnjoeiClient(
            pages: [EnjoeiFixtures.page(ids: [1, 2, 3], endCursor: nil)],
            failuresByProductID: [1: .notAuthenticated]
        )
        let runner = makeRunner(client: client)

        runner.start(sellerID: 1)
        await runner.waitUntilFinished()

        #expect(runner.phase == .failed(EnjoeiError.notAuthenticated.localizedDescription))
        #expect(await client.megaphonedIDs.isEmpty)
        #expect(runner.items[2].status == .pending)
    }

    @Test("muitas falhas seguidas não param a rodada — segue pros próximos produtos")
    func naoParaDepoisDeFalhasSeguidas() async {
        let ids = Array(1...6)
        let client = StubEnjoeiClient(
            pages: [EnjoeiFixtures.page(ids: ids, endCursor: nil)],
            failuresByProductID: Dictionary(
                uniqueKeysWithValues: ids.dropLast().map { ($0, EnjoeiError.http(status: 400, message: "não rolou")) }
            )
        )
        let runner = makeRunner(client: client)

        runner.start(sellerID: 1)
        await runner.waitUntilFinished()

        #expect(runner.phase == .finished)
        #expect(runner.failedCount == 5)
        #expect(runner.succeededCount == 1)
        #expect(runner.items.allSatisfy { $0.status.isFinished })
    }

    @Test("token CSRF recusado é renovado e o produto segue megafonado")
    func renovaTokenRecusado() async {
        let client = StubEnjoeiClient(
            pages: [EnjoeiFixtures.page(ids: [1], endCursor: nil)],
            csrfRejectionsRemaining: 1
        )
        let runner = makeRunner(client: client)

        runner.start(sellerID: 1)
        await runner.waitUntilFinished()

        #expect(runner.phase == .finished)
        #expect(await client.megaphonedIDs == [1])
        // Um token na abertura da rodada, outro depois da recusa.
        #expect(await client.csrfCallCount == 2)
        #expect(await client.usedTokens == ["token-1", "token-2"])
    }

    @Test("loja sem produtos termina sem megafonar nada")
    func lojaVazia() async {
        let client = StubEnjoeiClient(pages: [EnjoeiFixtures.page(ids: [], endCursor: nil)])
        let runner = makeRunner(client: client)

        runner.start(sellerID: 1)
        await runner.waitUntilFinished()

        #expect(runner.phase == .finished)
        #expect(runner.items.isEmpty)
        #expect(await client.csrfCallCount == 0)
    }

    @Test("cancelar devolve o produto em andamento para a fila")
    func cancelamento() async {
        let client = StubEnjoeiClient(pages: [EnjoeiFixtures.page(ids: [1, 2, 3], endCursor: nil)])
        let runner = MegaphoneRunner(client: client)
        runner.delayBetweenProducts = .seconds(30)

        runner.start(sellerID: 1)
        await waitUntil { runner.processedCount >= 1 }
        runner.cancel()
        await runner.waitUntilFinished()

        #expect(runner.phase == .cancelled)
        #expect(runner.items[0].status == .succeeded)
        #expect(runner.items[1].status == .pending)
        #expect(runner.currentItemID == nil)
    }

    @Test("repete a lista inteira quantas rodadas o usuário pedir")
    func repeteAListaVariasRodadas() async {
        let client = StubEnjoeiClient(pages: [EnjoeiFixtures.page(ids: [1, 2], endCursor: nil)])
        let runner = makeRunner(client: client)

        runner.start(sellerID: 1, rounds: .times(3))
        await runner.waitUntilFinished()

        #expect(runner.phase == .finished)
        #expect(await client.megaphonedIDs == [1, 2, 1, 2, 1, 2])
        #expect(runner.totalSucceeded == 6)
        #expect(runner.totalFailed == 0)
        #expect(runner.round == 3)
        // A lista de produtos é buscada uma vez só; as rodadas seguintes reaproveitam.
        #expect(await client.requestedCursors.count == 1)
    }

    @Test("cada rodada recomeça a fila do zero, mas os somatórios continuam")
    func rodadaSeguinteRecomecaAFila() async {
        let client = StubEnjoeiClient(pages: [EnjoeiFixtures.page(ids: [1, 2, 3], endCursor: nil)])
        let runner = MegaphoneRunner(client: client)
        runner.delayBetweenProducts = .milliseconds(1)

        runner.start(sellerID: 1, rounds: .times(2))
        await runner.waitUntilFinished()

        #expect(runner.phase == .finished)
        #expect(await client.megaphonedIDs == [1, 2, 3, 1, 2, 3])
        #expect(runner.totalSucceeded == 6)
        // A fila em si só guarda a última rodada.
        #expect(runner.items.count == 3)
    }

    @Test("repetição infinita só para quando o usuário manda")
    func repeticaoInfinita() async {
        let client = StubEnjoeiClient(pages: [EnjoeiFixtures.page(ids: [1, 2], endCursor: nil)])
        let runner = makeRunner(client: client)

        runner.start(sellerID: 1, rounds: .unlimited)
        await waitUntil { runner.totalSucceeded >= 6 }
        runner.cancel()
        await runner.waitUntilFinished()

        #expect(runner.phase == .cancelled)
        // Passou da terceira rodada sem que ninguém tenha pedido um limite.
        #expect(runner.round >= 3)
    }

    @Test("segundo plano pausa e a volta retoma do mesmo ponto")
    func pausaEmSegundoPlano() async {
        let client = StubEnjoeiClient(pages: [EnjoeiFixtures.page(ids: [1, 2, 3], endCursor: nil)])
        let runner = MegaphoneRunner(client: client)
        runner.delayBetweenProducts = .milliseconds(20)

        runner.start(sellerID: 1, rounds: .once)
        await waitUntil { runner.processedCount >= 1 }
        runner.pauseForBackground()
        let processedWhilePaused = runner.processedCount

        #expect(runner.phase == .paused(round: 1, of: .once, reason: .background))
        // Fica parado de verdade: nada avança enquanto o app está fora.
        for _ in 0..<200 { await Task.yield() }
        #expect(runner.processedCount == processedWhilePaused)

        runner.resumeFromBackground()
        await runner.waitUntilFinished()

        #expect(runner.phase == .finished)
        #expect(await client.megaphonedIDs == [1, 2, 3])
    }

    @Test("pausa do usuário sobrevive a sair e voltar do app")
    func pausaDoUsuarioNaoEhDesfeitaPeloAppVoltando() async {
        let client = StubEnjoeiClient(pages: [EnjoeiFixtures.page(ids: [1, 2, 3], endCursor: nil)])
        let runner = MegaphoneRunner(client: client)
        runner.delayBetweenProducts = .milliseconds(20)

        runner.start(sellerID: 1, rounds: .once)
        await waitUntil { runner.processedCount >= 1 }
        runner.pause()

        // Sai e volta do app: a pausa foi pedida pelo usuário, então continua de pé.
        runner.pauseForBackground()
        runner.resumeFromBackground()
        let processed = runner.processedCount
        for _ in 0..<200 { await Task.yield() }

        #expect(runner.phase == .paused(round: 1, of: .once, reason: .user))
        #expect(runner.processedCount == processed)

        runner.resume()
        await runner.waitUntilFinished()
        #expect(runner.phase == .finished)
    }

    @Test("o botão continuar também tira da pausa de segundo plano")
    func continuarDesfazPausaDeSegundoPlano() async {
        let client = StubEnjoeiClient(pages: [EnjoeiFixtures.page(ids: [1, 2], endCursor: nil)])
        let runner = MegaphoneRunner(client: client)
        runner.delayBetweenProducts = .milliseconds(20)

        runner.start(sellerID: 1, rounds: .once)
        await waitUntil { runner.processedCount >= 1 }
        runner.pauseForBackground()
        runner.resume()
        await runner.waitUntilFinished()

        #expect(runner.phase == .finished)
        #expect(runner.isPaused == false)
    }

    @Test("parar enquanto está pausado não trava o app")
    func cancelarPausado() async {
        let client = StubEnjoeiClient(pages: [EnjoeiFixtures.page(ids: [1, 2, 3], endCursor: nil)])
        let runner = MegaphoneRunner(client: client)
        runner.delayBetweenProducts = .milliseconds(20)

        runner.start(sellerID: 1, rounds: .once)
        await waitUntil { runner.processedCount >= 1 }
        runner.pause()
        runner.cancel()
        await runner.waitUntilFinished()

        #expect(runner.phase == .cancelled)
        #expect(runner.isPaused == false)
    }

    @Test("erro fatal numa rodada não deixa as seguintes rodarem")
    func erroFatalParaTodasAsRodadas() async {
        let client = StubEnjoeiClient(
            pages: [EnjoeiFixtures.page(ids: [1, 2], endCursor: nil)],
            failuresByProductID: [1: .notAuthenticated]
        )
        let runner = makeRunner(client: client)

        runner.start(sellerID: 1, rounds: .times(4))
        await runner.waitUntilFinished()

        #expect(runner.phase == .failed(EnjoeiError.notAuthenticated.localizedDescription))
        #expect(await client.megaphonedIDs.isEmpty)
        #expect(runner.round == 1)
    }

    @Test("fim da rodada avisa quem guarda o resumo")
    func fimDaRodadaAvisaOResumo() async {
        let client = StubEnjoeiClient(
            pages: [EnjoeiFixtures.page(ids: [1, 2, 3], endCursor: nil)],
            failuresByProductID: [2: .http(status: 429, message: "calma lá")]
        )
        let runner = makeRunner(client: client)
        var summaries: [MegaphoneRoundSummary] = []
        runner.onRoundFinished = { summaries.append($0) }

        runner.start(sellerID: 1)
        await runner.waitUntilFinished()

        #expect(summaries.count == 1)
        #expect(summaries.first?.succeeded == 2)
        #expect(summaries.first?.failed == 1)
    }

    @Test("cancelar também avisa o resumo, com o que já tinha sido feito")
    func cancelarAvisaOResumo() async {
        let client = StubEnjoeiClient(pages: [EnjoeiFixtures.page(ids: [1, 2, 3], endCursor: nil)])
        let runner = MegaphoneRunner(client: client)
        runner.delayBetweenProducts = .seconds(30)
        var summaries: [MegaphoneRoundSummary] = []
        runner.onRoundFinished = { summaries.append($0) }

        runner.start(sellerID: 1)
        await waitUntil { runner.processedCount >= 1 }
        runner.cancel()
        await runner.waitUntilFinished()

        #expect(summaries.count == 1)
        #expect(summaries.first?.succeeded == 1)
    }

    @Test("sessão expirada avisa quem precisa marcar a conta como deslogada")
    func sessaoExpiradaAvisaOSessionExpired() async {
        let client = StubEnjoeiClient(
            pages: [EnjoeiFixtures.page(ids: [1, 2, 3], endCursor: nil)],
            failuresByProductID: [1: .notAuthenticated]
        )
        let runner = makeRunner(client: client)
        var sessionExpiredCount = 0
        runner.onSessionExpired = { sessionExpiredCount += 1 }

        runner.start(sellerID: 1)
        await runner.waitUntilFinished()

        #expect(sessionExpiredCount == 1)
    }

    @Test("uma falha comum não é confundida com sessão expirada")
    func falhaComumNaoDisparaSessionExpired() async {
        let client = StubEnjoeiClient(
            pages: [EnjoeiFixtures.page(ids: [1, 2, 3], endCursor: nil)],
            failuresByProductID: [2: .http(status: 429, message: "calma lá")]
        )
        let runner = makeRunner(client: client)
        var sessionExpiredCount = 0
        runner.onSessionExpired = { sessionExpiredCount += 1 }

        runner.start(sellerID: 1)
        await runner.waitUntilFinished()

        #expect(sessionExpiredCount == 0)
    }

    @Test("cada item carregado vem com a exposição correspondente, quando a API devolve uma")
    func itensVemComExposicao() async {
        let client = StubEnjoeiClient(
            pages: [EnjoeiFixtures.page(ids: [1, 2], endCursor: nil)],
            exposuresByProductID: [
                1: MegaphoneExposure(
                    productID: 1, kind: .maximumAfterDiscount, priceToIncreaseExposure: 100, discountLabel: "- 20%"
                )
            ]
        )
        let runner = makeRunner(client: client)

        runner.start(sellerID: 1)
        await runner.waitUntilFinished()

        #expect(runner.items.first { $0.id == 1 }?.exposure?.kind == .maximumAfterDiscount)
        #expect(runner.items.first { $0.id == 2 }?.exposure == nil)
    }

    @Test("pede exposição em lotes do tamanho configurado")
    func pedeExposicaoEmLotes() async {
        let ids = Array(1...5)
        let client = StubEnjoeiClient(pages: [EnjoeiFixtures.page(ids: ids, endCursor: nil)])
        let runner = makeRunner(client: client)
        runner.exposureBatchSize = 2

        runner.start(sellerID: 1)
        await runner.waitUntilFinished()

        let batches = await client.requestedExposureBatches
        #expect(batches.count == 3)
        #expect(batches.flatMap { $0 } == ids)
    }

    @Test("carregar a loja sozinho (load) já confere a exposição também, não só start")
    func loadTambemConfereExposicao() async {
        let client = StubEnjoeiClient(
            pages: [EnjoeiFixtures.page(ids: [1, 2, 3], endCursor: nil)],
            exposuresByProductID: [
                1: MegaphoneExposure(
                    productID: 1, kind: .maximumAfterDiscount, priceToIncreaseExposure: 100, discountLabel: "- 20%"
                )
            ]
        )
        let runner = makeRunner(client: client)

        runner.load(sellerID: 1)
        await runner.waitUntilFinished()

        #expect(runner.items.first { $0.id == 1 }?.exposure?.kind == .maximumAfterDiscount)
        #expect(await client.requestedExposureBatches.isEmpty == false)
    }

    @Test("reload busca a exposição de novo do zero, junto com os produtos")
    func reloadBuscaExposicaoDeNovo() async {
        let client = StubEnjoeiClient(pages: [
            EnjoeiFixtures.page(ids: [1, 2], endCursor: nil),
            EnjoeiFixtures.page(ids: [1, 2, 3], endCursor: nil)
        ])
        let runner = makeRunner(client: client)
        runner.load(sellerID: 1)
        await runner.waitUntilFinished()
        #expect(await client.requestedExposureBatches.count == 1)

        runner.reload(sellerID: 1)
        await runner.waitUntilFinished()

        #expect(await client.requestedExposureBatches.count == 2)
    }

    @Test("aplicar desconto num item ainda não alcançado pelo laço megafona com o preço sugerido")
    func aplicarDescontoComSucesso() async {
        let client = StubEnjoeiClient(
            pages: [EnjoeiFixtures.page(ids: [1, 2], endCursor: nil)],
            exposuresByProductID: [
                2: MegaphoneExposure(
                    productID: 2, kind: .maximumAfterDiscount, priceToIncreaseExposure: 100, discountLabel: "- 20%"
                )
            ]
        )
        let runner = makeRunner(client: client)
        runner.start(sellerID: 1)
        runner.pause()
        await waitUntil { !runner.items.isEmpty }

        runner.applyDiscount(for: 2)
        await waitUntil { runner.items.first { $0.id == 2 }?.status != .megaphoning }

        #expect(runner.items.first { $0.id == 2 }?.status == .succeeded)
        #expect(await client.appliedDiscounts[2] == 100)

        runner.cancel()
        await runner.waitUntilFinished()
    }

    @Test("token CSRF recusado ao aplicar desconto é renovado e o desconto sai aplicado do mesmo jeito")
    func aplicarDescontoRenovaTokenRecusado() async {
        let client = StubEnjoeiClient(
            pages: [EnjoeiFixtures.page(ids: [1, 2], endCursor: nil)],
            csrfRejectionsRemaining: 1,
            exposuresByProductID: [
                2: MegaphoneExposure(
                    productID: 2, kind: .maximumAfterDiscount, priceToIncreaseExposure: 100, discountLabel: "- 20%"
                )
            ]
        )
        let runner = makeRunner(client: client)
        runner.start(sellerID: 1)
        runner.pause()
        await waitUntil { !runner.items.isEmpty }

        runner.applyDiscount(for: 2)
        await waitUntil { runner.items.first { $0.id == 2 }?.status != .megaphoning }

        #expect(runner.items.first { $0.id == 2 }?.status == .succeeded)
        // "token-1" já saiu antes da pausa valer: `run` busca um token pra fila logo depois de
        // carregar os itens, antes do laço checar `pauseReason`.
        #expect(await client.usedTokens == ["token-2", "token-3"])

        runner.cancel()
        await runner.waitUntilFinished()
    }

    @Test("laço automático pula um item que está sendo aplicado na mão, sem chamar a rota duas vezes")
    func lacoPulaItemEmAplicacaoManual() async {
        let client = StubEnjoeiClient(
            pages: [EnjoeiFixtures.page(ids: [1, 2], endCursor: nil)],
            exposuresByProductID: [
                1: MegaphoneExposure(
                    productID: 1, kind: .maximumAfterDiscount, priceToIncreaseExposure: 50, discountLabel: "- 50%"
                )
            ]
        )
        let runner = makeRunner(client: client)
        runner.start(sellerID: 1)
        runner.pause()
        await waitUntil { !runner.items.isEmpty }

        runner.applyDiscount(for: 1)
        await waitUntil { runner.items.first { $0.id == 1 }?.status != .megaphoning }

        runner.resume()
        await runner.waitUntilFinished()

        #expect(runner.items.first { $0.id == 1 }?.status == .succeeded)
        #expect(await client.appliedDiscounts[1] == 50)
        #expect(await client.megaphonedIDs.filter { $0 == 1 }.count == 1)
        #expect(runner.phase == .finished)
    }

    @Test("load só carrega e confere exposição, sem megafonar nada")
    func loadSoCarrega() async {
        let client = StubEnjoeiClient(
            pages: [EnjoeiFixtures.page(ids: [1, 2], endCursor: nil)],
            exposuresByProductID: [
                1: MegaphoneExposure(
                    productID: 1, kind: .maximumAfterDiscount, priceToIncreaseExposure: 100, discountLabel: "- 20%"
                )
            ]
        )
        let runner = makeRunner(client: client)

        runner.load(sellerID: 1)
        await runner.waitUntilFinished()

        #expect(runner.items.map(\.id) == [1, 2])
        #expect(runner.items.first { $0.id == 1 }?.exposure?.kind == .maximumAfterDiscount)
        #expect(await client.megaphonedIDs.isEmpty)
        #expect(runner.phase == .idle)
        #expect(runner.isRunning == false)
    }

    @Test("load numa loja vazia deixa a lista vazia, sem erro")
    func loadLojaVazia() async {
        let client = StubEnjoeiClient(pages: [EnjoeiFixtures.page(ids: [], endCursor: nil)])
        let runner = makeRunner(client: client)

        runner.load(sellerID: 1)
        await runner.waitUntilFinished()

        #expect(runner.items.isEmpty)
        #expect(runner.phase == .idle)
    }

    @Test("load não faz nada enquanto já está rodando")
    func loadIgnoradoEnquantoRoda() async {
        let client = StubEnjoeiClient(pages: [EnjoeiFixtures.page(ids: [1, 2, 3], endCursor: nil)])
        let runner = MegaphoneRunner(client: client)
        runner.delayBetweenProducts = .seconds(30)
        runner.start(sellerID: 1)
        await waitUntil { runner.processedCount >= 1 }

        runner.load(sellerID: 1)

        #expect(runner.isRunning)
        runner.cancel()
        await runner.waitUntilFinished()
    }

    @Test("start reaproveita a lista já carregada em vez de buscar a loja de novo")
    func startReaproveitaListaCarregada() async {
        let client = StubEnjoeiClient(pages: [EnjoeiFixtures.page(ids: [1, 2], endCursor: nil)])
        let runner = makeRunner(client: client)
        runner.load(sellerID: 1)
        await runner.waitUntilFinished()
        #expect(await client.requestedCursors.count == 1)

        runner.start(sellerID: 1)
        await runner.waitUntilFinished()

        #expect(runner.phase == .finished)
        #expect(await client.megaphonedIDs == [1, 2])
        #expect(await client.requestedCursors.count == 1)
    }

    @Test("reload descarta a lista carregada e busca a loja de novo")
    func reloadBuscaDeNovo() async {
        let client = StubEnjoeiClient(pages: [
            EnjoeiFixtures.page(ids: [1], endCursor: nil),
            EnjoeiFixtures.page(ids: [1, 2], endCursor: nil)
        ])
        let runner = makeRunner(client: client)
        runner.start(sellerID: 1)
        await runner.waitUntilFinished()
        #expect(runner.items.map(\.id) == [1])

        runner.reload(sellerID: 1)
        await runner.waitUntilFinished()

        #expect(runner.items.map(\.id) == [1, 2])
        #expect(await client.requestedCursors.count == 2)
    }

    @Test("reload só recarrega, nunca megafona sozinho")
    func reloadNaoMegafonaSozinho() async {
        let client = StubEnjoeiClient(pages: [EnjoeiFixtures.page(ids: [1, 2], endCursor: nil)])
        let runner = makeRunner(client: client)

        runner.reload(sellerID: 1)
        await runner.waitUntilFinished()

        #expect(runner.items.map(\.id) == [1, 2])
        #expect(await client.megaphonedIDs.isEmpty)
        #expect(runner.phase == .idle)
        #expect(runner.isRunning == false)
    }

    @Test("load bem sucedido guarda a lista carregada na persistência")
    func loadGuardaListaNaPersistencia() async {
        let client = StubEnjoeiClient(pages: [EnjoeiFixtures.page(ids: [1, 2], endCursor: nil)])
        let accountID = EnjoeiAccountID()
        let persistence = InMemoryMegaphoneItemsPersistence()
        let runner = makeRunner(client: client, accountID: accountID, itemsPersistence: persistence)

        runner.load(sellerID: 1)
        await runner.waitUntilFinished()

        #expect(persistence.loadItems(accountID: accountID).map(\.id) == [1, 2])
    }

    @Test("um runner novo com a mesma persistência recupera a lista sem buscar a loja de novo")
    func runnerNovoRecuperaListaPersistida() async {
        let client = StubEnjoeiClient(pages: [EnjoeiFixtures.page(ids: [1, 2], endCursor: nil)])
        let accountID = EnjoeiAccountID()
        let persistence = InMemoryMegaphoneItemsPersistence()
        let firstRunner = makeRunner(client: client, accountID: accountID, itemsPersistence: persistence)
        firstRunner.load(sellerID: 1)
        await firstRunner.waitUntilFinished()

        // Simula reabrir o app: um runner novo, mesma conta, mesma persistência.
        let secondRunner = makeRunner(client: client, accountID: accountID, itemsPersistence: persistence)

        #expect(secondRunner.items.map(\.id) == [1, 2])
        #expect(await client.requestedCursors.count == 1)
    }

    @Test("reload descarta a lista persistida na hora, antes mesmo da busca nova terminar")
    func reloadDescartaListaPersistidaNaHora() async {
        let client = StubEnjoeiClient(pages: [EnjoeiFixtures.page(ids: [1, 2], endCursor: nil)])
        let accountID = EnjoeiAccountID()
        let persistence = InMemoryMegaphoneItemsPersistence()
        let runner = makeRunner(client: client, accountID: accountID, itemsPersistence: persistence)
        runner.load(sellerID: 1)
        await runner.waitUntilFinished()
        #expect(persistence.loadItems(accountID: accountID).isEmpty == false)

        runner.reload(sellerID: 1)

        #expect(persistence.loadItems(accountID: accountID).isEmpty)
        await runner.waitUntilFinished()
    }

    @Test("start soma aos totais o que a lista carregada já tinha de sucesso")
    func startSomaSucessosJaAplicados() async {
        let client = StubEnjoeiClient(
            pages: [EnjoeiFixtures.page(ids: [1, 2], endCursor: nil)],
            exposuresByProductID: [
                1: MegaphoneExposure(
                    productID: 1, kind: .maximumAfterDiscount, priceToIncreaseExposure: 50, discountLabel: "- 50%"
                )
            ]
        )
        let runner = makeRunner(client: client)
        runner.load(sellerID: 1)
        await runner.waitUntilFinished()
        runner.applyDiscount(for: 1)
        await waitUntil { runner.items.first { $0.id == 1 }?.status != .megaphoning }

        runner.start(sellerID: 1)
        await runner.waitUntilFinished()

        #expect(runner.totalSucceeded == 2)
        #expect(await client.megaphonedIDs == [1, 2])
    }

    @Test("apagar produto com sucesso marca deleteStatuses como succeeded")
    func apagarComSucesso() async {
        let client = StubEnjoeiClient()
        let runner = makeRunner(client: client)

        runner.deleteProduct(productID: 1)
        await waitUntil { runner.deleteStatuses[1] != .megaphoning && runner.deleteStatuses[1] != nil }

        #expect(runner.deleteStatuses[1] == .succeeded)
        let call = await client.deleteProductCalls.first
        #expect(call?.productID == 1)
    }

    @Test("erro ao apagar vira falha")
    func apagarFalha() async {
        let client = StubEnjoeiClient(deleteProductError: .http(status: 500, message: "o enjoei caiu"))
        let runner = makeRunner(client: client)

        runner.deleteProduct(productID: 1)
        await waitUntil { runner.deleteStatuses[1] != .megaphoning && runner.deleteStatuses[1] != nil }

        #expect(runner.deleteStatuses[1] == .failed("o enjoei caiu"))
    }

    @Test("token CSRF recusado ao apagar é renovado e a exclusão sai do mesmo jeito")
    func apagarRenovaTokenRecusado() async {
        let client = StubEnjoeiClient(csrfRejectionsRemaining: 1)
        let runner = makeRunner(client: client)

        runner.deleteProduct(productID: 1)
        await waitUntil { runner.deleteStatuses[1] != .megaphoning && runner.deleteStatuses[1] != nil }

        #expect(runner.deleteStatuses[1] == .succeeded)
        let tokens = await client.deleteProductCalls.map(\.token)
        #expect(tokens == ["token-1", "token-2"])
    }

    @Test("um segundo toque enquanto já está apagando não dispara outra chamada")
    func apagarDuploToqueNaoDuplica() async {
        let client = StubEnjoeiClient()
        let runner = makeRunner(client: client)

        runner.deleteProduct(productID: 1)
        runner.deleteProduct(productID: 1)
        await waitUntil { runner.deleteStatuses[1] != .megaphoning && runner.deleteStatuses[1] != nil }

        #expect(await client.deleteProductCalls.count == 1)
    }

    @Test("produto já apagado não é megafonado numa rodada")
    func megafoneAllPulaItemApagado() async {
        let client = StubEnjoeiClient(pages: [EnjoeiFixtures.page(ids: [1, 2], endCursor: nil)])
        let runner = makeRunner(client: client)
        runner.start(sellerID: 1)
        runner.pause()
        await waitUntil { !runner.items.isEmpty }

        runner.deleteProduct(productID: 1)
        await waitUntil { runner.deleteStatuses[1] == .succeeded }

        runner.resume()
        await runner.waitUntilFinished()

        #expect(await client.megaphonedIDs == [2])
        #expect(runner.items.first { $0.id == 1 }?.status != .succeeded)
    }

    @Test("produto já apagado não pode receber desconto aplicado")
    func aplicarDescontoNaoAgeSobreProdutoApagado() async {
        let client = StubEnjoeiClient(pages: [EnjoeiFixtures.page(ids: [1], endCursor: nil)])
        let runner = makeRunner(client: client)
        runner.start(sellerID: 1)
        runner.pause()
        await waitUntil { !runner.items.isEmpty }

        runner.deleteProduct(productID: 1)
        await waitUntil { runner.deleteStatuses[1] == .succeeded }

        runner.applyDiscount(for: 1)

        #expect(runner.items.first { $0.id == 1 }?.status == .pending)
        #expect(await client.megaphonedIDs.isEmpty)
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

    @Test("inativar um produto lê o template inteiro primeiro e reenvia com product_state disable")
    func inativarComSucesso() async {
        let client = StubEnjoeiClient(templatesByProductID: [1: makeTemplate(productID: 1)])
        let runner = makeRunner(client: client)

        runner.inactivateProduct(productID: 1)
        await waitUntil { runner.inactivateStatuses[1] != .megaphoning && runner.inactivateStatuses[1] != nil }

        #expect(runner.inactivateStatuses[1] == .succeeded)
        #expect(await client.requestedTemplateIDs == [1])
        let call = await client.updateProductStateCalls.first
        #expect(call?.productID == 1)
        #expect(call?.request.product.title == "produto 1")
    }

    @Test("erro ao ler o template antes de inativar vira falha, sem chegar a inativar")
    func inativarFalhaAoLerTemplate() async {
        let client = StubEnjoeiClient(templateError: .http(status: 500, message: "o enjoei caiu"))
        let runner = makeRunner(client: client)

        runner.inactivateProduct(productID: 1)
        await waitUntil { runner.inactivateStatuses[1] != .megaphoning && runner.inactivateStatuses[1] != nil }

        #expect(runner.inactivateStatuses[1] == .failed("o enjoei caiu"))
        #expect(await client.updateProductStateCalls.isEmpty)
    }

    @Test("token CSRF recusado ao inativar é renovado e a inativação sai do mesmo jeito")
    func inativarRenovaTokenRecusado() async {
        let client = StubEnjoeiClient(
            csrfRejectionsRemaining: 1,
            templatesByProductID: [1: makeTemplate(productID: 1)]
        )
        let runner = makeRunner(client: client)

        runner.inactivateProduct(productID: 1)
        await waitUntil { runner.inactivateStatuses[1] != .megaphoning && runner.inactivateStatuses[1] != nil }

        #expect(runner.inactivateStatuses[1] == .succeeded)
        let tokens = await client.updateProductStateCalls.map(\.token)
        #expect(tokens == ["token-1", "token-2"])
    }

    @Test("um segundo toque enquanto já está inativando não dispara outra chamada")
    func inativarDuploToqueNaoDuplica() async {
        let client = StubEnjoeiClient(templatesByProductID: [1: makeTemplate(productID: 1)])
        let runner = makeRunner(client: client)

        runner.inactivateProduct(productID: 1)
        runner.inactivateProduct(productID: 1)
        await waitUntil { runner.inactivateStatuses[1] != .megaphoning && runner.inactivateStatuses[1] != nil }

        #expect(await client.updateProductStateCalls.count == 1)
    }

    @Test("produto já inativado não é megafonado numa rodada")
    func megafoneAllPulaItemInativado() async {
        let client = StubEnjoeiClient(
            pages: [EnjoeiFixtures.page(ids: [1, 2], endCursor: nil)],
            templatesByProductID: [1: makeTemplate(productID: 1)]
        )
        let runner = makeRunner(client: client)
        runner.start(sellerID: 1)
        runner.pause()
        await waitUntil { !runner.items.isEmpty }

        runner.inactivateProduct(productID: 1)
        await waitUntil { runner.inactivateStatuses[1] == .succeeded }

        runner.resume()
        await runner.waitUntilFinished()

        #expect(await client.megaphonedIDs == [2])
        #expect(runner.items.first { $0.id == 1 }?.status != .succeeded)
    }

    /// Espera uma condição do runner sem prender o teste para sempre se algo der errado.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<10_000 where !condition() {
            await Task.yield()
        }
    }
}
