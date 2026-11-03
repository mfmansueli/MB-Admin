import SwiftUI

/// Uma linha de "não deu pra verificar": produto sem par que a comparação não pôde dar como ausente
/// (foto que não carregou, lista incompleta, sem foto comparável…) — com o motivo. Sem botão de
/// postar nem seleção: postar na outra loja presume que o produto não está lá.
struct UnverifiedProductRowView: View, Equatable {
    let listing: UnverifiedListing
    let storeName: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProductPhotoView(product: listing.product)
            VStack(alignment: .leading, spacing: 2) {
                Text(listing.product.title)
                    .productTitleFont()
                    .lineLimit(2)
                Text("em \(storeName)")
                    .font(.subheadline)
                    .foregroundStyle(.supportingText)
                ForEach(listing.reasons, id: \.self) { reason in
                    Text(reason.text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // Fundo sólido pro scroll do mouse funcionar na row inteira no Mac Catalyst.
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .contentShape(.rect)
        .contextMenu {
            ShareLink(item: listing.product.storePageURL) {
                Label("compartilhar", systemImage: "square.and.arrow.up")
            }
        }
    }
}
