import Foundation

/// Corpo de `POST /api/products/v2` — cria um anúncio novo. `init(template:)` é a lógica central do
/// repost: mapeia o que `ProductTemplate` leu do anúncio original pros campos (e unidades) que a
/// criação espera.
nonisolated struct ProductCreateRequest: Equatable, Sendable, Encodable {
    let product: Product
    let uploadUUID: String

    /// - Parameter uploadUUID: um UUID novo por anúncio criado — o Enjoei usa pra correlacionar o
    ///   upload das fotos, mesmo quando elas são reaproveitadas do original.
    init(template: ProductTemplate, uploadUUID: String = UUID().uuidString) {
        product = Product(template: template)
        self.uploadUUID = uploadUUID
    }

    private enum CodingKeys: String, CodingKey {
        case product
        case uploadUUID = "upload_uuid"
    }

    nonisolated struct Product: Equatable, Sendable, Encodable {
        let brand: String?
        let quantity: Int
        let categoryID: Int
        let content: String
        let photosAttributes: [PhotoAttribute]
        let price: Int
        let productSizeID: String?
        let shippingInsuranceEnabled: Bool
        let shippingType: String
        let title: String
        let used: Bool
        let weight: String
        let planID: String
        let smartPriceEnabled: Bool

        init(template: ProductTemplate) {
            brand = template.brand
            quantity = template.quantity
            categoryID = template.category.id
            content = template.description
            photosAttributes = template.photos.map(PhotoAttribute.init)
            // ⚠️ usa o preço ORIGINAL (sem desconto), em centavos — a criação espera reais. Usar
            // `template.price` carregaria um desconto ativo pro anúncio novo.
            price = Int((Double(template.originalPrice) / 100).rounded())
            productSizeID = template.size
            shippingInsuranceEnabled = template.shipping.hasInsurance
            shippingType = template.shipping.type
            title = template.title
            used = template.used
            weight = template.weight
            // `origin_plan_id` ausente ou 0 cai pro plano 1, igual ao pseudocódigo do spec.
            planID = String(template.originPlanID.flatMap { $0 > 0 ? $0 : nil } ?? 1)
            smartPriceEnabled = template.smartPrice?.enabled ?? false
        }

        private enum CodingKeys: String, CodingKey {
            case brand, quantity
            case categoryID = "category_id"
            case content
            case photosAttributes = "photos_attributes"
            case price
            case productSizeID = "product_size_id"
            case shippingInsuranceEnabled = "shipping_insurance_enabled"
            case shippingType = "shipping_type"
            case title, used, weight
            case planID = "plan_id"
            case smartPriceEnabled = "smart_price_enabled"
        }

        nonisolated struct PhotoAttribute: Equatable, Sendable, Encodable {
            let imagePublicID: String
            let position: Int

            init(photo: ProductTemplate.Photo) {
                imagePublicID = photo.imagePublicID
                position = photo.position
            }

            private enum CodingKeys: String, CodingKey {
                case imagePublicID = "image_public_id"
                case position
            }
        }
    }
}
