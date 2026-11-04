import Foundation

/// As duas lojas e a evidência entre elas só com os anúncios publicados (`PublishedListingFilter`) —
/// o que o `ComparisonResolver` recebe. A evidência é montada uma vez sobre a listagem inteira (o passo
/// caro: fotos de A × fotos de B) e recortada aqui, renumerando os índices: tirar um anúncio que acabou
/// de ser inativado ou apagado recalcula o resultado na hora, sem montar a evidência de novo.
///
/// Um anúncio que sai leva junto todo par dele (com a outra loja e com a própria loja); o grupo de capas
/// iguais que fica com um só anúncio deixa de ser grupo. As fotos genéricas continuam as mesmas.
nonisolated enum PublishedSubset {
    nonisolated struct Inputs: Sendable {
        let sideA: ComparisonSide
        let sideB: ComparisonSide
        let evidence: ComparisonEvidenceBuilder.Output
    }

    /// - Parameters:
    ///   - unpublishedA: ids dos produtos de A que saem.
    ///   - unpublishedB: os de B.
    static func restrict(
        _ sideA: ComparisonSide,
        _ sideB: ComparisonSide,
        evidence: ComparisonEvidenceBuilder.Output,
        unpublishedA: Set<Int>,
        unpublishedB: Set<Int>
    ) -> Inputs {
        guard !unpublishedA.isEmpty || !unpublishedB.isEmpty else {
            return Inputs(sideA: sideA, sideB: sideB, evidence: evidence)
        }
        let mapA = newIndices(of: sideA, removing: unpublishedA)
        let mapB = newIndices(of: sideB, removing: unpublishedB)

        var output = ComparisonEvidenceBuilder.Output()
        output.genericPhotosA = evidence.genericPhotosA
        output.genericPhotosB = evidence.genericPhotosB
        for pair in evidence.pairs.values {
            guard let indexA = mapA[pair.indexA], let indexB = mapB[pair.indexB] else { continue }
            output.pairs[.init(indexA: indexA, indexB: indexB)] = pair.reindexed(indexA: indexA, indexB: indexB)
        }
        output.coverGroupsA = remap(evidence.coverGroupsA, mapA)
        output.coverGroupsB = remap(evidence.coverGroupsB, mapB)
        output.storePairsA = remap(evidence.storePairsA, mapA)
        output.storePairsB = remap(evidence.storePairsB, mapB)

        return Inputs(sideA: kept(sideA, unpublishedA), sideB: kept(sideB, unpublishedB), evidence: output)
    }

    /// Índice antigo → novo; `nil` pra quem sai. A ordem dos que ficam não muda.
    private static func newIndices(of side: ComparisonSide, removing unpublished: Set<Int>) -> [Int?] {
        var next = 0
        return side.listings.map { listing in
            guard !unpublished.contains(listing.product.id) else { return nil }
            defer { next += 1 }
            return next
        }
    }

    private static func kept(_ side: ComparisonSide, _ unpublished: Set<Int>) -> ComparisonSide {
        ComparisonSide(
            sellerID: side.sellerID,
            name: side.name,
            listings: side.listings.filter { !unpublished.contains($0.product.id) },
            status: side.status
        )
    }

    private static func remap(_ groups: [[Int]], _ map: [Int?]) -> [[Int]] {
        groups.compactMap { group in
            let kept = group.compactMap { map[$0] }
            return kept.count >= 2 ? kept : nil
        }
    }

    /// Pares dentro da mesma loja: os dois anúncios precisam ficar.
    private static func remap(_ pairs: [ListingPairEvidence], _ map: [Int?]) -> [ListingPairEvidence] {
        pairs.compactMap { pair in
            guard let first = map[pair.indexA], let second = map[pair.indexB] else { return nil }
            return pair.reindexed(indexA: first, indexB: second)
        }
    }
}
