import Foundation

/// Roda uma operação que avisa o próprio progresso aos poucos e desiste dela quando passa
/// `timeout` sem aviso nenhum — pra chamadas que podem ficar penduradas pra sempre sem erro, como o
/// `callAsyncJavaScript` do lote do megafone (ver `MegaphoneRunner.batchStallTimeout`): se a página
/// de bastidores trava, o processo dela é suspenso ou um pedido fica sem resposta, a chamada
/// simplesmente nunca volta.
///
/// O prazo conta a partir do começo e reinicia a cada `markProgress()` — uma operação longa que
/// continua dando notícia nunca é interrompida, só a que fica calada.
///
/// Desistir não interrompe a operação de verdade: o `Task` dela é cancelado, mas nem toda operação
/// respeita isso (`callAsyncJavaScript` não respeita). Quem chama precisa aguentar avisos de
/// progresso atrasados chegando depois do erro, e desfazer o que sobrou dela por conta própria
/// (no megafone, recarregar a página mata o laço em JS que ficou pra trás).
enum StallTimeout {
    static func run<Value>(
        timeout: Duration,
        stalledError: any Error,
        operation: @escaping (_ markProgress: @escaping () -> Void) async throws -> Value
    ) async throws -> Value {
        let state = State<Value>()
        return try await withCheckedThrowingContinuation { continuation in
            state.continuation = continuation
            state.operationTask = Task {
                do {
                    let value = try await operation { state.markProgress() }
                    state.finish(.success(value))
                } catch {
                    state.finish(.failure(error))
                }
            }
            state.watchdogTask = Task {
                while !Task.isCancelled {
                    let deadline = state.lastProgress.advanced(by: timeout)
                    if ContinuousClock.now >= deadline {
                        state.finish(.failure(stalledError))
                        return
                    }
                    try? await Task.sleep(until: deadline, clock: .continuous)
                }
            }
        }
    }

    /// Estado compartilhado entre a operação e o vigia — quem terminar primeiro responde, o outro
    /// é ignorado.
    private final class State<Value> {
        var continuation: CheckedContinuation<Value, any Error>?
        var lastProgress = ContinuousClock.now
        var operationTask: Task<Void, Never>?
        var watchdogTask: Task<Void, Never>?

        func markProgress() {
            lastProgress = .now
        }

        func finish(_ result: Result<Value, any Error>) {
            guard let continuation else { return }
            self.continuation = nil
            watchdogTask?.cancel()
            operationTask?.cancel()
            continuation.resume(with: result)
        }
    }
}
