import UIKit

/// Cache de imagens de produto em memória, compartilhado pelo app inteiro — usado por
/// `CachedAsyncImage` pra não redecodificar a mesma foto toda vez que uma linha de lista sai e volta
/// pra área visível ao rolar (o SwiftUI recria a view de cada linha nesse momento, então sem esse
/// cache a busca por rede/disco acontecia de novo a cada rolagem). `NSCache` esvazia sozinho sob
/// pressão de memória, então não precisa de limite de contagem pensado a dedo.
///
/// Chave é a URL + o tamanho de pixel pedido (não só a URL) — o mesmo produto aparece em rows de
/// tamanhos diferentes (48pt na comparação, 64pt no resto), e cada tamanho guarda seu próprio bitmap
/// já reduzido por `CachedAsyncImage.downsample`, em vez de um cache só por URL forçar reaproveitar
/// (ou upscalar) o bitmap errado.
enum ImageMemoryCache {
    static let shared = NSCache<NSString, UIImage>()
}
