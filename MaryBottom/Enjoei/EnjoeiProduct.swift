import Foundation

/// Produto à venda numa loja do Enjoei.
nonisolated struct EnjoeiProduct: Identifiable, Equatable, Sendable, Codable {
    let id: Int
    let title: String
    let path: String
    let photoPublicID: String?
    let currentPrice: Double?
    let originalPrice: Double?
    /// `nil` até `ProductDetailsLoader` buscar o produto inteiro (`EnjoeiClientProtocol
    /// .productTemplate`) — nenhuma das rotas usadas pra listar a loja devolve descrição, só esse
    /// pedido avulso por produto.
    var description: String? = nil

    /// Cópia com a descrição preenchida — usado por `MegaphoneRunner.applyDescription` depois que
    /// `ProductDetailsLoader` busca o produto inteiro.
    func withDescription(_ description: String) -> EnjoeiProduct {
        EnjoeiProduct(
            id: id,
            title: title,
            path: path,
            photoPublicID: photoPublicID,
            currentPrice: currentPrice,
            originalPrice: originalPrice,
            description: description
        )
    }

    var photoURL: URL? {
        guard let photoPublicID else { return nil }
        return EnjoeiPhoto.url(publicID: photoPublicID, size: .thumbnail)
    }

    /// Versão maior da foto, pra quando o usuário toca na miniatura pra ver melhor.
    var largePhotoURL: URL? {
        guard let photoPublicID else { return nil }
        return EnjoeiPhoto.url(publicID: photoPublicID, size: .card)
    }

    var formattedPrice: String? {
        guard let currentPrice else { return nil }
        return currentPrice.formatted(.currency(code: "BRL").presentation(.narrow))
    }

    var formattedOriginalPrice: String? {
        guard let originalPrice else { return nil }
        return originalPrice.formatted(.currency(code: "BRL").presentation(.narrow))
    }

    /// Link do produto no site do Enjoei, pra compartilhar.
    var storePageURL: URL {
        EnjoeiAPI.productURL(path: path)
    }
}
