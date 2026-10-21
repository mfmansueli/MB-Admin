import SwiftUI

/// Tela com a foto do produto num tamanho maior, aberta ao tocar na miniatura — ocupa a área toda
/// da view e permite pinçar pra dar zoom (ou dois toques pra alternar zoom rápido).
struct ProductPhotoFullSizeView: View {
    let photoURL: URL?
    let title: String
    /// A miniatura que a row já mostra (e já tem decodificada em cache) — vira o placeholder
    /// enquanto a foto grande chega, pra a transição de zoom (ver `ProductPhotoView`) crescer a
    /// própria foto em vez de um spinner. `nil` cai no spinner de antes.
    var thumbnailURL: URL?
    /// Mesmo `maxPixelSize` da miniatura na row — é parte da chave do `ImageMemoryCache`, então
    /// precisa bater pra achar a imagem já pronta.
    var thumbnailPixelSize: CGFloat = 0

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 5

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                AsyncImage(url: photoURL) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(magnification)
                        // Arrastar só move a foto ampliada — sem zoom, o gesto fica livre pro
                        // arrastar-pra-baixo do sistema que fecha a tela de volta pra miniatura.
                        .simultaneousGesture(drag, including: scale > minScale ? .all : .none)
                        .onTapGesture(count: 2, perform: toggleZoom)
                } placeholder: {
                    thumbnailPlaceholder
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // `.fixedSize()` evita o texto truncar no Mac (idiom otimizado) — sem isso, o
                    // botão encolhe pro tamanho de uma "pill" fixa em vez de acompanhar o texto.
                    Button("fechar") { dismiss() }
                        .fixedSize()
                }
            }
        }
        // Fundo sempre preto, como num visualizador de fotos — título e "fechar" no estilo escuro
        // também no modo claro, senão ficavam pretos em cima do preto.
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var thumbnailPlaceholder: some View {
        if let thumbnailURL, thumbnailPixelSize > 0 {
            CachedAsyncImage(url: thumbnailURL, maxPixelSize: thumbnailPixelSize) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                ProgressView()
            }
        } else {
            ProgressView()
        }
    }

    private var magnification: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(lastScale * value, minScale), maxScale)
            }
            .onEnded { _ in
                lastScale = scale
                if scale == minScale { resetOffset() }
            }
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > minScale else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in lastOffset = offset }
    }

    private func toggleZoom() {
        withAnimation {
            if scale > minScale {
                scale = minScale
                lastScale = minScale
                resetOffset()
            } else {
                scale = maxScale
                lastScale = maxScale
            }
        }
    }

    private func resetOffset() {
        offset = .zero
        lastOffset = .zero
    }
}

#Preview {
    ProductPhotoFullSizeView(
        photoURL: EnjoeiProduct(
            id: 145657034,
            title: "brinco argola estrela 50mm",
            path: "brinco-argola-estrela-145657034",
            photoPublicID: nil,
            currentPrice: 273,
            originalPrice: 399
        ).photoURL,
        title: "brinco argola estrela 50mm"
    )
}
