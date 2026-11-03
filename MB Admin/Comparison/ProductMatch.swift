import Foundation

/// Um par de anúncios — um de cada loja — com o que a comparação concluiu sobre ele e por quê.
nonisolated struct ProductMatch: Identifiable, Equatable, Sendable {
    nonisolated enum Status: Sendable {
        /// A mesma foto, sem nenhum concorrente nem atributo em conflito.
        case strong
        /// Você confirmou "mesmo produto".
        case confirmed
        /// Há um indício (foto parecida, mesma foto em vários anúncios, texto) mas não dá pra
        /// concluir sozinho.
        case needsReview
        /// Você marcou "produtos diferentes".
        case rejected
    }

    let productA: EnjoeiProduct
    let productB: EnjoeiProduct
    let keyA: ListingKey
    let keyB: ListingKey
    let status: Status
    let reasons: [ComparisonReason]
    /// A melhor comparação entre as fotos dos dois (`nil` se nenhuma foto liga os dois).
    let photoEvidence: PhotoPairEvidence?
    /// As fotos que deram essa evidência — o que a revisão mostra lado a lado (as capas, sem ela).
    let photoA: String?
    let photoB: String?
    /// Jaccard das palavras de título + descrição (0 a 1) — medida, não probabilidade.
    let textSimilarity: Double

    var id: String { "\(productA.id)-\(productB.id)" }
    var pairKey: ListingPairKey { ListingPairKey(keyA, keyB) }
    var isMatch: Bool { status == .strong || status == .confirmed }
    var hasUserDecision: Bool { status == .confirmed || status == .rejected }

    /// A foto que a revisão mostra de cada lado.
    var displayPhotoA: String? { photoA ?? productA.photoPublicID }
    var displayPhotoB: String? { photoB ?? productB.photoPublicID }

    /// O estado em poucas palavras, pra linha da lista e o detalhe.
    var statusText: String {
        switch status {
        case .strong: "correspondência forte"
        case .confirmed: "confirmado por você"
        case .needsReview: "precisa revisar"
        case .rejected: "marcado como diferentes"
        }
    }

    /// O motivo principal, em uma frase. Em revisão, a dúvida (tamanhos diferentes, foto em vários
    /// anúncios, variante…) vem antes da evidência ("a mesma foto", "títulos parecidos") — é ela que
    /// explica por que o par não virou correspondência sozinho.
    var summaryText: String? {
        guard status == .needsReview else { return reasons.first?.text }
        let evidence: [ComparisonReason] = [.samePhoto, .samePublicID, .similarText]
        return (reasons.first { !evidence.contains($0) } ?? reasons.first)?.text
    }
}
