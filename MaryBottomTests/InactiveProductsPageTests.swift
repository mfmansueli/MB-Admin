import Foundation
import Testing
@testable import MaryBottom

@Suite("decodificação da página de produtos inativos")
struct InactiveProductsPageTests {
    @Test("decodifica produtos e o número máximo de página")
    func decodificaPagina() throws {
        let json = """
        {
            "max_page": 19,
            "products": [
                {
                    "id": 143304960,
                    "path": "brinco-pino-diamond-cravejado-10mm-prata-295-143304960",
                    "title": "brinco pino diamond cravejado 10mm prata 295",
                    "price": 229.0,
                    "photo_public_id": "abc123",
                    "inactive_since": "12/03/2026"
                }
            ]
        }
        """
        let page = try JSONDecoder().decode(InactiveProductsPage.self, from: Data(json.utf8))

        #expect(page.maxPage == 19)
        #expect(page.products.count == 1)
        let product = try #require(page.products.first)
        #expect(product.id == 143304960)
        #expect(product.path == "brinco-pino-diamond-cravejado-10mm-prata-295-143304960")
        #expect(product.title == "brinco pino diamond cravejado 10mm prata 295")
        #expect(product.price == 229.0)
        #expect(product.photoPublicID == "abc123")
        #expect(product.inactiveSince == "12/03/2026")
    }

    @Test("campos opcionais ausentes decodificam como nil, sem erro")
    func camposOpcionaisAusentes() throws {
        let json = """
        { "max_page": 1, "products": [{ "id": 1, "path": "produto-1", "title": "produto 1", "price": null, "photo_public_id": null, "inactive_since": null }] }
        """
        let page = try JSONDecoder().decode(InactiveProductsPage.self, from: Data(json.utf8))

        let product = try #require(page.products.first)
        #expect(product.price == nil)
        #expect(product.photoPublicID == nil)
        #expect(product.inactiveSince == nil)
    }

    @Test("lista vazia decodifica sem erro")
    func listaVazia() throws {
        let page = try JSONDecoder().decode(InactiveProductsPage.self, from: Data(#"{"max_page": 1, "products": []}"#.utf8))
        #expect(page.products.isEmpty)
    }
}
