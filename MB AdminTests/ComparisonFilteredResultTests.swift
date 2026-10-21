import Foundation
import Testing
@testable import MB_Admin

@Suite("resultado da comparação depois do filtro e da busca")
struct ComparisonFilteredResultTests {
    private func product(_ id: Int, title: String) -> EnjoeiProduct {
        EnjoeiProduct(id: id, title: title, path: "p-\(id)", photoPublicID: nil, currentPrice: 100, originalPrice: 100)
    }

    private var result: AccountComparisonResult {
        AccountComparisonResult(
            matches: [
                ProductMatch(
                    productA: product(1, title: "brinco argola estrela"),
                    productB: product(2, title: "argola estrela leve"),
                    similarity: 0.82
                )
            ],
            onlyInA: [product(3, title: "colar coração"), product(4, title: "anel aro 17")],
            onlyInB: [product(5, title: "pulseira elos")]
        )
    }

    @Test("sem filtro nem busca, mostra as três seções inteiras")
    func semFiltro() {
        let filtered = ComparisonFilteredResult(result: result, filter: .all, searchText: "")

        #expect(filtered.matches.count == 1)
        #expect(filtered.onlyInA.map(\.id) == [3, 4])
        #expect(filtered.onlyInB.map(\.id) == [5])
    }

    @Test("o filtro deixa só a seção escolhida")
    func filtroDeixaUmaSecao() {
        let onlyMatches = ComparisonFilteredResult(result: result, filter: .matches, searchText: "")
        #expect(onlyMatches.matches.count == 1)
        #expect(onlyMatches.onlyInA.isEmpty)
        #expect(onlyMatches.onlyInB.isEmpty)

        let onlyInB = ComparisonFilteredResult(result: result, filter: .onlyInB, searchText: "")
        #expect(onlyInB.matches.isEmpty)
        #expect(onlyInB.onlyInA.isEmpty)
        #expect(onlyInB.onlyInB.map(\.id) == [5])
    }

    @Test("a busca acha um par também pelo nome que ele tem na outra conta")
    func buscaPeloNomeDaOutraConta() {
        let filtered = ComparisonFilteredResult(result: result, filter: .all, searchText: "LEVE")

        #expect(filtered.matches.count == 1)
        #expect(filtered.onlyInA.isEmpty)
        #expect(filtered.onlyInB.isEmpty)
    }

    @Test("só os produtos que faltam numa conta entram na seleção — os pares nunca")
    func selecionaveis() {
        let filtered = ComparisonFilteredResult(result: result, filter: .all, searchText: " ")

        #expect(filtered.selectableIDs == [3, 4, 5])
    }

    @Test("busca sem nenhum resultado deixa tudo vazio")
    func buscaSemResultado() {
        #expect(ComparisonFilteredResult(result: result, filter: .all, searchText: "nada disso").isEmpty)
    }
}
