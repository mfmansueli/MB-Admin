import SwiftUI

/// Cartão no topo da fila de ações: quanto falta pra próxima ação (ou qual está em voo agora, ou
/// que a fila está pausada) e, embaixo, o ritmo e quantas esperam a vez.
///
/// View própria por causa do `TimelineView`: o tique de cada segundo só invalida este cartão, não a
/// lista inteira da fila — e nem a barra de cima, que já mostrou "Unable to simultaneously satisfy
/// constraints" a cada tique quando o relógio morava junto dela.
struct PostQueueScheduleCard: View {
    let postQueue: PostQueue
    let waitingCount: Int

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack(spacing: 12) {
                Image(systemName: symbolName)
                    .font(.title2)
                    .foregroundStyle(symbolColor)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(headline)
                        .font(.headline)
                        .monospacedDigit()
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.supportingText)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
        }
    }

    private var secondsUntilNextAction: Int? {
        guard let nextActionAt = postQueue.nextActionAt, nextActionAt > .now else { return nil }
        return Int(nextActionAt.timeIntervalSinceNow.rounded(.up))
    }

    private var headline: String {
        PostQueueStatusText.headline(
            isPaused: postQueue.isPaused,
            inFlightKind: postQueue.currentItem?.kind,
            secondsUntilNextAction: secondsUntilNextAction,
            waitingCount: waitingCount
        )
    }

    private var subtitle: String {
        if postQueue.isPaused {
            return waitingCount > 0
                ? "toque em continuar quando quiser · \(waitingCount) na fila"
                : "toque em continuar quando quiser"
        }
        return PostQueueStatusText.summary(interval: postQueue.interval, waitingCount: waitingCount)
    }

    private var symbolName: String {
        if postQueue.isPaused { return "pause.circle" }
        if postQueue.currentItem != nil { return "arrow.triangle.2.circlepath" }
        return "timer"
    }

    private var symbolColor: Color {
        if postQueue.currentItem != nil, !postQueue.isPaused { return .statusInProgress }
        return .supportingText
    }
}
