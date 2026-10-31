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

    @Test("com o grupo da próxima ação, o resumo diz pra quem vale o ritmo")
    func resumoComGrupo() {
        #expect(
            PostQueueStatusText.summary(interval: 15, waitingCount: 12, group: .statusChange)
                == "1 a cada 15s pra ativar e inativar · 12 na fila"
        )
        #expect(
            PostQueueStatusText.summary(interval: 30, waitingCount: 0, group: .posting)
                == "1 a cada 30s pra postar, repostar e apagar"
        )
    }

    @Test("menu de intervalo mostra os dois ritmos, postar primeiro")
    func rotuloDoMenuDeIntervalo() {
        #expect(PostQueueStatusText.intervalMenuLabel(posting: 30, statusChange: 15) == "30s · 15s")
        #expect(PostQueueStatusText.intervalMenuLabel(posting: 120, statusChange: 60) == "2 min · 1 min")
        #expect(
            PostQueueStatusText.intervalMenuAccessibilityValue(posting: 30, statusChange: 15)
                == "postar, repostar e apagar: 1 a cada 30s; ativar e inativar: 1 a cada 15s"
        )
    }

    @Test("confirmação em massa termina no ritmo que a fila vai usar")
    func notaDoRitmoNaConfirmacao() {
        #expect(
            PostQueueStatusText.queuePaceNote(interval: 15)
                == "a fila faz 1 a cada 15s — dá pra mudar o intervalo na tela da fila de ações."
        )
    }

    @Test("progresso conta os já terminados, com sucesso ou erro, no singular e no plural")
    func progresso() {
        #expect(PostQueueStatusText.progress(processed: 12, total: 150) == "12 de 150 produtos processados")
        #expect(PostQueueStatusText.progress(processed: 0, total: 1) == "0 de 1 produto processado")
        #expect(PostQueueStatusText.failures(count: 2) == "2 com erro")
    }

    @Test("a seguir, a próxima ação no infinitivo, com as contas")
    func proximaAcao() {
        let source = UUID()
        let destination = UUID()
        func item(_ kind: PostQueueItem.Kind, to destinationID: UUID) -> PostQueueItem {
            PostQueueItem(
                id: UUID(),
                product: EnjoeiFixtures.product(id: 1),
                kind: kind,
                sourceAccountID: source,
                sourceAccountName: "antonia",
                destinationAccountID: destinationID,
                destinationAccountName: destinationID == source ? "antonia" : "loja B"
            )
        }
        #expect(PostQueueStatusText.upcomingAction(for: item(.post, to: destination)) == "postar de antonia para loja B")
        #expect(PostQueueStatusText.upcomingAction(for: item(.post, to: source)) == "repostar em antonia")
        #expect(PostQueueStatusText.upcomingAction(for: item(.delete, to: source)) == "apagar em antonia")
        #expect(PostQueueStatusText.upcomingAction(for: item(.inactivate, to: source)) == "inativar em antonia")
        #expect(PostQueueStatusText.upcomingAction(for: item(.activate, to: source)) == "ativar em antonia")
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

    @Test("sem espera nem ação em voo: processando se ainda tem fila, senão acabou — com ou sem erro")
    func linhaPrincipalSemEspera() {
        #expect(
            PostQueueStatusText.headline(isPaused: false, inFlightKind: nil, secondsUntilNextAction: nil, waitingCount: 1)
                == "processando agora…"
        )
        #expect(
            PostQueueStatusText.headline(isPaused: false, inFlightKind: nil, secondsUntilNextAction: nil, waitingCount: 0)
                == "tudo processado"
        )
        #expect(
            PostQueueStatusText.headline(
                isPaused: false, inFlightKind: nil, secondsUntilNextAction: nil, waitingCount: 0, failedCount: 2
            ) == "acabou, 2 com erro"
        )
    }
}
