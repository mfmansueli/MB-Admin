import Foundation
import Testing
@testable import MB_Admin

@Suite("decodificação de produtos de preço esperto")
struct SmartPriceProductTests {
    /// Recorte real da resposta de `GET /api/smart_price/v2` (ver
    /// `~/Downloads/enjoeiprecoespertoapi.md`).
    private let productJSON = """
    {
        "id": 150088854,
        "price": 359,
        "description": { "color": "#00A637", "text": "preço bom, máxima exposição" },
        "image_public_id": "czM6Ly9waG90b3M",
        "min_price": 251,
        "max_price": 430,
        "blocked": false,
        "smart_price_enabled": true
    }
    """

    @Test("decodifica os campos, achatando description em statusText/statusColor")
    func decodificaOsCampos() throws {
        let product = try JSONDecoder().decode(SmartPriceProduct.self, from: Data(productJSON.utf8))

        #expect(product.id == 150088854)
        #expect(product.price == 359)
        #expect(product.minPrice == 251)
        #expect(product.maxPrice == 430)
        #expect(product.blocked == false)
        #expect(product.smartPriceEnabled == true)
        #expect(product.statusText == "preço bom, máxima exposição")
        #expect(product.statusColor == "#00A637")
        #expect(product.photoPublicID == "czM6Ly9waG90b3M")
    }

    @Test("description ausente não falha a decodificação — statusText/statusColor ficam nil")
    func descriptionAusente() throws {
        let json = """
        {
            "id": 1, "price": 100, "min_price": 70, "max_price": 150,
            "blocked": false, "smart_price_enabled": false
        }
        """
        let product = try JSONDecoder().decode(SmartPriceProduct.self, from: Data(json.utf8))

        #expect(product.statusText == nil)
        #expect(product.statusColor == nil)
        #expect(product.photoPublicID == nil)
    }

    @Test("codifica e decodifica de volta sem perder nada — round trip usado pela persistência")
    func roundTrip() throws {
        let original = try JSONDecoder().decode(SmartPriceProduct.self, from: Data(productJSON.utf8))

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SmartPriceProduct.self, from: data)

        #expect(decoded == original)
    }

    @Test("decodifica o envelope paginado, achatando pagination em currentPage/totalPages")
    func decodificaOEnvelope() throws {
        let json = """
        {
            "with_smart_price_tab": false,
            "product_count": 77,
            "total_available_products_count": 1532,
            "pagination": { "current_page": 2, "total_pages": 4, "per_page": 20 },
            "products": [\(productJSON)]
        }
        """
        let page = try JSONDecoder().decode(SmartPriceProductsPage.self, from: Data(json.utf8))

        #expect(page.currentPage == 2)
        #expect(page.totalPages == 4)
        #expect(page.products.map(\.id) == [150088854])
    }
}
