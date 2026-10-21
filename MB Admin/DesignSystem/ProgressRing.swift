import SwiftUI

/// Anel de progresso da row de uma conta rodando na lista de contas — o mesmo andamento da barra do
/// painel do megafone, num formato que cabe no canto da row. Desenha com o `foregroundStyle` do
/// ambiente (a trilha na mesma cor, mais clara), pra quem usa decidir a cor — inclusive um estilo
/// hierárquico numa row selecionada.
struct ProgressRing: View {
    let progress: Double
    var size: CGFloat = 36
    var lineWidth: CGFloat = 4

    var body: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: lineWidth)
                .opacity(0.2)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .animation(.default, value: progress)
        .accessibilityElement()
        .accessibilityLabel("progresso")
        .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
    }
}

#Preview {
    ProgressRing(progress: 0.21)
        .foregroundStyle(.tint)
        .padding()
}
