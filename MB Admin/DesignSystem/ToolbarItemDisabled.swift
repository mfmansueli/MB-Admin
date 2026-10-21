import SwiftUI

/// `.disabled(_:)` pros botões da barra de cima que mudam de estado sozinhos (recarregar,
/// selecionar) — no Mac Catalyst esse estado nunca chega no botão. Lá, um botão de toolbar vira um
/// `NSToolbarButton`, e trocar ele de habilitado pra desabilitado enquanto a barra está sendo
/// montada (o que acontece ao abrir uma conta: o carregamento começa na hora e desabilita o
/// recarregar) derruba o app — "Unable to install constraint on view… NSToolbarButton …
/// NSToolbarItemGroupLayoutWrapper". No Mac, quem usa protege a própria ação (ver os usos).
struct ToolbarItemDisabled: ViewModifier {
    let isDisabled: Bool

    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        content
        #else
        content.disabled(isDisabled)
        #endif
    }
}

extension View {
    func toolbarItemDisabled(_ isDisabled: Bool) -> some View {
        modifier(ToolbarItemDisabled(isDisabled: isDisabled))
    }
}
