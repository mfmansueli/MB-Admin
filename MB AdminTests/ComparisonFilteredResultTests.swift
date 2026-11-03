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
            ],
            duplicatesA: [Fixtures.duplicates(Fixtures.sellerA, [
                Fixtures.product(13, title: "brinco gota", cover: nil), Fixtures.product(14, title: "brinco gota", cover: nil)
            ])],
            duplicatesB: [Fixtures.duplicates(Fixtures.sellerB, [
                Fixtures.product(15, title: "choker veludo", cover: nil), Fixtures.product(16, title: "choker veludo", cover: nil)
            ], status: .possible)],
            dismissedDuplicates: [Fixtures.duplicates(Fixtures.sellerA, [
                Fixtures.product(17, title: "argola lisa", cover: nil), Fixtures.product(18, title: "argola lisa", cover: nil)
            ], status: .dismissed)]
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
        #expect(filtered.duplicatesA.map(\.title) == ["brinco gota"])
        #expect(filtered.duplicatesB.map(\.title) == ["choker veludo"])
        #expect(filtered.dismissedDuplicates.map(\.title) == ["argola lisa"])
    }

    @Test("o filtro deixa só a seção escolhida", arguments: ComparisonResultFilter.allCases.filter { $0 != .all })
    func filtroDeixaUmaSecao(filter: ComparisonResultFilter) {
        let filtered = ComparisonFilteredResult(result: result, filter: filter, searchText: "")
        #expect(filtered.matches.isEmpty == (filter != .matches))
        #expect(filtered.reviews.isEmpty == (filter != .review))
        #expect(filtered.families.isEmpty == (filter != .variants))
        #expect(filtered.duplicatesA.isEmpty == (filter != .duplicates))
        #expect(filtered.duplicatesB.isEmpty == (filter != .duplicates))
        #expect(filtered.rejected.isEmpty == (filter != .rejected))
        // Os não repetidos ficam junto dos pares marcados como diferentes.
        #expect(filtered.dismissedDuplicates.isEmpty == (filter != .rejected))
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

    @Test("a busca acha os repetidos de cada loja pelo título de qualquer anúncio do grupo")
    func buscaNosRepetidos() {
        let filtered = ComparisonFilteredResult(result: result, filter: .all, searchText: "choker")
        #expect(filtered.duplicatesA.isEmpty)
        #expect(filtered.duplicatesB.map(\.title) == ["choker veludo"])
        #expect(ComparisonFilteredResult(result: result, filter: .rejected, searchText: "argola").dismissedDuplicates.count == 1)
    }

    @Test("o filtro de repetidos conta os grupos das duas lojas; \"todos\" não soma os grupos de novo")
    func rotuloDosRepetidos() {
        #expect(ComparisonResultFilter.duplicates.label(result: result, accountAName: "antonia", accountBName: "loja B") == "repetidos na mesma loja (2)")
        #expect(ComparisonResultFilter.all.label(result: result, accountAName: "antonia", accountBName: "loja B") == "todos (8)")
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
