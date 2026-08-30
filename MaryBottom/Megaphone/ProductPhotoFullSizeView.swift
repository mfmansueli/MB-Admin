import SwiftUI

/// Tela com a foto do produto num tamanho maior, aberta ao tocar na miniatura.
struct ProductPhotoFullSizeView: View {
    let product: EnjoeiProduct

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AsyncImage(url: product.largePhotoURL ?? product.photoURL) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                ProgressView()
            }
            .padding()
            .navigationTitle(product.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("fechar") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    ProductPhotoFullSizeView(
        product: EnjoeiProduct(
            id: 145657034,
            title: "brinco argola estrela 50mm",
            path: "brinco-argola-estrela-145657034",
            photoPublicID: nil,
            currentPrice: 273,
            originalPrice: 399
        )
    )
}
