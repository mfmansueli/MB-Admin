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

    func megaphoneBatch(
        productIDs: [Int],
        csrfToken: String,
        delayMilliseconds: Int,
        onProgress: @escaping (Int, MegaphoneWebResponse) -> Void
    ) async throws -> String {
        guard !productIDs.isEmpty else { return csrfToken }
        let result = try await webSession.runBatch(
            EnjoeiJavaScript.megaphoneBatch,
            arguments: ["productIDs": productIDs, "token": csrfToken, "delayMilliseconds": delayMilliseconds],
            onProgress: onProgress
        )
        return result as? String ?? csrfToken
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

    func productTemplate(productID: Int) async throws -> ProductTemplate {
        let result = try await webSession.run(
            EnjoeiJavaScript.productTemplate,
            arguments: ["productID": productID]
        )
        let response = MegaphoneWebResponse(javaScriptResult: result)
        if let error = response.failure { throw error }
        return try JSONDecoder().decode(ProductTemplate.self, from: Data(response.body.utf8))
    }

    func createProduct(_ request: ProductCreateRequest, csrfToken: String) async throws -> ProductCreateResponse {
        let bodyData = try JSONEncoder().encode(request)
        guard let bodyString = String(data: bodyData, encoding: .utf8) else {
            throw EnjoeiError.unexpectedResponse
        }
        let result = try await webSession.run(
            EnjoeiJavaScript.createProduct,
            arguments: ["requestBody": bodyString, "token": csrfToken]
        )
        let response = MegaphoneWebResponse(javaScriptResult: result)
        if let error = response.failure { throw error }
        // Formato da resposta não documentado no spec (só diz "logue a resposta pra extrair o
        // ID/URL do novo anúncio") — logar aqui é o jeito de confirmar o formato real na primeira
        // vez que um repost rodar de verdade, caso `ProductCreateResponse` ainda não ache o link.
        #if DEBUG
        print("[repost] resposta de POST /api/products/v2: \(response.body)")
        #endif
        // Sem conseguir decodificar nenhum formato conhecido, `path` fica nil — quem mostra o
        // resultado não deve fingir que tem link nenhum nesse caso.
        return (try? JSONDecoder().decode(ProductCreateResponse.self, from: Data(response.body.utf8)))
            ?? ProductCreateResponse(path: nil)
    }

    func deleteProduct(productID: Int, csrfToken: String) async throws {
        let result = try await webSession.run(
            EnjoeiJavaScript.deleteProduct,
            arguments: ["productID": productID, "token": csrfToken]
        )
        let response = MegaphoneWebResponse(javaScriptResult: result)
        if let error = response.failure { throw error }
    }

    func updateProductState(_ request: ProductStateUpdateRequest, productID: Int, csrfToken: String) async throws {
        let bodyData = try JSONEncoder().encode(request)
        guard let bodyString = String(data: bodyData, encoding: .utf8) else {
            throw EnjoeiError.unexpectedResponse
        }
        let result = try await webSession.run(
            EnjoeiJavaScript.updateProductState,
            arguments: ["productID": productID, "requestBody": bodyString, "token": csrfToken]
        )
        let response = MegaphoneWebResponse(javaScriptResult: result)
        if let error = response.failure { throw error }
    }

    func inactiveProductsPage(page: Int) async throws -> InactiveProductsPage {
        let result = try await webSession.run(
            EnjoeiJavaScript.inactiveProductsPage,
            arguments: ["page": page]
        )
        let response = MegaphoneWebResponse(javaScriptResult: result)
        #if DEBUG
        print("[inativos] página \(page) — status \(response.status), corpo: \(response.body)")
        #endif
        if let error = response.failure { throw error }
        return try JSONDecoder().decode(InactiveProductsPage.self, from: Data(response.body.utf8))
    }

    func smartPriceProductsPage(page: Int, tab: Bool) async throws -> SmartPriceProductsPage {
        let result = try await webSession.run(
            EnjoeiJavaScript.smartPriceProductsPage,
            arguments: ["page": page, "tab": tab]
        )
        let response = MegaphoneWebResponse(javaScriptResult: result)
        if let error = response.failure { throw error }
        return try JSONDecoder().decode(SmartPriceProductsPage.self, from: Data(response.body.utf8))
    }

    func setSmartPrice(productID: Int, activate: Bool, csrfToken: String) async throws {
        let result = try await webSession.run(
            EnjoeiJavaScript.setSmartPrice,
            arguments: ["productID": productID, "token": csrfToken, "activate": activate]
        )
        let response = MegaphoneWebResponse(javaScriptResult: result)
        if let error = response.failure { throw error }
    }

    func reloadPage() async {
        await webSession.load(EnjoeiAPI.webBaseURL)
    }
}
