import Foundation

/// Resposta do `POST /api/megaphones` feito dentro da WebView.
nonisolated struct MegaphoneWebResponse: Equatable, Sendable {
    let status: Int
    let body: String

    init(status: Int, body: String = "") {
        self.status = status
        self.body = body
    }

    init(javaScriptResult: Any?) {
        let dictionary = javaScriptResult as? [String: Any] ?? [:]
        status = (dictionary["status"] as? NSNumber)?.intValue ?? 0
        body = dictionary["body"] as? String ?? ""
    }

    /// O erro correspondente ao status, ou `nil` quando o megafone saiu.
    var failure: EnjoeiError? {
        if (200..<300).contains(status) { return nil }
        switch status {
        case 401:
            return .notAuthenticated
        case 422:
            return .invalidCSRFToken
        default:
            return .http(status: status, message: EnjoeiError.serverMessage(in: Data(body.utf8)))
        }
    }
}
