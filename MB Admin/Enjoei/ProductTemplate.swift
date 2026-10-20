import Foundation

/// Resposta de `GET /api/similars/products/{id}/template` — todos os campos que o formulário de
/// duplicar/editar do Enjoei usa pra pré-preencher um anúncio, incluindo as fotos já com
/// `image_public_id` (não precisa reenviar).
nonisolated struct ProductTemplate: Equatable, Sendable, Decodable {
    let title: String
    let description: String
    let brand: String?
    let used: Bool
    /// Em centavos, como o Enjoei devolve. É o preço COM qualquer desconto ativo — a criação do
    /// repost usa `originalPrice`, não este, pra não carregar o desconto pro anúncio novo.
    let price: Int
    /// Em centavos, sem desconto — é o que a criação do repost usa como `price`.
    let originalPrice: Int
    let weight: String
    let quantity: Int
    let category: Category
    /// `null` quando a categoria não tem tamanhos.
    let size: String?
    let shipping: Shipping
    let photos: [Photo]
    let originPlanID: Int?
    let smartPrice: SmartPrice?

    struct Category: Equatable, Sendable, Decodable {
        let id: Int
    }

    struct Shipping: Equatable, Sendable, Decodable {
        let type: String
        let hasInsurance: Bool

        private enum CodingKeys: String, CodingKey {
            case type
            case hasInsurance = "has_insurance"
        }
    }

    struct Photo: Equatable, Sendable, Decodable {
        let imagePublicID: String
        let position: Int

        private enum CodingKeys: String, CodingKey {
            case imagePublicID = "image_public_id"
            case position
        }
    }

    struct SmartPrice: Equatable, Sendable, Decodable {
        let enabled: Bool
    }

    private enum CodingKeys: String, CodingKey {
        case title, description, brand, used, price, weight, quantity, category, size, shipping, photos
        case originalPrice = "original_price"
        case originPlanID = "origin_plan_id"
        case smartPrice = "smart_price"
    }
}
