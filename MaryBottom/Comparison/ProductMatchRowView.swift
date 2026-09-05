import SwiftUI

/// Uma linha da seção "produtos em comum": os dois lados do par, com o `%` de similaridade entre
/// eles.
struct ProductMatchRowView: View {
    let match: ProductMatch

    @State private var isShowingDifference = false

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
                VStack(spacing: 6) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                    // O cálculo de `ProductMatchDifference` só acontece dentro do `.sheet` — o
                    // SwiftUI não avalia esse conteúdo até o usuário efetivamente abrir, então
                    // nenhuma comparação extra roda só por essa row existir na lista.
                    //
                    // Círculo com tamanho mínimo, mesmo padrão dos botões de ícone do resto do
                    // app (ex.: "recarregar produtos") — sem isso, o alvo de toque ficava do
                    // tamanho do próprio glifo, pequeno demais pra acertar de primeira.
                    Button {
                        isShowingDifference = true
                    } label: {
                        Image(systemName: "text.magnifyingglass")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 34, minHeight: 34)
                            .background(.quaternary, in: .circle)
                    }
                    .buttonStyle(.plain)
                }
                side(for: match.productB)
            }
        }
        .padding(.vertical, 4)
        // Fundo sólido pro scroll do mouse/trackpad funcionar em qualquer área da row no Mac
        // Catalyst, não só em cima da foto — ver o mesmo comentário em `MegaphoneRowView`.
        .background(.background)
        .contentShape(.rect)
        .sheet(isPresented: $isShowingDifference) {
            ProductMatchDifferenceSheet(match: match)
        }
    }

    @ViewBuilder
    private func side(for product: EnjoeiProduct) -> some View {
        VStack(spacing: 4) {
            // Mesmo tamanho de foto, título e preço das outras listas de produto (publicados,
            // inativos) — mesmo com duas colunas lado a lado aqui, o tamanho tem que bater.
            ProductPhotoView(product: product)
            Text(product.title)
                .productTitleFont()
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if let price = product.formattedPrice {
                Text(price)
                    .productPriceFont()
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
