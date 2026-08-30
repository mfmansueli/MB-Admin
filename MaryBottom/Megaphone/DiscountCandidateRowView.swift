import SwiftUI

/// Linha da lista de produtos que pedem decisão de desconto: foto, título, preço atual e o preço
/// sugerido pra alcançar exposição máxima.
struct DiscountCandidateRowView: View {
    let candidate: DiscountCandidate
    let loader: DiscountCandidatesLoader

    @State private var isConfirmingApply = false

    var body: some View {
        HStack(spacing: 12) {
            ProductPhotoView(product: candidate.product)

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.product.title)
                    .font(.subheadline)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let originalPrice = candidate.product.formattedOriginalPrice {
                        Text(originalPrice)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .strikethrough()
                    }
                    if let suggestedPrice = candidate.suggestedPriceText {
                        Text(suggestedPrice)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                    if let percent = candidate.computedDiscountPercent {
                        Text("-\(percent)%")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer(minLength: 8)

            actionView
        }
        .padding(.vertical, 2)
        .confirmationDialog(
            "aplicar \(candidate.exposure.discountLabel ?? "desconto") e megafonar?",
            isPresented: $isConfirmingApply,
            titleVisibility: .visible
        ) {
            Button("aplicar desconto") { loader.applyDiscount(for: candidate.id) }
            Button("cancelar", role: .cancel) {}
        } message: {
            if let current = candidate.product.formattedPrice, let suggested = candidate.suggestedPriceText {
                Text("o preço vai de \(current) para \(suggested), e o produto é megafonado na hora.")
            }
        }
    }

    @ViewBuilder
    private var actionView: some View {
        switch candidate.status {
        case .pending:
            Button {
                isConfirmingApply = true
            } label: {
                Text(candidate.exposure.discountLabel ?? "aplicar")
                    .font(.caption.weight(.bold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)

        case .megaphoning:
            ProgressView()

        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)

        case .failed(let message):
            VStack(alignment: .trailing, spacing: 2) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Button("tentar de novo") { isConfirmingApply = true }
                    .font(.caption2)
            }
            .help(message)
        }
    }
}

#Preview {
    let product = EnjoeiProduct(
        id: 142963399,
        title: "brinco argola estrela 50mm leve moderno joia prata 925",
        path: "brinco-argola-estrela-142963399",
        photoPublicID: nil,
        currentPrice: 799,
        originalPrice: 799
    )
    let exposure = MegaphoneExposure(
        productID: 142963399,
        kind: .maximumAfterDiscount,
        priceToIncreaseExposure: 351,
        discountLabel: "- 56%"
    )
    let loader = DiscountCandidatesLoader(
        client: WebViewEnjoeiClient(webSession: EnjoeiWebSession(dataStoreIdentifier: UUID()))
    )
    return List {
        DiscountCandidateRowView(
            candidate: DiscountCandidate(product: product, exposure: exposure),
            loader: loader
        )
    }
}
