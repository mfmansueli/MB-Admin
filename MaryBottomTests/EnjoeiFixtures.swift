import Foundation
@testable import MaryBottom

/// Dados de exemplo compartilhados pelos testes, no formato que o Enjoei devolve de verdade.
nonisolated enum EnjoeiFixtures {
    static func product(id: Int, title: String = "brinco prata 925") -> EnjoeiProduct {
        EnjoeiProduct(
            id: id,
            title: title,
            path: "\(title.replacingOccurrences(of: " ", with: "-"))-\(id)",
            photoPublicID: "czM6Ly9waG90b3M",
            currentPrice: 273,
            originalPrice: 399
        )
    }

    static func page(ids: [Int], total: Int? = nil, endCursor: String? = "cursor") -> StoreProductsPage {
        StoreProductsPage(
            products: ids.map { product(id: $0) },
            total: total ?? ids.count,
            endCursor: endCursor
        )
    }

    /// Recorte real da resposta de `searchProductsForStore`.
    static let storeSearchJSON = """
    {
      "data": {
        "seller": {
          "search": {
            "products": {
              "total": 1495,
              "edges": [
                {
                  "cursor": "165537532022233012:1",
                  "node": {
                    "id": "145657034",
                    "path": "brinco-argola-estrela-145657034",
                    "photo": { "image_public_id": "czM6Ly9waG90b3MuZW5qb2Vp" },
                    "title": { "name": "brinco argola estrela 50mm" },
                    "price": { "original": 399, "current": 273 }
                  }
                },
                {
                  "cursor": "165537526022505319:1",
                  "node": {
                    "id": "147640589",
                    "path": "brinco-estrela-cravejado-147640589",
                    "photo": { "image_public_id": "czM6Ly9waG90b3MuZW5qb2VpMg" },
                    "title": { "name": "brinco estrela cravejado" },
                    "price": { "original": 299, "current": 192 }
                  }
                }
              ]
            }
          }
        }
      }
    }
    """

    static let currentUserJSON = """
    {
      "id": 28714888,
      "nickname": "antonia-40d0aa",
      "name": "antonia",
      "avatar": { "image_public_id": "czM6Ly9hdmF0YXI" },
      "counters": { "available_products_count": 1496 }
    }
    """
}

nonisolated extension EnjoeiUser {
    static let stub = EnjoeiUser(
        id: 28714888,
        nickname: "antonia-40d0aa",
        name: "antonia",
        avatarPublicID: nil,
        availableProductsCount: 1496
    )
}
