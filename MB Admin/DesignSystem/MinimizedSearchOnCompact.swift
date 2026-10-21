import SwiftUI

/// No iPhone, a busca vira só o botão redondo de lupa na barra de baixo (abre o campo ao tocar) —
/// sem isso o campo inteiro disputa espaço com "megafonar". No iPad/Mac ela já fica no topo e
/// continua aberta. Só existe a partir do iOS/Mac Catalyst 26.
struct MinimizedSearchOnCompact: ViewModifier {
    let isCompact: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            content.searchToolbarBehavior(isCompact ? .minimize : .automatic)
        } else {
            content
        }
    }
}
