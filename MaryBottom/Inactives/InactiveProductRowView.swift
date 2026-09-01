import SwiftUI

/// Uma linha da lista de inativos: foto, título, preço e desde quando está inativo — em modo de
/// seleção, vira uma linha marcável.
struct InactiveProductRowView: View {
    let product: InactiveProduct
    var isSelecting = false
    var isSelected = false
    var onToggleSelection: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .font(.title3)
            }
            ProductPhotoView(product: product)

            VStack(alignment: .leading, spacing: 2) {
                // Mesmo tamanho de fonte da row de "publicados" (`MegaphoneRowView`).
                Text(product.title)
                    .productTitleFont()
                    .lineLimit(2)
                if let price = product.formattedPrice {
                    Text(price)
                        .productPriceFont()
                        .foregroundStyle(.secondary)
                }
                if let inactiveSince = product.inactiveSince {
                    Text("inativo desde \(inactiveSince)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .onTapGesture {
            if isSelecting { onToggleSelection() }
        }
    }
}

#Preview {
    InactiveProductRowView(
        product: InactiveProduct(
            id: 143304960,
            path: "brinco-pino-diamond-cravejado-10mm-prata-295-143304960",
            title: "brinco pino diamond cravejado 10mm prata 295",
            price: 229,
            photoPublicID: nil,
            inactiveSince: "12/03/2026"
        )
    )
    .padding()
}
