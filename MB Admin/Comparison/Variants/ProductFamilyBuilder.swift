import Foundation

/// Agrupa anúncios que dividem a mesma foto — entre as duas lojas (qualquer das 5 fotos) e dentro de
/// cada loja (a mesma capa) — em famílias de versões, e diz, versão por versão, onde cada uma está:
/// nas duas lojas, só numa, pra revisar ou não verificada. Só entra família que tem versões de
/// verdade: 3 anúncios ou mais, 2 na mesma loja, ou um par em que os atributos discordam (aro 16 numa
/// loja, aro 18 na outra). Um par 1:1 comum não é família. A mesma foto em anúncios de títulos que
/// não têm nada a ver (`ListingAttributes.sharesBaseTitle`) não junta os dois.
nonisolated enum ProductFamilyBuilder {
    nonisolated struct Link: Hashable, Sendable {
        let indexA: Int
        let indexB: Int
    }

    nonisolated struct Input: Sendable {
        let listingsA: [ComparableListing]
        let listingsB: [ComparableListing]
        /// Pares com a mesma foto (ou a mesma pose em outra cor) entre as lojas, com o título base
        /// parecido — inclusive os que são outra versão.
        let photoLinks: [Link]
        let coverGroupsA: [[Int]]
        let coverGroupsB: [[Int]]
        /// Pares fortes ou confirmados.
        let matches: [Link]
        let reviewA: Set<Int>
        let reviewB: Set<Int>
        let unverifiedA: Set<Int>
        let unverifiedB: Set<Int>
        /// Pares em que os atributos descrevem versões diferentes.
        let versionLinks: [Link]
    }

    nonisolated struct Output: Sendable {
        var families: [ProductFamily] = []
        /// Os anúncios de alguma família — o template deles vale buscar mesmo já tendo par, pra
        /// conferir que a versão bate (ver `AccountComparisonLoader`).
        var memberKeys: Set<ListingKey> = []
    }

    static func build(_ input: Input) -> Output {
        let countA = input.listingsA.count
        var groups = DisjointSet(count: countA + input.listingsB.count)
        for link in input.photoLinks {
            groups.union(link.indexA, countA + link.indexB)
        }
        for group in input.coverGroupsA {
            unionRelated(group, of: input.listingsA, offset: 0, into: &groups)
        }
        for group in input.coverGroupsB {
            unionRelated(group, of: input.listingsB, offset: countA, into: &groups)
        }

        let versionLinkedA = Set(input.versionLinks.map(\.indexA))
        let versionLinkedB = Set(input.versionLinks.map(\.indexB))
        var output = Output()
        for group in groups.groups() {
            let membersA = group.filter { $0 < countA }
            let membersB = group.filter { $0 >= countA }.map { $0 - countA }
            let limit = MatchIndexParameters.familyMaximumListings
            guard membersA.count <= limit, membersB.count <= limit else { continue }
            let hasVersionLink = membersA.contains(where: versionLinkedA.contains) || membersB.contains(where: versionLinkedB.contains)
            guard group.count >= 3 || membersA.count >= 2 || membersB.count >= 2 || hasVersionLink else { continue }
            output.families.append(family(membersA: membersA, membersB: membersB, input: input))
            output.memberKeys.formUnion(membersA.map { input.listingsA[$0].key })
            output.memberKeys.formUnion(membersB.map { input.listingsB[$0].key })
        }
        output.families.sort {
            if $0.hasMissingVersions != $1.hasMissingVersions { return $0.hasMissingVersions }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        return output
    }

    /// Dentro de um grupo de capas iguais da mesma loja, junta só quem tem o título base parecido.
    private static func unionRelated(_ group: [Int], of listings: [ComparableListing], offset: Int, into groups: inout DisjointSet) {
        for (position, first) in group.enumerated() {
            for second in group[(position + 1)...] where listings[first].attributes.sharesBaseTitle(with: listings[second].attributes) {
                groups.union(offset + first, offset + second)
            }
        }
    }

    private static func family(membersA: [Int], membersB: [Int], input: Input) -> ProductFamily {
        let listings = membersA.map { input.listingsA[$0] } + membersB.map { input.listingsB[$0] }
        let dimensions = VariantDimension.allCases.filter { dimension in
            Set(listings.compactMap { $0.attributes.reading(dimension)?.decisiveValue?.canonical }).count >= 2
        }
        let pricesVary = Set(listings.compactMap(\.attributes.price)).count >= 2
        func label(_ listing: ComparableListing) -> String {
            if !dimensions.isEmpty { return listing.attributes.label(for: dimensions) }
            if pricesVary, let price = listing.attributes.price { return "preço inicial \(PriceRelation.format(price))" }
            return ""
        }

        let rows = versions(membersA: membersA, membersB: membersB, input: input, label: label)
        let first = listings[0]
        let side = membersA.isEmpty ? "B" : "A"
        return ProductFamily(
            id: "familia-\(side)\(first.product.id)",
            title: first.product.title,
            photoPublicID: first.product.photoPublicID,
            dimensions: dimensions,
            versions: rows
        )
    }

    private static func versions(
        membersA: [Int],
        membersB: [Int],
        input: Input,
        label: (ComparableListing) -> String
    ) -> [ProductFamilyVersion] {
        var matchOfA: [Int: Int] = [:]
        var matchOfB: [Int: Int] = [:]
        for match in input.matches {
            if matchOfA[match.indexA] == nil { matchOfA[match.indexA] = match.indexB }
            if matchOfB[match.indexB] == nil { matchOfB[match.indexB] = match.indexA }
        }
        func pair(_ indexA: Int, _ indexB: Int) -> ProductFamilyVersion {
            let listingA = input.listingsA[indexA]
            let listingB = input.listingsB[indexB]
            let text = bestLabel(label(listingA), label(listingB))
            return ProductFamilyVersion(label: text, productA: listingA.product, productB: listingB.product, presence: .both)
        }

        var versions: [ProductFamilyVersion] = []
        var placedB = Set<Int>()
        for indexA in membersA {
            if let indexB = matchOfA[indexA] {
                placedB.insert(indexB)
                versions.append(pair(indexA, indexB))
            } else {
                let presence: ProductFamilyVersion.Presence = input.reviewA.contains(indexA) ? .needsReview
                    : input.unverifiedA.contains(indexA) ? .unverified : .onlyInA
                let listing = input.listingsA[indexA]
                versions.append(.init(label: label(listing), productA: listing.product, productB: nil, presence: presence))
            }
        }
        for indexB in membersB where !placedB.contains(indexB) {
            if let indexA = matchOfB[indexB] {
                versions.append(pair(indexA, indexB))
            } else {
                let presence: ProductFamilyVersion.Presence = input.reviewB.contains(indexB) ? .needsReview
                    : input.unverifiedB.contains(indexB) ? .unverified : .onlyInB
                let listing = input.listingsB[indexB]
                versions.append(.init(label: label(listing), productA: nil, productB: listing.product, presence: presence))
            }
        }
        return versions.sorted {
            let order = $0.label.localizedStandardCompare($1.label)
            if order != .orderedSame { return order == .orderedAscending }
            return $0.presence < $1.presence
        }
    }

    /// Num par, o rótulo de quem diz mais (menos eixos "não informado").
    private static func bestLabel(_ labelA: String, _ labelB: String) -> String {
        let missing = { (label: String) in label.components(separatedBy: "não informado").count }
        return missing(labelB) < missing(labelA) ? labelB : labelA
    }
}
