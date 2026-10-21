import SwiftUI

/// `.buttonStyle(.glass)` do iOS/Mac Catalyst 26 nas cápsulas soltas do redesign ("todos", o menu
/// de repetições), com `.bordered` antes disso. Aplica também em `Menu` — o rótulo de um menu
/// segue o estilo de botão do ambiente.
struct GlassButtonStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

extension View {
    func glassButtonStyle() -> some View {
        modifier(GlassButtonStyleModifier())
    }
}
