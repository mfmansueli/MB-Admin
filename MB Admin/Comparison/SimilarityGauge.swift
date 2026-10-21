import SwiftUI

/// Anel com o quanto os títulos de um par se parecem, e o número no meio ("82") — na cor da ação
/// principal quando o par é quase certo, cinza quando vale conferir.
struct SimilarityGauge: View {
    let match: ProductMatch
    var size: CGFloat = 40

    var body: some View {
        ProgressRing(progress: match.similarity, size: size, lineWidth: 4)
            .foregroundStyle(match.isConfident ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.supportingText))
            .overlay {
                Text("\(match.similarityPercent)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(4)
            }
            .accessibilityElement()
            .accessibilityLabel("\(match.similarityPercent)% parecido")
    }
}

#Preview {
    HStack {
        SimilarityGauge(
            match: ProductMatch(
                productA: EnjoeiProduct(id: 1, title: "a", path: "a", photoPublicID: nil, currentPrice: 1, originalPrice: 1),
                productB: EnjoeiProduct(id: 2, title: "b", path: "b", photoPublicID: nil, currentPrice: 1, originalPrice: 1),
                similarity: 0.82
            )
        )
        SimilarityGauge(
            match: ProductMatch(
                productA: EnjoeiProduct(id: 1, title: "a", path: "a", photoPublicID: nil, currentPrice: 1, originalPrice: 1),
                productB: EnjoeiProduct(id: 2, title: "b", path: "b", photoPublicID: nil, currentPrice: 1, originalPrice: 1),
                similarity: 0.64
            )
        )
    }
    .padding()
}
