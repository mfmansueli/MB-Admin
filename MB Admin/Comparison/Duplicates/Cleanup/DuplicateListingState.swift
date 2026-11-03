import Foundation

/// Onde um anúncio de um grupo de repetidos está no caminho de ser apagado — o que a linha mostra e
/// o que decide se ele ainda pode ser o anúncio que fica (`DuplicateCleanup`). Vem da fila de ações
/// (`PostQueue.items`, o histórico dela) e do andamento da própria conta
/// (`MegaphoneRunner.deleteStatuses`) — ver `DuplicateListingStateReader`.
nonisolated enum DuplicateListingState: Equatable, Sendable {
    /// Continua na loja, sem nada pedido.
    case listed
    /// Esperando a vez na fila de ações.
    case queued
    case deleting
    case deleted
    /// A exclusão falhou e o item continua na fila (pra tentar de novo ou tirar de lá).
    case failed(String)

    var isListed: Bool { self == .listed }

    /// O que a linha do anúncio mostra — `nil` pra quem continua na loja.
    var text: String? {
        switch self {
        case .listed: nil
        case .queued: "na fila pra apagar"
        case .deleting: "apagando…"
        case .deleted: "apagado"
        case .failed: "não deu pra apagar — veja na fila de ações"
        }
    }

    /// - Parameters:
    ///   - runnerStatus: o andamento de apagar este produto na conta (`MegaphoneRunner.deleteStatuses`).
    ///   - isQueued: há um item de apagar este produto em `PostQueue.items`.
    ///   - wasDeleted: o histórico da fila tem este produto apagado com sucesso — sobrevive a fechar o
    ///     app, ao contrário de `runnerStatus`.
    static func make(runnerStatus: MegaphoneStatus?, isQueued: Bool, wasDeleted: Bool) -> DuplicateListingState {
        if runnerStatus == .succeeded || wasDeleted { return .deleted }
        if runnerStatus == .megaphoning { return .deleting }
        guard isQueued else { return .listed }
        if let message = runnerStatus?.failureMessage { return .failed(message) }
        return .queued
    }
}
