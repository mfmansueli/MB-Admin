import Foundation

/// Compara títulos de produto por similaridade, não por igualdade — dois produtos "quase iguais"
/// (mesma peça, uma palavra a mais ou a menos entre título de duas contas diferentes) devem pontuar
/// alto, não zero.
nonisolated enum ProductSimilarity {
    /// Similaridade de Jaccard entre os conjuntos de palavras normalizadas dos dois títulos —
    /// `|interseção| / |união|`, de `0` (nada em comum) a `1` (mesmo conjunto de palavras).
    /// Robusto à ordem das palavras; sensível ao tamanho do título (poucas palavras diferentes
    /// pesam mais num título curto do que num longo, o que já é o comportamento desejado).
    static func score(_ titleA: String, _ titleB: String) -> Double {
        let tokensA = tokenize(titleA)
        let tokensB = tokenize(titleB)
        guard !tokensA.isEmpty, !tokensB.isEmpty else { return 0 }
        let intersection = tokensA.intersection(tokensB).count
        let union = tokensA.union(tokensB).count
        guard union > 0 else { return 0 }
        return Double(intersection) / Double(union)
    }

    /// Minúsculas, sem acento, sem pontuação, separado em palavras — pra "Colar Curto!" e "colar
    /// curto" (ou "colár cürto") virarem o mesmo conjunto de tokens.
    static func tokenize(_ title: String) -> Set<String> {
        let folded = title
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let words = folded
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return Set(words)
    }
}
