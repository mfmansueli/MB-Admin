import Foundation
import Testing
@testable import MaryBottom

@Suite("rodada de megafone")
struct MegaphoneRunnerTests {
    /// Sem espera entre produtos, os testes não ficam presos ao ritmo real do app.
    private func makeRunner(client: StubEnjoeiClient) -> MegaphoneRunner {
        let runner = MegaphoneRunner(client: client)
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

    @Test("para depois de muitas falhas seguidas")
    func paraDepoisDeFalhasSeguidas() async {
        let ids = Array(1...6)
        let client = StubEnjoeiClient(
            pages: [EnjoeiFixtures.page(ids: ids, endCursor: nil)],
            failuresByProductID: Dictionary(
                uniqueKeysWithValues: ids.map { ($0, EnjoeiError.http(status: 400, message: "não rolou")) }
            )
        )
        let runner = makeRunner(client: client)
        runner.maxConsecutiveFailures = 3

        runner.start(sellerID: 1)
        await runner.waitUntilFinished()

        #expect(runner.failedCount == 3)
        #expect(runner.items[3].status == .pending)
        if case .failed(let message) = runner.phase {
            #expect(message.contains("3 erros seguidos"))
        } else {
            Issue.record("esperava a rodada ter parado sozinha, phase = \(runner.phase)")
        }
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

    /// Espera uma condição do runner sem prender o teste para sempre se algo der errado.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<10_000 where !condition() {
            await Task.yield()
        }
    }
}
