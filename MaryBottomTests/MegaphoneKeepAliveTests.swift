import Foundation
import Testing
@testable import MaryBottom

@Suite("manter o megafone rodando")
struct MegaphoneKeepAliveTests {
    private func makeRunner() -> MegaphoneRunner {
        let client = StubEnjoeiClient(pages: [EnjoeiFixtures.page(ids: [1, 2, 3], endCursor: nil)])
        let runner = MegaphoneRunner(client: client)
        runner.delayBetweenProducts = .milliseconds(20)
        return runner
    }

    @Test("com áudio segurando o app, sair da tela não pausa a rodada")
    func segundoPlanoComAudioNaoPausa() async {
        let runner = makeRunner()
        let audio = FakeBackgroundAudio()
        let keepAlive = MegaphoneKeepAlive(runner: runner, coordinator: MegaphoneKeepAliveCoordinator(audio: audio))
        runner.start(sellerID: 1)
        keepAlive.start()

        keepAlive.applicationWentToBackground()

        #expect(audio.startCount == 1)
        #expect(keepAlive.keepsRunningInBackground)
        #expect(runner.isPaused == false)
        runner.cancel()
        await runner.waitUntilFinished()
    }

    @Test("sem áudio, sair da tela pausa para não acumular erro")
    func segundoPlanoSemAudioPausa() async {
        let runner = makeRunner()
        let audio = FakeBackgroundAudio()
        audio.failsToStart = true
        let keepAlive = MegaphoneKeepAlive(runner: runner, coordinator: MegaphoneKeepAliveCoordinator(audio: audio))
        runner.start(sellerID: 1)
        keepAlive.start()

        keepAlive.applicationWentToBackground()

        #expect(keepAlive.keepsRunningInBackground == false)
        #expect(runner.pauseReason == .background)

        keepAlive.applicationBecameActive()
        #expect(runner.isPaused == false)
        runner.cancel()
        await runner.waitUntilFinished()
    }

    @Test("ligação recebida pausa a rodada e o fim dela retoma")
    func interrupcaoDeAudioPausaERetoma() async {
        let runner = makeRunner()
        let audio = FakeBackgroundAudio()
        let keepAlive = MegaphoneKeepAlive(runner: runner, coordinator: MegaphoneKeepAliveCoordinator(audio: audio))
        runner.start(sellerID: 1)
        keepAlive.start()

        audio.interrupt(began: true)
        #expect(runner.pauseReason == .background)

        audio.interrupt(began: false)
        #expect(runner.isPaused == false)

        await runner.waitUntilFinished()
        #expect(runner.phase == .finished)
    }

    @Test("terminar a rodada desliga o áudio")
    func fimDaRodadaDesligaOAudio() async {
        let runner = makeRunner()
        let audio = FakeBackgroundAudio()
        let keepAlive = MegaphoneKeepAlive(runner: runner, coordinator: MegaphoneKeepAliveCoordinator(audio: audio))

        keepAlive.start()
        keepAlive.stop()

        #expect(audio.stopCount == 1)
        #expect(audio.isKeepingAwake == false)
    }

    @Test("parar uma conta não desliga o áudio de outra ainda rodando")
    func duasContasCompartilhamOCoordenador() async {
        let audio = FakeBackgroundAudio()
        let coordinator = MegaphoneKeepAliveCoordinator(audio: audio)
        let runnerA = makeRunner()
        let runnerB = makeRunner()
        let keepAliveA = MegaphoneKeepAlive(runner: runnerA, coordinator: coordinator)
        let keepAliveB = MegaphoneKeepAlive(runner: runnerB, coordinator: coordinator)

        keepAliveA.start()
        keepAliveB.start()
        #expect(audio.startCount == 1)

        // A conta A termina primeiro; a conta B continua rodando.
        keepAliveA.stop()
        #expect(audio.isKeepingAwake)
        #expect(coordinator.isKeepingAwake)

        keepAliveB.stop()
        #expect(audio.isKeepingAwake == false)
        #expect(audio.stopCount == 1)

        runnerA.cancel()
        runnerB.cancel()
        await runnerA.waitUntilFinished()
        await runnerB.waitUntilFinished()
    }
}
