import AppIntents
import SwiftUI
import WidgetKit

/// "pausar"/"continuar" e "parar", lado a lado — embaixo da Dynamic Island expandida. Mesmo efeito
/// dos botões do painel do megafone no app (ver `ToggleMegaphonePauseIntent`/`StopMegaphoneIntent`).
struct MegaphoneActivityButtons: View {
    let accountID: UUID
    let isPaused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button(intent: ToggleMegaphonePauseIntent(accountID: accountID)) {
                Text(isPaused ? "continuar" : "pausar")
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(LiveActivityPalette.buttonFill, in: .capsule)
            }
            .foregroundStyle(.white)
            Button(intent: StopMegaphoneIntent(accountID: accountID)) {
                Text("parar")
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(LiveActivityPalette.stop, in: .capsule)
            }
            .foregroundStyle(.black)
        }
        .buttonStyle(.plain)
        .font(.subheadline.weight(.semibold))
    }
}
