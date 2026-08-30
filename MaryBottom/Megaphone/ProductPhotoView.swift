import SwiftUI

/// Miniatura de um produto que, ao ser tocada, mostra a foto num tamanho maior.
struct ProductPhotoView: View {
    let product: EnjoeiProduct
    var size: CGFloat = 64

    @State private var isShowingFullSize = false

    var body: some View {
        AsyncImage(url: product.photoURL) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            RoundedRectangle(cornerRadius: 10).fill(.quaternary)
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: 10))
        .contentShape(.rect)
        .onTapGesture { isShowingFullSize = true }
        .sheet(isPresented: $isShowingFullSize) {
            ProductPhotoFullSizeView(product: product)
        }
    }
}

#Preview {
    ProductPhotoView(
        product: EnjoeiProduct(
            id: 145657034,
            title: "brinco argola estrela 50mm",
            path: "brinco-argola-estrela-145657034",
            photoPublicID: nil,
            currentPrice: 273,
            originalPrice: 399
        )
    )
    .padding()
}
