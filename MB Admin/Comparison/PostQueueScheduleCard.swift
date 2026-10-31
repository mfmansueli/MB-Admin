import SwiftUI

/// Cartão no topo da fila de ações: em que pé a fila está — quanto falta pra próxima ação (a
/// contagem em vermelho), qual está em voo agora, pausada ou já acabou —, qual ação roda agora e
/// qual vem a seguir, e o progresso geral ("12 de 150 produtos processados", com os erros ao lado).
///
/// View própria por causa do `TimelineView`: o tique de cada segundo só invalida este cartão, não a
/// lista inteira da fila — e nem a barra de cima, que já mostrou "Unable to simultaneously satisfy
/// constraints" a cada tique quando o relógio morava junto dela.
struct PostQueueScheduleCard: View {
    let postQueue: PostQueue
    let sections: PostQueueSections

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(alignment: .leading, spacing: 14) {
                header
                if postQueue.currentItem != nil || nextItem != nil {
                    actions
                }
                if sections.totalCount > 0 {
                    progress
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
        }
    }

    // MARK: - Situação

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.title2)
                .foregroundStyle(symbolColor)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                headlineText
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.supportingText)
            }
        }
    }

    /// Esperando o intervalo, só a contagem fica vermelha ("próxima ação em **0:24**"); o resto
    /// do texto continua na cor normal.
    @ViewBuilder
    private var headlineText: some View {
        if isCountingDown, let secondsUntilNextAction {
            let countdown = Text(PostQueueStatusText.countdown(seconds: secondsUntilNextAction))
                .foregroundStyle(.statusFailure)
            Text("\(PostQueueStatusText.waitingPrefix) \(countdown)")
        } else {
            Text(headline)
        }
    }

    private var secondsUntilNextAction: Int? {
        guard let nextActionAt = postQueue.nextActionAt, nextActionAt > .now else { return nil }
        return Int(nextActionAt.timeIntervalSinceNow.rounded(.up))
    }

    private var isCountingDown: Bool {
        !postQueue.isPaused && postQueue.currentItem == nil && (secondsUntilNextAction ?? 0) > 0
    }

    private var waitingCount: Int { sections.items(in: .waiting).count }
    private var failedCount: Int { sections.items(in: .failed).count }
    private var nextItem: PostQueueItem? { postQueue.nextItem }

    private var headline: String {
        PostQueueStatusText.headline(
            isPaused: postQueue.isPaused,
            inFlightKind: postQueue.currentItem?.kind,
            secondsUntilNextAction: secondsUntilNextAction,
            waitingCount: waitingCount,
            failedCount: failedCount
        )
    }

    /// O ritmo que vale pra próxima ação (o do grupo dela) e quantas esperam a vez.
    private var subtitle: String {
        if postQueue.isPaused {
            return waitingCount > 0
                ? "toque em continuar quando quiser · \(waitingCount) na fila"
                : "toque em continuar quando quiser"
        }
        guard let nextItem else {
            return waitingCount > 0 ? "\(waitingCount) na fila" : "nada esperando a vez"
        }
        return PostQueueStatusText.summary(
            interval: postQueue.interval(for: nextItem.kind),
            waitingCount: waitingCount,
            group: PostQueueIntervalGroup(kind: nextItem.kind)
        )
    }

    private var symbolName: String {
        if postQueue.isPaused { return "pause.circle.fill" }
        if postQueue.currentItem != nil { return "arrow.triangle.2.circlepath" }
        if isCountingDown { return "timer" }
        if waitingCount > 0 { return "arrow.triangle.2.circlepath" }
        return failedCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
    }

    /// Azul trabalhando, vermelho esperando (junto da contagem) ou com erro no fim, verde quando
    /// tudo deu certo, cinza pausada.
    private var symbolColor: Color {
        if postQueue.isPaused { return .supportingText }
        if postQueue.currentItem != nil { return .statusInProgress }
        if isCountingDown { return .statusFailure }
        if waitingCount > 0 { return .statusInProgress }
        return failedCount > 0 ? .statusFailure : .statusSuccess
    }

    // MARK: - Agora / a seguir

    private var actions: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
            if let current = postQueue.currentItem {
                actionRow(
                    label: "agora",
                    color: .statusInProgress,
                    title: current.product.title,
                    detail: current.originDestinationLine
                )
            }
            if let nextItem {
                actionRow(
                    label: "a seguir",
                    color: .supportingText,
                    title: nextItem.product.title,
                    detail: PostQueueStatusText.upcomingAction(for: nextItem)
                )
            }
        }
    }

    private func actionRow(label: String, color: Color, title: String, detail: String) -> some View {
        GridRow {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .gridColumnAlignment(.leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.supportingText)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Progresso

    private var progress: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: Double(sections.processedCount), total: Double(sections.totalCount))
                .tint(.statusSuccess)
                .accessibilityHidden(true)
            HStack(spacing: 4) {
                Text(PostQueueStatusText.progress(processed: sections.processedCount, total: sections.totalCount))
                    .foregroundStyle(.supportingText)
                if failedCount > 0 {
                    Text("· \(PostQueueStatusText.failures(count: failedCount))")
                        .fontWeight(.semibold)
                        .foregroundStyle(.statusFailure)
                }
            }
            .font(.subheadline)
            .monospacedDigit()
            .accessibilityElement(children: .combine)
        }
    }
}
