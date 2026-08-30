import Foundation

/// Uma página da listagem de produtos de uma loja, vinda do GraphQL de busca.
///
/// A persisted query `searchProductsForStore` não devolve `pageInfo`: a paginação é feita mandando
/// o `cursor` da última aresta no parâmetro `after`, até vir uma página vazia.
nonisolated struct StoreProductsPage: Equatable, Sendable {
    let products: [EnjoeiProduct]
    let total: Int
    let endCursor: String?

    var isEmpty: Bool { products.isEmpty }
}

nonisolated extension StoreProductsPage: Decodable {
    init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: RootKeys.self)
        let data = try root.nestedContainer(keyedBy: DataKeys.self, forKey: .data)
        let seller = try data.nestedContainer(keyedBy: SellerKeys.self, forKey: .seller)
        let search = try seller.nestedContainer(keyedBy: SearchKeys.self, forKey: .search)
        let products = try search.nestedContainer(keyedBy: ProductsKeys.self, forKey: .products)

        total = try products.decodeIfPresent(Int.self, forKey: .total) ?? 0
        let edges = try products.decodeIfPresent([Edge].self, forKey: .edges) ?? []
        self.products = edges.compactMap { $0.node.makeProduct() }
        endCursor = edges.last?.cursor
    }

    private enum RootKeys: String, CodingKey { case data }
    private enum DataKeys: String, CodingKey { case seller }
    private enum SellerKeys: String, CodingKey { case search }
    private enum SearchKeys: String, CodingKey { case products }
    private enum ProductsKeys: String, CodingKey { case total, edges }

    private struct Edge: Decodable {
        let cursor: String?
        let node: Node
    }

    private struct Node: Decodable {
        let id: String?
        let path: String?
        let title: Title?
        let photo: Photo?
        let price: Price?

        struct Title: Decodable { let name: String? }
        struct Photo: Decodable {
            let imagePublicID: String?
            private enum CodingKeys: String, CodingKey { case imagePublicID = "image_public_id" }
        }
        struct Price: Decodable {
            let current: Double?
            let original: Double?
        }

        func makeProduct() -> EnjoeiProduct? {
            guard let id, let numericID = Int(id) else { return nil }
            return EnjoeiProduct(
                id: numericID,
                title: title?.name ?? "produto \(numericID)",
                path: path ?? "",
                photoPublicID: photo?.imagePublicID,
                currentPrice: price?.current,
                originalPrice: price?.original
            )
        }
    }
}
