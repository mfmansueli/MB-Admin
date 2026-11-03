import SwiftUI

/// Uma linha de par — em "mesmo produto", "precisa revisar" ou "marcados como diferentes": as fotos
/// que ligaram os dois lado a lado, o produto de uma loja e, embaixo, como ele se chama na outra, o
/// motivo e o índice de correspondência. Em revisão, os dois botões de decidir ficam numa faixa
/// embaixo da linha; a lupa abre o detalhe (fotos grandes, todos os motivos, as parcelas do índice,
/// os atributos lado a lado, diferenças de texto, desfazer).
struct ProductMatchRowView: View {
    let match: ProductMatch
    let accountAName: String
    let accountBName: String
    var onDecide: (ComparisonDecision.Verdict) -> Void = { _ in }
    var onUndo: () -> Void = {}

    @State private var isShowingDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ComparisonPhotoPairView(
                    photoA: match.displayPhotoA,
                    photoB: match.displayPhotoB,
                    titleA: match.productA.title,
                    titleB: match.productB.title
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(match.productA.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                    Text("\(accountBName): \(match.productB.title)")
                        .font(.subheadline)
                        .foregroundStyle(.supportingText)
                        .lineLimit(2)
                    if let summary = match.summaryText {
                        Text(summary)
                            .font(.footnote)
                            .foregroundStyle(match.status == .needsReview ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                VStack(spacing: 6) {
                    // O detalhe (e `ProductMatchDifference`) só é montado quando o sheet abre de verdade.
                    Button {
                        isShowingDetail = true
                    } label: {
                        Image(systemName: "text.magnifyingglass")
                    }
                    .buttonStyle(.neutral(isCircle: true, size: 38))
                    .accessibilityLabel("ver detalhes do par")
                    if !match.index.components.isEmpty {
                        MatchIndexBadge(index: match.index)
                    }
                }
            }
            if match.status == .needsReview {
                reviewButtons
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // Fundo sólido pro scroll do mouse/trackpad funcionar em qualquer área da row no Mac
        // Catalyst, não só em cima das fotos — ver o mesmo comentário em `MegaphoneRowView`.
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .contentShape(.rect)
        .contextMenu {
            ShareLink(item: match.productA.storePageURL) {
                Label("compartilhar o de \(accountAName)", systemImage: "square.and.arrow.up")
            }
            ShareLink(item: match.productB.storePageURL) {
                Label("compartilhar o de \(accountBName)", systemImage: "square.and.arrow.up")
            }
        }
        .sheet(isPresented: $isShowingDetail) {
            ComparisonPairDetailSheet(
                match: match,
                accountAName: accountAName,
                accountBName: accountBName,
                onDecide: onDecide,
                onUndo: onUndo
            )
        }
    }

    /// Numa faixa própria, na largura da linha toda — do lado das duas fotos a coluna de texto é
    /// estreita demais e o botão saía cortado ("m…"). Um embaixo do outro só com letra muito grande.
    private var reviewButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { reviewButtonPair }
            VStack(spacing: 8) { reviewButtonPair }
        }
    }

    @ViewBuilder private var reviewButtonPair: some View {
        decisionButton("mesmo produto", systemImage: "equal.circle", verdict: .sameProduct)
        decisionButton("diferentes", systemImage: "nosign", verdict: .differentProducts)
    }

    private func decisionButton(_ title: String, systemImage: String, verdict: ComparisonDecision.Verdict) -> some View {
        Button {
            onDecide(verdict)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(Color(uiColor: .tertiarySystemFill), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(verdict == .sameProduct ? "é o mesmo produto" : "são produtos diferentes")
    }
}

#Preview {
    let productA = EnjoeiProduct(
        id: 1, title: "brinco argola estrela 50mm prata 925", path: "brinco-1", photoPublicID: nil, currentPrice: 299, originalPrice: 299
    )
    let productB = EnjoeiProduct(
        id: 2, title: "argola estrela 50 mm prata 925 leve", path: "brinco-2", photoPublicID: nil, currentPrice: 289, originalPrice: 289
    )
    VStack(spacing: 0) {
        ProductMatchRowView(
            match: ProductMatch(
                productA: productA, productB: productB,
                keyA: ListingKey(sellerID: 1, productID: 1), keyB: ListingKey(sellerID: 2, productID: 2),
                status: .strong, reasons: [.samePhoto], photoEvidence: nil, photoA: nil, photoB: nil, textSimilarity: 0.5
            ),
            accountAName: "antonia",
            accountBName: "loja B"
        )
        ProductMatchRowView(
            match: ProductMatch(
                productA: productA, productB: productB,
                keyA: ListingKey(sellerID: 1, productID: 1), keyB: ListingKey(sellerID: 2, productID: 2),
                status: .needsReview, reasons: [.colorVariant], photoEvidence: nil, photoA: nil, photoB: nil, textSimilarity: 0.5
            ),
            accountAName: "antonia",
            accountBName: "loja B"
        )
    }
}
