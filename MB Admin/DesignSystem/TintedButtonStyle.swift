import SwiftUI

/// Botão preenchido do redesign — cápsula (ou círculo, só com ícone) numa cor de papel: a ação
/// principal (`.accentColor`), "parar"/"apagar" (`.statusFailure`), o desconto pendente
/// (`.statusDecision`). O texto usa sempre `.onTint` em vez de branco fixo: no escuro a ação
/// principal vira quase branca (`#F2F2F7`), e texto branco em cima dela sumiria.
///
/// Vidro tingido a partir do iOS/Mac Catalyst 26, cor sólida antes disso — mesmo critério de
/// `BulkConfirmButton`.
struct TintedButtonStyle: ButtonStyle {
    enum Shape {
        case capsule
        case circle
    }

    let tint: Color
    var shape: Shape = .capsule
    /// Altura (e largura, no círculo) — 44 é o mínimo de alvo de toque; o painel do megafone e a
    /// barra de baixo usam 48 pra combinar com as cápsulas de vidro ao lado.
    var size: CGFloat = 44

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(.onTint)
            .padding(.horizontal, shape == .capsule ? 16 : 0)
            .frame(width: shape == .circle ? size : nil, height: size)
            .modifier(TintedBackground(tint: tint, shape: shape))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(.rect)
    }

    private struct TintedBackground: ViewModifier {
        let tint: Color
        let shape: TintedButtonStyle.Shape

        func body(content: Content) -> some View {
            switch shape {
            case .capsule: tinted(content, in: Capsule())
            case .circle: tinted(content, in: Circle())
            }
        }

        @ViewBuilder
        private func tinted(_ content: Content, in shape: some SwiftUI.Shape) -> some View {
            if #available(iOS 26.0, macCatalyst 26.0, *) {
                content.glassEffect(.regular.tint(tint).interactive(), in: shape)
            } else {
                content.background(tint, in: shape)
            }
        }
    }
}

extension ButtonStyle where Self == TintedButtonStyle {
    static func tinted(_ tint: Color, shape: TintedButtonStyle.Shape = .capsule, size: CGFloat = 44) -> TintedButtonStyle {
        TintedButtonStyle(tint: tint, shape: shape, size: size)
    }
}

#Preview {
    VStack(spacing: 12) {
        Button {} label: { Label("megafonar", systemImage: "megaphone.fill") }
            .buttonStyle(.tinted(.accentColor, size: 48))
        Button {} label: { Label("parar", systemImage: "stop.fill") }
            .buttonStyle(.tinted(.statusFailure, size: 48))
        Button {} label: { Text("- 56%") }
            .buttonStyle(.tinted(.statusDecision, size: 34))
        Button {} label: { Image(systemName: "checkmark") }
            .buttonStyle(.tinted(.accentColor, shape: .circle))
    }
    .padding()
}
