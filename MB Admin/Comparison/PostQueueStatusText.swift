import Foundation

/// Os textos do cartão no topo da fila de ações ("próxima ação em 0:42" / "1 a cada minuto · 5 na
/// fila" / "12 de 150 produtos processados"), do menu de intervalo e do ritmo citado nas
/// confirmações em massa — puros, pra tela só escolher qual mostrar.
nonisolated enum PostQueueStatusText {
    /// Rótulo curto do intervalo, no menu da barra de baixo: "30s" abaixo de um minuto, "N min" a
    /// partir de 1 minuto.
    static func intervalLabel(_ interval: TimeInterval) -> String {
        interval < 60 ? "\(Int(interval))s" : "\(Int(interval / 60)) min"
    }

    /// O ritmo da fila em palavras — "1 a cada minuto", "1 a cada 2 min", "1 a cada 30s".
    static func pace(interval: TimeInterval) -> String {
        interval == 60 ? "1 a cada minuto" : "1 a cada \(intervalLabel(interval))"
    }

    /// Linha de apoio do cartão: o ritmo e quantos ainda esperam a vez (quando tem algum). Com o
    /// grupo da próxima ação, diz pra quem vale esse ritmo ("1 a cada 15s pra inativar").
    static func summary(interval: TimeInterval, waitingCount: Int, group: PostQueueIntervalGroup? = nil) -> String {
        var pace = pace(interval: interval)
        if let group { pace += " pra \(group.title)" }
        return waitingCount > 0 ? "\(pace) · \(waitingCount) na fila" : pace
    }

    /// Rótulo do menu de intervalo na barra de baixo: os dois ritmos, postar primeiro ("30s · 15s").
    static func intervalMenuLabel(posting: TimeInterval, inactivating: TimeInterval) -> String {
        "\(intervalLabel(posting)) · \(intervalLabel(inactivating))"
    }

    /// O que o VoiceOver lê no menu de intervalo, com o nome de cada grupo.
    static func intervalMenuAccessibilityValue(posting: TimeInterval, inactivating: TimeInterval) -> String {
        "\(PostQueueIntervalGroup.posting.title): \(pace(interval: posting)); "
            + "\(PostQueueIntervalGroup.inactivating.title): \(pace(interval: inactivating))"
    }

    /// Fim da mensagem das confirmações em massa que entram na fila — o ritmo que vai valer, já
    /// que ele não se escolhe ali, só na tela da fila.
    static func queuePaceNote(interval: TimeInterval) -> String {
        "a fila faz \(pace(interval: interval)) — dá pra mudar o intervalo na tela da fila de ações."
    }

    /// "12 de 150 produtos processados" — processado é o que já terminou, com sucesso ou com erro.
    static func progress(processed: Int, total: Int) -> String {
        total == 1 ? "\(processed) de 1 produto processado" : "\(processed) de \(total) produtos processados"
    }

    /// "1 com erro" / "3 com erro", ao lado do progresso.
    static func failures(count: Int) -> String {
        "\(count) com erro"
    }

    /// A próxima ação no infinitivo, pro "a seguir" do cartão: "postar de antonia para loja B",
    /// "repostar em antonia", "inativar em antonia".
    static func upcomingAction(for item: PostQueueItem) -> String {
        switch item.kind {
        case .post:
            item.sourceAccountID == item.destinationAccountID
                ? "repostar em \(item.sourceAccountName)"
                : "postar de \(item.sourceAccountName) para \(item.destinationAccountName)"
        case .delete: "apagar em \(item.sourceAccountName)"
        case .inactivate: "inativar em \(item.sourceAccountName)"
        case .activate: "ativar em \(item.sourceAccountName)"
        }
    }

    /// O começo da linha principal enquanto a fila espera — a tela pinta só a contagem que vem
    /// depois dele de vermelho.
    static let waitingPrefix = "próxima ação em"

    /// "0:42", "4:05" — minutos e segundos que faltam pra próxima ação.
    static func countdown(seconds: Int) -> String {
        let seconds = max(seconds, 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// Linha principal do cartão. Pausada fala mais alto que tudo; com uma ação em voo, diz qual;
    /// esperando o intervalo, quanto falta; e parada sem nada esperando, que acabou — com erro ou
    /// não.
    static func headline(
        isPaused: Bool,
        inFlightKind: PostQueueItem.Kind?,
        secondsUntilNextAction: Int?,
        waitingCount: Int,
        failedCount: Int = 0
    ) -> String {
        if isPaused { return "fila pausada" }
        if let inFlightKind { return inFlightLabel(for: inFlightKind) }
        if let secondsUntilNextAction, secondsUntilNextAction > 0 {
            return "\(waitingPrefix) \(countdown(seconds: secondsUntilNextAction))"
        }
        if waitingCount > 0 { return "processando agora…" }
        return failedCount > 0 ? "acabou, \(failures(count: failedCount))" : "tudo processado"
    }

    static func inFlightLabel(for kind: PostQueueItem.Kind) -> String {
        switch kind {
        case .post: "postando agora…"
        case .delete: "apagando agora…"
        case .inactivate: "inativando agora…"
        case .activate: "ativando agora…"
        }
    }
}
