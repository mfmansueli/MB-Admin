import Foundation

/// Cliente que faz as chamadas autenticadas de dentro da WebView logada, e delega o resto para as
/// rotas públicas.
@MainActor
final class WebViewEnjoeiClient: EnjoeiClientProtocol {
    private let webSession: EnjoeiWebSession
    private let publicAPI: EnjoeiPublicAPI

    init(webSession: EnjoeiWebSession? = nil, publicAPI: EnjoeiPublicAPI? = nil) {
        self.webSession = webSession ?? .shared
        self.publicAPI = publicAPI ?? EnjoeiPublicClient()
    }

    func currentUser(reloadingPage: Bool) async throws -> EnjoeiUser {
        let identity = try await identity(reloadingPage: reloadingPage)
        guard let nickname = identity.nickname else {
            throw EnjoeiError.notIdentified(detail: identity.diagnosticSummary)
        }
        // O perfil público completa o que o script não vê: id numérico, avatar e contadores.
        return try await publicAPI.user(nickname: nickname)
    }

    func identity(reloadingPage: Bool) async throws -> EnjoeiIdentity {
        let result = try await webSession.run(EnjoeiJavaScript.identity, reloadingPage: reloadingPage)
        return EnjoeiIdentity(javaScriptResult: result)
    }

    func storeProductsPage(sellerID: Int, after: String?) async throws -> StoreProductsPage {
        try await publicAPI.storeProductsPage(sellerID: sellerID, after: after)
    }

    func csrfToken() async throws -> String {
        // Token vazio é aceitável: a rota de megafone nem sempre exige, e o app tenta assim mesmo.
        try await webSession.run(EnjoeiJavaScript.csrfToken) as? String ?? ""
    }

    func megaphone(productID: Int, csrfToken: String) async throws {
        let result = try await webSession.run(
            EnjoeiJavaScript.megaphone,
            arguments: ["productID": productID, "token": csrfToken]
        )
        let response = MegaphoneWebResponse(javaScriptResult: result)
        if let error = response.failure { throw error }
    }
}
