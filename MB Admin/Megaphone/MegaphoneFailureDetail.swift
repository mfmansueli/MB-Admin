import Foundation

/// Diagnóstico completo de uma ação que falhou — mais informação do que a mensagem curta que
/// aparece embaixo do produto (`MegaphoneStatus.failureMessage`), pra ajudar a entender o que
/// aconteceu de verdade quando o problema precisar ser revisitado depois. `Codable` porque
/// `PostHistoryEntry` guarda isso pra sempre (ver `PostHistoryEntry.failureDetail`); os outros usos
/// (fila e megafone ao vivo, em `MegaphoneRunner.failureDetails`/`CrossAccountPoster.failureDetails`)
/// só vivem em memória, e somem quando o app fecha.
nonisolated struct MegaphoneFailureDetail: Equatable, Sendable, Codable {
    /// Qual ação falhou — mais granular que `PostQueueItem.Kind`: cobre também `megaphone` (o
    /// boost em si, fora da fila) e `applyDiscount` (aplicar o desconto sugerido manualmente).
    enum Action: String, Sendable, Codable {
        case megaphone
        case applyDiscount
        case post
        case delete
        case inactivate
        case activate

        var label: String {
            switch self {
            case .megaphone: "megafonar"
            case .applyDiscount: "aplicar desconto"
            case .post: "postar"
            case .delete: "apagar"
            case .inactivate: "inativar"
            case .activate: "ativar"
            }
        }

        init(kind: PostQueueItem.Kind) {
            switch kind {
            case .post: self = .post
            case .delete: self = .delete
            case .inactivate: self = .inactivate
            case .activate: self = .activate
            }
        }
    }

    let action: Action
    let occurredAt: Date
    /// Descrição técnica do erro de verdade — tipo e valores associados quando é um `EnjoeiError`
    /// reconhecido (ver `EnjoeiError.diagnosticDescription`), senão a descrição bruta do `Error`
    /// (ex.: erro de decodificação, `URLError`). Sempre presente, ao contrário de `httpStatus`/
    /// `serverMessage` — nem todo erro tem os dois.
    let technicalDescription: String
    let httpStatus: Int?
    let serverMessage: String?

    /// Monta a partir do `Error` de verdade capturado no `catch` — ponto único que sabe extrair
    /// o que dá pra extrair de um `EnjoeiError` (status HTTP, mensagem do servidor) e cai pra
    /// descrição genérica pra qualquer outro tipo de erro.
    init(action: Action, error: Error, occurredAt: Date = .now) {
        self.action = action
        self.occurredAt = occurredAt
        if let enjoeiError = error as? EnjoeiError {
            technicalDescription = enjoeiError.diagnosticDescription
            if case .http(let status, let message) = enjoeiError {
                httpStatus = status
                serverMessage = message
            } else {
                httpStatus = nil
                serverMessage = nil
            }
        } else {
            technicalDescription = String(describing: error)
            httpStatus = nil
            serverMessage = nil
        }
    }

    /// Pra falhas sintéticas, sem `Error` nenhum por trás (ex.: "conta não está mais logada" — a
    /// fila decide isso sozinha, sem chamar rede nenhuma) — `technicalDescription` repete a
    /// mensagem, já que não existe nada mais técnico por trás dela.
    init(action: Action, syntheticMessage: String, occurredAt: Date = .now) {
        self.action = action
        self.occurredAt = occurredAt
        technicalDescription = syntheticMessage
        httpStatus = nil
        serverMessage = nil
    }

    /// Texto único, pronto pra compartilhar/copiar — reúne tudo que o sheet mostra separado, num
    /// formato simples de colar num bug report.
    var shareText: String {
        var lines = [
            "ação: \(action.label)",
            "quando: \(occurredAt.formatted(date: .abbreviated, time: .standard))",
            "descrição técnica: \(technicalDescription)"
        ]
        if let httpStatus { lines.append("status HTTP: \(httpStatus)") }
        if let serverMessage { lines.append("resposta do servidor: \(serverMessage)") }
        return lines.joined(separator: "\n")
    }
}
