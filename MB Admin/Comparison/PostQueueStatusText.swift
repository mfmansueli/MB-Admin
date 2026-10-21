import Foundation

/// Os textos do cartão no topo da fila de ações ("próxima ação em 0:42" / "1 a cada minuto · 5 na
/// fila") e do menu de intervalo — puros, pra tela só escolher qual mostrar.
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

    /// Linha de apoio do cartão: o ritmo e quantos ainda esperam a vez (quando tem algum).
    static func summary(interval: TimeInterval, waitingCount: Int) -> String {
        let pace = pace(interval: interval)
        return waitingCount > 0 ? "\(pace) · \(waitingCount) na fila" : pace
    }

    /// "0:42", "4:05" — minutos e segundos que faltam pra próxima ação.
    static func countdown(seconds: Int) -> String {
        let seconds = max(seconds, 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// Linha principal do cartão. Pausada fala mais alto que tudo; com uma ação em voo, diz qual;
    /// esperando o intervalo, quanto falta; e parada sem nada esperando, que já acabou.
    static func headline(
        isPaused: Bool,
        inFlightKind: PostQueueItem.Kind?,
        secondsUntilNextAction: Int?,
        waitingCount: Int
    ) -> String {
        if isPaused { return "fila pausada" }
        if let inFlightKind { return inFlightLabel(for: inFlightKind) }
        if let secondsUntilNextAction, secondsUntilNextAction > 0 {
            return "próxima ação em \(countdown(seconds: secondsUntilNextAction))"
        }
        return waitingCount > 0 ? "processando agora…" : "nada esperando a vez"
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
