import Foundation
import Testing
@testable import MB_Admin

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

    @Test("teto de memória se desfazendo promove todas as contas na fila, não só a primeira")
    func tetoDesfazendoPromoveTodasAsContasNaFila() async {
        let queue = MegaphoneQueue(concurrencyLimit: .max)
        let runnerA = makeRunner()
        let runnerB = makeRunner()
        let runnerC = makeRunner()
        await queue.acquire(runnerA)
        queue.applyMemoryPressureCap(1)

        let acquiredB = Task { await queue.acquire(runnerB) }
        let acquiredC = Task { await queue.acquire(runnerC) }
        await waitUntil { queue.isWaiting(runnerB) && queue.isWaiting(runnerC) }
        #expect(queue.isWaiting(runnerB))
        #expect(queue.isWaiting(runnerC))

        // A fila esvazia (só A rodava) e o teto cai — as duas vagas abrem juntas.
        queue.release(runnerA)
        await acquiredB.value
        await acquiredC.value

        #expect(!queue.isWaiting(runnerB))
        #expect(!queue.isWaiting(runnerC))
    }

    @Test("tirar o teto de memória na mão já promove quem estava esperando por causa dele")
    func tirarOTetoNaMaoPromoveQuemEsperava() async {
        let queue = MegaphoneQueue(concurrencyLimit: .max)
        let runnerA = makeRunner()
        let runnerB = makeRunner()
        await queue.acquire(runnerA)
        queue.applyMemoryPressureCap(1)

        let acquiredB = Task { await queue.acquire(runnerB) }
        await waitUntil { queue.isWaiting(runnerB) }
        #expect(queue.isWaiting(runnerB))

        // A continua rodando — mesmo assim B entra, sem esperar A liberar.
        queue.applyMemoryPressureCap(nil)
        await acquiredB.value

        #expect(!queue.isWaiting(runnerB))
    }

    @Test("aviso de memória com ninguém megafonando não deixa teto pendurado pra próxima sessão")
    func avisoComFilaVaziaNaoDeixaTetoPendurado() async {
        let queue = MegaphoneQueue(concurrencyLimit: .max)
        let runnerA = makeRunner()
        let runnerB = makeRunner()
        let runnerC = makeRunner()

        queue.applyMemoryPressureCap(1)

        // Se o teto tivesse ficado armado, B ficaria esperando A pra sempre (A nunca libera aqui).
        await queue.acquire(runnerA)
        await queue.acquire(runnerB)
        await queue.acquire(runnerC)

        #expect(!queue.isWaiting(runnerB))
        #expect(!queue.isWaiting(runnerC))
    }

    @Test("promover várias de uma vez nunca passa do limite base")
    func promoverVariasNuncaPassaDoLimiteBase() async {
        let queue = MegaphoneQueue(concurrencyLimit: 2)
        let runnerA = makeRunner()
        let runnerB = makeRunner()
        let runnerC = makeRunner()
        let runnerD = makeRunner()
        await queue.acquire(runnerA)
        queue.applyMemoryPressureCap(1)

        let acquiredB = Task { await queue.acquire(runnerB) }
        await waitUntil { queue.isWaiting(runnerB) }
        let acquiredC = Task { await queue.acquire(runnerC) }
        await waitUntil { queue.isWaiting(runnerC) }
        let acquiredD = Task { await queue.acquire(runnerD) }
        await waitUntil { queue.isWaiting(runnerD) }

        // O teto cai com três esperando, mas o limite base continua 2: só B e C (a ordem de
        // chegada) entram; D segue esperando uma vaga de verdade.
        queue.release(runnerA)
        await acquiredB.value
        await acquiredC.value
        #expect(queue.isWaiting(runnerD))

        queue.release(runnerB)
        await acquiredD.value
        #expect(!queue.isWaiting(runnerD))
    }

    /// Espera uma condição sem prender o teste pra sempre se algo der errado.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<10_000 where !condition() {
            await Task.yield()
        }
    }
}
