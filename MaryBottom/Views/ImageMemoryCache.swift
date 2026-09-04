import UIKit

/// Cache de imagens de produto em memória, compartilhado pelo app inteiro — usado por
/// `CachedAsyncImage` pra não redecodificar a mesma foto toda vez que uma linha de lista sai e volta
/// pra área visível ao rolar (o SwiftUI recria a view de cada linha nesse momento, então sem esse
/// cache a busca por rede/disco acontecia de novo a cada rolagem). `NSCache` esvazia sozinho sob
/// pressão de memória, então não precisa de limite de contagem pensado a dedo.
enum ImageMemoryCache {
    static let shared = NSCache<NSURL, UIImage>()
}
