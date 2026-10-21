import Foundation
import Testing
@testable import MB_Admin

@Suite("filtro do resultado da comparação")
struct ComparisonResultFilterTests {
    private let result = AccountComparisonResult(
        matches: [
            ProductMatch(productA: EnjoeiFixtures.product(id: 1), productB: EnjoeiFixtures.product(id: 2), similarity: 0.9)
        ],
        onlyInA: [EnjoeiFixtures.product(id: 3), EnjoeiFixtures.product(id: 4)],
        onlyInB: [EnjoeiFixtures.product(id: 5)]
    )

    @Test("cada opção do menu diz quantos produtos mostra — \"só em A\" é o que falta em B")
    func rotulos() {
        #expect(ComparisonResultFilter.all.label(result: result, accountAName: "loja A", accountBName: "loja B") == "todos (4)")
        #expect(ComparisonResultFilter.matches.label(result: result, accountAName: "loja A", accountBName: "loja B") == "em comum (1)")
        #expect(
            ComparisonResultFilter.onlyInA.label(result: result, accountAName: "loja A", accountBName: "loja B")
                == "não encontrados em loja B (2)"
        )
        #expect(
            ComparisonResultFilter.onlyInB.label(result: result, accountAName: "loja A", accountBName: "loja B")
                == "não encontrados em loja A (1)"
        )
    }

    @Test("\"todos\" inclui qualquer seção; os outros, só a própria")
    func inclui() {
        #expect(ComparisonResultFilter.all.includes(.onlyInB))
        #expect(ComparisonResultFilter.matches.includes(.matches))
        #expect(!ComparisonResultFilter.matches.includes(.onlyInA))
    }
}
