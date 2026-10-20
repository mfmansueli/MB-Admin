import Foundation

/// Corpo de `PATCH /perfil/minha-lojinha/a-venda/update_product/{id}` — inativa OU ativa um
/// produto reenviando o objeto inteiro dele, mudando só `product_state`. Não existe endpoint
/// dedicado pra nenhuma das duas ações: é a mesma rota de edição completa que o site usa pra
/// qualquer alteração no anúncio, com `"disable"` ou `"active"` como única diferença entre elas
/// (ver `~/Downloads/enjoei_inativar_produto (1).md`, capturado do tráfego real do painel — a
/// captura de ativar trouxe também `plan_id`/`smart_price` no `product`, mas eles ficam de fora
/// pelo mesmo motivo do `shipping_type` abaixo).
///
/// Só carrega os campos que `ProductTemplate` (a rota de "duplicar", já usada pelo repost) dá com
/// certeza de formato batendo com o esperado aqui. Alguns campos do exemplo capturado ficam de
/// fora de propósito, por não ter de onde vir com confiança:
/// - `shipping_type`: no exemplo real vem um código numérico; o único dado equivalente que este
///   app tem (`ProductTemplate.shipping.type`) é uma string de OUTRO endpoint, formato
///   incompatível — mandar errado arriscaria trocar a configuração de frete do anúncio de verdade.
/// - `variations_attributes`: registros de estoque/variação por tamanho, com id próprio — não
///   existe em `ProductTemplate` nenhuma fonte pra isso.
/// - `plan_id`/`smart_price`: só apareceram na captura de ativar, e o formato exato (`plan_id`
///   string ou número nessa rota específica) não foi confirmado — mesmo raciocínio do
///   `shipping_type`.
///
/// Om Rails, um campo comum ausente no corpo de um `update` normalmente significa "não mexe nele"
/// (mass-assignment só aplica o que veio) — omitir é mais seguro do que adivinhar um valor errado
/// e sobrescrever configuração real do produto.
nonisolated struct ProductStateUpdateRequest: Equatable, Sendable {
    enum ProductState: String, Equatable, Sendable {
        case disable
        case active
    }

    let redirectTo: String
    let productState: ProductState
    let product: Product

    init(
        template: ProductTemplate,
        state: ProductState,
        redirectTo: String = "/perfil/minha-lojinha/a-venda/ativos"
    ) {
        self.redirectTo = redirectTo
        productState = state
        product = Product(template: template)
    }

    nonisolated struct Product: Equatable, Sendable {
        let price: Int
        let title: String
        let content: String
        let categoryTagIDs: [Int]
        let categoryTagSuggestions: [String]
        let brand: String?
        let weight: String
        let categoryID: Int
        let photosAttributes: [PhotoAttribute]

        init(template: ProductTemplate) {
            // Reais, não centavos — mesma conversão do repost (`ProductCreateRequest`), e é o
            // preço ORIGINAL (sem desconto), pra não gravar um preço promocional como se fosse o
            // de tabela.
            price = Int((Double(template.originalPrice) / 100).rounded())
            title = template.title
            content = template.description
            categoryTagIDs = []
            categoryTagSuggestions = []
            brand = template.brand
            weight = template.weight
            categoryID = template.category.id
            photosAttributes = template.photos.map(PhotoAttribute.init)
        }

        nonisolated struct PhotoAttribute: Equatable, Sendable {
            let angle: Int
            let imagePublicID: String
            let originalImageURL: String
            let position: Int
            let version: String?

            init(photo: ProductTemplate.Photo) {
                angle = 0
                imagePublicID = photo.imagePublicID
                // O exemplo capturado mostra os dois campos com o mesmo valor pra cada foto.
                originalImageURL = photo.imagePublicID
                position = photo.position
                version = nil
            }
        }
    }
}

nonisolated extension ProductStateUpdateRequest: Encodable {
    private enum CodingKeys: String, CodingKey {
        case redirectTo = "redirect_to"
        case productState = "product_state"
        case days
        case product
    }

    /// Codificação manual pra `days` sair como `null` explícito no JSON (igual aos exemplos
    /// capturados) — a sintetizada automaticamente omitiria a chave por ser `Optional`.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(redirectTo, forKey: .redirectTo)
        try container.encode(productState.rawValue, forKey: .productState)
        try container.encode(Int?.none, forKey: .days)
        try container.encode(product, forKey: .product)
    }
}

nonisolated extension ProductStateUpdateRequest.Product: Encodable {
    private enum CodingKeys: String, CodingKey {
        case price, title, content, brand, weight
        case categoryTagIDs = "category_tag_ids"
        case categoryTagSuggestions = "category_tag_suggestions"
        case categoryID = "category_id"
        case photosAttributes = "photos_attributes"
    }
}

nonisolated extension ProductStateUpdateRequest.Product.PhotoAttribute: Encodable {
    private enum CodingKeys: String, CodingKey {
        case angle
        case imagePublicID = "image_public_id"
        case originalImageURL = "original_image_url"
        case position
        case version
    }
}
