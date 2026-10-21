import SwiftUI

/// Miniatura de um produto que, ao ser tocada, mostra a foto num tamanho maior. Recebe as URLs
/// prontas em vez de um `EnjoeiProduct` pra também servir a `InactiveProduct`, que tem seu próprio
/// tipo de foto.
///
/// No iPhone/iPad a foto abre em tela cheia crescendo a partir da própria miniatura (a transição de
/// zoom do sistema, o mesmo efeito dos cards da aba Today da App Store) e volta pro lugar ao fechar
/// — inclusive arrastando pra baixo. No Mac continua num sheet comum: lá `.fullScreenCover` já
/// quebrou o layout em versões mais antigas do Catalyst (ver `AccountsListView`), e a transição de
/// zoom nem existe antes do Catalyst 18.
struct ProductPhotoView: View {
    let photoURL: URL?
    let largePhotoURL: URL?
    let title: String
    var size: CGFloat = 64

    @State private var isShowingFullSize = false
    @Namespace private var zoomNamespace
    @Environment(\.displayScale) private var displayScale

    /// Um id só basta: cada miniatura tem seu próprio `zoomNamespace`.
    private static let zoomSourceID = "photo"

    var body: some View {
        thumbnail
            .contentShape(.rect)
            .onTapGesture { isShowingFullSize = true }
            .accessibilityElement()
            .accessibilityLabel("foto de \(title)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { isShowingFullSize = true }
            #if targetEnvironment(macCatalyst)
            .sheet(isPresented: $isShowingFullSize) {
                fullSizeView
            }
            #else
            .matchedTransitionSource(id: Self.zoomSourceID, in: zoomNamespace) { source in
                source.clipShape(.rect(cornerRadius: 10))
            }
            .fullScreenCover(isPresented: $isShowingFullSize) {
                fullSizeView
                    .navigationTransition(.zoom(sourceID: Self.zoomSourceID, in: zoomNamespace))
            }
            #endif
    }

    /// Pixels de verdade, não pontos — pra `CachedAsyncImage` decodificar/guardar só o tanto de
    /// pixel que essa row realmente desenha, em vez do `300x300` que a foto vem da rede.
    private var thumbnailPixelSize: CGFloat { size * displayScale }

    private var thumbnail: some View {
        CachedAsyncImage(url: photoURL, maxPixelSize: thumbnailPixelSize) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            RoundedRectangle(cornerRadius: 10).fill(.quaternary)
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: 10))
    }

    private var fullSizeView: some View {
        ProductPhotoFullSizeView(
            photoURL: largePhotoURL ?? photoURL,
            title: title,
            thumbnailURL: photoURL,
            thumbnailPixelSize: thumbnailPixelSize
        )
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
