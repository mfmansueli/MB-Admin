import Foundation

/// Lê, uma vez por render da lista, o que a fila de ações sabe sobre apagar anúncios — os itens de
/// apagar na fila e os apagados com sucesso no histórico — e monta o `DuplicateListingState` de cada
/// anúncio dos grupos de repetidos. Sem grupo nenhum, nem encosta na fila (a lista não passa a
/// observar a fila à toa).
@MainActor
struct DuplicateListingStateReader {
    private struct Key: Hashable {
        let accountID: EnjoeiAccountID
        let productID: Int
    }

    private let queue: PostQueue
    private var queued: Set<Key>?
    private var deleted: Set<Key>?

    init(queue: PostQueue) {
        self.queue = queue
    }

    /// O estado de cada anúncio desses grupos, todos da loja de `account`, pelo id do anúncio.
    mutating func states(of groups: [StoreDuplicateGroup], account: AccountSession) -> [Int: DuplicateListingState] {
        guard !groups.isEmpty else { return [:] }
        let queued = queued ?? Set(queue.items.filter { $0.kind == .delete }.map { Key(accountID: $0.sourceAccountID, productID: $0.product.id) })
        let deleted = deleted ?? Set(
            queue.history
                .filter { $0.kind == .delete && $0.outcome == .succeeded }
                .map { Key(accountID: $0.sourceAccountID, productID: $0.product.id) }
        )
        self.queued = queued
        self.deleted = deleted
        let runnerStatuses = account.runner.deleteStatuses
        var states: [Int: DuplicateListingState] = [:]
        for product in groups.lazy.flatMap(\.products) {
            let key = Key(accountID: account.id, productID: product.id)
            states[product.id] = DuplicateListingState.make(
                runnerStatus: runnerStatuses[product.id],
                isQueued: queued.contains(key),
                wasDeleted: deleted.contains(key)
            )
        }
        return states
    }
}
