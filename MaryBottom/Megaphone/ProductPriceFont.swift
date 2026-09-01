import SwiftUI

/// Fonte do preço nas linhas de produto (publicados, inativos, comparação) — mesmo peso do
/// `.subheadline` do sistema, só que 2pt maior de base; continua escalando com Dynamic Type. O
/// preço atual (com desconto aplicado) usa peso `.semibold`, então o peso fica configurável.
struct ProductPriceFont: ViewModifier {
    var weight: Font.Weight = .regular

    @ScaledMetric(relativeTo: .subheadline) private var size: CGFloat = 17

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight))
    }
}

extension View {
    func productPriceFont(weight: Font.Weight = .regular) -> some View {
        modifier(ProductPriceFont(weight: weight))
    }
}

#Preview {
    Text("229,00 R$")
        .productPriceFont()
        .padding()
}
