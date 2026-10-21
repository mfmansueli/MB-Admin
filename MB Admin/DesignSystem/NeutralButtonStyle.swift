import SwiftUI

/// Botão secundário em cinza ("pausar", "acompanhar" desligado) — usado *dentro* de superfícies que
/// já são de vidro (o painel do megafone), onde outro vidro por cima ficaria embaçado demais. Fora
/// delas, os botões soltos usam o `.glass` do sistema.
struct NeutralButtonStyle: ButtonStyle {
    /// Círculo só com ícone (largura = altura) em vez de cápsula com texto.
    var isCircle = false
    var size: CGFloat = 48

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(.primary)
            .padding(.horizontal, isCircle ? 0 : 16)
            .frame(width: isCircle ? size : nil, height: size)
            .background(Color(uiColor: .tertiarySystemFill), in: .capsule)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(.capsule)
    }
}

extension ButtonStyle where Self == NeutralButtonStyle {
    static var neutral: NeutralButtonStyle { NeutralButtonStyle() }

    static func neutral(isCircle: Bool = false, size: CGFloat = 48) -> NeutralButtonStyle {
        NeutralButtonStyle(isCircle: isCircle, size: size)
    }
}

#Preview {
    HStack {
        Button {} label: { Label("pausar", systemImage: "pause.fill") }
            .buttonStyle(.neutral)
        Button {} label: { Image(systemName: "location") }
            .buttonStyle(.neutral(isCircle: true))
    }
    .padding()
}
