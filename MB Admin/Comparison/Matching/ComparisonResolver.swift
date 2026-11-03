import Foundation

/// Transforma a evidência (`ComparisonEvidenceBuilder`) + as revisões manuais num
/// `AccountComparisonResult`. Sem ordem gulosa: cada par é classificado pelo **tipo** de evidência,
/// pelos atributos de variante (aro, banho, cor, medida — `PairAssessor`) e pelos concorrentes que os
/// dois anúncios têm. O índice de correspondência (`MatchIndex`) acompanha todo par pra explicar, e só
/// decide uma coisa: qual versão é qual quando várias dividem a mesma foto.
///
/// - **Outra versão** (não é estado de par): a mesma foto (ou a mesma pose em outra cor), mas algum
///   atributo decisivo em conflito — aro 16 × aro 18, ouro × ródio. Nunca vira par nem revisão; cada
///   lado segue pra ausência com a nota de qual versão a outra loja tem (`otherVersions`).
/// - **Correspondência forte**: a mesma fotografia (ou o mesmo arquivo), sem conflito, e nenhum dos
///   dois tem outro par com a mesma foto — ou tem, mas o índice deste passa o de todo concorrente por
///   `MatchIndexParameters.versionResolutionMargin` (os atributos/preço apontam só este). Também sem
///   foto quase tão parecida com outro, sem variante de cor, categoria/marca em conflito, nem preço
///   inicial bem diferente sem o texto confirmar. Dado faltando não é conflito.
/// - **Precisa revisar**: mesma foto com concorrente empatado ou alguma dúvida; foto parecida; texto
///   parecido (só quando as fotos não estão todas analisadas, ou o texto é quase idêntico). Nunca
///   vira par sozinho, e duplicatas numa loja não são forçadas a 1:1.
/// - **Possivelmente ausente**: nenhuma ligação (fora "outra versão"), todas as fotos do anúncio
///   analisadas, a lista da outra loja completa, e nenhum anúncio não verificado de lá com título
///   parecido.
/// - **Não foi possível verificar**: nenhuma ligação, mas falta alguma dessas condições.
///
/// Revisões manuais valem acima de tudo enquanto os anúncios não mudarem (`ListingFingerprint`):
/// "mesmo produto" vira par confirmado (mesmo com atributo em conflito); "produtos diferentes"
/// remove a ligação. E ensinam (`ReviewLearning`): com exemplos suficientes das duas respostas, um
/// par em revisão com índice claramente do lado de "mesmo produto" (só um candidato de cada lado)
/// vira par, e um claramente do lado de "diferentes" sai da revisão — os dois com o motivo dizendo
/// que veio das suas revisões. Cada decisão recalcula tudo, então uma revisão mexe nas outras listas
/// na hora.
///
/// Por cima disso, cada loja é comparada com ela mesma (`StoreDuplicateFinder`): o mesmo produto
/// cadastrado mais de uma vez na mesma loja. Repetidos não são versões um do outro, então não formam
/// família entre eles. As revisões manuais entre dois anúncios da mesma loja valem só pra isso. Um
/// anúncio repetido (grupo certo) de um que já tem par na outra loja não fica em revisão com esse par
/// nem vira "possivelmente ausente": é o mesmo produto, cadastrado de novo.
nonisolated enum ComparisonResolver {
    static func resolve(
        _ sideA: ComparisonSide,
        _ sideB: ComparisonSide,
        evidence: ComparisonEvidenceBuilder.Output,
        decisions: [ComparisonDecision],
        runID: UUID = UUID(),
        revision: Int = 0
    ) -> AccountComparisonResult {
        var run = Run(sideA: sideA, sideB: sideB, evidence: evidence)
        run.applyDecisions(decisions.filter { $0.first.sellerID != $0.second.sellerID })
        run.findDuplicates(decisions.filter { $0.first.sellerID == $0.second.sellerID })
        run.classifyEdges()
        return run.result(runID: runID, revision: revision)
    }

    private enum EdgeKind: Int, Comparable {
        case text = 0
        case similar = 1
        case strong = 2

        static func < (lhs: EdgeKind, rhs: EdgeKind) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private struct Edge {
        var evidence: ListingPairEvidence
        var kind: EdgeKind
        var assessment: PairAssessment
        var verdict: ComparisonDecision.Verdict?
        var isStaleDecision = false
        var status: ProductMatch.Status = .needsReview
        var reasons: [ComparisonReason] = []
        var isDropped = false
        /// Mesma foto (ou mesma pose em outra cor) com atributo em conflito: outra versão do produto.
        var isVersionLink = false

        var indexA: Int { evidence.indexA }
        var indexB: Int { evidence.indexB }
        var score: Int { assessment.index.score }
        var isActive: Bool { !isDropped && status != .rejected }
        var isMatch: Bool { isActive && (status == .strong || status == .confirmed) }
        var isReview: Bool { isActive && status == .needsReview }
        /// Liga as duas fotos como a mesma fotografia, ou a mesma pose em outra cor — o que agrupa
        /// versões numa família.
        var isPhotoLink: Bool { kind == .strong || evidence.photo?.colorsDiffer == true }
    }

    private struct Run {
        private typealias Limits = PhotoMatchingParameters

        let sideA: ComparisonSide
        let sideB: ComparisonSide
        private let evidence: ComparisonEvidenceBuilder.Output
        private var edges: [Edge] = []
        private let coverageA: [[UnverifiedReason]]
        private let coverageB: [[UnverifiedReason]]
        private var staleDecisionCount = 0
        private var duplicatesA = StoreDuplicateFinder.Output()
        private var duplicatesB = StoreDuplicateFinder.Output()
        private var duplicateGroupsA = DuplicateGroupIndex()
        private var duplicateGroupsB = DuplicateGroupIndex()
        private var learning = ReviewLearning.none

        init(sideA: ComparisonSide, sideB: ComparisonSide, evidence: ComparisonEvidenceBuilder.Output) {
            self.sideA = sideA
            self.sideB = sideB
            self.evidence = evidence
            let coverageA = sideA.listings.map { Self.coverageReasons($0, generic: evidence.genericPhotosA) }
            let coverageB = sideB.listings.map { Self.coverageReasons($0, generic: evidence.genericPhotosB) }
            self.coverageA = coverageA
            self.coverageB = coverageB
            edges = evidence.pairs.values
                .sorted { ($0.indexA, $0.indexB) < ($1.indexA, $1.indexB) }
                .compactMap { pair in
                    Self.kind(of: pair).map { kind in
                        Edge(evidence: pair, kind: kind, assessment: PairAssessor.assess(
                            sideA.listings[pair.indexA], sideB.listings[pair.indexB], evidence: pair,
                            photosComplete: coverageA[pair.indexA].isEmpty && coverageB[pair.indexB].isEmpty
                        ))
                    }
                }
        }

        private static func kind(of pair: ListingPairEvidence) -> EdgeKind? {
            if let photo = pair.photo {
                if photo.level >= .samePhoto { return .strong }
                if photo.level == .similar { return .similar }
            }
            return pair.textSimilarity >= Limits.textCandidateThreshold ? .text : nil
        }

        /// Por que o próprio anúncio não está todo analisado (vazio = está).
        private static func coverageReasons(_ listing: ComparableListing, generic: Set<String>) -> [UnverifiedReason] {
            var reasons: [UnverifiedReason] = []
            if !listing.hasAllPhotos { reasons.append(.detailsUnavailable) }
            let failed = listing.failedPhotoCount + listing.notAnalyzedPhotoCount
            if failed > 0 { reasons.append(.photosFailed(failed)) }
            let usable = listing.photos.count { $0.isUsable && !generic.contains($0.publicID) }
            if usable == 0, failed == 0 { reasons.append(.noUsablePhoto) }
            return reasons
        }

        private func isComplete(_ edge: Edge) -> Bool {
            coverageA[edge.indexA].isEmpty && coverageB[edge.indexB].isEmpty
        }

        // MARK: - Revisões manuais

        mutating func applyDecisions(_ decisions: [ComparisonDecision]) {
            let indexA = Dictionary(sideA.listings.enumerated().map { ($1.key, $0) }, uniquingKeysWith: { first, _ in first })
            let indexB = Dictionary(sideB.listings.enumerated().map { ($1.key, $0) }, uniquingKeysWith: { first, _ in first })
            var current: [ListingKey: ListingFingerprint] = [:]
            for listing in sideA.listings + sideB.listings {
                current[listing.key] = ListingFingerprint(product: listing.product)
            }
            var edgeByPair: [ComparisonEvidenceBuilder.PairIndex: Int] = [:]
            for (index, edge) in edges.enumerated() {
                edgeByPair[.init(indexA: edge.indexA, indexB: edge.indexB)] = index
            }

            for decision in decisions {
                guard let pair = Self.pairIndex(of: decision, indexA: indexA, indexB: indexB) else { continue }
                let existing = edgeByPair[pair]
                if decision.isStale(current: current) {
                    staleDecisionCount += 1
                    if let existing { edges[existing].isStaleDecision = true }
                    continue
                }
                if let existing {
                    edges[existing].verdict = decision.verdict
                } else {
                    // Par confirmado/rejeitado que não tem (mais) evidência nenhuma — continua valendo.
                    let listingA = sideA.listings[pair.indexA]
                    let listingB = sideB.listings[pair.indexB]
                    let evidence = ListingPairEvidence(
                        indexA: pair.indexA, indexB: pair.indexB,
                        textSimilarity: ProductSimilarity.jaccard(listingA.words, listingB.words)
                    )
                    let assessment = PairAssessor.assess(
                        listingA, listingB, evidence: evidence,
                        photosComplete: coverageA[pair.indexA].isEmpty && coverageB[pair.indexB].isEmpty
                    )
                    edges.append(Edge(evidence: evidence, kind: .text, assessment: assessment, verdict: decision.verdict))
                    edgeByPair[pair] = edges.count - 1
                }
            }
        }

        /// Os anúncios repetidos dentro de cada loja, com as revisões manuais entre anúncios da própria
        /// loja.
        mutating func findDuplicates(_ decisions: [ComparisonDecision]) {
            duplicatesA = StoreDuplicateFinder.find(.init(
                side: sideA,
                pairs: evidence.storePairsA,
                photosComplete: coverageA.map(\.isEmpty),
                decisions: decisions.filter { $0.first.sellerID == sideA.sellerID }
            ))
            duplicatesB = StoreDuplicateFinder.find(.init(
                side: sideB,
                pairs: evidence.storePairsB,
                photosComplete: coverageB.map(\.isEmpty),
                decisions: decisions.filter { $0.first.sellerID == sideB.sellerID }
            ))
            duplicateGroupsA = DuplicateGroupIndex(duplicatesA.groups, side: sideA)
            duplicateGroupsB = DuplicateGroupIndex(duplicatesB.groups, side: sideB)
        }

        private static func pairIndex(
            of decision: ComparisonDecision,
            indexA: [ListingKey: Int],
            indexB: [ListingKey: Int]
        ) -> ComparisonEvidenceBuilder.PairIndex? {
            if let first = indexA[decision.first], let second = indexB[decision.second] {
                return .init(indexA: first, indexB: second)
            }
            if let first = indexA[decision.second], let second = indexB[decision.first] {
                return .init(indexA: first, indexB: second)
            }
            return nil
        }

        // MARK: - Classificação

        mutating func classifyEdges() {
            for index in edges.indices {
                let edge = edges[index]
                switch edge.verdict {
                case .differentProducts:
                    edges[index].status = .rejected
                    edges[index].reasons = [.rejectedByUser] + versionReasons(edge)
                case .sameProduct:
                    edges[index].status = .confirmed
                    edges[index].reasons = [.confirmedByUser] + photoReasons(edge) + versionReasons(edge)
                case nil:
                    if edge.assessment.isVariant {
                        // Outra versão do produto: nunca par nem revisão. Só a ligação por foto conta
                        // como "a outra loja tem outra versão"; texto parecido com atributo em
                        // conflito é só outro anúncio.
                        edges[index].isVersionLink = edge.isPhotoLink && sharesBaseTitle(edge)
                        edges[index].isDropped = true
                    } else if edge.kind == .text, isComplete(edge), edge.evidence.textSimilarity < Limits.textNearIdenticalThreshold {
                        // Texto sozinho, com as fotos dos dois lados todas analisadas e nenhuma
                        // ligando os dois: só sobra se o texto for quase idêntico.
                        edges[index].isDropped = true
                    }
                }
            }

            var edgesOfA = Array(repeating: [Int](), count: sideA.listings.count)
            var edgesOfB = Array(repeating: [Int](), count: sideB.listings.count)
            for (index, edge) in edges.enumerated() where edge.isActive {
                edgesOfA[edge.indexA].append(index)
                edgesOfB[edge.indexB].append(index)
            }

            for index in edges.indices where edges[index].isActive && edges[index].verdict == nil && edges[index].kind == .strong {
                let others = (edgesOfA[edges[index].indexA] + edgesOfB[edges[index].indexB]).filter { $0 != index }
                let outcome = doubts(about: index, others: others)
                edges[index].status = outcome.doubts.isEmpty ? .strong : .needsReview
                edges[index].reasons = (outcome.resolution.map { [$0] } ?? []) + photoReasons(edges[index]) + outcome.doubts
            }
            applyLearning()
            finishReviews()
        }

        // MARK: - Aprendido das suas revisões

        /// Os pares em revisão que as suas revisões de outros pares já decidem (`ReviewLearning`).
        private mutating func applyLearning() {
            learning = ReviewLearning.learn(from: edges.compactMap { edge in
                guard let verdict = edge.verdict, !edge.isStaleDecision, !edge.assessment.isVariant else { return nil }
                return ReviewLearning.Sample(score: edge.score, verdict: verdict)
            })
            let candidates = edges.indices.filter { edges[$0].isReview && edges[$0].verdict == nil }.map { index in
                let edge = edges[index]
                return ReviewLearning.Candidate(id: index, indexA: edge.indexA, indexB: edge.indexB, score: edge.score, isPhotoLink: edge.kind != .text)
            }
            let verdicts = learning.verdicts(
                for: candidates, matchedA: Set(edges.filter(\.isMatch).map(\.indexA)), matchedB: Set(edges.filter(\.isMatch).map(\.indexB))
            )
            for (index, verdict) in verdicts {
                if verdict == .sameProduct, let floor = learning.sameFloor {
                    edges[index].status = .strong
                    edges[index].reasons = [.learnedSame(decisions: learning.sameDecisions, floor: floor)] + photoReasons(edges[index])
                    learning.learnedSame += 1
                } else if verdict == .differentProducts, let ceiling = learning.differentCeiling {
                    edges[index].status = .rejected
                    edges[index].reasons = [.learnedDifferent(decisions: learning.differentDecisions, ceiling: ceiling)] + kindReasons(edges[index])
                    learning.learnedDifferent += 1
                }
            }
        }

        /// O que impede uma "mesma foto" de virar par sozinha — e, quando a mesma foto liga outras
        /// versões e o índice deste par passa o de todas, o motivo de ter virado mesmo assim.
        private func doubts(about index: Int, others: [Int]) -> (doubts: [ComparisonReason], resolution: ComparisonReason?) {
            let edge = edges[index]
            let assessment = edge.assessment
            var doubts: [ComparisonReason] = []
            var resolution: ComparisonReason?
            let sameElsewhere = others.filter { edges[$0].kind == .strong || edges[$0].verdict == .sameProduct }
            if !sameElsewhere.isEmpty {
                let margin = MatchIndexParameters.versionResolutionMargin
                let isDistinguished = sameElsewhere.allSatisfy { edges[$0].verdict == nil && edge.score - edges[$0].score >= margin }
                if isDistinguished {
                    // Só os eixos que separam este par de algum concorrente ("prata" em todos não diz nada,
                    // e "prata" sozinho nunca é o que separa).
                    let competitorAgreements = sameElsewhere.map { Set(edges[$0].assessment.agreements) }
                    let discriminating = assessment.strongAgreements.filter { dimension in
                        !competitorAgreements.allSatisfy { $0.contains(dimension) }
                    }
                    let attributes = sideA.listings[edge.indexA].attributes
                    let label = discriminating.compactMap { attributes.reading($0)?.display }.joined(separator: " · ")
                    resolution = .versionResolved(label.isEmpty ? nil : label)
                } else {
                    let linked = Set(([index] + sameElsewhere).map { edges[$0].indexA }).count
                        + Set(([index] + sameElsewhere).map { edges[$0].indexB }).count
                    doubts.append(.photoUsedByManyListings(max(linked, edge.evidence.linkedListingCount)))
                }
            }
            let correlation = edge.evidence.photo?.contentCorrelation ?? 1
            let hasCloseCompetitor = others.contains {
                guard edges[$0].kind == .similar, let photo = edges[$0].evidence.photo, !photo.colorsDiffer else { return false }
                return photo.contentCorrelation >= correlation - Limits.competitorCorrelationMargin
            }
            if hasCloseCompetitor { doubts.append(.closeCompetitor) }
            if edge.evidence.hasColorConflict { doubts.append(.colorVariant) }
            if assessment.categoriesDiffer { doubts.append(.categoryDiffers) }
            if assessment.brandsDiffer {
                doubts.append(.brandDiffers(assessment.brandA ?? "", assessment.brandB ?? ""))
            }
            if assessment.pricesFarApart, !assessment.textConfirms, sameElsewhere.isEmpty,
               let priceA = sideA.listings[edge.indexA].attributes.price, let priceB = sideB.listings[edge.indexB].attributes.price {
                doubts.append(.priceDiffers(PriceRelation.format(priceA), PriceRelation.format(priceB)))
            }
            return (doubts, resolution)
        }

        private func photoReasons(_ edge: Edge) -> [ComparisonReason] {
            guard let photo = edge.evidence.photo, photo.level >= .samePhoto else { return [] }
            return [photo.isSamePublicID ? .samePublicID : .samePhoto]
        }

        /// Os dois lados parecem o mesmo produto pelo título base — só assim a mesma foto liga versões.
        private func sharesBaseTitle(_ edge: Edge) -> Bool {
            sideA.listings[edge.indexA].attributes.sharesBaseTitle(with: sideB.listings[edge.indexB].attributes)
        }

        private func versionReasons(_ edge: Edge) -> [ComparisonReason] {
            guard edge.assessment.isVariant else { return [] }
            return [.attributesDiffer(edge.assessment.conflicts.map(\.text).joined(separator: ", "))]
        }

        /// Revisões que sobram depois dos pares: some a ligação fraca quando um dos lados já tem par
        /// forte/confirmado que a explica melhor —
        /// - os dois lados já têm par: nada a revisar;
        /// - só texto parecido, e um lado já tem par;
        /// - só foto parecida (nem a mesma foto, nem variante de cor) e texto diferente, e um lado já
        ///   tem par: aquele anúncio já é a mesma fotografia de outro, e esta é só uma peça parecida
        ///   (comum em catálogos de joias com fundo branco). Com texto parecido junto, fica.
        private mutating func finishReviews() {
            let matches = edges.filter(\.isMatch)
            let matchedA = Set(matches.map(\.indexA))
            let matchedB = Set(matches.map(\.indexB))
            // Um repetido do anúncio que já tem par também é aquele produto: nada a revisar.
            let pairedA = duplicateGroupsA.paired(matches.map { (here: $0.indexA, other: $0.indexB) })
            let pairedB = duplicateGroupsB.paired(matches.map { (here: $0.indexB, other: $0.indexA) })
            for index in edges.indices where edges[index].isReview {
                let edge = edges[index]
                let isDuplicateOfPair = pairedA.explains(edge.indexA, with: edge.indexB) || pairedB.explains(edge.indexB, with: edge.indexA)
                let isMatchedA = matchedA.contains(edge.indexA)
                let isMatchedB = matchedB.contains(edge.indexB)
                let isWeakSimilar = edge.kind == .similar && edge.evidence.photo?.colorsDiffer != true
                    && edge.evidence.textSimilarity < Limits.textCandidateThreshold
                if isDuplicateOfPair || (isMatchedA && isMatchedB) || ((edge.kind == .text || isWeakSimilar) && (isMatchedA || isMatchedB)) {
                    edges[index].isDropped = true
                    continue
                }
                var reasons = edge.kind == .strong ? edge.reasons : kindReasons(edge)
                if edge.kind != .text, edge.evidence.textSimilarity >= Limits.textCandidateThreshold {
                    reasons.append(.similarText)
                }
                if isMatchedA || isMatchedB { reasons.append(.otherListingAlreadyPaired) }
                edges[index].reasons = reasons
            }
            for index in edges.indices where edges[index].isStaleDecision && !edges[index].isDropped {
                edges[index].reasons.append(.staleDecision)
            }
        }

        private func kindReasons(_ edge: Edge) -> [ComparisonReason] {
            switch edge.kind {
            case .strong:
                return photoReasons(edge)
            case .similar:
                return [edge.evidence.photo?.colorsDiffer == true ? .colorVariant : .similarPhoto]
            case .text:
                return [.similarText, isComplete(edge) ? .nearIdenticalTextDifferentPhotos : .photosUnavailable]
            }
        }

        // MARK: - Resultado

        func result(runID: UUID, revision: Int) -> AccountComparisonResult {
            // Repetido de um anúncio que tem par (ou revisão) na outra loja também está lá.
            let connectedA = duplicateGroupsA.expanding(Set(edges.filter { $0.isMatch || $0.isReview }.map(\.indexA)))
            let connectedB = duplicateGroupsB.expanding(Set(edges.filter { $0.isMatch || $0.isReview }.map(\.indexB)))
            let matchedA = Set(edges.filter(\.isMatch).map(\.indexA))
            let matchedB = Set(edges.filter(\.isMatch).map(\.indexB))
            // Anúncios sem par que não deu pra analisar por inteiro — podem ser o par de alguém.
            let blockersA = sideA.listings.indices.filter { !matchedA.contains($0) && !coverageA[$0].isEmpty }
            let blockersB = sideB.listings.indices.filter { !matchedB.contains($0) && !coverageB[$0].isEmpty }

            let absenceA = absence(of: sideA, coverage: coverageA, connected: connectedA, otherSide: sideB, otherBlockers: blockersB)
            let absenceB = absence(of: sideB, coverage: coverageB, connected: connectedB, otherSide: sideA, otherBlockers: blockersA)
            let reviews = edges.filter(\.isReview).sorted {
                if $0.kind != $1.kind { return $0.kind > $1.kind }
                if $0.score != $1.score { return $0.score > $1.score }
                return ($0.indexA, $0.indexB) < ($1.indexA, $1.indexB)
            }
            let families = families(absenceA: absenceA, absenceB: absenceB)
            let matchedKeys = Set(edges.filter(\.isMatch).flatMap { [sideA.listings[$0.indexA].key, sideB.listings[$0.indexB].key] })
            let incompleteKeys = Set(sideA.listings.filter { !$0.hasAllPhotos }.map(\.key) + sideB.listings.filter { !$0.hasAllPhotos }.map(\.key))
            return AccountComparisonResult(
                id: runID,
                revision: revision,
                storeA: .make(sideA, unverified: absenceA.unverified),
                storeB: .make(sideB, unverified: absenceB.unverified),
                matches: edges.filter(\.isMatch).map(makeMatch),
                reviews: reviews.map(makeMatch),
                rejected: edges.filter { !$0.isDropped && $0.status == .rejected }.map(makeMatch),
                possiblyMissingInB: absenceA.missing.map { sideA.listings[$0].product },
                possiblyMissingInA: absenceB.missing.map { sideB.listings[$0].product },
                unverifiedA: absenceA.unverified,
                unverifiedB: absenceB.unverified,
                staleDecisionCount: staleDecisionCount,
                families: families.families,
                otherVersions: otherVersions(missingA: absenceA.missing, missingB: absenceB.missing),
                keysWantingDetails: families.memberKeys.intersection(matchedKeys).intersection(incompleteKeys)
                    .union(duplicatesA.keysWantingDetails).union(duplicatesB.keysWantingDetails),
                duplicatesA: duplicatesA.groups,
                duplicatesB: duplicatesB.groups,
                dismissedDuplicates: duplicatesA.dismissed + duplicatesB.dismissed,
                learning: learning
            )
        }

        private struct Absence {
            var missing: [Int] = []
            var unverified: [UnverifiedListing] = []
            var unverifiedIndices: Set<Int> = []
        }

        private func absence(
            of side: ComparisonSide,
            coverage: [[UnverifiedReason]],
            connected: Set<Int>,
            otherSide: ComparisonSide,
            otherBlockers: [Int]
        ) -> Absence {
            var absence = Absence()
            for (index, listing) in side.listings.enumerated() where !connected.contains(index) {
                var reasons = coverage[index]
                if !otherSide.status.allowsAbsenceConclusions {
                    reasons.append(.otherStoreListingIncomplete(storeName: otherSide.name))
                }
                if reasons.isEmpty, let title = possibleCounterpart(of: listing, among: otherBlockers, in: otherSide) {
                    reasons.append(.possibleUnverifiedCounterpart(title: title))
                }
                if reasons.isEmpty {
                    absence.missing.append(index)
                } else {
                    absence.unverified.append(UnverifiedListing(product: listing.product, reasons: reasons))
                    absence.unverifiedIndices.insert(index)
                }
            }
            return absence
        }

        private func possibleCounterpart(of listing: ComparableListing, among blockers: [Int], in side: ComparisonSide) -> String? {
            var best: (score: Double, title: String)?
            for index in blockers {
                let candidate = side.listings[index]
                let score = ProductSimilarity.jaccard(listing.titleWords, candidate.titleWords)
                if score >= Limits.unverifiedBlockingTextThreshold, score > (best?.score ?? 0) {
                    best = (score, candidate.product.title)
                }
            }
            return best?.title
        }

        // MARK: - Versões

        /// De cada possivelmente ausente: as versões dele na outra loja (ligações "outra versão"),
        /// da que menos muda pra que mais muda.
        private func otherVersions(missingA: [Int], missingB: [Int]) -> [ListingKey: [OtherVersion]] {
            var result: [ListingKey: [OtherVersion]] = [:]
            let missingSetA = Set(missingA)
            let missingSetB = Set(missingB)
            for edge in edges where edge.isVersionLink {
                let listingA = sideA.listings[edge.indexA]
                let listingB = sideB.listings[edge.indexB]
                if missingSetA.contains(edge.indexA) {
                    result[listingA.key, default: []].append(OtherVersion(product: listingB.product, differences: edge.assessment.conflicts))
                }
                if missingSetB.contains(edge.indexB) {
                    result[listingB.key, default: []].append(OtherVersion(
                        product: listingA.product, differences: edge.assessment.conflicts.map(\.reversed)
                    ))
                }
            }
            return result.mapValues { versions in
                versions.sorted {
                    if $0.differences.count != $1.differences.count { return $0.differences.count < $1.differences.count }
                    return $0.label.localizedStandardCompare($1.label) == .orderedAscending
                }
            }
        }

        private func families(absenceA: Absence, absenceB: Absence) -> ProductFamilyBuilder.Output {
            let link = { (edge: Edge) in ProductFamilyBuilder.Link(indexA: edge.indexA, indexB: edge.indexB) }
            return ProductFamilyBuilder.build(ProductFamilyBuilder.Input(
                listingsA: sideA.listings,
                listingsB: sideB.listings,
                photoLinks: edges.filter { $0.isPhotoLink && sharesBaseTitle($0) }.map(link),
                coverGroupsA: evidence.coverGroupsA,
                coverGroupsB: evidence.coverGroupsB,
                duplicatePairsA: duplicatesA.linkedPairs,
                duplicatePairsB: duplicatesB.linkedPairs,
                matches: edges.filter(\.isMatch).map(link),
                reviewA: Set(edges.filter(\.isReview).map(\.indexA)),
                reviewB: Set(edges.filter(\.isReview).map(\.indexB)),
                unverifiedA: absenceA.unverifiedIndices,
                unverifiedB: absenceB.unverifiedIndices,
                versionLinks: edges.filter(\.isVersionLink).map(link)
            ))
        }

        // MARK: - Montagem

        private func makeMatch(_ edge: Edge) -> ProductMatch {
            let listingA = sideA.listings[edge.indexA]
            let listingB = sideB.listings[edge.indexB]
            return ProductMatch(
                productA: listingA.product,
                productB: listingB.product,
                keyA: listingA.key,
                keyB: listingB.key,
                status: edge.status,
                reasons: edge.reasons,
                photoEvidence: edge.evidence.photo,
                photoA: edge.evidence.photoA,
                photoB: edge.evidence.photoB,
                textSimilarity: edge.evidence.textSimilarity,
                index: edge.assessment.index,
                attributeRows: MatchAttributeRow.rows(listingA.attributes, listingB.attributes)
            )
        }
    }
}
