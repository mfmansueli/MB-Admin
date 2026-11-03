import Foundation

/// Transforma a evidência (`ComparisonEvidenceBuilder`) + as revisões manuais num
/// `AccountComparisonResult`. Sem ordem gulosa nem nota somada: cada par é classificado pelo **tipo**
/// de evidência e pelos concorrentes que os dois anúncios têm.
///
/// - **Correspondência forte**: a mesma fotografia (ou o mesmo arquivo), e nenhum dos dois anúncios
///   tem outro par com a mesma foto, nem uma foto quase tão parecida com outro, nem variante de cor,
///   nem tamanho/categoria em conflito (dado faltando não é conflito; preço nunca entra).
/// - **Precisa revisar**: mesma foto com concorrente ou conflito; foto parecida; texto parecido
///   (só quando as fotos não estão todas analisadas, ou o texto é quase idêntico). Nunca vira par
///   sozinho, e duplicatas numa loja não são forçadas a 1:1 — cada ligação aparece pra revisar.
/// - **Possivelmente ausente**: nenhuma ligação, todas as fotos do anúncio analisadas, a lista da
///   outra loja completa, e nenhum anúncio não verificado da outra loja com título parecido.
/// - **Não foi possível verificar**: nenhuma ligação, mas falta alguma dessas condições.
///
/// Revisões manuais valem acima de tudo enquanto os anúncios não mudarem (`ListingFingerprint`):
/// "mesmo produto" vira par confirmado; "produtos diferentes" remove a ligação.
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
        run.applyDecisions(decisions)
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
        var verdict: ComparisonDecision.Verdict?
        var isStaleDecision = false
        var status: ProductMatch.Status = .needsReview
        var reasons: [ComparisonReason] = []
        var isDropped = false

        var indexA: Int { evidence.indexA }
        var indexB: Int { evidence.indexB }
        var isActive: Bool { !isDropped && status != .rejected }
        var isMatch: Bool { isActive && (status == .strong || status == .confirmed) }
        var isReview: Bool { isActive && status == .needsReview }
    }

    private struct Run {
        private typealias Limits = PhotoMatchingParameters

        let sideA: ComparisonSide
        let sideB: ComparisonSide
        private var edges: [Edge] = []
        private let coverageA: [[UnverifiedReason]]
        private let coverageB: [[UnverifiedReason]]
        private var staleDecisionCount = 0

        init(sideA: ComparisonSide, sideB: ComparisonSide, evidence: ComparisonEvidenceBuilder.Output) {
            self.sideA = sideA
            self.sideB = sideB
            coverageA = sideA.listings.map { Self.coverageReasons($0, generic: evidence.genericPhotosA) }
            coverageB = sideB.listings.map { Self.coverageReasons($0, generic: evidence.genericPhotosB) }
            edges = evidence.pairs.values
                .sorted { ($0.indexA, $0.indexB) < ($1.indexA, $1.indexB) }
                .compactMap { pair in Self.kind(of: pair).map { Edge(evidence: pair, kind: $0) } }
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
                    var evidence = ListingPairEvidence(indexA: pair.indexA, indexB: pair.indexB)
                    evidence.textSimilarity = ProductSimilarity.jaccard(
                        sideA.listings[pair.indexA].words, sideB.listings[pair.indexB].words
                    )
                    edges.append(Edge(evidence: evidence, kind: .text, verdict: decision.verdict))
                    edgeByPair[pair] = edges.count - 1
                }
            }
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
                switch edges[index].verdict {
                case .differentProducts:
                    edges[index].status = .rejected
                    edges[index].reasons = [.rejectedByUser]
                case .sameProduct:
                    edges[index].status = .confirmed
                    edges[index].reasons = [.confirmedByUser] + photoReasons(edges[index])
                case nil:
                    // Texto sozinho, com as fotos dos dois lados todas analisadas e nenhuma ligando os
                    // dois: só sobra se o texto for quase idêntico.
                    if edges[index].kind == .text, isComplete(edges[index]),
                       edges[index].evidence.textSimilarity < Limits.textNearIdenticalThreshold {
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
                let doubts = doubts(about: index, others: others)
                edges[index].status = doubts.isEmpty ? .strong : .needsReview
                edges[index].reasons = photoReasons(edges[index]) + doubts
            }
            finishReviews()
        }

        /// O que impede uma "mesma foto" de virar par sozinha.
        private func doubts(about index: Int, others: [Int]) -> [ComparisonReason] {
            let edge = edges[index]
            var doubts: [ComparisonReason] = []
            let sameElsewhere = others.filter { edges[$0].kind == .strong || edges[$0].verdict == .sameProduct }
            if !sameElsewhere.isEmpty {
                let linked = Set(([index] + sameElsewhere).map { edges[$0].indexA }).count
                    + Set(([index] + sameElsewhere).map { edges[$0].indexB }).count
                doubts.append(.photoUsedByManyListings(max(linked, edge.evidence.linkedListingCount)))
            }
            let correlation = edge.evidence.photo?.contentCorrelation ?? 1
            let hasCloseCompetitor = others.contains {
                guard edges[$0].kind == .similar, let photo = edges[$0].evidence.photo, !photo.colorsDiffer else { return false }
                return photo.contentCorrelation >= correlation - Limits.competitorCorrelationMargin
            }
            if hasCloseCompetitor { doubts.append(.closeCompetitor) }
            if edge.evidence.hasColorConflict { doubts.append(.colorVariant) }
            let listingA = sideA.listings[edge.indexA]
            let listingB = sideB.listings[edge.indexB]
            if let sizeA = listingA.size, let sizeB = listingB.size, sizeA != sizeB {
                doubts.append(.sizeDiffers(sizeA, sizeB))
            }
            if let categoryA = listingA.categoryID, let categoryB = listingB.categoryID, categoryA != categoryB {
                doubts.append(.categoryDiffers)
            }
            return doubts
        }

        private func photoReasons(_ edge: Edge) -> [ComparisonReason] {
            guard let photo = edge.evidence.photo, photo.level >= .samePhoto else { return [] }
            return [photo.isSamePublicID ? .samePublicID : .samePhoto]
        }

        /// Revisões que sobram depois dos pares: some a ligação fraca quando um dos lados já tem par
        /// forte/confirmado que a explica melhor —
        /// - os dois lados já têm par: nada a revisar;
        /// - só texto parecido, e um lado já tem par;
        /// - só foto parecida (nem a mesma foto, nem variante de cor) e texto diferente, e um lado já
        ///   tem par: aquele anúncio já é a mesma fotografia de outro, e esta é só uma peça parecida
        ///   (comum em catálogos de joias com fundo branco). Com texto parecido junto, fica.
        private mutating func finishReviews() {
            let matchedA = Set(edges.filter(\.isMatch).map(\.indexA))
            let matchedB = Set(edges.filter(\.isMatch).map(\.indexB))
            for index in edges.indices where edges[index].isReview {
                let edge = edges[index]
                let isMatchedA = matchedA.contains(edge.indexA)
                let isMatchedB = matchedB.contains(edge.indexB)
                let isWeakSimilar = edge.kind == .similar && edge.evidence.photo?.colorsDiffer != true
                    && edge.evidence.textSimilarity < Limits.textCandidateThreshold
                if (isMatchedA && isMatchedB) || ((edge.kind == .text || isWeakSimilar) && (isMatchedA || isMatchedB)) {
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
            let connectedA = Set(edges.filter { $0.isMatch || $0.isReview }.map(\.indexA))
            let connectedB = Set(edges.filter { $0.isMatch || $0.isReview }.map(\.indexB))
            let matchedA = Set(edges.filter(\.isMatch).map(\.indexA))
            let matchedB = Set(edges.filter(\.isMatch).map(\.indexB))
            // Anúncios sem par que não deu pra analisar por inteiro — podem ser o par de alguém.
            let blockersA = sideA.listings.indices.filter { !matchedA.contains($0) && !coverageA[$0].isEmpty }
            let blockersB = sideB.listings.indices.filter { !matchedB.contains($0) && !coverageB[$0].isEmpty }

            let absenceA = absence(
                of: sideA, coverage: coverageA, connected: connectedA,
                otherSide: sideB, otherBlockers: blockersB
            )
            let absenceB = absence(
                of: sideB, coverage: coverageB, connected: connectedB,
                otherSide: sideA, otherBlockers: blockersA
            )
            let reviews = edges.filter(\.isReview).sorted {
                if $0.kind != $1.kind { return $0.kind > $1.kind }
                return ($0.indexA, $0.indexB) < ($1.indexA, $1.indexB)
            }
            return AccountComparisonResult(
                id: runID,
                revision: revision,
                storeA: summary(of: sideA, unverified: absenceA.unverified),
                storeB: summary(of: sideB, unverified: absenceB.unverified),
                matches: edges.filter(\.isMatch).map(makeMatch),
                reviews: reviews.map(makeMatch),
                rejected: edges.filter { !$0.isDropped && $0.status == .rejected }.map(makeMatch),
                possiblyMissingInB: absenceA.missing,
                possiblyMissingInA: absenceB.missing,
                unverifiedA: absenceA.unverified,
                unverifiedB: absenceB.unverified,
                staleDecisionCount: staleDecisionCount
            )
        }

        private func absence(
            of side: ComparisonSide,
            coverage: [[UnverifiedReason]],
            connected: Set<Int>,
            otherSide: ComparisonSide,
            otherBlockers: [Int]
        ) -> (missing: [EnjoeiProduct], unverified: [UnverifiedListing]) {
            var missing: [EnjoeiProduct] = []
            var unverified: [UnverifiedListing] = []
            for (index, listing) in side.listings.enumerated() where !connected.contains(index) {
                var reasons = coverage[index]
                if !otherSide.status.allowsAbsenceConclusions {
                    reasons.append(.otherStoreListingIncomplete(storeName: otherSide.name))
                }
                if reasons.isEmpty, let title = possibleCounterpart(of: listing, among: otherBlockers, in: otherSide) {
                    reasons.append(.possibleUnverifiedCounterpart(title: title))
                }
                if reasons.isEmpty {
                    missing.append(listing.product)
                } else {
                    unverified.append(UnverifiedListing(product: listing.product, reasons: reasons))
                }
            }
            return (missing, unverified)
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

        private func summary(of side: ComparisonSide, unverified: [UnverifiedListing]) -> ComparisonStoreSummary {
            ComparisonStoreSummary(
                sellerID: side.sellerID,
                name: side.name,
                status: side.status,
                listingCount: side.listings.count,
                listingsWithPhotoFailures: unverified.count { $0.reasons.contains { if case .photosFailed = $0 { true } else { false } } },
                listingsWithDetailsFailures: unverified.count { $0.reasons.contains(.detailsUnavailable) }
            )
        }

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
                textSimilarity: edge.evidence.textSimilarity
            )
        }
    }
}
