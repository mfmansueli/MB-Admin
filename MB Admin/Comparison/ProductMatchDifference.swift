import Foundation

/// As palavras (já normalizadas: minúsculas, sem acento, no singular — ver
/// `ProductSimilarity.tokenize`) que só aparecem de um lado do par — o que o texto dos dois tem de
/// diferente, pra quem está revisando.
/// Calculado sob demanda (`init`), nunca guardado por linha da lista — tokenizar título+descrição
/// de cada par pra toda a lista de "produtos em comum" seria trabalho refeito à toa pra quem nunca
/// abre o detalhe de nenhum. `ComparisonPairDetailSheet` só cria isto dentro do `.sheet`, que o
/// SwiftUI só avalia quando o usuário efetivamente abre.
nonisolated struct ProductMatchDifference {
    let onlyInA: [String]
    let onlyInB: [String]

    init(match: ProductMatch) {
        let tokensA = ProductSimilarity.tokenize(AccountProductMatcher.comparableText(for: match.productA))
        let tokensB = ProductSimilarity.tokenize(AccountProductMatcher.comparableText(for: match.productB))
        onlyInA = tokensA.subtracting(tokensB).sorted()
        onlyInB = tokensB.subtracting(tokensA).sorted()
    }
}
