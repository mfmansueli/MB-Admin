import Foundation
import Testing
@testable import MB_Admin

@Suite("filtro do resultado da comparação")
struct ComparisonResultFilterTests {
    typealias Fixtures = ComparisonFixtures

    private let result = Fixtures.result(
        matches: [Fixtures.match(1, 2)],
        reviews: [Fixtures.match(6, 7, status: .needsReview), Fixtures.match(8, 9, status: .needsReview)],
        rejected: [Fixtures.match(10, 11, status: .rejected)],
        missingInB: [Fixtures.product(3, title: "colar", cover: nil), Fixtures.product(4, title: "anel", cover: nil)],
        missingInA: [Fixtures.product(5, title: "pulseira", cover: nil)],
        unverifiedB: [UnverifiedListing(product: Fixtures.product(12, title: "brinco", cover: nil), reasons: [.noUsablePhoto])]
    )

    private func label(_ filter: ComparisonResultFilter) -> String {
        filter.label(result: result, accountAName: "loja A", accountBName: "loja B")
    }

    @Test("cada opção do menu diz quantos produtos mostra — \"ausentes em B\" são produtos de A")
    func rotulos() {
        #expect(label(.all) == "todos (8)")
        #expect(label(.matches) == "mesmo produto (1)")
        #expect(label(.review) == "precisa revisar (2)")
        #expect(label(.missingInB) == "possivelmente ausentes em loja B (2)")
        #expect(label(.missingInA) == "possivelmente ausentes em loja A (1)")
        #expect(label(.unverified) == "não verificados (1)")
        #expect(label(.rejected) == "marcados como diferentes (1)")
    }

    @Test("\"todos\" inclui qualquer seção; os outros, só a própria")
    func inclui() {
        #expect(ComparisonResultFilter.all.includes(.missingInA))
        #expect(ComparisonResultFilter.matches.includes(.matches))
        #expect(!ComparisonResultFilter.matches.includes(.review))
        #expect(!ComparisonResultFilter.unverified.includes(.missingInB))
    }
}
