import Foundation
import Testing
@testable import MB_Admin

@Suite("textos do cartão da fila de ações")
struct PostQueueStatusTextTests {
    @Test("intervalo curto em segundos, a partir de um minuto em minutos")
    func rotuloDoIntervalo() {
        #expect(PostQueueStatusText.intervalLabel(30) == "30s")
        #expect(PostQueueStatusText.intervalLabel(60) == "1 min")
        #expect(PostQueueStatusText.intervalLabel(180) == "3 min")
    }

    @Test("ritmo em palavras — um minuto vira \"1 a cada minuto\"")
    func ritmo() {
        #expect(PostQueueStatusText.pace(interval: 60) == "1 a cada minuto")
        #expect(PostQueueStatusText.pace(interval: 30) == "1 a cada 30s")
        #expect(PostQueueStatusText.pace(interval: 120) == "1 a cada 2 min")
    }

    @Test("linha de apoio junta o ritmo e quantos esperam a vez, só quando tem algum esperando")
    func resumo() {
        #expect(PostQueueStatusText.summary(interval: 60, waitingCount: 5) == "1 a cada minuto · 5 na fila")
        #expect(PostQueueStatusText.summary(interval: 60, waitingCount: 0) == "1 a cada minuto")
    }

    @Test("contagem regressiva em minutos e segundos, sem passar de zero")
    func contagemRegressiva() {
        #expect(PostQueueStatusText.countdown(seconds: 42) == "0:42")
        #expect(PostQueueStatusText.countdown(seconds: 245) == "4:05")
        #expect(PostQueueStatusText.countdown(seconds: -3) == "0:00")
    }

    @Test("pausada fala mais alto que tudo; depois a ação em voo; depois quanto falta")
    func linhaPrincipal() {
        #expect(
            PostQueueStatusText.headline(isPaused: true, inFlightKind: .post, secondsUntilNextAction: 30, waitingCount: 2)
                == "fila pausada"
        )
        #expect(
            PostQueueStatusText.headline(isPaused: false, inFlightKind: .delete, secondsUntilNextAction: nil, waitingCount: 2)
                == "apagando agora…"
        )
        #expect(
            PostQueueStatusText.headline(isPaused: false, inFlightKind: nil, secondsUntilNextAction: 42, waitingCount: 2)
                == "próxima ação em 0:42"
        )
    }

    @Test("sem espera nem ação em voo: processando se ainda tem fila, senão nada esperando")
    func linhaPrincipalSemEspera() {
        #expect(
            PostQueueStatusText.headline(isPaused: false, inFlightKind: nil, secondsUntilNextAction: nil, waitingCount: 1)
                == "processando agora…"
        )
        #expect(
            PostQueueStatusText.headline(isPaused: false, inFlightKind: nil, secondsUntilNextAction: nil, waitingCount: 0)
                == "nada esperando a vez"
        )
    }
}
