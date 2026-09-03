import Foundation

/// Um item que passou pela fila de ações e já terminou (com sucesso ou erro) — continua salvo
/// mesmo depois que o item some de `PostQueue.items` (removido da fila, fila limpa, ou o app
/// fechado e aberto de novo), diferente de `PostQueueItem`, que só existe enquanto a ação está
/// pendente ou em andamento na fila ativa.
nonisolated struct PostHistoryEntry: Identifiable, Equatable, Sendable, Codable, AccountActionDescribing {
    enum Outcome: Equatable, Sendable {
        case succeeded
        case failed(String)
    }

    let id: UUID
    let product: EnjoeiProduct
    let kind: PostQueueItem.Kind
    let sourceAccountID: EnjoeiAccountID
    let sourceAccountName: String
    let destinationAccountID: EnjoeiAccountID
    let destinationAccountName: String
    let outcome: Outcome
    let completedAt: Date
    /// Diagnóstico completo, quando `outcome` é `.failed` — `nil` pra `.succeeded`, e também `nil`
    /// em qualquer entrada gravada antes dessa propriedade existir (decodifica como `nil` de
    /// propósito, pra não quebrar leitura de histórico já persistido). Ver `MegaphoneFailureDetail`.
    let failureDetail: MegaphoneFailureDetail?

    init(
        id: UUID,
        product: EnjoeiProduct,
        kind: PostQueueItem.Kind,
        sourceAccountID: EnjoeiAccountID,
        sourceAccountName: String,
        destinationAccountID: EnjoeiAccountID,
        destinationAccountName: String,
        outcome: Outcome,
        completedAt: Date,
        failureDetail: MegaphoneFailureDetail? = nil
    ) {
        self.id = id
        self.product = product
        self.kind = kind
        self.sourceAccountID = sourceAccountID
        self.sourceAccountName = sourceAccountName
        self.destinationAccountID = destinationAccountID
        self.destinationAccountName = destinationAccountName
        self.outcome = outcome
        self.completedAt = completedAt
        self.failureDetail = failureDetail
    }
}

extension PostHistoryEntry.Outcome {
    /// `nil` pra `.pending`/`.megaphoning` — um item só vira entrada de histórico depois que a
    /// chamada de rede de verdade termina, nunca enquanto ainda está em voo.
    init?(status: MegaphoneStatus) {
        switch status {
        case .succeeded: self = .succeeded
        case .failed(let message): self = .failed(message)
        case .pending, .megaphoning: return nil
        }
    }
}

/// Manual porque a associated value de `.failed` impede a síntese automática — mesmo padrão de
/// `MegaphoneStatus.Codable`.
nonisolated extension PostHistoryEntry.Outcome: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "succeeded": self = .succeeded
        case "failed": self = .failed(try container.decode(String.self, forKey: .message))
        default: self = .succeeded
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .succeeded: try container.encode("succeeded", forKey: .kind)
        case .failed(let message):
            try container.encode("failed", forKey: .kind)
            try container.encode(message, forKey: .message)
        }
    }
}
