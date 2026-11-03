import Foundation

/// Tudo de um anúncio que, além das fotos, diz qual produto (e qual **versão** dele) ele é: os eixos
/// de variante lidos do texto (`AttributeExtractor`), a marca, a categoria, o preço inicial e as
/// palavras do título/descrição sem o vocabulário de variante.
///
/// Prioridade por eixo: o campo de tamanho do template > o título > a descrição (só o que o título
/// não disse). No banho, "prata" sozinho é o valor mais fraco: uma descrição que diz "banho de ouro"
/// vale mais que o "prata 925" do título — é exatamente o caso das lojas que mantêm o mesmo título
/// pra todas as versões e mudam só a descrição.
nonisolated struct ListingAttributes: Equatable, Sendable {
    let readings: [VariantDimension: AttributeReading]
    /// Normalizada (minúsculas, sem acento) pra comparar; `nil` quando vazia ou "sem marca".
    let brand: String?
    let brandDisplay: String?
    let categoryID: Int?
    /// Preço sem desconto ("preço inicial"); o atual quando o original não vem.
    let price: Double?
    /// Título sem as palavras de variante — o produto "base".
    let baseTitleWords: Set<String>
    /// Descrição sem as palavras de variante (nem o texto padrão da loja, depois de
    /// `removingDescriptionWords`); `nil` quando a descrição não foi buscada (ou é vazia).
    private(set) var descriptionWords: Set<String>?

    init(
        readings: [VariantDimension: AttributeReading] = [:],
        brand: String? = nil,
        categoryID: Int? = nil,
        price: Double? = nil,
        baseTitleWords: Set<String> = [],
        descriptionWords: Set<String>? = nil
    ) {
        self.readings = readings
        let trimmedBrand = brand?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBrand = trimmedBrand.map(Self.normalizedBrand)
        if let normalizedBrand, !normalizedBrand.isEmpty, !Self.placeholderBrands.contains(normalizedBrand) {
            self.brand = normalizedBrand
            brandDisplay = trimmedBrand
        } else {
            self.brand = nil
            brandDisplay = nil
        }
        self.categoryID = categoryID
        self.price = price
        self.baseTitleWords = baseTitleWords
        self.descriptionWords = descriptionWords
    }

    init(product: EnjoeiProduct, details: ProductListingDetails?) {
        let titleTokens = AttributeExtractor.tokens(product.title)
        let description = (product.description ?? details?.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let descriptionTokens = description.isEmpty ? [] : AttributeExtractor.tokens(description)
        let fromTitle = AttributeExtractor.values(in: titleTokens, source: .title)
        let fromDescription = AttributeExtractor.values(in: descriptionTokens, source: .description)

        var readings: [VariantDimension: AttributeReading] = [:]
        for dimension in VariantDimension.allCases {
            let reading = Self.reading(dimension, title: fromTitle[dimension] ?? [], description: fromDescription[dimension] ?? [])
            if let reading { readings[dimension] = reading }
        }
        let mentionsRing = AttributeExtractor.mentionsRing(titleTokens) || AttributeExtractor.mentionsRing(descriptionTokens)
        if let size = AttributeExtractor.templateSize(details?.size, preferRingLabel: mentionsRing) {
            readings[.size] = .decisive(size)
        }

        let descriptionWords = description.isEmpty ? nil : AttributeExtractor.baseWords(ProductSimilarity.tokenize(description))
        self.init(
            readings: readings,
            brand: details?.brand,
            categoryID: details?.categoryID,
            price: product.originalPrice ?? product.currentPrice,
            baseTitleWords: AttributeExtractor.baseWords(ProductSimilarity.tokenize(product.title)),
            descriptionWords: descriptionWords
        )
    }

    /// O título base dos dois tem palavras o bastante em comum pra ser o mesmo produto (talvez em
    /// outra versão). Sem título base de um lado (só palavras de versão), não dá pra dizer que não.
    func sharesBaseTitle(with other: ListingAttributes) -> Bool {
        guard !baseTitleWords.isEmpty, !other.baseTitleWords.isEmpty else { return true }
        return ProductSimilarity.jaccard(baseTitleWords, other.baseTitleWords) >= MatchIndexParameters.familyMinimumTitleSimilarity
    }

    /// Os mesmos atributos sem essas palavras na descrição (o texto padrão da loja). Os atributos de
    /// versão continuam lidos da descrição inteira.
    func removingDescriptionWords(_ words: Set<String>) -> ListingAttributes {
        guard let descriptionWords, !words.isEmpty else { return self }
        var copy = self
        copy.descriptionWords = descriptionWords.subtracting(words)
        return copy
    }

    private static func reading(_ dimension: VariantDimension, title: [VariantValue], description: [VariantValue]) -> AttributeReading? {
        guard dimension == .finish else {
            return AttributeReading.from(title.isEmpty ? description : title)
        }
        let isPlain: (VariantValue) -> Bool = { $0 == AttributeExtractor.plainSilver }
        let strongTitle = title.filter { !isPlain($0) }
        let strongDescription = description.filter { !isPlain($0) }
        if !strongTitle.isEmpty { return AttributeReading.from(strongTitle) }
        if !strongDescription.isEmpty { return AttributeReading.from(strongDescription) }
        return AttributeReading.from(title.isEmpty ? description : title)
    }

    func reading(_ dimension: VariantDimension) -> AttributeReading? { readings[dimension] }

    /// "aro 16 · ródio" — os valores destes eixos, na ordem dada; o eixo sem valor decisivo vira
    /// "<eixo> não informado".
    func label(for dimensions: [VariantDimension]) -> String {
        dimensions.map { dimension in
            readings[dimension]?.display ?? "\(dimension.label) não informado"
        }
        .joined(separator: " · ")
    }

    private static let placeholderBrands: Set = [
        "sem marca", "outra", "outras", "outro", "outros", "nenhuma", "generica", "generico", "nao tem", "-", "n/a", "na"
    ]

    private static func normalizedBrand(_ brand: String) -> String {
        brand.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
