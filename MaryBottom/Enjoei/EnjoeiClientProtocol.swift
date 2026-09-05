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
    /// Megafona uma lista de produtos num lote só, sem sair da página (ver
    /// `EnjoeiJavaScript.megaphoneBatch`) — usado pelo laço automático (`MegaphoneRunner.megaphoneAll()`)
    /// em vez de chamar `megaphone(productID:csrfToken:newPrice:)` um a um, pra cortar o round-trip
    /// de IPC por produto. `onProgress` é chamado uma vez por produto, na ordem em que cada resposta
    /// chega — antes do lote inteiro terminar. Devolve o token CSRF em uso ao final (pode ter sido
    /// renovado no meio do lote).
    func megaphoneBatch(
        productIDs: [Int],
        csrfToken: String,
        delayMilliseconds: Int,
        onProgress: @escaping (Int, MegaphoneWebResponse) -> Void
    ) async throws -> String
    /// Como cada produto se encaixa no megafone: se pede desconto pra alcançar exposição máxima.
    func megaphoneExposures(productIDs: [Int]) async throws -> [MegaphoneExposure]
    /// Lê todos os campos de um produto já publicado, pra repostar (duplicar) o anúncio.
    func productTemplate(productID: Int) async throws -> ProductTemplate
    /// Cria um anúncio novo a partir do corpo já montado (ver `ProductCreateRequest`).
    func createProduct(_ request: ProductCreateRequest, csrfToken: String) async throws -> ProductCreateResponse
    /// Apaga um produto de vez. Ação destrutiva e provavelmente irreversível.
    func deleteProduct(productID: Int, csrfToken: String) async throws
    /// Inativa ou ativa um produto — reenvia o objeto inteiro dele (ver
    /// `ProductStateUpdateRequest`) com `product_state` mudado, mesma rota que a edição completa
    /// do anúncio usa (não existe endpoint dedicado pra nenhuma das duas ações). Nunca cria nada:
    /// só lê (`productTemplate`) e reenvia.
    func updateProductState(_ request: ProductStateUpdateRequest, productID: Int, csrfToken: String) async throws
    /// Uma página da listagem de produtos inativos da própria loja (extraída do HTML — não existe
    /// API JSON pra isso). `page` começa em 1.
    func inactiveProductsPage(page: Int) async throws -> InactiveProductsPage
    /// Uma página da listagem de "preço esperto" da própria loja. `tab` escolhe entre produtos já
    /// ativados (`true`) e ainda sem preço esperto (`false`); `page` começa em 1.
    func smartPriceProductsPage(page: Int, tab: Bool) async throws -> SmartPriceProductsPage
    /// Ativa (ou desativa) o preço esperto de um produto (ver `EnjoeiJavaScript.setSmartPrice`).
    func setSmartPrice(productID: Int, activate: Bool, csrfToken: String) async throws
    /// Recarrega a página de bastidores — mesma operação de recuperação que `EnjoeiWebSession.run`
    /// já faz sozinha quando um script falha em segundo plano, só que aqui é preventivo: reseta o
    /// heap JS/DOM que a própria página do Enjoei acumula numa sessão muito longa (centenas de
    /// chamadas seguidas, várias rodadas de megafone — ver `MegaphoneRunner.pageReloadThreshold`),
    /// sem recriar a `WKWebView`/`WKWebsiteDataStore` (essa área já teve um crash real do próprio
    /// WebKit — ver `AccountsStore.swift`). Login/cookies sobrevivem a um reload de página.
    func reloadPage() async
}
