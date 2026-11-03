import Foundation

/// Acha, dentro de **uma** loja, o mesmo produto cadastrado mais de uma vez — com as mesmas medidas da
/// comparação entre lojas (`PairAssessor`: foto, título base, descrição, aro/banho/cor/medida, marca,
/// categoria, preço inicial) aplicadas à evidência entre anúncios da própria loja
/// (`StorePairEvidenceBuilder`):
///
/// - **Repetidos**: a mesma fotografia (ou o mesmo arquivo), o mesmo título base, nenhum atributo,
///   marca ou categoria em conflito, preço inicial sem diferença grande, e o template dos dois
///   conferido (o aro pode estar só no campo de tamanho ou na descrição).
/// - **Talvez repetidos**: a mesma foto com alguma dúvida (template não buscado, preço bem diferente,
///   outra foto com outra cor, marca ou categoria diferente). Foto só parecida não entra: num catálogo
///   de joias em fundo branco, peças diferentes da mesma linha têm fotos parecidas e títulos que só
///   mudam no fim.
/// - **Não são repetidos**: a mesma foto em versões (aro 16 × aro 18, ouro × ródio) — essas são
///   família —, ou num anúncio de outro produto (título base diferente).
///
/// Revisões manuais ("são repetidos" / "não são repetidos") valem acima de tudo enquanto os anúncios
/// não mudarem (`ListingFingerprint`), como entre lojas. Os anúncios ligados viram grupos (union-find)
/// — os certos (repetidos e confirmados) separados dos "talvez", pra uma ligação fraca nunca puxar um
/// grupo certo pra dúvida; grupo maior que `MatchIndexParameters.familyMaximumListings` é foto
/// genérica, não produto.
nonisolated enum StoreDuplicateFinder {
    private typealias PairIndex = ComparisonEvidenceBuilder.PairIndex

    nonisolated struct Input: Sendable {
        /// A loja, já sem o texto padrão das descrições (`DescriptionBoilerplate`).
        let side: ComparisonSide
        let pairs: [ListingPairEvidence]
        /// Por anúncio (mesma ordem de `side.listings`): todas as fotos analisadas.
        let photosComplete: [Bool]
        /// Revisões manuais entre anúncios desta loja.
        let decisions: [ComparisonDecision]
    }

    nonisolated struct Output: Sendable {
        /// Repetidos, confirmados e talvez repetidos.
        var groups: [StoreDuplicateGroup] = []
        /// Os que você marcou como não repetidos — pra poder desfazer.
        var dismissed: [StoreDuplicateGroup] = []
        /// Pares (índices na loja) repetidos ou talvez repetidos — não são versões um do outro.
        var linkedPairs: Set<ComparisonEvidenceBuilder.PairIndex> = []
        /// Anúncios de algum grupo sem o template — a etapa 2 da comparação busca, pra conferir.
        var keysWantingDetails: Set<ListingKey> = []
    }

    private struct Link {
        let pair: PairIndex
        let status: StoreDuplicateGroup.Status
        let reasons: [DuplicateReason]
        let index: MatchIndex
        let photo: String?
    }

    static func find(_ input: Input) -> Output {
        let listings = input.side.listings
        guard listings.count >= 2 else { return Output() }
        var evidenceByPair: [PairIndex: ListingPairEvidence] = [:]
        for pair in input.pairs where pair.indexA != pair.indexB {
            evidenceByPair[PairIndex(indexA: min(pair.indexA, pair.indexB), indexB: max(pair.indexA, pair.indexB))] = pair
        }
        let verdicts = verdicts(input.decisions, listings: listings)
        // Revisão manual de um par que perdeu a evidência continua valendo.
        for pair in verdicts.keys where evidenceByPair[pair] == nil {
            evidenceByPair[pair] = ListingPairEvidence(
                indexA: pair.indexA, indexB: pair.indexB,
                textSimilarity: ProductSimilarity.jaccard(listings[pair.indexA].words, listings[pair.indexB].words)
            )
        }

        let links = evidenceByPair
            .sorted { ($0.key.indexA, $0.key.indexB) < ($1.key.indexA, $1.key.indexB) }
            .compactMap { pair, evidence in classify(pair, evidence, verdict: verdicts[pair], input: input) }
        let active = links.filter { $0.status != .dismissed }

        var output = Output()
        let byTitle = { (first: StoreDuplicateGroup, second: StoreDuplicateGroup) in
            first.title.localizedStandardCompare(second.title) == .orderedAscending
        }
        output.groups = groups(active.filter { $0.status != .possible }, input: input).sorted(by: byTitle)
            + groups(active.filter { $0.status == .possible }, input: input).sorted(by: byTitle)
        output.dismissed = groups(links.filter { $0.status == .dismissed }, input: input).sorted(by: byTitle)
        let grouped = Set(output.groups.flatMap(\.keys))
        output.linkedPairs = Set(active.map(\.pair).filter {
            grouped.contains(listings[$0.indexA].key) && grouped.contains(listings[$0.indexB].key)
        })
        output.keysWantingDetails = Set(listings.filter { grouped.contains($0.key) && !$0.hasAllPhotos }.map(\.key))
        return output
    }

    /// As revisões que ainda valem (nenhum dos dois mudou), pelos índices na loja.
    private static func verdicts(_ decisions: [ComparisonDecision], listings: [ComparableListing]) -> [PairIndex: ComparisonDecision.Verdict] {
        let indexByKey = Dictionary(listings.enumerated().map { ($1.key, $0) }, uniquingKeysWith: { first, _ in first })
        var current: [ListingKey: ListingFingerprint] = [:]
        for listing in listings { current[listing.key] = ListingFingerprint(product: listing.product) }
        var verdicts: [PairIndex: ComparisonDecision.Verdict] = [:]
        for decision in decisions where !decision.isStale(current: current) {
            guard let first = indexByKey[decision.first], let second = indexByKey[decision.second], first != second else { continue }
            verdicts[PairIndex(indexA: min(first, second), indexB: max(first, second))] = decision.verdict
        }
        return verdicts
    }

    private static func classify(
        _ pair: PairIndex,
        _ evidence: ListingPairEvidence,
        verdict: ComparisonDecision.Verdict?,
        input: Input
    ) -> Link? {
        let first = input.side.listings[pair.indexA]
        let second = input.side.listings[pair.indexB]
        let assessment = PairAssessor.assess(
            first, second, evidence: evidence,
            photosComplete: input.photosComplete[pair.indexA] && input.photosComplete[pair.indexB]
        )
        let photoReason = photoReason(evidence)
        func link(_ status: StoreDuplicateGroup.Status, _ reasons: [DuplicateReason]) -> Link {
            Link(pair: pair, status: status, reasons: reasons, index: assessment.index, photo: evidence.photoA)
        }
        switch verdict {
        case .differentProducts:
            return link(.dismissed, [.dismissedByUser] + [photoReason].compactMap { $0 })
        case .sameProduct:
            return link(.confirmed, [.confirmedByUser] + [photoReason].compactMap { $0 })
        case nil:
            break
        }

        // Versão (aro, banho, cor, medida diferente) ou outro produto com a mesma foto: não é repetido.
        guard let photoReason, !assessment.isVariant, first.attributes.sharesBaseTitle(with: second.attributes) else { return nil }
        let reasons = [photoReason] + details(first, second, evidence: evidence, assessment: assessment)
        return link(reasons.contains(where: \.isDoubt) ? .possible : .repeated, reasons)
    }

    /// O que mais o par diz além da foto: o mesmo preço, ou as dúvidas que deixam em "talvez".
    private static func details(
        _ first: ComparableListing,
        _ second: ComparableListing,
        evidence: ListingPairEvidence,
        assessment: PairAssessment
    ) -> [DuplicateReason] {
        var reasons: [DuplicateReason] = []
        if assessment.priceRelation == .same, let price = first.attributes.price {
            reasons.append(.samePrice(PriceRelation.format(price)))
        }
        if evidence.hasColorConflict { reasons.append(.colorVariant) }
        if assessment.brandsDiffer { reasons.append(.brandDiffers(assessment.brandA ?? "", assessment.brandB ?? "")) }
        if assessment.categoriesDiffer { reasons.append(.categoryDiffers) }
        if assessment.pricesFarApart, !assessment.textConfirms, let priceA = first.attributes.price, let priceB = second.attributes.price {
            reasons.append(.priceDiffers(PriceRelation.format(priceA), PriceRelation.format(priceB)))
        }
        if !first.hasAllPhotos || !second.hasAllPhotos { reasons.append(.detailsMissing) }
        return reasons
    }

    private static func photoReason(_ evidence: ListingPairEvidence) -> DuplicateReason? {
        guard let photo = evidence.photo else { return nil }
        switch photo.level {
        case .identical, .samePhoto: return photo.isSamePublicID ? .samePublicID : .samePhoto
        case .similar, .different: return nil
        }
    }

    /// Os anúncios ligados, em grupos — cada um com o estado que o par mais fraco permite.
    private static func groups(_ links: [Link], input: Input) -> [StoreDuplicateGroup] {
        let listings = input.side.listings
        var sets = DisjointSet(count: listings.count)
        for link in links { sets.union(link.pair.indexA, link.pair.indexB) }
        var linksByRoot: [Int: [Link]] = [:]
        for link in links { linksByRoot[sets.find(link.pair.indexA), default: []].append(link) }

        return sets.groups().compactMap { members in
            guard members.count <= MatchIndexParameters.familyMaximumListings,
                  let groupLinks = linksByRoot[sets.find(members[0])] else { return nil }
            let status: StoreDuplicateGroup.Status
            if groupLinks.allSatisfy({ $0.status == .dismissed }) {
                status = .dismissed
            } else if groupLinks.contains(where: { $0.status == .possible }) {
                status = .possible
            } else if groupLinks.allSatisfy({ $0.status == .confirmed }) {
                status = .confirmed
            } else {
                status = .repeated
            }
            var reasons: [DuplicateReason] = []
            for reason in groupLinks.flatMap(\.reasons) where !reasons.contains(reason) {
                reasons.append(reason)
            }
            let weakest = groupLinks.min { $0.index.score < $1.index.score }
            return StoreDuplicateGroup(
                sellerID: input.side.sellerID,
                storeName: input.side.name,
                products: members.map { listings[$0].product }.sorted { $0.id < $1.id },
                status: status,
                reasons: reasons,
                index: weakest?.index ?? .empty,
                photoPublicID: groupLinks.lazy.compactMap(\.photo).first ?? listings[members[0]].product.photoPublicID,
                pairKeys: groupLinks.map { ListingPairKey(listings[$0.pair.indexA].key, listings[$0.pair.indexB].key) }
            )
        }
    }
}
