import Foundation

/// Algo que o app viu acontecer com um anúncio depois (ou antes) da listagem da loja: saiu de
/// "publicados" (inativado, apagado) ou voltou pra lá. É o que `PublishedListingFilter` usa pra tirar
/// da comparação o que não está mais no ar — a listagem (`searchProductsForStore`) é a vitrine no
/// momento em que foi buscada, e o resultado (na tela ou salvo em disco) continua valendo depois.
///
/// De onde vem:
/// - **Fila de ações** (`PostQueue.history`, só os que deram certo): apagar, inativar e ativar —
///   com a hora em que terminou, e sobrevive a fechar o app.
/// - **Aba inativos** (`InactiveProductsLoader`): todo produto da lista carregada nesta sessão estava
///   inativo na hora em que ela foi buscada. A lista restaurada do disco (sem hora) não conta.
nonisolated struct ListingStateChange: Equatable, Sendable {
    enum State: Equatable, Sendable {
        /// Voltou pra vitrine (ativado).
        case published
        /// Fora da vitrine, mas ainda existe (dá pra ativar de novo no Enjoei).
        case inactive
        /// Apagado de vez — nunca mais volta pra vitrine com o mesmo id.
        case deleted
    }

    let productID: Int
    let state: State
    let date: Date

    /// A ação da fila que tirou (ou devolveu) o anúncio da vitrine — `nil` pra postar (que cria
    /// outro anúncio, não muda este) e pra qualquer ação que falhou.
    init?(entry: PostHistoryEntry) {
        guard entry.outcome == .succeeded else { return nil }
        switch entry.kind {
        case .post: return nil
        case .delete: state = .deleted
        case .inactivate: state = .inactive
        case .activate: state = .published
        }
        productID = entry.product.id
        date = entry.completedAt
    }

    init(productID: Int, state: State, date: Date) {
        self.productID = productID
        self.state = state
        self.date = date
    }

    /// O que a fila de ações fez com os anúncios da conta.
    static func history(_ entries: [PostHistoryEntry], accountID: EnjoeiAccountID) -> [ListingStateChange] {
        entries.lazy
            .filter { $0.sourceAccountID == accountID }
            .compactMap(ListingStateChange.init(entry:))
    }

    /// Os produtos da aba inativos, como estavam quando a lista foi buscada.
    static func inactiveList(_ productIDs: [Int], loadedAt: Date) -> [ListingStateChange] {
        productIDs.map { ListingStateChange(productID: $0, state: .inactive, date: loadedAt) }
    }

    /// Tudo que o app sabe da conta agora: a fila de ações e a aba inativos carregada nesta sessão.
    @MainActor
    static func known(for account: AccountSession, history entries: [PostHistoryEntry]) -> [ListingStateChange] {
        var changes = history(entries, accountID: account.id)
        let inactive = account.inactiveProductsLoader
        if let loadedAt = inactive.loadedAt {
            changes += inactiveList(inactive.items.map(\.id), loadedAt: loadedAt)
        }
        return changes
    }
}
