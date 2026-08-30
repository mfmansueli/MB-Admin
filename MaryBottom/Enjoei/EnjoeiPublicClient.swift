import Foundation

/// Cliente das rotas públicas do Enjoei (perfil da loja e busca de produtos).
///
/// O que exige login não passa por aqui: o Enjoei recusa cookie replicado para fora do navegador,
/// então isso fica com a `WebViewEnjoeiClient`.
nonisolated final class EnjoeiPublicClient: EnjoeiPublicAPI {
    private let session: URLSession
    private let browserID: String

    init(session: URLSession = .enjoeiShared, browserID: String = BrowserIdentifier.current()) {
        self.session = session
        self.browserID = browserID
    }

    func user(nickname: String) async throws -> EnjoeiUser {
        let (data, response) = try await get(EnjoeiAPI.userURL(nickname: nickname))
        try validate(response, data: data)
        let payload = try JSONDecoder().decode(EnjoeiUserPayload.self, from: data)
        guard let user = payload.makeUser() else { throw EnjoeiError.unexpectedResponse }
        return user
    }

    func storeProductsPage(sellerID: Int, after: String?) async throws -> StoreProductsPage {
        let url = EnjoeiAPI.storeProductsURL(sellerID: sellerID, after: after, browserID: browserID)
        let (data, response) = try await get(url)
        try validate(response, data: data)
        do {
            return try JSONDecoder().decode(StoreProductsPage.self, from: data)
        } catch {
            throw EnjoeiError.unexpectedResponse
        }
    }

    private func get(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue(EnjoeiAPI.webBaseURL.absoluteString + "/", forHTTPHeaderField: "Referer")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EnjoeiError.unexpectedResponse
        }
        return (data, httpResponse)
    }

    private func validate(_ response: HTTPURLResponse, data: Data) throws {
        guard !(200..<300).contains(response.statusCode) else { return }
        throw EnjoeiError.http(status: response.statusCode, message: EnjoeiError.serverMessage(in: data))
    }
}
