import AppIntents
import SwiftUI
import WidgetKit

/// A Live Activity na tela bloqueada (e no banner): o megafone, "antonia · rodada 2 de 5", o número
/// grande ("12 de 340") com o pausar/continuar ao lado, a barra de andamento e, embaixo, o que pede
/// atenção ("2 com erro · 3 pedem desconto").
struct MegaphoneLockScreenView: View {
    let attributes: MegaphoneActivityAttributes
    let content: MegaphoneActivityContent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "megaphone.fill")
                    .font(.title3)
                    .foregroundStyle(LiveActivityPalette.iconTileForeground)
                    .frame(width: 44, height: 44)
                    .background(LiveActivityPalette.iconTileBackground, in: .rect(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(LiveActivityPalette.supportingText)
                        .lineLimit(1)
                    Text(content.title)
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
                if !content.isFinished {
                    Button(intent: ToggleMegaphonePauseIntent(accountID: attributes.accountID)) {
                        Image(systemName: content.isPaused ? "play.fill" : "pause.fill")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                            .background(LiveActivityPalette.buttonFill, in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(content.isPaused ? "continuar rodada" : "pausar rodada")
                }
            }
            MegaphoneActivityProgressBar(progress: content.progress)
            if let detailText = content.detailText {
                Text(detailText)
                    .font(.footnote)
                    .foregroundStyle(LiveActivityPalette.supportingText)
                    .lineLimit(2)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
    }

    /// "antonia · rodada 2 de 5" — pausado, avisa no lugar da rodada.
    private var subtitle: String {
        let state = content.isPaused ? "pausado" : content.roundText
        return [attributes.accountName, state].compactMap { $0 }.joined(separator: " · ")
    }
}
