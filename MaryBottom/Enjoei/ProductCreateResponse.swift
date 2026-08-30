import Foundation

/// Resposta de `POST /api/products/v2` — o spec de repost não documenta o formato exato (só diz
/// "logue a resposta pra extrair o ID/URL do novo anúncio"), então tenta os formatos mais
/// prováveis pro link do anúncio novo, nessa ordem de prioridade: `path`, `slug`, `url` — soltos
/// na raiz ou aninhados em `product` (espelhando o formato do corpo que a criação recebe). Sem
/// nenhum desses, `path` fica `nil` — quem chamar não deve fingir que tem link nenhum nesse caso.
/// `WebViewEnjoeiClient.createProduct` loga o corpo bruto em debug — se o botão de "visualizar"
/// continuar sem aparecer depois de um repost real, o log tem o formato exato pra ajustar aqui.
nonisolated struct ProductCreateResponse: Equatable, Sendable, Decodable {
    let path: String?

    init(path: String?) {
        self.path = path
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let found = try Self.path(in: container) {
            self.path = found
        } else if let nested = try container.decodeIfPresent(NestedProduct.self, forKey: .product) {
            self.path = nested.path
        } else {
            self.path = nil
        }
    }

    private static func path(in container: KeyedDecodingContainer<CodingKeys>) throws -> String? {
        if let path = try container.decodeIfPresent(String.self, forKey: .path) {
            return path
        }
        if let slug = try container.decodeIfPresent(String.self, forKey: .slug) {
            return slug
        }
        return try container.decodeIfPresent(String.self, forKey: .url)
    }

    private enum CodingKeys: String, CodingKey {
        case path, slug, url, product
    }

    private struct NestedProduct: Decodable {
        let path: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.path = try ProductCreateResponse.path(in: container)
        }
    }
}
