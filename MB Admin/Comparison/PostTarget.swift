import Foundation

/// Identifica uma postagem específica: qual produto, pra qual conta de destino — chave de
/// `CrossAccountPoster.statuses`/`postedProductURLs`/`failureDetails`. Só `product.id` não bastava:
/// o mesmo produto postado pra duas contas de destino diferentes (ex.: comparado contra a conta B
/// e, depois, contra a conta C, antes da primeira postagem terminar) colidia na mesma chave — a
/// segunda postagem nunca rodava de verdade, aparecendo como concluída (reaproveitando o
/// `.succeeded` da primeira) sem nunca ter acontecido.
nonisolated struct PostTarget: Hashable, Sendable {
    let productID: Int
    let destinationAccountID: EnjoeiAccountID
}
