import Foundation

/// Lê do texto de um anúncio os atributos que separam versões do mesmo produto: tamanho/aro, banho,
/// cor da pedra e medidas. Puro (sem regex nem NLP): o texto vira uma sequência de palavras
/// (minúsculas, sem acento) e números, e cada eixo procura seus padrões nela.
///
/// Conservador de propósito: mais de um valor no mesmo eixo ("aro 14 ao 20", "branca e rosa") vira
/// `AttributeReading.ambiguous`, que nunca decide nada. Da **descrição** só sai o que o título não
/// disse, e as medidas/cores só com uma palavra de contexto perto ("corrente 45 cm", "zircônia
/// rosa") — descrição tem tabela de medidas, instruções de cuidado e lista de cores disponíveis.
nonisolated enum AttributeExtractor {
    /// Um pedaço do texto normalizado.
    nonisolated struct Token: Equatable, Sendable {
        let text: String
        /// O valor, quando o pedaço é um número ("16", "2.5").
        let number: Double?
    }

    /// De onde o texto veio — a descrição só vale com contexto.
    nonisolated enum Source: Sendable {
        case title
        case description
    }

    // MARK: - Texto → pedaços

    /// Minúsculas, sem acento, "nº 16" → "numero 16", letras e números sempre separados ("45cm" →
    /// "45", "cm"; "aro16" → "aro", "16"), vírgula/ponto entre dígitos vira decimal.
    static func tokens(_ text: String) -> [Token] {
        let prepared = text.lowercased()
            .replacingOccurrences(of: "n.º", with: " numero ")
            .replacingOccurrences(of: "nº", with: " numero ")
            .replacingOccurrences(of: "n°", with: " numero ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "pt_BR"))
        let characters = Array(prepared)
        var tokens: [Token] = []
        var current = ""
        var isNumber = false

        func flush() {
            guard !current.isEmpty else { return }
            tokens.append(Token(text: current, number: isNumber ? Double(current) : nil))
            current = ""
        }

        for (offset, character) in characters.enumerated() {
            let isDigit = character.isASCII && character.isNumber
            if isDigit {
                if !isNumber { flush() }
                isNumber = true
                current.append(character)
            } else if character.isLetter {
                if isNumber { flush() }
                isNumber = false
                current.append(character)
            } else if character == "," || character == ".", isNumber, !current.contains("."),
                      offset + 1 < characters.count, characters[offset + 1].isASCII, characters[offset + 1].isNumber {
                current.append(".")
            } else {
                flush()
                isNumber = false
            }
        }
        flush()
        return tokens
    }

    // MARK: - Pedaços → atributos

    /// Os valores de cada eixo achados no texto (vazio = o texto não diz).
    static func values(in tokens: [Token], source: Source) -> [VariantDimension: [VariantValue]] {
        var consumed = Set<Int>()
        var result: [VariantDimension: [VariantValue]] = [:]
        result[.finish] = finishes(in: tokens, consumed: &consumed)
        result[.size] = sizes(in: tokens, consumed: &consumed)
        result[.measure] = measures(in: tokens, source: source, consumed: &consumed)
        result[.stoneColor] = colors(in: tokens, source: source, consumed: consumed)
        return result.filter { !$0.value.isEmpty }
    }

    /// "prata" (sem banho nenhum) é o valor mais fraco do banho: só vale quando o texto não diz outro.
    static let plainSilver = VariantValue(canonical: "prata", display: "prata")

    // MARK: - Banho

    private static let finishPhrases: [(words: [String], value: VariantValue)] = {
        let blackRhodium = VariantValue(canonical: "rodio negro", display: "ródio negro")
        let whiteGold = VariantValue(canonical: "ouro branco", display: "ouro branco")
        let roseGold = VariantValue(canonical: "ouro rose", display: "ouro rosé")
        let rhodium = VariantValue(canonical: "rodio", display: "ródio")
        let silverPlated = VariantValue(canonical: "prateado", display: "prateado")
        let gold = VariantValue(canonical: "ouro", display: "ouro")
        // Mais longas primeiro: "ródio negro" antes de "ródio", "ouro rosé" antes de "ouro".
        return [
            (["rodio", "negro"], blackRhodium), (["rodio", "preto"], blackRhodium), (["rodio", "black"], blackRhodium),
            (["banho", "negro"], blackRhodium),
            (["ouro", "branco"], whiteGold),
            (["ouro", "rose"], roseGold), (["ouro", "rosa"], roseGold), (["rose", "gold"], roseGold), (["rosegold"], roseGold),
            (["rose"], roseGold),
            (["rodio", "branco"], rhodium), (["rodio"], rhodium), (["rodinado"], rhodium), (["rodinada"], rhodium),
            (["rodiado"], rhodium), (["rodiada"], rhodium),
            (["folheado", "a", "prata"], silverPlated), (["folheada", "a", "prata"], silverPlated),
            (["banho", "de", "prata"], silverPlated), (["banhado", "a", "prata"], silverPlated),
            (["banhada", "a", "prata"], silverPlated), (["banho", "prata"], silverPlated),
            (["prateado"], silverPlated), (["prateada"], silverPlated), (["prateados"], silverPlated), (["prateadas"], silverPlated),
            (["ouro"], gold), (["dourado"], gold), (["dourada"], gold), (["dourados"], gold), (["douradas"], gold),
            (["gold"], gold), (["folheado"], gold), (["folheada"], gold), (["folheados"], gold), (["folheadas"], gold)
        ]
    }()

    private static func finishes(in tokens: [Token], consumed: inout Set<Int>) -> [VariantValue] {
        var found: [VariantValue] = []
        var hasPlainSilver = false
        var offset = 0
        while offset < tokens.count {
            if let phrase = finishPhrases.first(where: { matches($0.words, tokens, at: offset) }) {
                found.append(phrase.value)
                consumed.formUnion(offset..<(offset + phrase.words.count))
                offset += phrase.words.count
                continue
            }
            if tokens[offset].text == "prata" {
                hasPlainSilver = true
                consumed.insert(offset)
            }
            offset += 1
        }
        if found.isEmpty, hasPlainSilver { return [plainSilver] }
        return found
    }

    private static func matches(_ words: [String], _ tokens: [Token], at offset: Int) -> Bool {
        guard offset + words.count <= tokens.count else { return false }
        return words.indices.allSatisfy { tokens[offset + $0].text == words[$0] }
    }

    // MARK: - Tamanho

    private static let ringSizeTriggers: Set = ["aro", "aros"]
    private static let sizeTriggers: Set = ["aro", "aros", "tam", "tamanho", "tamanhos", "numero", "num", "numeracao"]
    private static let sizeFillers: Set = ["de", "do", "da", "n", "no", "numero"]
    private static let rangeConnectors: Set = ["a", "ao", "ate", "e", "ou"]
    private static let letterSizes: Set = ["pp", "p", "m", "g", "gg", "xg", "xgg", "eg", "egg"]
    private static let units: Set = ["cm", "mm", "m", "g", "k", "kg", "ml", "l", "centimetros", "milimetros", "quilates"]

    private static func sizes(in tokens: [Token], consumed: inout Set<Int>) -> [VariantValue] {
        var found: [VariantValue] = []
        for (offset, token) in tokens.enumerated() where sizeTriggers.contains(token.text) && !consumed.contains(offset) {
            let isRing = ringSizeTriggers.contains(token.text)
            var cursor = offset + 1
            while cursor < tokens.count, sizeFillers.contains(tokens[cursor].text) { cursor += 1 }
            while cursor < tokens.count, let value = sizeValue(tokens, at: cursor, isRing: isRing) {
                found.append(value)
                consumed.insert(cursor)
                cursor += 1
                // "aro 14 ao 20", "aro 16/18", "tamanho p e m": continua lendo valores.
                if cursor < tokens.count, rangeConnectors.contains(tokens[cursor].text) { cursor += 1 }
            }
            consumed.insert(offset)
        }
        return found
    }

    private static func sizeValue(_ tokens: [Token], at offset: Int, isRing: Bool) -> VariantValue? {
        let token = tokens[offset]
        if let number = token.number {
            let followedByUnit = offset + 1 < tokens.count && units.contains(tokens[offset + 1].text)
            guard !followedByUnit, number >= 1, number <= 60, number == number.rounded() else { return nil }
            let text = String(Int(number))
            return VariantValue(canonical: text, display: isRing ? "aro \(text)" : "tam. \(text)")
        }
        guard !isRing, letterSizes.contains(token.text) else { return nil }
        let text = token.text.uppercased()
        return VariantValue(canonical: text, display: "tam. \(text)")
    }

    /// O campo `size` do template ("16", "M", "Único") — `nil` pra vazio e tamanho único, que muita
    /// loja deixa como padrão sem significar nada.
    static func templateSize(_ raw: String?, preferRingLabel: Bool) -> VariantValue? {
        guard let raw else { return nil }
        let tokens = tokens(raw)
        guard tokens.count == 1, let token = tokens.first, !["unico", "u", "unica"].contains(token.text) else { return nil }
        if let number = token.number, number == number.rounded(), number >= 1, number <= 60 {
            let text = String(Int(number))
            return VariantValue(canonical: text, display: preferRingLabel ? "aro \(text)" : "tam. \(text)")
        }
        guard letterSizes.contains(token.text) else { return nil }
        let text = token.text.uppercased()
        return VariantValue(canonical: text, display: "tam. \(text)")
    }

    /// O texto fala em "aro" — pra mostrar o tamanho do template como "aro 16" em vez de "tam. 16".
    static func mentionsRing(_ tokens: [Token]) -> Bool {
        tokens.contains { ringSizeTriggers.contains($0.text) }
    }

    // MARK: - Medidas

    private static let measureContext: Set = [
        "comprimento", "corrente", "colar", "cordao", "gargantilha", "pulseira", "tornozeleira", "choker", "argola", "diametro"
    ]

    private static func measures(in tokens: [Token], source: Source, consumed: inout Set<Int>) -> [VariantValue] {
        var found: [VariantValue] = []
        for (offset, token) in tokens.enumerated() where offset + 1 < tokens.count && !consumed.contains(offset) {
            guard let number = token.number, number > 0 else { continue }
            let unit = tokens[offset + 1].text
            let millimeters: Double
            let unitLabel: String
            switch unit {
            case "mm", "milimetros":
                millimeters = number
                unitLabel = "mm"
            case "cm", "centimetros":
                millimeters = number * 10
                unitLabel = "cm"
            default:
                continue
            }
            if source == .description {
                let context = tokens[max(0, offset - 3)..<offset]
                guard context.contains(where: { measureContext.contains($0.text) }) else { continue }
            }
            guard millimeters <= 3000 else { continue }
            let canonical = String(format: "%.1f", millimeters)
            found.append(VariantValue(canonical: canonical, display: "\(formatted(number)) \(unitLabel)"))
            consumed.formUnion([offset, offset + 1])
        }
        return found
    }

    private static func formatted(_ number: Double) -> String {
        number == number.rounded() ? String(Int(number)) : String(format: "%.1f", number).replacingOccurrences(of: ".", with: ",")
    }

    // MARK: - Cor da pedra

    /// Cada cor no feminino (zircônia é feminino) — "branco" e "branca" são a mesma.
    private static let colorNames: [String: String] = [
        "branca": "branca", "branco": "branca", "rosa": "rosa", "pink": "rosa", "azul": "azul", "verde": "verde",
        "vermelha": "vermelha", "vermelho": "vermelha", "preta": "preta", "preto": "preta", "negra": "preta", "negro": "preta",
        "lilas": "lilás", "roxa": "roxa", "roxo": "roxa", "amarela": "amarela", "amarelo": "amarela", "laranja": "laranja",
        "cristal": "cristal", "transparente": "cristal", "incolor": "cristal", "colorida": "colorida", "colorido": "colorida",
        "multicolor": "colorida", "champagne": "champagne", "champanhe": "champagne", "fume": "fumê", "turquesa": "turquesa",
        "marsala": "marsala", "nude": "nude", "bege": "bege", "marrom": "marrom", "cinza": "cinza", "vinho": "vinho"
    ]

    private static let stoneContext: Set = [
        "zirconia", "zirconias", "pedra", "pedras", "cristal", "cristais", "strass", "perola", "perolas", "esmalte",
        "resina", "cor", "cores", "cravejado", "cravejada"
    ]

    private static func colors(in tokens: [Token], source: Source, consumed: Set<Int>) -> [VariantValue] {
        var found: [VariantValue] = []
        for (offset, token) in tokens.enumerated() where !consumed.contains(offset) {
            guard let name = colorName(token.text) else { continue }
            if source == .description {
                let context = tokens[max(0, offset - 2)..<offset]
                guard context.contains(where: { stoneContext.contains($0.text) }) else { continue }
            }
            found.append(VariantValue(canonical: name, display: name))
        }
        return found
    }

    private static func colorName(_ word: String) -> String? {
        if let name = colorNames[word] { return name }
        // "brancas", "rosas", "azuis" (este fica de fora: plural irregular raro em título).
        if word.count > 4, word.hasSuffix("s") { return colorNames[String(word.dropLast())] }
        return nil
    }

    // MARK: - Vocabulário de variante

    /// Palavras que só dizem a versão — saem do título/descrição "base" (o que identifica o produto
    /// independente da versão). Já no formato de `ProductSimilarity.tokenize` (singular, sem acento).
    static let variantVocabulary: Set<String> = {
        var words: Set<String> = [
            "aro", "tam", "tamanho", "numero", "num", "numeracao", "cm", "mm", "centimetro", "milimetro",
            "k", "banho", "banhado", "banhada", "folheado", "folheada", "rodio", "rodinado", "rodinada", "rodiado", "rodiada",
            "ouro", "rose", "gold", "rosegold", "dourado", "dourada", "prateado", "prateada", "prata", "negro", "preto", "black"
        ]
        words.formUnion(letterSizes)
        words.formUnion(colorNames.keys)
        return words
    }()

    /// Preposições e artigos que sobram de "banho **de** ouro", "aro 16 **com** pedra" — sem eles, a
    /// versão que diz o banho e a que não diz ficam com o mesmo título base.
    private static let stopWords: Set = ["de", "da", "do", "com", "e", "em", "a", "o", "para", "na", "no", "um", "uma"]

    /// Tira o vocabulário de variante, preposições/artigos e tudo que começa com número ("16", "925",
    /// "50mm", "18k") de um conjunto de palavras já tokenizado.
    static func baseWords(_ words: Set<String>) -> Set<String> {
        words.filter { word in !variantVocabulary.contains(word) && !stopWords.contains(word) && word.first?.isNumber != true }
    }
}
