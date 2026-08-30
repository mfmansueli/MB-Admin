import Foundation

/// Produto à venda numa loja do Enjoei.
nonisolated struct EnjoeiProduct: Identifiable, Equatable, Sendable {
    let id: Int
    let title: String
    let path: String
    let photoPublicID: String?
    let currentPrice: Double?
    let originalPrice: Double?

    var photoURL: URL? {
        guard let photoPublicID else { return nil }
        return EnjoeiPhoto.url(publicID: photoPublicID, size: .thumbnail)
    }

    var formattedPrice: String? {
        guard let currentPrice else { return nil }
        return currentPrice.formatted(.currency(code: "BRL").presentation(.narrow))
    }
}
