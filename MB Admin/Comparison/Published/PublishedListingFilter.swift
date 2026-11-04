import Foundation

/// A regra de "o que está no ar": a comparação entre duas lojas (pares, revisões, possivelmente
/// ausentes, não verificados, versões, repetidos) e o aviso de "postar em outra loja" só olham os
/// anúncios **publicados** de cada loja. Inativo, apagado ou fora da vitrine por qualquer motivo não
/// conta pra nada — nem como par, nem como prova de que o produto existe na outra loja. Por isso um
/// produto cujo único par na outra loja foi inativado passa a ser "possivelmente ausente" lá.
///
/// Publicado = veio na listagem da loja (a vitrine, `searchProductsForStore`) e o app não viu ele sair
/// de lá depois (`ListingStateChange`):
/// - **Apagado** nunca volta, não importa quando.
/// - **Inativo** vale quando aconteceu depois da listagem — ou até `searchLagGrace` antes dela, pra
///   cobrir a busca da loja demorando pra tirar da vitrine um produto recém-inativado. Mais antigo que
///   isso, a listagem é a informação mais nova (ele foi ativado de novo por fora do app).
/// - **Ativado** depois de inativo: volta a valer o que a listagem diz.
///
/// Vale sempre a mudança mais recente de cada anúncio.
nonisolated enum PublishedListingFilter {
    /// Quanto antes da listagem uma inativação ainda ganha dela. Não medido: a busca do Enjoei é um
    /// índice à parte, e não se sabe quanto ela demora pra refletir uma inativação. O custo de errar
    /// pra mais é pequeno — só esconderia um produto inativado pelo app e reativado por fora nessa
    /// mesma janela.
    static let searchLagGrace: TimeInterval = 30 * 60

    /// Dos anúncios que vieram na listagem (`listedIDs`, buscada em `listedAt`), os que não estão mais
    /// publicados.
    static func unpublished(listedIDs: [Int], listedAt: Date, changes: [ListingStateChange]) -> Set<Int> {
        guard !changes.isEmpty else { return [] }
        var latest: [Int: ListingStateChange] = [:]
        var deleted: Set<Int> = []
        for change in changes {
            if change.state == .deleted { deleted.insert(change.productID) }
            if let current = latest[change.productID], current.date > change.date { continue }
            latest[change.productID] = change
        }
        let inactiveSince = listedAt.addingTimeInterval(-searchLagGrace)
        return Set(listedIDs.filter { id in
            if deleted.contains(id) { return true }
            guard let change = latest[id] else { return false }
            switch change.state {
            case .deleted: return true
            case .inactive: return change.date >= inactiveSince
            case .published: return false
            }
        })
    }
}
