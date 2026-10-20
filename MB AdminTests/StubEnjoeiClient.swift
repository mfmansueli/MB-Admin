import Foundation
@testable import MB_Admin

/// Dublê do Enjoei: devolve páginas e falhas combinadas pelo teste e registra o que foi pedido.
actor StubEnjoeiClient: EnjoeiClientProtocol {
    var user: EnjoeiUser
    var currentUserError: EnjoeiError?
    /// Espera artificial antes de responder `currentUser` — só para testar que restaurar várias
    /// contas em paralelo publica na ordem persistida mesmo quando uma responde antes da outra.
    var currentUserDelay: Duration = .zero
    /// Espera artificial antes de responder `inactiveProductsPage`/`smartPriceProductsPage` — só
    /// para testar que `pageConcurrency` busca páginas de verdade ao mesmo tempo (ver
    /// `maxConcurrentPageRequests` abaixo), não só que dá pra configurar o número.
    var pageDelay: Duration = .zero
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
    /// Erro a lançar em qualquer chamada de `updateProductState`.
    var updateProductStateError: EnjoeiError?
    /// Página combinada por número, devolvida por `inactiveProductsPage`. Página não configurada
    /// devolve vazia com `maxPage: 1`, pra um teste que só configura a página 1 não travar.
    var inactivePagesByNumber: [Int: InactiveProductsPage]
    /// Erro a lançar em qualquer chamada de `inactiveProductsPage`.
    var inactiveProductsError: EnjoeiError?
    /// Página combinada por número, devolvida por `smartPriceProductsPage(page:tab:)` (só a aba
    /// `tab: false`, a única que o app usa). Página não configurada devolve vazia com
    /// `totalPages: 1`, pra um teste que só configura a página 1 não travar.
    var smartPricePagesByNumber: [Int: SmartPriceProductsPage]
    /// Erro a lançar em qualquer chamada de `smartPriceProductsPage`.
    var smartPriceProductsError: EnjoeiError?
    /// Erro a lançar em qualquer chamada de `setSmartPrice`, por id de produto.
    var setSmartPriceFailuresByProductID: [Int: EnjoeiError]

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
    /// Um item por chamada a `updateProductState` (inativar ou ativar), com o id, o corpo e o token usados.
    private(set) var updateProductStateCalls: [(productID: Int, request: ProductStateUpdateRequest, token: String)] = []
    /// Um item por chamada a `inactiveProductsPage`, com o número da página pedida.
    private(set) var requestedInactivePages: [Int] = []
    /// Um item por chamada a `smartPriceProductsPage`, com a página e a aba pedidas.
    private(set) var requestedSmartPricePages: [(page: Int, tab: Bool)] = []
    /// Um item por chamada a `setSmartPrice`, com o id, se ativou/desativou e o token usados.
    private(set) var setSmartPriceCalls: [(productID: Int, activate: Bool, token: String)] = []
    /// Quantas chamadas a `inactiveProductsPage`/`smartPriceProductsPage` estavam com `pageDelay`
    /// em andamento ao mesmo tempo, no pico — prova determinística de concorrência de verdade
    /// (contadores mexidos em volta de uma suspensão real, não um limiar de tempo de parede).
    private(set) var maxConcurrentPageRequests = 0
    private var currentConcurrentPageRequests = 0

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
        deleteProductError: EnjoeiError? = nil,
        updateProductStateError: EnjoeiError? = nil,
        inactivePagesByNumber: [Int: InactiveProductsPage] = [:],
        inactiveProductsError: EnjoeiError? = nil,
        smartPricePagesByNumber: [Int: SmartPriceProductsPage] = [:],
        smartPriceProductsError: EnjoeiError? = nil,
        setSmartPriceFailuresByProductID: [Int: EnjoeiError] = [:],
        currentUserDelay: Duration = .zero,
        pageDelay: Duration = .zero
    ) {
        self.user = user
        self.currentUserError = currentUserError
        self.currentUserDelay = currentUserDelay
        self.pageDelay = pageDelay
        self.pages = pages
        self.failuresByProductID = failuresByProductID
        self.csrfRejectionsRemaining = csrfRejectionsRemaining
        self.exposuresByProductID = exposuresByProductID
        self.exposuresError = exposuresError
        self.templatesByProductID = templatesByProductID
        self.inactivePagesByNumber = inactivePagesByNumber
        self.inactiveProductsError = inactiveProductsError
        self.smartPricePagesByNumber = smartPricePagesByNumber
        self.smartPriceProductsError = smartPriceProductsError
        self.setSmartPriceFailuresByProductID = setSmartPriceFailuresByProductID
        self.templateError = templateError
        self.createProductError = createProductError
        self.createProductResponse = createProductResponse
        self.deleteProductError = deleteProductError
        self.updateProductStateError = updateProductStateError
    }

    private(set) var reloadingPageCalls: [Bool] = []

    /// Pra testes trocarem o erro entre uma chamada e outra (ex.: `retryCheckingSession`), sem
    /// precisar criar um client novo.
    func setCurrentUserError(_ error: EnjoeiError?) {
        currentUserError = error
    }

    func currentUser(reloadingPage: Bool) async throws -> EnjoeiUser {
        reloadingPageCalls.append(reloadingPage)
        if currentUserDelay > .zero { try? await Task.sleep(for: currentUserDelay) }
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

    /// Reaproveita `megaphone(productID:csrfToken:newPrice:)` item a item — mesma checagem de
    /// `csrfRejectionsRemaining`/`failuresByProductID` do dublê de sempre, só reempacotada como
    /// `MegaphoneWebResponse` pro `onProgress` poder chamar `.failure` como o código de produção faz.
    /// Não tenta reproduzir o laço em JS de verdade (`EnjoeiJavaScript.megaphoneBatch`) — isso só dá
    /// para validar numa conta real, dentro da WebView.
    func megaphoneBatch(
        productIDs: [Int],
        csrfToken: String,
        delayMilliseconds: Int,
        onProgress: @escaping (Int, MegaphoneWebResponse) -> Void
    ) async throws -> String {
        var currentToken = csrfToken
        for productID in productIDs {
            let response: MegaphoneWebResponse
            do {
                try await megaphone(productID: productID, csrfToken: currentToken, newPrice: nil)
                response = MegaphoneWebResponse(status: 200)
            } catch let error as EnjoeiError where error.isCSRFRejection {
                currentToken = try await self.csrfToken()
                do {
                    try await megaphone(productID: productID, csrfToken: currentToken, newPrice: nil)
                    response = MegaphoneWebResponse(status: 200)
                } catch {
                    response = MegaphoneWebResponse(status: (error as? EnjoeiError)?.stubHTTPStatus ?? 500)
                }
            } catch {
                response = MegaphoneWebResponse(status: (error as? EnjoeiError)?.stubHTTPStatus ?? 500)
            }
            onProgress(productID, response)
            if response.status == 401 { break }
        }
        return currentToken
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

    func updateProductState(_ request: ProductStateUpdateRequest, productID: Int, csrfToken: String) async throws {
        updateProductStateCalls.append((productID, request, csrfToken))
        if csrfRejectionsRemaining > 0 {
            csrfRejectionsRemaining -= 1
            throw EnjoeiError.invalidCSRFToken
        }
        if let updateProductStateError { throw updateProductStateError }
    }

    func inactiveProductsPage(page: Int) async throws -> InactiveProductsPage {
        requestedInactivePages.append(page)
        await waitPageDelay()
        if let inactiveProductsError { throw inactiveProductsError }
        return inactivePagesByNumber[page] ?? InactiveProductsPage(products: [], maxPage: 1)
    }

    func smartPriceProductsPage(page: Int, tab: Bool) async throws -> SmartPriceProductsPage {
        requestedSmartPricePages.append((page, tab))
        await waitPageDelay()
        if let smartPriceProductsError { throw smartPriceProductsError }
        return smartPricePagesByNumber[page] ?? SmartPriceProductsPage(products: [], currentPage: page, totalPages: 1)
    }

    /// Conta quantas chamadas de página estão penduradas na espera artificial ao mesmo tempo —
    /// ver `maxConcurrentPageRequests`.
    private func waitPageDelay() async {
        guard pageDelay > .zero else { return }
        currentConcurrentPageRequests += 1
        maxConcurrentPageRequests = max(maxConcurrentPageRequests, currentConcurrentPageRequests)
        try? await Task.sleep(for: pageDelay)
        currentConcurrentPageRequests -= 1
    }

    private(set) var reloadPageCallCount = 0

    func reloadPage() async {
        reloadPageCallCount += 1
    }

    private(set) var releaseMemoryIfIdleCallCount = 0

    func releaseMemoryIfIdle() async {
        releaseMemoryIfIdleCallCount += 1
    }

    func setSmartPrice(productID: Int, activate: Bool, csrfToken: String) async throws {
        setSmartPriceCalls.append((productID, activate, csrfToken))
        if csrfRejectionsRemaining > 0 {
            csrfRejectionsRemaining -= 1
            throw EnjoeiError.invalidCSRFToken
        }
        if let failure = setSmartPriceFailuresByProductID[productID] { throw failure }
    }
}

private extension EnjoeiError {
    /// Status HTTP equivalente, só para `StubEnjoeiClient.megaphoneBatch` reconstruir um
    /// `MegaphoneWebResponse` plausível a partir do erro combinado no teste — o tipo real nunca
    /// nasce assim, sempre de um status de verdade vindo do servidor.
    var stubHTTPStatus: Int {
        switch self {
        case .notAuthenticated: 401
        case .invalidCSRFToken: 422
        case .http(let status, _): status
        default: 500
        }
    }
}
