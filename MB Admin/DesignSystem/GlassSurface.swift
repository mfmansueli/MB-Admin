import SwiftUI

/// Fundo de "vidro líquido" das superfícies soltas do redesign (painel do megafone, barra de ações
/// da seleção) — o material só existe a partir do iOS/Mac Catalyst 26; antes disso cai num
/// `.regularMaterial` com borda fina, que lembra o mesmo efeito sem depender da API nova.
struct GlassSurface: ViewModifier {
    let shape: AnyShape

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(.separator, lineWidth: 0.5))
        }
    }
}

extension View {
    func glassSurface(in shape: some Shape) -> some View {
        modifier(GlassSurface(shape: AnyShape(shape)))
    }
}
