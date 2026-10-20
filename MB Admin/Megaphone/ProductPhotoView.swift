import SwiftUI

/// Miniatura de um produto que, ao ser tocada, mostra a foto num tamanho maior. Recebe as URLs
/// prontas em vez de um `EnjoeiProduct` pra também servir a `InactiveProduct`, que tem seu próprio
/// tipo de foto.
struct ProductPhotoView: View {
    let photoURL: URL?
    let largePhotoURL: URL?
    let title: String
    var size: CGFloat = 64

    @State private var isShowingFullSize = false
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        // Pixels de verdade, não pontos — pra `CachedAsyncImage` decodificar/guardar só o tanto de
        // pixel que essa row realmente desenha, em vez do `300x300` que a foto vem da rede.
        CachedAsyncImage(url: photoURL, maxPixelSize: size * displayScale) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            RoundedRectangle(cornerRadius: 10).fill(.quaternary)
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: 10))
        .contentShape(.rect)
        .onTapGesture { isShowingFullSize = true }
        .sheet(isPresented: $isShowingFullSize) {
            ProductPhotoFullSizeView(photoURL: largePhotoURL ?? photoURL, title: title)
        }
    }
}

extension ProductPhotoView {
    init(product: EnjoeiProduct, size: CGFloat = 64) {
        self.init(photoURL: product.photoURL, largePhotoURL: product.largePhotoURL, title: product.title, size: size)
    }

    init(product: InactiveProduct, size: CGFloat = 64) {
        self.init(photoURL: product.thumbnailURL, largePhotoURL: product.largePhotoURL, title: product.title, size: size)
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
