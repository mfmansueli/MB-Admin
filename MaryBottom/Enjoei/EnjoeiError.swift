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
    /// A persisted query da listagem de produtos (`EnjoeiAPI.searchQueryID`) não é mais
    /// reconhecida pelo servidor — o Enjoei provavelmente publicou uma versão nova do site.
    /// Detectado em `EnjoeiError.isStalePersistedQuery(in:)`, a partir do corpo GraphQL da
    /// resposta, pra não aparecer pro usuário como um genérico "resposta que não entendi".
    case stalePersistedQuery

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
        case .stalePersistedQuery:
            "o enjoei atualizou o site e a busca de produtos parou de funcionar. "
                + "recapture o query_id na aba network do site e atualize EnjoeiAPI.searchQueryID."
        }
    }

    /// Descrição técnica (o `case` e os valores associados) — para diagnóstico, diferente de
    /// `errorDescription` (voltado pro usuário final, que esconde esse tipo de detalhe de
    /// propósito). Usada em `MegaphoneFailureDetail`, pro sheet de detalhe de erro poder mostrar
    /// mais do que a mensagem curta que já aparece embaixo do produto.
    var diagnosticDescription: String {
        switch self {
        case .notAuthenticated:
            "EnjoeiError.notAuthenticated"
        case .notIdentified(let detail):
            "EnjoeiError.notIdentified(detail: \"\(detail)\")"
        case .invalidCSRFToken:
            "EnjoeiError.invalidCSRFToken"
        case .http(let status, let message):
            "EnjoeiError.http(status: \(status), message: \(message.map { "\"\($0)\"" } ?? "nil"))"
        case .unexpectedResponse:
            "EnjoeiError.unexpectedResponse"
        case .stalePersistedQuery:
            "EnjoeiError.stalePersistedQuery"
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

    /// O corpo é um erro GraphQL de persisted query desconhecida (`{"errors":[{"message":
    /// "PersistedQueryNotFound"}]}` e variações)? A API de busca do Enjoei responde 200 mesmo
    /// nesse caso — não dá pra detectar pelo status HTTP, só olhando o corpo.
    static func isStalePersistedQuery(in data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        guard let errors = object["errors"] as? [[String: Any]] else { return false }
        return errors.contains { entry in
            guard let message = entry["message"] as? String else { return false }
            // Sem espaço: o erro padrão do protocolo de persisted queries da Apollo é
            // "PersistedQueryNotFound", uma palavra só em camelCase.
            let normalized = message.lowercased().replacingOccurrences(of: " ", with: "")
            return normalized.contains("persistedquery")
        }
    }
}
