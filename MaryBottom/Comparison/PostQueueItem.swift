import Foundation

/// Um produto esperando (ou já processado) na fila de ações entre contas. Guarda o nome das
/// contas, não só o id — se uma delas for deslogada enquanto o item ainda está na fila, a tela
/// continua mostrando "de X para Y" certo mesmo sem achar mais a `AccountSession` de verdade.
nonisolated struct PostQueueItem: Identifiable, Equatable, Sendable, Codable, AccountActionDescribing {
    /// O que fazer com o produto — postar (numa conta diferente, ou repostar na mesma), apagar,
    /// inativar ou ativar. Pra `.delete`/`.inactivate`/`.activate`, origem e destino são sempre a
    /// mesma conta (não existe "destino" de verdade).
    enum Kind: Equatable, Hashable, Sendable, Codable, CaseIterable {
        case post
        case delete
        case inactivate
        case activate
    }

    let id: UUID
    let product: EnjoeiProduct
    var kind: Kind = .post
    let sourceAccountID: EnjoeiAccountID
    let sourceAccountName: String
    let destinationAccountID: EnjoeiAccountID
    let destinationAccountName: String

    /// Chave de `CrossAccountPoster.statuses`/`postedProductURLs`/`failureDetails` pra esse item —
    /// só faz sentido pra `.kind == .post` (as outras três ações vivem nos dicionários do
    /// `MegaphoneRunner` da própria conta, chaveados só por produto, já que origem e destino são
    /// sempre a mesma conta ali).
    var postTarget: PostTarget {
        PostTarget(productID: product.id, destinationAccountID: destinationAccountID)
    }
}
