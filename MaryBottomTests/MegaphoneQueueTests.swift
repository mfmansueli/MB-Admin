import Foundation
import Testing
@testable import MaryBottom

@Suite("fila de concorrência do megafone")
struct MegaphoneQueueTests {
    private func makeRunner() -> MegaphoneRunner {
        MegaphoneRunner(client: StubEnjoeiClient())
    }

    @Test("com vaga livre, acquire não espera")
    func comVagaLivreAcquireNaoEspera() async {
        let queue = MegaphoneQueue(concurrencyLimit: 2)
        let runnerA = makeRunner()
        let runnerB = makeRunner()

        await queue.acquire(runnerA)
        await queue.acquire(runnerB)

        #expect(!queue.isWaiting(runnerA))
        #expect(!queue.isWaiting(runnerB))
    }

    @Test("sem vaga livre, a segunda conta espera até a primeira liberar")
    func semVagaLivreSegundaContaEsperaAPrimeiraLiberar() async {
        let queue = MegaphoneQueue(concurrencyLimit: 1)
        let runnerA = makeRunner()
        let runnerB = makeRunner()

        await queue.acquire(runnerA)

        let acquiredB = Task { await queue.acquire(runnerB) }
        await waitUntil { queue.isWaiting(runnerB) }
        #expect(queue.isWaiting(runnerB))

        queue.release(runnerA)
        await acquiredB.value

        #expect(!queue.isWaiting(runnerB))
    }

    @Test("cancelar enquanto espera libera a vez sem travar a fila")
    func cancelarEnquantoEsperaLiberaAVezSemTravar() async {
        let queue = MegaphoneQueue(concurrencyLimit: 1)
        let runnerA = makeRunner()
        let runnerB = makeRunner()
        let runnerC = makeRunner()

        await queue.acquire(runnerA)

        let taskB = Task { await queue.acquire(runnerB) }
        await waitUntil { queue.isWaiting(runnerB) }
        taskB.cancel()
        await taskB.value
        await waitUntil { !queue.isWaiting(runnerB) }

        // Mesmo com B tendo desistido, C ainda consegue entrar na fila e ser promovido quando A
        // libera — a desistência de B não deixa a fila travada.
        let taskC = Task { await queue.acquire(runnerC) }
        await waitUntil { queue.isWaiting(runnerC) }

        queue.release(runnerA)
        await taskC.value

        #expect(!queue.isWaiting(runnerC))
    }

    @Test("release é seguro mesmo pra quem nunca chegou a ocupar uma vaga")
    func releaseSeguroParaQuemNuncaOcupouVaga() async {
        let queue = MegaphoneQueue(concurrencyLimit: 1)
        let runner = makeRunner()

        // Sem crash nem efeito colateral — só não faz nada, já que essa conta nunca chamou acquire.
        queue.release(runner)

        #expect(!queue.isWaiting(runner))
    }

    @Test("aviso de memória segura vaga nova mesmo com o limite base sem cap")
    func avisoDeMemoriaSeguraVagaNova() async {
        let queue = MegaphoneQueue(concurrencyLimit: .max)
        let runnerA = makeRunner()
        let runnerB = makeRunner()
        await queue.acquire(runnerA)

        queue.applyMemoryPressureCap(1)

        let acquiredB = Task { await queue.acquire(runnerB) }
        await waitUntil { queue.isWaiting(runnerB) }
        #expect(queue.isWaiting(runnerB))

        queue.release(runnerA)
        await acquiredB.value
        #expect(!queue.isWaiting(runnerB))
    }

    @Test("fila esvaziar esquece o teto de memória sozinha, sem aviso de \"acabou\" explícito")
    func filaEsvaziarEsqueceOTetoDeMemoria() async {
        let queue = MegaphoneQueue(concurrencyLimit: .max)
        let runnerA = makeRunner()
        let runnerB = makeRunner()
        await queue.acquire(runnerA)
        queue.applyMemoryPressureCap(1)

        // Só A rodando: libera A e a fila esvazia — o teto se desfaz sozinho (ver
        // `MegaphoneQueue.release`), então B (chegando depois, sem esperar ninguém) entra na hora,
        // sem precisar de outro aviso "voltou ao normal" do sistema.
        queue.release(runnerA)
        await queue.acquire(runnerB)

        #expect(!queue.isWaiting(runnerB))
    }

    /// Espera uma condição sem prender o teste pra sempre se algo der errado.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<10_000 where !condition() {
            await Task.yield()
        }
    }
}
