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

    private(set) var megaphonedIDs: [Int] = []
    private(set) var requestedCursors: [String?] = []
    private(set) var usedTokens: [String] = []
    private(set) var csrfCallCount = 0

    init(
        user: EnjoeiUser = .stub,
        currentUserError: EnjoeiError? = nil,
        pages: [StoreProductsPage] = [],
        failuresByProductID: [Int: EnjoeiError] = [:],
        csrfRejectionsRemaining: Int = 0
    ) {
        self.user = user
        self.currentUserError = currentUserError
        self.pages = pages
        self.failuresByProductID = failuresByProductID
        self.csrfRejectionsRemaining = csrfRejectionsRemaining
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

    func megaphone(productID: Int, csrfToken: String) async throws {
        usedTokens.append(csrfToken)
        if csrfRejectionsRemaining > 0 {
            csrfRejectionsRemaining -= 1
            throw EnjoeiError.invalidCSRFToken
        }
        if let failure = failuresByProductID[productID] { throw failure }
        megaphonedIDs.append(productID)
    }
}
