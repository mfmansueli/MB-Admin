import SwiftUI

/// Linha da lista de megafone: foto, título e o que aconteceu com aquele produto.
struct MegaphoneRowView: View {
    let item: MegaphoneItem

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: item.product.photoURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary)
            }
            .frame(width: 48, height: 48)
            .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.product.title)
                    .font(.subheadline)
                    .lineLimit(2)
                if let message = item.status.failureMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                } else if let price = item.product.formattedPrice {
                    Text(price)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            statusIcon
        }
        .padding(.vertical, 2)
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
    return List {
        MegaphoneRowView(item: MegaphoneItem(product: product, status: .pending))
        MegaphoneRowView(item: MegaphoneItem(product: product, status: .megaphoning))
        MegaphoneRowView(item: MegaphoneItem(product: product, status: .succeeded))
        MegaphoneRowView(item: MegaphoneItem(product: product, status: .failed("limite diário atingido")))
    }
}
