import Foundation

/// Endereços e constantes das APIs do Enjoei usadas pelo app.
///
/// A estrutura das requisições veio da coleção Postman `enjoeilogin.postman_collection.json`,
/// conferida contra o site em produção.
nonisolated enum EnjoeiAPI {
    static let webBaseURL = URL(string: "https://www.enjoei.com.br")!
    static let searchBaseURL = URL(string: "https://enjusearch.enjoei.com.br")!
    static let photosBaseURL = URL(string: "https://photos.enjoei.com.br")!

    static let cookieDomainSuffix = "enjoei.com.br"
    static let sessionCookieName = "_enjoei_session"

    /// Hash da persisted query `searchProductsForStore`. Pode mudar quando o Enjoei publica uma
    /// versão nova do site; se a listagem parar de responder, recapturar da aba Network.
    static let searchQueryID = "a626b8fc399a43f5eddf80b59a473795"

    /// O servidor limita a página em 50 itens mesmo quando pedimos mais.
    static let searchPageSize = 50

    static var loginURL: URL { webBaseURL.appendingPathComponent("usuario/identifique-se") }
    static var currentUserURL: URL { webBaseURL.appendingPathComponent("api/v3/current_user.json") }
    static var myStoreURL: URL { webBaseURL.appendingPathComponent("minha-loja") }
    static var megaphonesURL: URL { webBaseURL.appendingPathComponent("api/megaphones") }

    static func userURL(nickname: String) -> URL {
        webBaseURL.appendingPathComponent("api/v3/users/\(nickname).json")
    }

    static func storeURL(nickname: String) -> URL {
        webBaseURL.appendingPathComponent("@\(nickname)")
    }

    static func productURL(path: String) -> URL {
        webBaseURL.appendingPathComponent("p/\(path)")
    }

    /// Listagem paginada dos produtos à venda de uma loja (GraphQL de busca do Enjoei).
    ///
    /// - Parameter after: cursor da última aresta recebida; `nil` traz a primeira página.
    static func storeProductsURL(
        sellerID: Int,
        after: String?,
        browserID: String,
        pageSize: Int = searchPageSize
    ) -> URL {
        var components = URLComponents(
            url: searchBaseURL.appendingPathComponent("graphql-search-x"),
            resolvingAgainstBaseURL: false
        )!
        var query = [
            URLQueryItem(name: "operation_name", value: "searchProductsForStore"),
            URLQueryItem(name: "query_id", value: searchQueryID),
            URLQueryItem(name: "seller_id", value: String(sellerID)),
            URLQueryItem(name: "user_id", value: String(sellerID)),
            URLQueryItem(name: "first", value: String(pageSize)),
            URLQueryItem(name: "term", value: ""),
            URLQueryItem(name: "new_buyer", value: "false"),
            URLQueryItem(name: "search_context", value: "products_search_store_page_default"),
            URLQueryItem(name: "browser_id", value: browserID)
        ]
        if let after, !after.isEmpty {
            query.append(URLQueryItem(name: "after", value: after))
        }
        components.queryItems = query
        return components.url!
    }
}
