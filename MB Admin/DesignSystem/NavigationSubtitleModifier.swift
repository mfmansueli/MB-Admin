import SwiftUI

/// Linha pequena embaixo do título da barra de navegação ("351 megafones · 2 com erro") — só
/// existe a partir do iOS/Mac Catalyst 26; antes disso o título fica sozinho.
struct NavigationSubtitleModifier: ViewModifier {
    let subtitle: String

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            content.navigationSubtitle(subtitle)
        } else {
            content
        }
    }
}

extension View {
    func navigationSubtitleIfAvailable(_ subtitle: String) -> some View {
        modifier(NavigationSubtitleModifier(subtitle: subtitle))
    }
}
