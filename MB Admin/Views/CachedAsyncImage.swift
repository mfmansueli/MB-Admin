import ImageIO
import SwiftUI

/// Como `AsyncImage`, mas guarda em `ImageMemoryCache` uma imagem já decodificada E reduzida pro
/// tamanho de exibição (ver `downsample`) — sem isso, cada linha de uma lista busca a foto de novo
/// (rede ou, na melhor das hipóteses, disco) toda vez que sai e volta pra área visível ao rolar,
/// porque o SwiftUI recria a `AsyncImage`/`Image` daquela linha do zero nesse momento. Mesma
/// assinatura de `content`/`placeholder` do tipo original, pra trocar um pelo outro sem mexer em
/// quem chama.
///
/// Guardar só os bytes comprimidos (como `UIImage(data:)` faz) não bastava: a decodificação de
/// verdade só acontece no primeiro *draw*, na main thread — e como a `LazyVStack` das listas de
/// produto não faz *cell reuse* (recria a `View`, incluindo um `Image` novo, cada vez que a linha
/// volta pra área visível), esse decode acontecia de novo a cada rolagem, mesmo com o `UIImage`
/// achado no cache e nenhuma rede rodando. Isso é o que travava o scroll. Decodificar (e já reduzir
/// pro tamanho da row) uma vez só, fora da main thread, antes de cachear, resolve os dois problemas
/// de uma vez.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    /// Maior lado da imagem já decodificada, em pixels (não pontos) — normalmente `size * escala da
    /// tela` de quem chama (ver `ProductPhotoView`), pra não decodificar/guardar mais pixel do que a
    /// row realmente exibe.
    let maxPixelSize: CGFloat
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var uiImage: UIImage?

    private var cacheKey: NSString? {
        guard let url else { return nil }
        return "\(url.absoluteString)#\(Int(maxPixelSize))" as NSString
    }

    var body: some View {
        Group {
            if let uiImage {
                content(Image(uiImage: uiImage))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        guard let url, let cacheKey else {
            uiImage = nil
            return
        }
        if let cached = ImageMemoryCache.shared.object(forKey: cacheKey) {
            uiImage = cached
            return
        }
        uiImage = nil
        // `.returnCacheDataElseLoad`: uma vez que a foto está no `URLCache` de `.productPhotos`, usa
        // ela sempre, sem checar validade — uma foto de produto não muda de conteúdo sob a mesma URL
        // (o id público é gerado uma vez, na hora do upload), então "desatualizada" não existe aqui.
        // Sem isso, o boot frio do app (ou qualquer limpeza do `ImageMemoryCache` sob pressão real de
        // memória) buscava cada foto já vista de novo pela rede — ver `URLSession.productPhotos`.
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
        guard let (data, _) = try? await URLSession.productPhotos.data(for: request),
              let downsampled = await Self.downsample(data: data, maxPixelSize: maxPixelSize) else { return }
        ImageMemoryCache.shared.setObject(downsampled, forKey: cacheKey)
        uiImage = downsampled
    }

    /// Decodifica e reduz num passo só via `ImageIO`, em vez de `UIImage(data:)` (que só guarda os
    /// bytes comprimidos, decodificados sob demanda no draw) seguido de `.scaledToFill` (que reduz
    /// depois de decodificar o tamanho inteiro). `kCGImageSourceShouldCacheImmediately` força a
    /// decodificação a acontecer aqui, na `Task.detached`, não na main thread na hora do primeiro
    /// desenho.
    private static func downsample(data: Data, maxPixelSize: CGFloat) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return UIImage(cgImage: cgImage)
        }.value
    }
}
