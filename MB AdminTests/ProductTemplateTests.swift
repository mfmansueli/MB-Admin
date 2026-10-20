import Foundation
import Testing
@testable import MB_Admin

@Suite("decodificação do template de produto")
struct ProductTemplateTests {
    /// Recorte da resposta de `GET /api/similars/products/{id}/template`, do spec de repost.
    static let templateJSON = """
    {
      "id": 149812846,
      "title": "colar curto pingente cravejado menino zircônia branca classico ródio branco",
      "description": "colar curto com pingente de menino cravejado com zircônia cristal e coração",
      "used": false,
      "brand": "mary botton acessorios",
      "price": 29900,
      "original_price": 29900,
      "weight": "0.3",
      "quantity": 1,
      "state": "published",
      "shipping": {
        "type": "charge_by_weight",
        "has_insurance": true,
        "insurance_price": 0
      },
      "size": null,
      "category": {
        "id": 327,
        "slug": "feminino-acessorios-joias-e-bijouterias-colares",
        "has_sizes": false
      },
      "photos": [
        {
          "image_public_id": "czM6Ly9waG90b3MuZW5qb2VpLmNvbS5ici9wcm9kdWN0cy8yODcxNDg4OC8uLi5qcGc",
          "original_image_url": "https://photos.enjoei.com.br/products/28714888/....jpg",
          "position": 0
        }
      ],
      "plan": null,
      "smart_price": { "enabled": true },
      "use_photos": true,
      "origin_plan_id": 1
    }
    """

    @Test("lê os campos que a criação do anúncio novo usa")
    func decodificaTemplate() throws {
        let template = try JSONDecoder().decode(ProductTemplate.self, from: Data(Self.templateJSON.utf8))

        #expect(template.title == "colar curto pingente cravejado menino zircônia branca classico ródio branco")
        #expect(template.description == "colar curto com pingente de menino cravejado com zircônia cristal e coração")
        #expect(template.brand == "mary botton acessorios")
        #expect(template.used == false)
        #expect(template.price == 29900)
        #expect(template.weight == "0.3")
        #expect(template.quantity == 1)
        #expect(template.category.id == 327)
        #expect(template.size == nil)
        #expect(template.shipping.type == "charge_by_weight")
        #expect(template.shipping.hasInsurance == true)
        #expect(template.photos.count == 1)
        #expect(template.photos.first?.imagePublicID
            == "czM6Ly9waG90b3MuZW5qb2VpLmNvbS5ici9wcm9kdWN0cy8yODcxNDg4OC8uLi5qcGc")
        #expect(template.photos.first?.position == 0)
        #expect(template.originPlanID == 1)
        #expect(template.smartPrice?.enabled == true)
    }
}
