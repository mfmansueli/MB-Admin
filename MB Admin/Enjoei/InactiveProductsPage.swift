import Foundation

/// Uma página da listagem de inativos — o `body` que `EnjoeiJavaScript.inactiveProductsPage`
/// devolve depois de fazer o parse do HTML da página.
nonisolated struct InactiveProductsPage: Equatable, Sendable, Codable {
    let products: [InactiveProduct]
    let maxPage: Int

    private enum CodingKeys: String, CodingKey {
        case products
        case maxPage = "max_page"
    }
}
