import Foundation
@testable import MaryBottom

/// Dublê do Enjoei: devolve páginas e falhas combinadas pelo teste e registra o que foi pedido.
actor StubEnjoeiClient: EnjoeiClientProtocol {
    var user: EnjoeiUser
    var currentUserError: EnjoeiError?
    var pages: [StoreProductsPage]
    /// Erro a lançar no megafone de um produto específico.
    var failuresByProductID: [Int: EnjoeiError]
    /// Quantas vezes o servidor ainda vai recusar o token CSRF antes de aceitar.
    var csrfRejectionsRemaining: Int
    /// Exposição combinada por produto, devolvida pelos lotes de `megaphoneExposures`.
    var exposuresByProductID: [Int: MegaphoneExposure]
    /// Erro a lançar em qualquer chamada de `megaphoneExposures`.
    var exposuresError: EnjoeiError?
    /// Template combinado por produto, devolvido por `productTemplate`.
    var templatesByProductID: [Int: ProductTemplate]
    /// Erro a lançar em qualquer chamada de `productTemplate`.
    var templateError: EnjoeiError?
    /// Erro a lançar em qualquer chamada de `createProduct`.
    var createProductError: EnjoeiError?
    /// Resposta combinada de `createProduct`, quando a chamada tem sucesso.
    var createProductResponse: ProductCreateResponse
    /// Erro a lançar em qualquer chamada de `deleteProduct`.
    var deleteProductError: EnjoeiError?

    private(set) var megaphonedIDs: [Int] = []
    private(set) var requestedCursors: [String?] = []
    private(set) var usedTokens: [String] = []
    private(set) var csrfCallCount = 0
    /// `new_price` usado em cada chamada de `megaphone`, por id de produto (só entra quando não é nil).
    private(set) var appliedDiscounts: [Int: Double] = [:]
    /// Um item por chamada a `megaphoneExposures`, com os ids pedidos naquele lote.
    private(set) var requestedExposureBatches: [[Int]] = []
    /// Um item por chamada a `productTemplate`, com o id pedido.
    private(set) var requestedTemplateIDs: [Int] = []
    /// Um item por chamada a `createProduct`, com o corpo e o token usados.
    private(set) var createProductCalls: [(request: ProductCreateRequest, token: String)] = []
    /// Um item por chamada a `deleteProduct`, com o id e o token usados.
    private(set) var deleteProductCalls: [(productID: Int, token: String)] = []

    init(
        user: EnjoeiUser = .stub,
        currentUserError: EnjoeiError? = nil,
        pages: [StoreProductsPage] = [],
        failuresByProductID: [Int: EnjoeiError] = [:],
        csrfRejectionsRemaining: Int = 0,
        exposuresByProductID: [Int: MegaphoneExposure] = [:],
        exposuresError: EnjoeiError? = nil,
        templatesByProductID: [Int: ProductTemplate] = [:],
        templateError: EnjoeiError? = nil,
        createProductError: EnjoeiError? = nil,
        createProductResponse: ProductCreateResponse = ProductCreateResponse(path: nil),
        deleteProductError: EnjoeiError? = nil
    ) {
        self.user = user
        self.currentUserError = currentUserError
        self.pages = pages
        self.failuresByProductID = failuresByProductID
        self.csrfRejectionsRemaining = csrfRejectionsRemaining
        self.exposuresByProductID = exposuresByProductID
        self.exposuresError = exposuresError
        self.templatesByProductID = templatesByProductID
        self.templateError = templateError
        self.createProductError = createProductError
        self.createProductResponse = createProductResponse
        self.deleteProductError = deleteProductError
    }

    private(set) var reloadingPageCalls: [Bool] = []

    func currentUser(reloadingPage: Bool) async throws -> EnjoeiUser {
        reloadingPageCalls.append(reloadingPage)
        if let currentUserError { throw currentUserError }
        return user
    }

    func storeProductsPage(sellerID: Int, after: String?) async throws -> StoreProductsPage {
        requestedCursors.append(after)
        guard !pages.isEmpty else {
            return StoreProductsPage(products: [], total: 0, endCursor: nil)
        }
        return pages.removeFirst()
    }

    func csrfToken() async throws -> String {
        csrfCallCount += 1
        return "token-\(csrfCallCount)"
    }

    func megaphone(productID: Int, csrfToken: String, newPrice: Double?) async throws {
        usedTokens.append(csrfToken)
        if let newPrice { appliedDiscounts[productID] = newPrice }
        if csrfRejectionsRemaining > 0 {
            csrfRejectionsRemaining -= 1
            throw EnjoeiError.invalidCSRFToken
        }
        if let failure = failuresByProductID[productID] { throw failure }
        megaphonedIDs.append(productID)
    }

    func megaphoneExposures(productIDs: [Int]) async throws -> [MegaphoneExposure] {
        requestedExposureBatches.append(productIDs)
        if let exposuresError { throw exposuresError }
        return productIDs.compactMap { exposuresByProductID[$0] }
    }

    func productTemplate(productID: Int) async throws -> ProductTemplate {
        requestedTemplateIDs.append(productID)
        if let templateError { throw templateError }
        guard let template = templatesByProductID[productID] else { throw EnjoeiError.unexpectedResponse }
        return template
    }

    func createProduct(_ request: ProductCreateRequest, csrfToken: String) async throws -> ProductCreateResponse {
        createProductCalls.append((request, csrfToken))
        if csrfRejectionsRemaining > 0 {
            csrfRejectionsRemaining -= 1
            throw EnjoeiError.invalidCSRFToken
        }
        if let createProductError { throw createProductError }
        return createProductResponse
    }

    func deleteProduct(productID: Int, csrfToken: String) async throws {
        deleteProductCalls.append((productID, csrfToken))
        if csrfRejectionsRemaining > 0 {
            csrfRejectionsRemaining -= 1
            throw EnjoeiError.invalidCSRFToken
        }
        if let deleteProductError { throw deleteProductError }
    }
}
