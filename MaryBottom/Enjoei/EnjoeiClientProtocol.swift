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
    /// Megafona um produto. `newPrice` aplica o desconto sugerido junto (ver
    /// `MegaphoneExposure.priceToIncreaseExposure`); `nil` megafona sem mexer no preço.
    func megaphone(productID: Int, csrfToken: String, newPrice: Double?) async throws
    /// Como cada produto se encaixa no megafone: se pede desconto pra alcançar exposição máxima.
    func megaphoneExposures(productIDs: [Int]) async throws -> [MegaphoneExposure]
    /// Lê todos os campos de um produto já publicado, pra repostar (duplicar) o anúncio.
    func productTemplate(productID: Int) async throws -> ProductTemplate
    /// Cria um anúncio novo a partir do corpo já montado (ver `ProductCreateRequest`).
    func createProduct(_ request: ProductCreateRequest, csrfToken: String) async throws -> ProductCreateResponse
    /// Apaga um produto de vez. Ação destrutiva e provavelmente irreversível.
    func deleteProduct(productID: Int, csrfToken: String) async throws
    /// Uma página da listagem de produtos inativos da própria loja (extraída do HTML — não existe
    /// API JSON pra isso). `page` começa em 1.
    func inactiveProductsPage(page: Int) async throws -> InactiveProductsPage
}
