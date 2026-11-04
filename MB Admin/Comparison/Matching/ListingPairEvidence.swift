import Foundation

/// Tudo que liga um anúncio de A a um de B, ainda sem decidir nada: a melhor comparação entre as
/// fotos dos dois, quantos anúncios a mesma foto liga, se alguma foto do par é uma variante de cor e
/// o quanto o texto se parece.
nonisolated struct ListingPairEvidence: Sendable {
    let indexA: Int
    let indexB: Int
    private(set) var photo: PhotoPairEvidence?
    private(set) var photoA: String?
    private(set) var photoB: String?
    /// Anúncios (somando as duas lojas) ligados pela mesma fotografia da melhor evidência — 2 num par
    /// simples, mais quando a foto se repete.
    private(set) var linkedListingCount = 2
    /// Alguma foto do par bate como estrutura mas não como cor (variante) — mesmo que outra foto
    /// (uma foto de detalhe, uma embalagem) seja idêntica.
    private(set) var hasColorConflict = false
    var textSimilarity = 0.0

    init(indexA: Int, indexB: Int, textSimilarity: Double = 0) {
        self.indexA = indexA
        self.indexB = indexB
        self.textSimilarity = textSimilarity
    }

    /// A mesma evidência com outros índices — pra quando as listas das lojas perdem anúncios
    /// (`PublishedSubset`).
    func reindexed(indexA: Int, indexB: Int) -> ListingPairEvidence {
        var copy = ListingPairEvidence(indexA: indexA, indexB: indexB, textSimilarity: textSimilarity)
        copy.photo = photo
        copy.photoA = photoA
        copy.photoB = photoB
        copy.linkedListingCount = linkedListingCount
        copy.hasColorConflict = hasColorConflict
        return copy
    }

    mutating func consider(_ evidence: PhotoPairEvidence, photoA: String, photoB: String, linkedListingCount: Int) {
        if evidence.colorsDiffer { hasColorConflict = true }
        guard photo.map({ evidence.isStronger(than: $0) }) ?? true else { return }
        photo = evidence
        self.photoA = photoA
        self.photoB = photoB
        self.linkedListingCount = linkedListingCount
    }
}
