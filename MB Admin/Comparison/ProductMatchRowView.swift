import SwiftUI

/// Uma linha da seção "produtos em comum": o anel com o quanto os dois títulos se parecem, o produto
/// de uma conta e, embaixo, como ele se chama na outra. Par pouco parecido ganha o anel cinza e o
/// aviso de conferir antes de tratar como igual. A lupa abre as diferenças entre os dois; os links
/// de cada lado ficam no menu de contexto.
struct ProductMatchRowView: View {
    let match: ProductMatch
    let accountBName: String

    @State private var isShowingDifference = false

    var body: some View {
        HStack(spacing: 12) {
            SimilarityGauge(match: match)
            VStack(alignment: .leading, spacing: 3) {
                Text(match.productA.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                Text("\(accountBName): \(match.productB.title)")
                    .font(.subheadline)
                    .foregroundStyle(.supportingText)
                    .lineLimit(2)
                if !match.isConfident {
                    Text("confira antes de considerar igual")
                        .font(.subheadline.weight(.semibold))
                }
            }
            Spacer(minLength: 8)
            // O cálculo de `ProductMatchDifference` só acontece dentro do `.sheet` — o SwiftUI não
            // avalia esse conteúdo até o usuário efetivamente abrir, então nenhuma comparação extra
            // roda só por essa row existir na lista.
            Button {
                isShowingDifference = true
            } label: {
                Image(systemName: "text.magnifyingglass")
            }
            .buttonStyle(.neutral(isCircle: true, size: 38))
            .accessibilityLabel("ver diferenças do par")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // Fundo sólido pro scroll do mouse/trackpad funcionar em qualquer área da row no Mac
        // Catalyst, não só em cima do anel — ver o mesmo comentário em `MegaphoneRowView`.
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .contentShape(.rect)
        .contextMenu {
            ShareLink(item: match.productA.storePageURL) {
                Label("compartilhar \(match.productA.title)", systemImage: "square.and.arrow.up")
            }
            ShareLink(item: match.productB.storePageURL) {
                Label("compartilhar o de \(accountBName)", systemImage: "square.and.arrow.up")
            }
        }
        .sheet(isPresented: $isShowingDifference) {
            ProductMatchDifferenceSheet(match: match)
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        ProductMatchRowView(
            match: ProductMatch(
                productA: EnjoeiProduct(
                    id: 1,
                    title: "brinco argola estrela 50mm prata 925",
                    path: "brinco-1",
                    photoPublicID: nil,
                    currentPrice: 299,
                    originalPrice: 299
                ),
                productB: EnjoeiProduct(
                    id: 2,
                    title: "argola estrela 50 mm prata 925 leve",
                    path: "brinco-2",
                    photoPublicID: nil,
                    currentPrice: 289,
                    originalPrice: 289
                ),
                similarity: 0.82
            ),
            accountBName: "loja B"
        )
        ProductMatchRowView(
            match: ProductMatch(
                productA: EnjoeiProduct(
                    id: 3,
                    title: "anel aro 17 entrelaçado zircônia",
                    path: "anel-3",
                    photoPublicID: nil,
                    currentPrice: 149,
                    originalPrice: 149
                ),
                productB: EnjoeiProduct(
                    id: 4,
                    title: "anel entrelaçado cravejado aro 16",
                    path: "anel-4",
                    photoPublicID: nil,
                    currentPrice: 149,
                    originalPrice: 149
                ),
                similarity: 0.64
            ),
            accountBName: "loja B"
        )
    }
}
