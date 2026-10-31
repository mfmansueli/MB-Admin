import Foundation
import Testing
@testable import MB_Admin

@Suite("ativar em N da aba sem preço esperto")
struct SmartPriceBulkActivationTests {
    private func item(id: Int, blocked: Bool = false, smartPriceEnabled: Bool = false) -> SmartPriceListItem {
        SmartPriceListItem(
            product: SmartPriceProduct(
                id: id, price: 100, minPrice: 80, maxPrice: 110, blocked: blocked,
                smartPriceEnabled: smartPriceEnabled, statusText: "preço atual", statusColor: "#1A7F37",
                photoPublicID: nil
            ),
            matched: nil
        )
    }

    private func activation(
        _ items: [SmartPriceListItem],
        filter: SmartPriceStatusFilter = .current,
        statuses: [Int: MegaphoneStatus] = [:],
        isSearching: Bool = false
    ) -> SmartPriceBulkActivation {
        SmartPriceBulkActivation(items: items, filter: filter, activationStatuses: statuses, isSearching: isSearching)
    }

    @Test("entram os da lista sem bloqueio, sem preço esperto e fora da fila de ativar, na ordem da lista")
    func idsElegiveis() {
        let items = [
            item(id: 1),
            item(id: 2, blocked: true),
            item(id: 3),
            item(id: 4),
            item(id: 5),
            item(id: 6),
            item(id: 7, smartPriceEnabled: true)
        ]

        let result = activation(items, statuses: [3: .succeeded, 4: .pending, 5: .megaphoning, 6: .failed("504")])

        // Quem falhou antes entra de novo.
        #expect(result.eligibleIDs == [1, 6])
        #expect(result.count == 2)
        #expect(result.blockedCount == 1)
        #expect(result.activatingCount == 2)
    }

    @Test("título com o nome do filtro, sem ele em \"todos\"")
    func tituloComOFiltro() {
        let items = (1...6).map { item(id: $0) }

        #expect(activation(items, filter: .current).title == "6 produtos com preço atual")
        #expect(activation(items, filter: .high).title == "6 produtos com preço alto, venda lenta")
        #expect(activation(items, filter: .all).title == "6 produtos")
        #expect(activation([item(id: 1)], filter: .low).title == "1 produto com preço baixo")
    }

    @Test("nada pra ativar: título diz, botão sem número")
    func nadaPraAtivar() {
        let result = activation([item(id: 1, blocked: true)])

        #expect(result.count == 0)
        #expect(result.title == "nada pra ativar com preço atual")
        #expect(result.buttonLabel == "ativar")
    }

    @Test("subtítulo: bloqueados que ficam de fora, no singular e no plural")
    func subtituloComBloqueados() {
        #expect(activation([item(id: 1), item(id: 2, blocked: true)]).subtitle == "1 bloqueado fica de fora")
        #expect(
            activation([item(id: 1), item(id: 2, blocked: true), item(id: 3, blocked: true)]).subtitle
                == "2 bloqueados ficam de fora"
        )
    }

    @Test("subtítulo sem bloqueados: só os que aparecem na lista, ou só os da busca")
    func subtituloSemBloqueados() {
        #expect(activation([item(id: 1)]).subtitle == "só os que aparecem na lista")
        #expect(activation([item(id: 1)], isSearching: true).subtitle == "só os da busca")
    }

    @Test("enquanto ativa: quantos faltam e como acompanhar")
    func ativando() {
        let result = activation(
            [item(id: 1), item(id: 2), item(id: 3), item(id: 4, blocked: true)],
            statuses: [1: .succeeded, 2: .megaphoning, 3: .pending]
        )

        #expect(result.isActivating)
        #expect(result.title == "ativando… faltam 2")
        #expect(result.subtitle == "um de cada vez, acompanhe pelo ícone de cada linha")
        #expect(result.compactSummary == "ativando… faltam 2")
    }

    @Test("botão conta os elegíveis")
    func rotuloDoBotao() {
        #expect(activation((1...6).map { item(id: $0) }).buttonLabel == "ativar em 6")
    }

    @Test("resumo de uma linha do iPhone leva os bloqueados junto")
    func resumoCompacto() {
        #expect(activation([item(id: 1), item(id: 2, blocked: true)]).compactSummary == "1 produto com preço atual · 1 bloqueado")
        #expect(activation([item(id: 1)]).compactSummary == "1 produto com preço atual")
    }

    @Test("alerta: título com o filtro e a mensagem avisando dos bloqueados")
    func alerta() {
        let base = "cada anúncio é ativado um de cada vez, com um intervalo entre um e o próximo — "
            + "acompanhe o andamento pelo ícone de cada linha."
        let items = (1...6).map { item(id: $0) } + [item(id: 7, blocked: true)]

        let one = activation(items)
        let none = activation((1...6).map { item(id: $0) }, filter: .all)
        let two = activation(items + [item(id: 8, blocked: true)])

        #expect(one.confirmationTitle == "ativar preço esperto em 6 produtos com preço atual?")
        #expect(one.confirmationMessage == base + " 1 produto bloqueado fica de fora.")
        #expect(none.confirmationTitle == "ativar preço esperto em 6 produtos?")
        #expect(none.confirmationMessage == base)
        #expect(two.confirmationMessage == base + " 2 produtos bloqueados ficam de fora.")
    }
}
