import Foundation
import Testing
@testable import MB_Admin

@Suite("seções da aba publicados")
struct PublishedProductSectionsTests {
    /// `suggestedPrice` nil = produto que não pede desconto; `currentPrice` nil = sem desconto já
    /// aplicado (preço atual igual ao original).
    private func item(
        id: Int,
        originalPrice: Double = 100,
        currentPrice: Double? = nil,
        suggestedPrice: Double? = nil
    ) -> MegaphoneItem {
        let product = EnjoeiProduct(
            id: id,
            title: "produto \(id)",
            path: "produto-\(id)",
            photoPublicID: nil,
            currentPrice: currentPrice ?? originalPrice,
            originalPrice: originalPrice
        )
        guard let suggestedPrice else { return MegaphoneItem(product: product) }
        return MegaphoneItem(
            product: product,
            exposure: MegaphoneExposure(
                productID: id,
                kind: .maximumAfterDiscount,
                priceToIncreaseExposure: suggestedPrice,
                discountLabel: nil
            )
        )
    }

    @Test("cada produto entra numa seção só: os que pedem desconto separados do resto")
    func separaPorDesconto() {
        let items = [item(id: 1), item(id: 2, suggestedPrice: 80), item(id: 3)]

        let sections = PublishedProductSections(items: items, filter: .all, matchingIDs: nil)

        #expect(sections.discount.map(\.id) == [2])
        #expect(sections.others.map(\.id) == [1, 3])
    }

    @Test("os que pedem desconto vêm em ordem crescente de desconto sugerido")
    func ordenaPorDescontoCrescente() {
        let items = [
            item(id: 1, suggestedPrice: 44), // 56%
            item(id: 2, suggestedPrice: 85), // 15%
            item(id: 3, suggestedPrice: 70) // 30%
        ]

        let sections = PublishedProductSections(items: items, filter: .all, matchingIDs: nil)

        #expect(sections.discount.map(\.id) == [2, 3, 1])
    }

    @Test("o resto vem do maior desconto já aplicado pro menor, os sem desconto no fim")
    func restoOrdenaPorDescontoAplicadoDecrescente() {
        let items = [
            item(id: 1), // sem desconto
            item(id: 2, currentPrice: 90), // 10%
            item(id: 3, currentPrice: 50), // 50%
            item(id: 4), // sem desconto
            item(id: 5, currentPrice: 70) // 30%
        ]

        let sections = PublishedProductSections(items: items, filter: .all, matchingIDs: nil)

        #expect(sections.others.map(\.id) == [3, 5, 2, 1, 4])
    }

    @Test("desconto aplicado empatado mantém a ordem da loja")
    func empateMantemOrdemDaLoja() {
        let items = [
            item(id: 7, currentPrice: 80), // 20%
            item(id: 3, currentPrice: 60), // 40%
            item(id: 9, currentPrice: 80), // 20%
            item(id: 1, currentPrice: 80) // 20%
        ]

        let sections = PublishedProductSections(items: items, filter: .all, matchingIDs: nil)

        #expect(sections.others.map(\.id) == [3, 7, 9, 1])
    }

    @Test("os que pedem desconto continuam pelo desconto sugerido, não pelo já aplicado")
    func secaoDescontoIgnoraDescontoAplicado() {
        let items = [
            item(id: 1, currentPrice: 50, suggestedPrice: 70), // aplicado 50%, sugerido 30%
            item(id: 2, currentPrice: 95, suggestedPrice: 85) // aplicado 5%, sugerido 15%
        ]

        let sections = PublishedProductSections(items: items, filter: .all, matchingIDs: nil)

        #expect(sections.discount.map(\.id) == [2, 1])
    }

    @Test("busca mantém a ordem por desconto aplicado entre os que bateram")
    func buscaMantemOrdemPorDescontoAplicado() {
        let items = [
            item(id: 1, currentPrice: 90), // 10%
            item(id: 2, currentPrice: 40), // 60%
            item(id: 3, currentPrice: 75) // 25%
        ]

        let sections = PublishedProductSections(items: items, filter: .all, matchingIDs: [1, 3])

        #expect(sections.others.map(\.id) == [3, 1])
    }

    @Test("filtro \"produtos pedem desconto\" esvazia o resto")
    func filtroSoDesconto() {
        let items = [item(id: 1), item(id: 2, suggestedPrice: 80)]

        let sections = PublishedProductSections(items: items, filter: .discountOnly, matchingIDs: nil)

        #expect(sections.discount.map(\.id) == [2])
        #expect(sections.others.isEmpty)
    }

    @Test("busca mantém só os ids que bateram, nas duas seções")
    func buscaFiltraAsDuasSecoes() {
        let items = [item(id: 1), item(id: 2, suggestedPrice: 80), item(id: 3), item(id: 4, suggestedPrice: 50)]

        let sections = PublishedProductSections(items: items, filter: .all, matchingIDs: [2, 3])

        #expect(sections.discount.map(\.id) == [2])
        #expect(sections.others.map(\.id) == [3])
    }

    @Test("busca sem nenhum resultado deixa tudo vazio")
    func buscaSemResultado() {
        let sections = PublishedProductSections(items: [item(id: 1)], filter: .all, matchingIDs: [])
        #expect(sections.isEmpty)
    }

    @Test("ids visíveis pulam as seções recolhidas, na ordem da tela")
    func idsVisiveis() {
        let items = [item(id: 1), item(id: 2, suggestedPrice: 80), item(id: 3)]
        let sections = PublishedProductSections(items: items, filter: .all, matchingIDs: nil)

        #expect(sections.visibleIDs(collapsed: []) == [2, 1, 3])
        #expect(sections.visibleIDs(collapsed: [.discount]) == [1, 3])
        #expect(sections.visibleIDs(collapsed: [.others]) == [2])
        #expect(sections.visibleIDs(collapsed: [.discount, .others]).isEmpty)
    }

    @Test("selecionar todos marca os que faltam do grupo, sem mexer no resto da seleção")
    func selecionarTodosMarcaOsQueFaltam() {
        let toggled = PublishedProductSections.togglingAll([1, 2, 3], in: [2, 9])
        #expect(toggled == [1, 2, 3, 9])
    }

    @Test("com o grupo todo marcado, desmarca só ele")
    func selecionarTodosDesmarcaSoOGrupo() {
        let toggled = PublishedProductSections.togglingAll([1, 2, 3], in: [1, 2, 3, 9])
        #expect(toggled == [9])
    }

    @Test("grupo vazio não mexe na seleção")
    func selecionarTodosGrupoVazio() {
        #expect(PublishedProductSections.togglingAll([], in: [4]) == [4])
    }
}
