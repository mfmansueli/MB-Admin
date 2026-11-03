import Foundation
import Testing
@testable import MB_Admin

@Suite("candidatos por texto")
struct TextCandidateIndexTests {
    private func words(_ title: String) -> Set<String> { ProductSimilarity.tokenize(title) }

    @Test("só pares a partir do limite, e com pelo menos uma palavra em comum")
    func limite() {
        let candidates = TextCandidateIndex.candidates(
            wordsA: [words("colar curto prata 925 zircônia branca"), words("brinco argola ouro")],
            wordsB: [words("colar curto prata 925 zircônia"), words("tênis esportivo azul")]
        )
        #expect(candidates.map { [$0.indexA, $0.indexB] } == [[0, 0]])
    }

    @Test("título genérico não casa com a loja toda: só os melhores dos dois lados sobrevivem")
    func mutuoTopK() {
        let generic = words("brinco prata 925")
        let candidates = TextCandidateIndex.candidates(
            wordsA: [generic],
            wordsB: Array(repeating: generic, count: 6),
            maxPerListing: 3
        )
        #expect(candidates.count == 3)
    }
}
