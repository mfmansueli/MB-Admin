import Foundation
import Testing
@testable import MB_Admin

@Suite("desistir de operação calada")
struct StallTimeoutTests {
    private struct Stalled: Error, Equatable {}
    private struct Broke: Error, Equatable {}

    @Test("devolve o valor de uma operação que termina")
    func devolveOValor() async throws {
        let value = try await StallTimeout.run(timeout: .seconds(5), stalledError: Stalled()) { _ in 42 }

        #expect(value == 42)
    }

    @Test("erro da própria operação passa direto")
    func erroDaOperacao() async {
        await #expect(throws: Broke.self) {
            try await StallTimeout.run(timeout: .seconds(5), stalledError: Stalled()) { _ -> Int in
                throw Broke()
            }
        }
    }

    @Test("desiste da operação que fica calada e cancela o Task dela")
    func desisteDaOperacaoCalada() async {
        var operationWasCancelled = false

        await #expect(throws: Stalled.self) {
            try await StallTimeout.run(timeout: .milliseconds(100), stalledError: Stalled()) { _ -> Int in
                do {
                    try await Task.sleep(for: .seconds(3600))
                } catch {
                    operationWasCancelled = true
                    throw error
                }
                return 1
            }
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while !operationWasCancelled, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }

        #expect(operationWasCancelled)
    }

    @Test("cada aviso de progresso reinicia o prazo")
    func progressoReiniciaOPrazo() async throws {
        // Dura uma vez e meia o prazo inteiro, mas avisa a cada 10ms — nenhum intervalo sem notícia
        // chega perto do prazo, nem com a suíte inteira disputando o main actor.
        let timeout = Duration.seconds(1)
        let end = ContinuousClock.now.advanced(by: timeout * 1.5)
        let value = try await StallTimeout.run(timeout: timeout, stalledError: Stalled()) { markProgress in
            while ContinuousClock.now < end {
                try await Task.sleep(for: .milliseconds(10))
                markProgress()
            }
            return "terminou"
        }

        #expect(value == "terminou")
    }
}
