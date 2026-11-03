#if DEBUG
import Foundation

/// As fotos de cada produto do `DemoMode`, por loja — ids `demo-<vendedor>-<posição>-<foto>`,
/// geradas na hora por `DemoPhotoRenderer` e servidas por `DemoPhotoURLProtocol`. O mesmo produto
/// tem a mesma posição em todas as lojas (e o mesmo título), com ids diferentes em cada uma, como num
/// reupload de verdade. Cenários da comparação por foto:
///
/// - antonia põe a foto de fundo branco primeiro; as outras lojas, às vezes em segundo (atrás de uma
///   foto "de ambiente" diferente) — a capa sozinha não acha o par;
/// - posição 3: mesma foto, tamanhos diferentes no template → revisão;
/// - posição 6: a mesma pose em dourado nas outras lojas → variante de cor, revisão;
/// - posição 9: mesmo título, outra peça na foto → texto quase igual, fotos diferentes, revisão;
/// - posição 12: a mesma foto também na posição 21 das outras lojas (duplicata) → revisão;
/// - posição 17: as fotos das outras lojas não carregam (404) → não foi possível verificar.
nonisolated enum DemoPhotoCatalog {
    typealias Spec = DemoPhotoRenderer.Spec

    static let antoniaSellerID = 1001
    static let variantPosition = 6
    static let differentPhotoPosition = 9
    static let duplicatedPosition = 12
    static let duplicatePosition = 21
    static let brokenPhotosPosition = 17
    static let sizeConflictPosition = 3

    private enum Kind: String {
        case white, ambient, detail
    }

    static func photoIDs(sellerID: Int, position: Int) -> [String] {
        let kinds: [Kind]
        if sellerID == antoniaSellerID {
            kinds = [.white, .ambient, .detail]
        } else {
            kinds = position % 4 == 1 ? [.ambient, .white, .detail] : [.white, .detail]
        }
        return kinds.map { "demo-\(sellerID)-\(position)-\($0.rawValue)" }
    }

    /// Tamanho do template — só a posição do conflito de tamanho tem.
    static func size(sellerID: Int, position: Int) -> String? {
        guard position == sizeConflictPosition else { return nil }
        return sellerID == antoniaSellerID ? "17" : "16"
    }

    /// Os bytes de uma foto da demonstração, ou `nil` (404) pra id desconhecido ou foto quebrada.
    static func photoData(publicID: String) -> Data? {
        let parts = publicID.split(separator: "-")
        guard parts.count == 4, parts[0] == "demo",
              let sellerID = Int(parts[1]), let position = Int(parts[2]),
              let kind = Kind(rawValue: String(parts[3])) else { return nil }
        let isAntonia = sellerID == antoniaSellerID
        if !isAntonia, position == brokenPhotosPosition { return nil }
        let spec = spec(kind: kind, sellerID: sellerID, position: position)
        // Cada loja com a sua recompressão — a mesma foto nunca tem os mesmos bytes nas duas.
        return DemoPhotoRenderer.jpeg(spec, side: 300, quality: isAntonia ? 0.88 : 0.62)
    }

    private static func spec(kind: Kind, sellerID: Int, position: Int) -> Spec {
        let isAntonia = sellerID == antoniaSellerID
        var productPosition = position
        if !isAntonia, position == duplicatePosition { productPosition = duplicatedPosition }
        var spec = productSpec(position: productPosition)
        if !isAntonia, position == variantPosition { spec.metal = .gold }
        if !isAntonia, position == differentPhotoPosition { spec.seed += 1000 }
        switch kind {
        case .white:
            break
        case .ambient:
            // Cada loja fotografou o "ambiente" de um jeito — nunca a mesma foto entre lojas.
            spec.background = .init(red: 0.62, green: 0.52, blue: 0.45)
            spec.backgroundGradient = 0.4
            spec.rotation = isAntonia ? 0.25 : -0.3
            spec.centerX = isAntonia ? 0.45 : 0.56
            spec.scale = 0.5
        case .detail:
            spec.seed += 500
            spec.scale = 0.85
        }
        return spec
    }

    private static func productSpec(position: Int) -> Spec {
        var spec = Spec(shape: Spec.Shape.allCases[position % Spec.Shape.allCases.count], seed: position + 1)
        if position % 7 == 2 { spec.metal = .gold }
        return spec
    }
}
#endif
