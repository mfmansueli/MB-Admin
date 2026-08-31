import Foundation
import Testing
@testable import MaryBottom

@Suite("mapeamento do template pro corpo de criação (repost)")
struct ProductCreateRequestTests {
    private func makeTemplate(
        brand: String? = "mary botton acessorios",
        originalPrice: Int = 29900,
        /// Preço COM desconto ativo — quando não informado, igual ao original (sem desconto).
        discountedPrice: Int? = nil,
        weight: String = "0.3",
        quantity: Int = 1,
        categoryID: Int = 327,
        size: String? = nil,
        shippingType: String = "charge_by_weight",
        hasInsurance: Bool = true,
        used: Bool = false,
        title: String = "colar curto pingente cravejado",
        description: String = "descrição do produto",
        photos: [ProductTemplate.Photo] = [
            ProductTemplate.Photo(imagePublicID: "czM6Ly9waG90b3M", position: 0)
        ],
        originPlanID: Int? = 1,
        smartPriceEnabled: Bool? = true
    ) -> ProductTemplate {
        ProductTemplate(
            title: title,
            description: description,
            brand: brand,
            used: used,
            price: discountedPrice ?? originalPrice,
            originalPrice: originalPrice,
            weight: weight,
            quantity: quantity,
            category: .init(id: categoryID),
            size: size,
            shipping: .init(type: shippingType, hasInsurance: hasInsurance),
            photos: photos,
            originPlanID: originPlanID,
            smartPrice: smartPriceEnabled.map { .init(enabled: $0) }
        )
    }

    @Test("preço vem do original do template em centavos e sai em reais, arredondado")
    func precoCentavosParaReais() {
        let request = ProductCreateRequest(template: makeTemplate(originalPrice: 29900))
        #expect(request.product.price == 299)
    }

    @Test("preço com centavos não-zero arredonda pro real mais próximo")
    func precoComCentavosNaoZero() {
        let request = ProductCreateRequest(template: makeTemplate(originalPrice: 2990))
        #expect(request.product.price == 30)
    }

    @Test("desconto ativo no produto não é carregado pro repost — usa o preço original, não o atual")
    func naoCarregaDescontoAtivo() {
        let request = ProductCreateRequest(
            template: makeTemplate(originalPrice: 29900, discountedPrice: 19900)
        )
        #expect(request.product.price == 299)
    }

    @Test("description do template vira content na criação")
    func descriptionViraContent() {
        let request = ProductCreateRequest(template: makeTemplate(description: "descrição bacana"))
        #expect(request.product.content == "descrição bacana")
    }

    @Test("shipping.has_insurance vira shipping_insurance_enabled")
    func hasInsuranceViraShippingInsuranceEnabled() {
        let request = ProductCreateRequest(template: makeTemplate(hasInsurance: true))
        #expect(request.product.shippingInsuranceEnabled == true)
    }

    @Test("fotos são reaproveitadas direto, sem reenviar")
    func fotosReaproveitadas() {
        let photos = [
            ProductTemplate.Photo(imagePublicID: "id-a", position: 0),
            ProductTemplate.Photo(imagePublicID: "id-b", position: 1)
        ]
        let request = ProductCreateRequest(template: makeTemplate(photos: photos))

        #expect(request.product.photosAttributes.map(\.imagePublicID) == ["id-a", "id-b"])
        #expect(request.product.photosAttributes.map(\.position) == [0, 1])
    }

    @Test("plan_id usa o origin_plan_id do template, como string")
    func planIDUsaOriginPlanID() {
        let request = ProductCreateRequest(template: makeTemplate(originPlanID: 5))
        #expect(request.product.planID == "5")
    }

    @Test("plan_id ausente ou zero cai pro plano 1")
    func planIDAusenteCaiPro1() {
        #expect(ProductCreateRequest(template: makeTemplate(originPlanID: nil)).product.planID == "1")
        #expect(ProductCreateRequest(template: makeTemplate(originPlanID: 0)).product.planID == "1")
    }

    @Test("smart_price_enabled sempre nasce desativado no repost, mesmo quando o produto original tinha")
    func smartPriceEnabled() {
        #expect(ProductCreateRequest(template: makeTemplate(smartPriceEnabled: true)).product.smartPriceEnabled == false)
        #expect(ProductCreateRequest(template: makeTemplate(smartPriceEnabled: nil)).product.smartPriceEnabled == false)
    }

    @Test("product_size_id vem do size do template, null quando sem tamanho")
    func productSizeID() {
        #expect(ProductCreateRequest(template: makeTemplate(size: nil)).product.productSizeID == nil)
        #expect(ProductCreateRequest(template: makeTemplate(size: "M")).product.productSizeID == "M")
    }

    @Test("weight, brand, quantity, category, title e used passam direto")
    func camposDiretos() {
        let request = ProductCreateRequest(
            template: makeTemplate(
                brand: "sem-marca",
                weight: "1.5",
                quantity: 3,
                categoryID: 42,
                shippingType: "free",
                used: true,
                title: "um título"
            )
        )

        #expect(request.product.brand == "sem-marca")
        #expect(request.product.weight == "1.5")
        #expect(request.product.quantity == 3)
        #expect(request.product.categoryID == 42)
        #expect(request.product.shippingType == "free")
        #expect(request.product.used == true)
        #expect(request.product.title == "um título")
    }

    @Test("upload_uuid é gerado novo por chamada quando não informado")
    func uploadUUIDGeradoNovo() {
        let a = ProductCreateRequest(template: makeTemplate())
        let b = ProductCreateRequest(template: makeTemplate())
        #expect(a.uploadUUID != b.uploadUUID)
    }

    @Test("codifica com os nomes de campo em snake_case que a API espera")
    func codificaComNomesCorretos() throws {
        let request = ProductCreateRequest(template: makeTemplate(), uploadUUID: "um-uuid")

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let product = json?["product"] as? [String: Any]

        #expect(json?["upload_uuid"] as? String == "um-uuid")
        #expect(product?["category_id"] as? Int == 327)
        #expect(product?["shipping_insurance_enabled"] as? Bool == true)
        #expect(product?["shipping_type"] as? String == "charge_by_weight")
        #expect(product?["product_size_id"] == nil || product?["product_size_id"] is NSNull)
        #expect(product?["plan_id"] as? String == "1")
        #expect(product?["smart_price_enabled"] as? Bool == false)
        let photosAttributes = product?["photos_attributes"] as? [[String: Any]]
        #expect(photosAttributes?.first?["image_public_id"] as? String == "czM6Ly9waG90b3M")
    }
}
