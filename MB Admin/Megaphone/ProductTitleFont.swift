import SwiftUI

/// Fonte do título nas linhas de produto (publicados, inativos, comparação) — mesmo peso do
/// `.headline` do sistema, só que 2pt maior de base; continua escalando com Dynamic Type.
struct ProductTitleFont: ViewModifier {
    @ScaledMetric(relativeTo: .headline) private var size: CGFloat = 19

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: .semibold))
    }
}

extension View {
    func productTitleFont() -> some View {
        modifier(ProductTitleFont())
    }
}

#Preview {
    Text("brinco argola estrela 50mm")
        .productTitleFont()
        .padding()
}
