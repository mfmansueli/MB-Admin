import Foundation

/// Toda a evidência entre anúncios da **mesma** loja — de onde saem os anúncios repetidos
/// (`StoreDuplicateFinder`). As mesmas medidas da comparação entre lojas (`ComparisonEvidenceBuilder`):
/// o mesmo id público liga na hora; o resto, toda foto (até 5 por anúncio) contra toda foto da loja
/// pelo hash do recorte, com a verificação completa (`PhotoPairComparison`) só nos candidatos. Cada
/// par de anúncios aparece uma vez (`indexA < indexB`), nunca o anúncio com ele mesmo.
///
/// **Só liga uma foto que é a capa de pelo menos um dos dois.** Dentro da mesma loja, as outras fotos
/// (ambiente, modelo, detalhe, embalagem) se repetem entre produtos diferentes — o mesmo fundo, a mesma
/// mão, a mesma caixinha. Um anúncio cadastrado de novo traz as mesmas fotos, e a capa de um aparece no
/// outro mesmo se a ordem mudou. A exceção é a foto que bate na forma e não na cor (qualquer posição):
/// ela não liga, só deixa um par que já tem a mesma capa em "talvez" — pode ser a versão em outro banho.
///
/// **Foto genérica da loja** não liga nada: a mesma fotografia em mais de
/// `MatchIndexParameters.familyMaximumListings` anúncios (banner, "foto ilustrativa"), ou em pelo menos
/// `PhotoMatchingParameters.genericPhotoMinimumListingsPerStore` sem ser a capa da maioria deles
/// (tabela de medidas, embalagem, cartão da loja). Um produto cadastrado quatro vezes continua
/// ligado: a foto repetida é a capa de todos.
nonisolated enum StorePairEvidenceBuilder {
    private typealias Limits = PhotoMatchingParameters

    /// Uma foto de um anúncio, achatada pra varrer rápido.
    private struct PhotoNode {
        let listing: Int
        let photo: ListingPhoto
    }

    private struct PhotoLink {
        let first: Int
        let second: Int
        let evidence: PhotoPairEvidence
    }

    static func build(_ listings: [ComparableListing]) -> [ListingPairEvidence] {
        let nodes = listings.enumerated().flatMap { index, listing in listing.photos.map { PhotoNode(listing: index, photo: $0) } }
        guard nodes.count >= 2 else { return [] }
        var generic = Set<Int>()
        let links = samePublicIDLinks(nodes, generic: &generic) + hashLinks(nodes)
        let clusters = clusters(links: links, nodes: nodes)
        generic.formUnion(clusters.genericNodes)

        var pairs: [ComparisonEvidenceBuilder.PairIndex: ListingPairEvidence] = [:]
        for link in links where !generic.contains(link.first) && !generic.contains(link.second)
            && (link.evidence.colorsDiffer || nodes[link.first].photo.position == 0 || nodes[link.second].photo.position == 0) {
            let one = nodes[link.first]
            let other = nodes[link.second]
            let (low, high) = one.listing < other.listing ? (one, other) : (other, one)
            let key = ComparisonEvidenceBuilder.PairIndex(indexA: low.listing, indexB: high.listing)
            var pair = pairs[key] ?? ListingPairEvidence(indexA: low.listing, indexB: high.listing)
            pair.consider(
                link.evidence,
                photoA: low.photo.publicID,
                photoB: high.photo.publicID,
                linkedListingCount: clusters.listingCount[link.first] ?? 2
            )
            pairs[key] = pair
        }
        for key in pairs.keys {
            pairs[key]?.textSimilarity = ProductSimilarity.jaccard(listings[key.indexA].words, listings[key.indexB].words)
        }
        return pairs.values.sorted { ($0.indexA, $0.indexB) < ($1.indexA, $1.indexB) }
    }

    /// O mesmo id público em anúncios diferentes (o mesmo arquivo reaproveitado). Foto analisada e lisa
    /// (placeholder) não liga nada; um id em anúncios demais já é genérico, sem gerar ligação nenhuma.
    private static func samePublicIDLinks(_ nodes: [PhotoNode], generic: inout Set<Int>) -> [PhotoLink] {
        var nodesByPublicID: [String: [Int]] = [:]
        for (index, node) in nodes.enumerated() where node.photo.signature?.isInformative != false {
            nodesByPublicID[node.photo.publicID, default: []].append(index)
        }
        var links: [PhotoLink] = []
        for group in nodesByPublicID.values where group.count >= 2 {
            guard Set(group.map { nodes[$0].listing }).count <= MatchIndexParameters.familyMaximumListings else {
                generic.formUnion(group)
                continue
            }
            for (position, first) in group.enumerated() {
                for second in group[(position + 1)...] where nodes[first].listing != nodes[second].listing {
                    links.append(PhotoLink(first: first, second: second, evidence: .samePublicID))
                }
            }
        }
        return links
    }

    /// Força bruta sobre os hashes, só a metade de cima da matriz (cada par de fotos uma vez), depois
    /// a verificação completa só nos candidatos de anúncios diferentes — ficam os de "mesma foto" e os de
    /// outra cor.
    private static func hashLinks(_ nodes: [PhotoNode]) -> [PhotoLink] {
        let usable = nodes.indices.filter { nodes[$0].photo.isUsable }
        let hashes = usable.map { nodes[$0].photo.signature?.contentHash ?? 0 }
        let listingOf = usable.map { nodes[$0].listing }
        let radius = Limits.candidateContentHashRadius

        var candidates: [(Int, Int)] = []
        hashes.withUnsafeBufferPointer { buffer in
            listingOf.withUnsafeBufferPointer { listings in
                for first in 0..<buffer.count {
                    let hash = buffer[first]
                    let listing = listings[first]
                    var second = first + 1
                    while second < buffer.count {
                        if listings[second] != listing, (hash ^ buffer[second]).nonzeroBitCount <= radius {
                            candidates.append((first, second))
                        }
                        second += 1
                    }
                }
            }
        }

        var links: [PhotoLink] = []
        for (first, second) in candidates {
            let photoFirst = nodes[usable[first]].photo
            let photoSecond = nodes[usable[second]].photo
            // Já ligadas pelo id — não conta duas vezes.
            guard photoFirst.publicID != photoSecond.publicID,
                  let signatureFirst = photoFirst.signature, let signatureSecond = photoSecond.signature else { continue }
            let evidence = PhotoPairComparison.compare(signatureFirst, signatureSecond)
            // Só a mesma fotografia liga: foto parecida, numa loja de joias em fundo branco, é peça da
            // mesma linha, não o mesmo anúncio cadastrado de novo. A de outra cor fica como conflito.
            if evidence.level >= .samePhoto || evidence.colorsDiffer {
                links.append(PhotoLink(first: usable[first], second: usable[second], evidence: evidence))
            }
        }
        return links
    }

    private struct Clusters {
        /// Fotos (nós) de fotografias genéricas da loja.
        var genericNodes: Set<Int> = []
        /// Quantos anúncios a fotografia de cada nó liga (só os nós em alguma ligação de "mesma foto").
        var listingCount: [Int: Int] = [:]
    }

    /// Agrupa as fotos que são a mesma fotografia e diz quais grupos são genéricos.
    private static func clusters(links: [PhotoLink], nodes: [PhotoNode]) -> Clusters {
        var sets = DisjointSet(count: nodes.count)
        for link in links where link.evidence.level >= .samePhoto {
            sets.union(link.first, link.second)
        }
        var output = Clusters()
        for group in sets.groups() {
            let listings = Set(group.map { nodes[$0].listing })
            let covers = Set(group.filter { nodes[$0].photo.position == 0 }.map { nodes[$0].listing })
            let isGeneric = listings.count > MatchIndexParameters.familyMaximumListings
                || (listings.count >= Limits.genericPhotoMinimumListingsPerStore && covers.count * 2 < listings.count)
            for node in group {
                output.listingCount[node] = listings.count
                if isGeneric { output.genericNodes.insert(node) }
            }
        }
        return output
    }
}
