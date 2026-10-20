import Foundation

/// Envelope de `GET /api/smart_price/v2?page=N&tab=BOOL` — paginado de verdade (`pagination`), ao
/// contrário da listagem de inativos (`InactiveProductsPage`), que precisa inferir o total de
/// páginas do HTML.
nonisolated struct SmartPriceProductsPage: Equatable, Sendable, Decodable {
    let products: [SmartPriceProduct]
    let currentPage: Int
    let totalPages: Int

    private struct Pagination: Decodable {
        let currentPage: Int
        let totalPages: Int

        private enum CodingKeys: String, CodingKey {
            case currentPage = "current_page"
            case totalPages = "total_pages"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case products, pagination
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        products = try container.decode([SmartPriceProduct].self, forKey: .products)
        let pagination = try container.decode(Pagination.self, forKey: .pagination)
        currentPage = pagination.currentPage
        totalPages = pagination.totalPages
    }

    init(products: [SmartPriceProduct], currentPage: Int, totalPages: Int) {
        self.products = products
        self.currentPage = currentPage
        self.totalPages = totalPages
    }
}
