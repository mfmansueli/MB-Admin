import Foundation

/// Detalha por que um `ProductMatch` não fechou 100% — as palavras (já normalizadas: minúsculas,
/// sem acento, no singular — ver `ProductSimilarity.tokenize`) que só aparecem de um lado do par.
/// Calculado sob demanda (`init`), nunca guardado por linha da lista — tokenizar título+descrição
/// de cada par pra toda a lista de "produtos em comum" seria trabalho refeito à toa pra quem nunca
/// abre o detalhe de nenhum. `ProductMatchDifferenceSheet` só cria isto dentro do `.sheet`, que o
/// SwiftUI só avalia quando o usuário efetivamente abre.
nonisolated struct ProductMatchDifference {
    let onlyInA: [String]
    let onlyInB: [String]
    let similarity: Double

    init(match: ProductMatch) {
        let tokensA = ProductSimilarity.tokenize(AccountProductMatcher.comparableText(for: match.productA))
        let tokensB = ProductSimilarity.tokenize(AccountProductMatcher.comparableText(for: match.productB))
        onlyInA = tokensA.subtracting(tokensB).sorted()
        onlyInB = tokensB.subtracting(tokensA).sorted()
        similarity = match.similarity
    }
}
