import SwiftUI

/// `.buttonStyle(.glassProminent)` do iOS/Mac Catalyst 26 nos botões de ação principal que moram
/// numa toolbar ("megafonar", "concluir seleção") — ali o vidro vem do sistema, então
/// `TintedButtonStyle` (que desenha o próprio fundo) ficaria com dois fundos. `.borderedProminent`
/// antes disso.
///
/// Quem usa precisa pôr `.foregroundStyle(.onTint)` no rótulo: os estilos proeminentes pintam o
/// texto de branco, que some em cima da ação principal no modo escuro (`#F2F2F7`).
struct ProminentGlassButtonStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}

extension View {
    func prominentGlassButtonStyle() -> some View {
        modifier(ProminentGlassButtonStyleModifier())
    }
}
