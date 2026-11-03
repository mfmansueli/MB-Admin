import Foundation
import Testing
@testable import MB_Admin

@Suite("resultado da comparação depois do filtro e da busca")
struct ComparisonFilteredResultTests {
    typealias Fixtures = ComparisonFixtures

    private var result: AccountComparisonResult {
        Fixtures.result(
            matches: [Fixtures.match(1, 2, titleA: "brinco argola estrela", titleB: "argola estrela leve")],
            reviews: [Fixtures.match(6, 7, status: .needsReview, titleA: "anel solitário", titleB: "anel solitário rosa")],
            rejected: [Fixtures.match(8, 9, status: .rejected, titleA: "colar curto", titleB: "colar longo")],
            missingInB: [Fixtures.product(3, title: "colar coração", cover: nil), Fixtures.product(4, title: "anel aro 17", cover: nil)],
            missingInA: [Fixtures.product(5, title: "pulseira elos", cover: nil)],
            unverifiedA: [UnverifiedListing(product: Fixtures.product(10, title: "tornozeleira", cover: nil), reasons: [.detailsUnavailable])],
            unverifiedB: [UnverifiedListing(product: Fixtures.product(11, title: "piercing", cover: nil), reasons: [.photosFailed(2)])],
            families: [
                Fixtures.family("familia-A3", title: "colar coração", versions: [
                    ProductFamilyVersion(label: "45 cm", productA: Fixtures.product(3, title: "colar coração", cover: nil), productB: nil, presence: .onlyInA),
                    ProductFamilyVersion(
                        label: "60 cm", productA: nil, productB: Fixtures.product(12, title: "gargantilha coração", cover: nil), presence: .onlyInB
                    )
                ])
            ]
        )
    }

    @Test("sem filtro nem busca, mostra todas as seções inteiras")
    func semFiltro() {
        let filtered = ComparisonFilteredResult(result: result, filter: .all, searchText: "")

        #expect(filtered.matches.map(\.id) == ["1-2"])
        #expect(filtered.reviews.map(\.id) == ["6-7"])
        #expect(filtered.rejected.map(\.id) == ["8-9"])
        #expect(filtered.missingInB.map(\.id) == [3, 4])
        #expect(filtered.missingInA.map(\.id) == [5])
        #expect(filtered.unverifiedA.map(\.product.id) == [10])
        #expect(filtered.unverifiedB.map(\.product.id) == [11])
        #expect(filtered.families.map(\.id) == ["familia-A3"])
    }

    @Test("o filtro deixa só a seção escolhida", arguments: ComparisonResultFilter.allCases.filter { $0 != .all })
    func filtroDeixaUmaSecao(filter: ComparisonResultFilter) {
        let filtered = ComparisonFilteredResult(result: result, filter: filter, searchText: "")
        #expect(filtered.matches.isEmpty == (filter != .matches))
        #expect(filtered.reviews.isEmpty == (filter != .review))
        #expect(filtered.families.isEmpty == (filter != .variants))
        #expect(filtered.rejected.isEmpty == (filter != .rejected))
        #expect(filtered.missingInB.isEmpty == (filter != .missingInB))
        #expect(filtered.missingInA.isEmpty == (filter != .missingInA))
        #expect(filtered.unverifiedA.isEmpty == (filter != .unverified))
        #expect(filtered.unverifiedB.isEmpty == (filter != .unverified))
    }

    @Test("a busca acha um par também pelo nome que ele tem na outra conta")
    func buscaPeloNomeDaOutraConta() {
        let filtered = ComparisonFilteredResult(result: result, filter: .all, searchText: "LEVE")

        #expect(filtered.matches.count == 1)
        #expect(filtered.reviews.isEmpty)
        #expect(filtered.missingInB.isEmpty)
        #expect(filtered.missingInA.isEmpty)
    }

    @Test("a busca acha uma família pelo título de qualquer versão, das duas lojas")
    func buscaNasFamilias() {
        #expect(ComparisonFilteredResult(result: result, filter: .variants, searchText: "gargantilha").families.count == 1)
        #expect(ComparisonFilteredResult(result: result, filter: .variants, searchText: "pulseira").families.isEmpty)
    }

    @Test("a busca também filtra os não verificados")
    func buscaNosNaoVerificados() {
        let filtered = ComparisonFilteredResult(result: result, filter: .unverified, searchText: "pier")
        #expect(filtered.unverifiedA.isEmpty)
        #expect(filtered.unverifiedB.map(\.product.id) == [11])
    }

    @Test("só os possivelmente ausentes entram na seleção — par, revisão e não verificado nunca")
    func selecionaveis() {
        let filtered = ComparisonFilteredResult(result: result, filter: .all, searchText: " ")

        #expect(filtered.selectableIDs == [3, 4, 5])
    }

    @Test("busca sem nenhum resultado deixa tudo vazio")
    func buscaSemResultado() {
        #expect(ComparisonFilteredResult(result: result, filter: .all, searchText: "nada disso").isEmpty)
    }
}
