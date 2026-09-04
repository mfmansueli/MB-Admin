import SwiftUI

/// Como `AsyncImage`, mas guarda a imagem já decodificada em `ImageMemoryCache` — sem isso, cada
/// linha de uma `List` busca a foto de novo (rede ou, na melhor das hipóteses, disco + redecode)
/// toda vez que sai e volta pra área visível ao rolar, porque o SwiftUI recria a `AsyncImage` daquela
/// linha do zero nesse momento. Mesma assinatura de `content`/`placeholder` do tipo original, pra
/// trocar um pelo outro sem mexer em quem chama.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var uiImage: UIImage?

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
        guard let url else {
            uiImage = nil
            return
        }
        if let cached = ImageMemoryCache.shared.object(forKey: url as NSURL) {
            uiImage = cached
            return
        }
        uiImage = nil
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let downloaded = UIImage(data: data) else { return }
        ImageMemoryCache.shared.setObject(downloaded, forKey: url as NSURL)
        uiImage = downloaded
    }
}
