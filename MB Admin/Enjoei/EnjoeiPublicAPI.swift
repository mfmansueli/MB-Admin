import Foundation

/// As rotas do Enjoei que respondem sem sessão — dá para chamar direto do `URLSession`.
nonisolated protocol EnjoeiPublicAPI: Sendable {
    /// Dados públicos de uma loja pelo apelido.
    func user(nickname: String) async throws -> EnjoeiUser
    /// Uma página dos produtos à venda da loja. `after` é o cursor da última aresta recebida.
    func storeProductsPage(sellerID: Int, after: String?) async throws -> StoreProductsPage
}
