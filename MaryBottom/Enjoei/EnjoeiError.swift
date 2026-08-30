import Foundation

/// Falhas previstas ao conversar com o Enjoei.
nonisolated enum EnjoeiError: LocalizedError, Equatable {
    /// Sem sessão válida — precisa logar de novo na WebView.
    case notAuthenticated
    /// A página carregou, mas não deu para saber quem é o usuário logado.
    case notIdentified(detail: String)
    /// O servidor recusou o token CSRF.
    case invalidCSRFToken
    /// Qualquer outro status fora da faixa 2xx, com a mensagem do servidor quando houver.
    case http(status: Int, message: String?)
    /// Resposta que não deu para interpretar.
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "sua sessão do enjoei expirou. entre de novo."
        case .notIdentified(let detail):
            detail.isEmpty
                ? "não consegui identificar sua conta no enjoei."
                : "não consegui identificar sua conta no enjoei (\(detail))."
        case .invalidCSRFToken:
            "o enjoei recusou o token de segurança da sessão."
        case .http(let status, let message):
            message ?? "o enjoei respondeu com erro \(status)."
        case .unexpectedResponse:
            "recebi uma resposta que não entendi do enjoei."
        }
    }

    /// O servidor recusou o token CSRF? Nesse caso vale renovar o token e tentar de novo — ele
    /// gira junto com a sessão.
    var isCSRFRejection: Bool {
        switch self {
        case .invalidCSRFToken: true
        case .http(let status, _): status == 403
        default: false
        }
    }

    /// Mensagem de erro que o Enjoei manda no corpo (`{"error": "..."}` e variações).
    static func serverMessage(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let error = object["error"] as? String, !error.isEmpty { return error }
        if let message = object["message"] as? String, !message.isEmpty { return message }
        if let errors = object["errors"] as? [String], let first = errors.first { return first }
        return nil
    }
}
