import SwiftUI

/// Uma linha da seção "produtos em comum": os dois lados do par, com o `%` de similaridade entre
/// eles.
struct ProductMatchRowView: View {
    let match: ProductMatch

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Spacer()
                Text("\(Int((match.similarity * 100).rounded()))% parecido")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(similarityColor)
                Spacer()
            }
            HStack(alignment: .top, spacing: 12) {
                side(for: match.productA)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                side(for: match.productB)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func side(for product: EnjoeiProduct) -> some View {
        VStack(spacing: 4) {
            ProductPhotoView(product: product, size: 56)
            Text(product.title)
                .font(.caption)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if let price = product.formattedPrice {
                Text(price)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ShareLink(item: product.storePageURL) {
                Image(systemName: "square.and.arrow.up")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    /// Quanto mais parecido, mais "certeza" a cor passa — abaixo do threshold padrão o par nem
    /// aparece aqui, então essas duas faixas já são as únicas relevantes.
    private var similarityColor: Color {
        match.similarity >= 0.8 ? .green : .orange
    }
}

#Preview {
    ProductMatchRowView(
        match: ProductMatch(
            productA: EnjoeiProduct(
                id: 1,
                title: "colar curto pingente cravejado menino zircônia branca",
                path: "colar-1",
                photoPublicID: nil,
                currentPrice: 299,
                originalPrice: 299
            ),
            productB: EnjoeiProduct(
                id: 2,
                title: "colar curto pingente cravejado zircônia branca clássico",
                path: "colar-2",
                photoPublicID: nil,
                currentPrice: 289,
                originalPrice: 289
            ),
            similarity: 0.82
        )
    )
    .padding()
}
