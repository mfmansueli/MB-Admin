import SwiftUI
import WidgetKit

/// A Live Activity de uma rodada do megafone: tela bloqueada (`MegaphoneLockScreenView`) e Dynamic
/// Island — compacta com o megafone e "12/340", expandida com o nome da conta, "12 de 340", a barra
/// e pausar/parar.
struct MegaphoneLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MegaphoneActivityAttributes.self) { context in
            MegaphoneLockScreenView(attributes: context.attributes, content: context.state)
                .activityBackgroundTint(LiveActivityPalette.lockScreenBackground)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.attributes.accountName)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: "megaphone.fill")
                            .foregroundStyle(LiveActivityPalette.brandCoral)
                    }
                    .font(.subheadline.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.title)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 12) {
                        MegaphoneActivityProgressBar(progress: context.state.progress)
                        if context.state.isFinished {
                            if let detailText = context.state.detailText {
                                Text(detailText)
                                    .font(.footnote)
                                    .foregroundStyle(LiveActivityPalette.supportingText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            MegaphoneActivityButtons(
                                accountID: context.attributes.accountID,
                                isPaused: context.state.isPaused
                            )
                        }
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "megaphone.fill")
                    .foregroundStyle(LiveActivityPalette.brandCoral)
            } compactTrailing: {
                Text(context.state.compactText)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "megaphone.fill")
                    .foregroundStyle(LiveActivityPalette.brandCoral)
            }
        }
    }
}

#Preview(
    "tela bloqueada",
    as: .content,
    using: MegaphoneActivityAttributes(accountID: UUID(), accountName: "antonia")
) {
    MegaphoneLiveActivityWidget()
} contentStates: {
    MegaphoneActivityContent(
        title: "12 de 340",
        compactText: "12/340",
        roundText: "rodada 2 de 5",
        progress: 0.21,
        detailText: "2 com erro · 3 pedem desconto",
        isPaused: false,
        isFinished: false
    )
}
