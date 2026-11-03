import Foundation

/// Mede um par de anúncios em todas as frentes — foto, título base, descrição, atributos de variante,
/// marca, categoria, preço inicial — e monta o índice de correspondência com as parcelas que a
/// revisão mostra. Não decide estado nenhum (isso é o `ComparisonResolver`).
nonisolated enum PairAssessor {
    private typealias Weights = MatchIndexParameters

    static func assess(
        _ listingA: ComparableListing,
        _ listingB: ComparableListing,
        evidence: ListingPairEvidence,
        photosComplete: Bool
    ) -> PairAssessment {
        let attributesA = listingA.attributes
        let attributesB = listingB.attributes
        var components: [MatchIndexComponent] = []
        if let photo = photoComponent(evidence, photosComplete: photosComplete) { components.append(photo) }
        if evidence.hasColorConflict, (evidence.photo?.level ?? .different) >= .samePhoto {
            components.append(.init(kind: .photo, points: Weights.colorConflictPoints, text: "outra foto do par bate só na forma, com outra cor"))
        }
        let text = textComponents(attributesA, attributesB)
        components += text.components
        let descriptionSimilarity = text.descriptionSimilarity

        let attributes = attributeComponents(attributesA, attributesB)
        components += attributes.components

        let brandsDiffer: Bool
        if let brandA = attributesA.brand, let brandB = attributesB.brand {
            brandsDiffer = brandA != brandB
            let display = "\(attributesA.brandDisplay ?? brandA) × \(attributesB.brandDisplay ?? brandB)"
            components.append(brandsDiffer
                ? .init(kind: .brand, points: Weights.brandConflictPoints, text: "marcas diferentes (\(display))")
                : .init(kind: .brand, points: Weights.brandAgreementPoints, text: "mesma marca (\(attributesA.brandDisplay ?? brandA))"))
        } else {
            brandsDiffer = false
        }
        let categoriesDiffer = attributesA.categoryID != nil && attributesB.categoryID != nil && attributesA.categoryID != attributesB.categoryID
        if categoriesDiffer {
            components.append(.init(kind: .category, points: Weights.categoryConflictPoints, text: "categorias diferentes"))
        }
        let priceRelation = PriceRelation.between(attributesA.price, attributesB.price)
        if let price = priceComponent(priceRelation, attributesA.price, attributesB.price) { components.append(price) }

        return PairAssessment(
            index: MatchIndex(components: components),
            conflicts: attributes.conflicts,
            agreements: attributes.agreements,
            strongAgreements: attributes.agreements.filter { dimension in
                dimension != .finish || attributesA.reading(.finish)?.decisiveValue != AttributeExtractor.plainSilver
            },
            brandA: attributesA.brandDisplay,
            brandB: attributesB.brandDisplay,
            brandsDiffer: brandsDiffer,
            categoriesDiffer: categoriesDiffer,
            priceRelation: priceRelation,
            pricesFarApart: PriceRelation.areFarApart(attributesA.price, attributesB.price),
            descriptionSimilarity: descriptionSimilarity
        )
    }

    private static func textComponents(
        _ attributesA: ListingAttributes,
        _ attributesB: ListingAttributes
    ) -> (components: [MatchIndexComponent], descriptionSimilarity: Double?) {
        var components: [MatchIndexComponent] = []
        if !attributesA.baseTitleWords.isEmpty, !attributesB.baseTitleWords.isEmpty {
            let similarity = ProductSimilarity.jaccard(attributesA.baseTitleWords, attributesB.baseTitleWords)
            components.append(.init(
                kind: .title,
                points: Int((similarity * Double(Weights.baseTitleMaxPoints)).rounded()),
                text: "título: \(percent(similarity)) das palavras em comum, fora tamanho, banho e cor"
            ))
        }
        var descriptionSimilarity: Double?
        if let wordsA = attributesA.descriptionWords, let wordsB = attributesB.descriptionWords, !wordsA.isEmpty, !wordsB.isEmpty {
            let similarity = ProductSimilarity.jaccard(wordsA, wordsB)
            descriptionSimilarity = similarity
            components.append(.init(
                kind: .description,
                points: Int((similarity * Double(Weights.descriptionMaxPoints)).rounded()),
                text: "descrição: \(percent(similarity)) das palavras em comum"
            ))
        }
        return (components, descriptionSimilarity)
    }

    private static func photoComponent(_ evidence: ListingPairEvidence, photosComplete: Bool) -> MatchIndexComponent? {
        guard let photo = evidence.photo else {
            return photosComplete
                ? .init(kind: .photo, points: Weights.noSharedPhotoPoints, text: "nenhuma foto em comum")
                : nil
        }
        switch photo.level {
        case .identical where photo.isSamePublicID:
            return .init(kind: .photo, points: Weights.samePublicIDPoints, text: "o mesmo arquivo de foto")
        case .identical, .samePhoto:
            return .init(kind: .photo, points: Weights.samePhotoPoints, text: "a mesma foto")
        case .similar where photo.colorsDiffer:
            return .init(kind: .photo, points: Weights.colorVariantPhotoPoints, text: "a mesma pose, com outra cor")
        case .similar:
            return .init(kind: .photo, points: Weights.similarPhotoPoints, text: "fotos parecidas")
        case .different:
            return nil
        }
    }

    private struct AttributeOutcome {
        var components: [MatchIndexComponent] = []
        var conflicts: [AttributeDifference] = []
        var agreements: [VariantDimension] = []
    }

    private static func attributeComponents(_ first: ListingAttributes, _ second: ListingAttributes) -> AttributeOutcome {
        var outcome = AttributeOutcome()
        var agreementPoints = 0
        for dimension in VariantDimension.allCases {
            let readingA = first.reading(dimension)
            let readingB = second.reading(dimension)
            switch AttributeRelation.between(readingA, readingB, dimension: dimension) {
            case .agrees:
                outcome.agreements.append(dimension)
                let points = min(Weights.attributeAgreementPoints, Weights.attributeAgreementMaxPoints - agreementPoints)
                agreementPoints += points
                outcome.components.append(.init(
                    kind: .attribute(dimension), points: points, text: "\(readingA?.display ?? "") nos dois"
                ))
            case .conflicts:
                guard let valueA = readingA?.decisiveValue, let valueB = readingB?.decisiveValue else { continue }
                let difference = AttributeDifference(dimension: dimension, valueA: valueA, valueB: valueB)
                outcome.conflicts.append(difference)
                outcome.components.append(.init(
                    kind: .attribute(dimension), points: Weights.attributeConflictPoints, text: "\(dimension.label): \(difference.text)"
                ))
            case .compatible, .unknown:
                continue
            }
        }
        return outcome
    }

    private static func priceComponent(_ relation: PriceRelation, _ priceA: Double?, _ priceB: Double?) -> MatchIndexComponent? {
        guard let priceA, let priceB else { return nil }
        let pair = "\(PriceRelation.format(priceA)) × \(PriceRelation.format(priceB))"
        switch relation {
        case .same:
            return .init(kind: .price, points: Weights.samePricePoints, text: "mesmo preço inicial (\(PriceRelation.format(priceA)))")
        case .close:
            return .init(kind: .price, points: 0, text: "preço inicial parecido (\(pair))")
        case .different:
            return .init(kind: .price, points: Weights.differentPricePoints, text: "preço inicial diferente (\(pair))")
        case .unknown:
            return nil
        }
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
