import Foundation

/// Um produto esperando (ou já processado) na fila de publicação entre duas contas. Guarda o nome
/// das contas, não só o id — se uma delas for deslogada enquanto o item ainda está na fila, a tela
/// continua mostrando "de X para Y" certo mesmo sem achar mais a `AccountSession` de verdade.
nonisolated struct PostQueueItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let product: EnjoeiProduct
    let sourceAccountID: EnjoeiAccountID
    let sourceAccountName: String
    let destinationAccountID: EnjoeiAccountID
    let destinationAccountName: String
}
