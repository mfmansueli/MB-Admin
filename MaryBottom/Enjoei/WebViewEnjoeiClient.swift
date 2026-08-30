import Foundation

/// Cliente que faz as chamadas autenticadas de dentro da WebView logada, e delega o resto para as
/// rotas públicas.
@MainActor
final class WebViewEnjoeiClient: EnjoeiClientProtocol {
    private let webSession: EnjoeiWebSession
    private let publicAPI: EnjoeiPublicAPI

    init(webSession: EnjoeiWebSession, publicAPI: EnjoeiPublicAPI? = nil) {
        self.webSession = webSession
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

    func megaphone(productID: Int, csrfToken: String, newPrice: Double?) async throws {
        let result = try await webSession.run(
            EnjoeiJavaScript.megaphone,
            // NSNull vira `null` do lado do JS — omitir a chave faria o script referenciar uma
            // variável inexistente, e `callAsyncJavaScript` não aceita valor `nil` direto num `Any`.
            arguments: ["productID": productID, "token": csrfToken, "newPrice": newPrice ?? NSNull()]
        )
        let response = MegaphoneWebResponse(javaScriptResult: result)
        if let error = response.failure { throw error }
    }

    func megaphoneExposures(productIDs: [Int]) async throws -> [MegaphoneExposure] {
        guard !productIDs.isEmpty else { return [] }
        let result = try await webSession.run(
            EnjoeiJavaScript.megaphoneExposures,
            arguments: ["productIDs": productIDs.map(String.init).joined(separator: ",")]
        )
        let response = MegaphoneWebResponse(javaScriptResult: result)
        if let error = response.failure { throw error }
        let payload = try JSONDecoder().decode(MegaphoneExposuresPayload.self, from: Data(response.body.utf8))
        return payload.products
    }
}
