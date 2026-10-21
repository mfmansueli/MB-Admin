import SwiftUI

/// Superfície presa em cima ou embaixo da tela — o seletor de abas do detalhe da conta (em cima), o
/// painel do megafone e a barra da seleção (embaixo). O conteúdo da lista rola por baixo dela e a
/// primeira/última linha continuam alcançáveis. `safeAreaBar` a partir do iOS/Mac Catalyst 26, que
/// ainda aplica o efeito de borda de rolagem do sistema atrás da barra; `safeAreaInset` antes
/// disso — aí, em cima, com um fundo de barra próprio, já que sem o efeito a lista apareceria
/// por trás do seletor.
struct FloatingBar<BarContent: View>: ViewModifier {
    let edge: VerticalEdge
    @ViewBuilder let barContent: () -> BarContent

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            content.safeAreaBar(edge: edge, content: barContent)
        } else {
            content.safeAreaInset(edge: edge) {
                if edge == .top {
                    barContent().background(.bar)
                } else {
                    barContent()
                }
            }
        }
    }
}

extension View {
    func floatingBottomBar(@ViewBuilder _ content: @escaping () -> some View) -> some View {
        modifier(FloatingBar(edge: .bottom, barContent: content))
    }

    func floatingTopBar(@ViewBuilder _ content: @escaping () -> some View) -> some View {
        modifier(FloatingBar(edge: .top, barContent: content))
    }
}
