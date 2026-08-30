import Foundation

/// Operações do Enjoei que o app usa. Existe como protocolo para os testes poderem substituir a
/// WebView e a rede por um dublê.
nonisolated protocol EnjoeiClientProtocol: Sendable {
    /// Quem está logado, segundo a página do Enjoei.
    ///
    /// - Parameter reloadingPage: recarrega a página de bastidores antes de perguntar. Necessário
    ///   logo depois do login, quando a página aberta lá ainda é anterior à sessão nova.
    func currentUser(reloadingPage: Bool) async throws -> EnjoeiUser
    /// Uma página dos produtos à venda da loja. `after` é o cursor da última aresta recebida.
    func storeProductsPage(sellerID: Int, after: String?) async throws -> StoreProductsPage
    /// Token CSRF atual da sessão. Vazio quando a página não expõe nenhum.
    func csrfToken() async throws -> String
    /// Megafona um produto.
    func megaphone(productID: Int, csrfToken: String) async throws
}
