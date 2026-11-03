import Foundation

/// Junta toda a evidência entre os anúncios de duas lojas — sem decidir nada (isso é o
/// `ComparisonResolver`):
///
/// 1. **Mesmo id público** dos dois lados (ex.: anúncio postado por este app na outra loja) liga as
///    fotos na hora, mesmo que o download tenha falhado.
/// 2. **Hash do recorte**: toda foto de A contra toda foto de B por distância de Hamming (barato: um
///    XOR por par), independente da posição e de qualquer palavra em comum. Só quem passa do raio de
///    candidato (`candidateContentHashRadius`) vai pra verificação completa (`PhotoPairComparison`).
/// 3. **Fotos genéricas**: fotografias que ligam muitos anúncios das duas lojas (embalagem, tabela
///    de medidas) deixam de valer como evidência.
/// 4. **Texto**: candidatos por Jaccard (`TextCandidateIndex`), e o Jaccard de todo par que já tem
///    evidência de foto.
nonisolated enum ComparisonEvidenceBuilder {
    private typealias Limits = PhotoMatchingParameters

    nonisolated struct PairIndex: Hashable, Sendable {
        let indexA: Int
        let indexB: Int
    }

    nonisolated struct Output: Sendable {
        var pairs: [PairIndex: ListingPairEvidence] = [:]
        /// Ids públicos tratados como genéricos em cada loja.
        var genericPhotosA: Set<String> = []
        var genericPhotosB: Set<String> = []
    }

    /// Uma foto de um anúncio, achatada pra varrer rápido.
    private struct PhotoNode {
        let listing: Int
        let photo: ListingPhoto
    }

    private struct PhotoLink {
        let nodeA: Int
        let nodeB: Int
        let evidence: PhotoPairEvidence
    }

    static func build(_ listingsA: [ComparableListing], _ listingsB: [ComparableListing]) -> Output {
        let nodesA = listingsA.enumerated().flatMap { index, listing in listing.photos.map { PhotoNode(listing: index, photo: $0) } }
        let nodesB = listingsB.enumerated().flatMap { index, listing in listing.photos.map { PhotoNode(listing: index, photo: $0) } }

        let links = samePublicIDLinks(nodesA, nodesB) + hashLinks(nodesA, nodesB)
        let clusters = PhotoClusters(links: links, nodesA: nodesA, nodesB: nodesB)

        var output = Output()
        output.genericPhotosA = clusters.genericPublicIDs(in: nodesA, side: .storeA)
        output.genericPhotosB = clusters.genericPublicIDs(in: nodesB, side: .storeB)

        for link in links where !clusters.isGeneric(nodeA: link.nodeA, nodeB: link.nodeB) {
            let nodeA = nodesA[link.nodeA]
            let nodeB = nodesB[link.nodeB]
            let key = PairIndex(indexA: nodeA.listing, indexB: nodeB.listing)
            var pair = output.pairs[key] ?? ListingPairEvidence(indexA: nodeA.listing, indexB: nodeB.listing)
            pair.consider(
                link.evidence,
                photoA: nodeA.photo.publicID,
                photoB: nodeB.photo.publicID,
                linkedListingCount: clusters.linkedListingCount(nodeA: link.nodeA)
            )
            output.pairs[key] = pair
        }

        for key in output.pairs.keys {
            output.pairs[key]?.textSimilarity = ProductSimilarity.jaccard(listingsA[key.indexA].words, listingsB[key.indexB].words)
        }
        for candidate in TextCandidateIndex.candidates(wordsA: listingsA.map(\.words), wordsB: listingsB.map(\.words)) {
            let key = PairIndex(indexA: candidate.indexA, indexB: candidate.indexB)
            if output.pairs[key] == nil {
                output.pairs[key] = ListingPairEvidence(indexA: candidate.indexA, indexB: candidate.indexB, textSimilarity: candidate.score)
            }
        }
        return output
    }

    /// Mesmo id público dos dois lados. Foto que foi analisada e é lisa (placeholder) não liga nada.
    private static func samePublicIDLinks(_ nodesA: [PhotoNode], _ nodesB: [PhotoNode]) -> [PhotoLink] {
        var nodesByPublicID: [String: [Int]] = [:]
        for (index, node) in nodesB.enumerated() {
            nodesByPublicID[node.photo.publicID, default: []].append(index)
        }
        var links: [PhotoLink] = []
        for (indexA, nodeA) in nodesA.enumerated() {
            for indexB in nodesByPublicID[nodeA.photo.publicID] ?? [] {
                let analyzedAndPlain = [nodeA.photo, nodesB[indexB].photo].contains { $0.signature?.isInformative == false }
                guard !analyzedAndPlain else { continue }
                links.append(PhotoLink(nodeA: indexA, nodeB: indexB, evidence: .samePublicID))
            }
        }
        return links
    }

    /// Força bruta sobre os hashes (XOR + contagem de bits), depois a verificação completa só nos
    /// candidatos. Ponteiros crus no laço interno: é o único trecho O(fotos de A × fotos de B).
    private static func hashLinks(_ nodesA: [PhotoNode], _ nodesB: [PhotoNode]) -> [PhotoLink] {
        let usableA = nodesA.indices.filter { nodesA[$0].photo.isUsable }
        let usableB = nodesB.indices.filter { nodesB[$0].photo.isUsable }
        let hashesA = usableA.map { nodesA[$0].photo.signature?.contentHash ?? 0 }
        let hashesB = usableB.map { nodesB[$0].photo.signature?.contentHash ?? 0 }
        let radius = Limits.candidateContentHashRadius

        var candidates: [(Int, Int)] = []
        hashesA.withUnsafeBufferPointer { bufferA in
            hashesB.withUnsafeBufferPointer { bufferB in
                for positionA in 0..<bufferA.count {
                    let hashA = bufferA[positionA]
                    for positionB in 0..<bufferB.count where (hashA ^ bufferB[positionB]).nonzeroBitCount <= radius {
                        candidates.append((positionA, positionB))
                    }
                }
            }
        }

        var links: [PhotoLink] = []
        for (positionA, positionB) in candidates {
            let nodeA = usableA[positionA]
            let nodeB = usableB[positionB]
            let photoA = nodesA[nodeA].photo
            let photoB = nodesB[nodeB].photo
            // Já ligadas pelo id — não conta duas vezes.
            guard photoA.publicID != photoB.publicID,
                  let signatureA = photoA.signature, let signatureB = photoB.signature else { continue }
            let evidence = PhotoPairComparison.compare(signatureA, signatureB)
            if evidence.level >= .similar {
                links.append(PhotoLink(nodeA: nodeA, nodeB: nodeB, evidence: evidence))
            }
        }
        return links
    }

    /// Grupos de fotos que são a mesma fotografia (ligações de nível "mesma foto" ou mais), pra saber
    /// quantos anúncios cada fotografia liga.
    private struct PhotoClusters {
        enum Side { case storeA, storeB }

        private var parent: [Int]
        private let countA: Int
        private var listingsPerRoot: [Int: (a: Set<Int>, b: Set<Int>)] = [:]

        init(links: [PhotoLink], nodesA: [PhotoNode], nodesB: [PhotoNode]) {
            countA = nodesA.count
            parent = Array(0..<(nodesA.count + nodesB.count))
            for link in links where link.evidence.level >= .samePhoto {
                union(link.nodeA, countA + link.nodeB)
            }
            for (index, node) in nodesA.enumerated() {
                listingsPerRoot[find(index), default: ([], [])].a.insert(node.listing)
            }
            for (index, node) in nodesB.enumerated() {
                listingsPerRoot[find(countA + index), default: ([], [])].b.insert(node.listing)
            }
        }

        private mutating func find(_ node: Int) -> Int {
            var root = node
            while parent[root] != root { root = parent[root] }
            var current = node
            while parent[current] != root {
                let next = parent[current]
                parent[current] = root
                current = next
            }
            return root
        }

        private func root(of node: Int) -> Int {
            var root = node
            while parent[root] != root { root = parent[root] }
            return root
        }

        private mutating func union(_ first: Int, _ second: Int) {
            let rootFirst = find(first)
            let rootSecond = find(second)
            if rootFirst != rootSecond { parent[rootSecond] = rootFirst }
        }

        private func isGenericRoot(_ root: Int) -> Bool {
            guard let listings = listingsPerRoot[root] else { return false }
            return listings.a.count >= Limits.genericPhotoMinimumListingsPerStore
                && listings.b.count >= Limits.genericPhotoMinimumListingsPerStore
        }

        func isGeneric(nodeA: Int, nodeB: Int) -> Bool {
            isGenericRoot(root(of: nodeA)) || isGenericRoot(root(of: countA + nodeB))
        }

        func linkedListingCount(nodeA: Int) -> Int {
            guard let listings = listingsPerRoot[root(of: nodeA)] else { return 2 }
            return max(2, listings.a.count + listings.b.count)
        }

        func genericPublicIDs(in nodes: [PhotoNode], side: Side) -> Set<String> {
            var result: Set<String> = []
            for (index, node) in nodes.enumerated() {
                let nodeIndex = side == .storeA ? index : countA + index
                if isGenericRoot(root(of: nodeIndex)) { result.insert(node.photo.publicID) }
            }
            return result
        }
    }
}
