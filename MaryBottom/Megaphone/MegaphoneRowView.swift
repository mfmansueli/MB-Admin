import SwiftUI

/// Linha da lista de megafone: foto, título, preço (com o desconto já aplicado na loja, quando
/// houver) e o que aconteceu com aquele produto — inclui o botão de aplicar o desconto sugerido
/// pelo megafone, quando o produto pede essa decisão.
struct MegaphoneRowView: View {
    let item: MegaphoneItem
    let runner: MegaphoneRunner

    @State private var isConfirmingApply = false

    var body: some View {
        HStack(spacing: 12) {
            ProductPhotoView(product: item.product)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.product.title)
                    .font(.headline)
                    .lineLimit(2)
                if let message = item.status.failureMessage {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                } else {
                    priceLine
                }
            }

            Spacer(minLength: 8)

            trailingView
        }
        .padding(.vertical, 2)
        .confirmationDialog(
            "aplicar \(item.exposure?.discountLabel ?? "desconto") e megafonar?",
            isPresented: $isConfirmingApply,
            titleVisibility: .visible
        ) {
            Button("aplicar desconto") { runner.applyDiscount(for: item.id) }
            Button("cancelar", role: .cancel) {}
        } message: {
            if let current = item.product.formattedPrice, let suggested = suggestedPriceText {
                Text("o preço vai de \(current) para \(suggested), e o produto é megafonado na hora.")
            }
        }
    }

    /// Preço já riscado quando a loja mostra o produto com desconto — independente de qualquer
    /// coisa relacionada ao megafone.
    @ViewBuilder
    private var priceLine: some View {
        HStack(spacing: 6) {
            if let original = item.product.formattedOriginalPrice, item.product.originalPrice != item.product.currentPrice {
                Text(original)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .strikethrough()
            }
            if let current = item.product.formattedPrice {
                Text(current)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            }
            if let percent = item.computedDiscountPercent {
                Text("-\(percent)%")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var suggestedPriceText: String? {
        guard let price = item.exposure?.priceToIncreaseExposure else { return nil }
        return price.formatted(.currency(code: "BRL").presentation(.narrow))
    }

    @ViewBuilder
    private var trailingView: some View {
        if item.status == .pending, let exposure = item.exposure, exposure.kind.requiresDiscountDecision {
            Button {
                isConfirmingApply = true
            } label: {
                Text(exposure.discountLabel ?? "aplicar")
                    .font(.subheadline.weight(.bold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        } else {
            statusIcon
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(.tertiary)
        case .megaphoning:
            ProgressView()
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}

#Preview {
    let product = EnjoeiProduct(
        id: 145657034,
        title: "brinco argola estrela 50mm leve moderno joia prata 925",
        path: "brinco-argola-estrela-145657034",
        photoPublicID: nil,
        currentPrice: 273,
        originalPrice: 399
    )
    let discountedProduct = EnjoeiProduct(
        id: 142963399,
        title: "colar coração prata 925",
        path: "colar-coracao-142963399",
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
    let runner = MegaphoneRunner(
        client: WebViewEnjoeiClient(webSession: EnjoeiWebSession(dataStoreIdentifier: UUID()))
    )
    return List {
        MegaphoneRowView(item: MegaphoneItem(product: product, status: .pending), runner: runner)
        MegaphoneRowView(item: MegaphoneItem(product: product, status: .megaphoning), runner: runner)
        MegaphoneRowView(item: MegaphoneItem(product: product, status: .succeeded), runner: runner)
        MegaphoneRowView(
            item: MegaphoneItem(product: product, status: .failed("limite diário atingido")),
            runner: runner
        )
        MegaphoneRowView(
            item: MegaphoneItem(product: discountedProduct, status: .pending, exposure: exposure),
            runner: runner
        )
    }
}
