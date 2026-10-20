import Foundation

/// O que o script de identificação encontrou dentro da página logada.
nonisolated struct EnjoeiIdentity: Equatable, Sendable {
    let nickname: String?
    let id: Int?
    let csrfToken: String?
    /// Status HTTP de `/api/v3/current_user.json`, guardado para explicar a falha ao usuário.
    let currentUserStatus: Int?
    let myStoreStatus: Int?

    var isIdentified: Bool { nickname != nil }

    /// Lê o dicionário devolvido pelo `callAsyncJavaScript`.
    init(javaScriptResult: Any?) {
        let dictionary = javaScriptResult as? [String: Any] ?? [:]
        let nickname = (dictionary["nickname"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.nickname = (nickname?.isEmpty ?? true) ? nil : nickname
        id = (dictionary["id"] as? NSNumber)?.intValue
        let token = dictionary["csrf"] as? String
        csrfToken = (token?.isEmpty ?? true) ? nil : token
        currentUserStatus = (dictionary["currentUserStatus"] as? NSNumber)?.intValue
        myStoreStatus = (dictionary["myStoreStatus"] as? NSNumber)?.intValue
    }

    init(nickname: String?, id: Int? = nil, csrfToken: String? = nil,
         currentUserStatus: Int? = nil, myStoreStatus: Int? = nil) {
        self.nickname = nickname
        self.id = id
        self.csrfToken = csrfToken
        self.currentUserStatus = currentUserStatus
        self.myStoreStatus = myStoreStatus
    }

    /// Resumo técnico do que a página respondeu, para aparecer quando nada foi identificado.
    var diagnosticSummary: String {
        var parts: [String] = []
        if let currentUserStatus { parts.append("current_user: \(currentUserStatus)") }
        if let myStoreStatus { parts.append("minha-loja: \(myStoreStatus)") }
        return parts.joined(separator: ", ")
    }
}
