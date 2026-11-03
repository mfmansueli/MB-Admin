import SwiftUI

/// Uma linha de seção da comparação desenhada como pedaço do cartão da seção: a primeira arredonda os
/// cantos de cima, a última os de baixo, e as do meio ficam retas — o mesmo cartão de antes, só que
/// cada linha é filha direta da `LazyVStack` (o cartão inteiro num `VStack` montava todas as linhas
/// da seção de uma vez, com foto, sheet e menu de cada uma, mesmo as que estavam longe da tela).
///
/// Sempre o mesmo `clipShape`, só com outros raios: uma linha que deixa de ser a última (uma revisão
/// manual tirou a de baixo) não troca de identidade nem perde o próprio estado.
struct ComparisonCardRow: ViewModifier {
    let isFirst: Bool
    let isLast: Bool

    private static let cornerRadius: CGFloat = 26

    func body(content: Content) -> some View {
        let top = isFirst ? Self.cornerRadius : 0
        let bottom = isLast ? Self.cornerRadius : 0
        content
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: top,
                bottomLeadingRadius: bottom,
                bottomTrailingRadius: bottom,
                topTrailingRadius: top,
                style: .continuous
            ))
            .padding(.horizontal, 16)
    }
}

extension View {
    /// Ver `ComparisonCardRow`.
    func comparisonCardRow(isFirst: Bool, isLast: Bool) -> some View {
        modifier(ComparisonCardRow(isFirst: isFirst, isLast: isLast))
    }
}
