import SwiftUI

/// Barra fina de andamento da rodada — branca sobre trilha translúcida, como no board. Sem
/// progresso conhecido (esperando a vez), fica só a trilha.
struct MegaphoneActivityProgressBar: View {
    let progress: Double?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                if let progress {
                    Capsule()
                        .fill(.white)
                        .frame(width: proxy.size.width * min(max(progress, 0), 1))
                }
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityLabel("progresso")
        .accessibilityValue(progress.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "")
    }
}
