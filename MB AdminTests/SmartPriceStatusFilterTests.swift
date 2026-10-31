import Foundation
import Testing
@testable import MB_Admin

@Suite("filtro de status da aba sem preço esperto")
struct SmartPriceStatusFilterTests {
    private func makeProduct(
        id: Int = 1,
        statusText: String?,
        statusColor: String? = nil,
        smartPriceEnabled: Bool = false
    ) -> SmartPriceProduct {
        SmartPriceProduct(
            id: id, price: 100, minPrice: 70, maxPrice: 150, blocked: false, smartPriceEnabled: smartPriceEnabled,
            statusText: statusText, statusColor: statusColor, photoPublicID: nil
        )
    }

    @Test(".all casa com qualquer produto, mesmo sem statusText")
    func todosCasaComQualquerProduto() {
        #expect(SmartPriceStatusFilter.all.matches(makeProduct(statusText: nil)))
        #expect(SmartPriceStatusFilter.all.matches(makeProduct(statusText: "preço atual")))
        #expect(SmartPriceStatusFilter.all.matches(makeProduct(statusText: "preço alto, venda lenta")))
    }

    @Test(".current casa só com \"preço atual\"")
    func atualCasaSoComPrecoAtual() {
        #expect(SmartPriceStatusFilter.current.matches(makeProduct(statusText: "preço atual")))
        #expect(!SmartPriceStatusFilter.current.matches(makeProduct(statusText: "preço alto, venda lenta")))
        #expect(!SmartPriceStatusFilter.current.matches(makeProduct(statusText: "preço baixo, lucre mais")))
        #expect(!SmartPriceStatusFilter.current.matches(makeProduct(statusText: nil)))
    }

    @Test(".high casa com qualquer rótulo que mencione \"alto\"")
    func altoCasaComORotuloDeVendaLenta() {
        #expect(SmartPriceStatusFilter.high.matches(makeProduct(statusText: "preço alto, venda lenta")))
        #expect(!SmartPriceStatusFilter.high.matches(makeProduct(statusText: "preço atual")))
        #expect(!SmartPriceStatusFilter.high.matches(makeProduct(statusText: "preço baixo, lucre mais")))
    }

    @Test(".low casa com qualquer rótulo que mencione \"baixo\"")
    func baixoCasaComORotuloDeLucreMais() {
        #expect(SmartPriceStatusFilter.low.matches(makeProduct(statusText: "preço baixo, lucre mais")))
        #expect(!SmartPriceStatusFilter.low.matches(makeProduct(statusText: "preço atual")))
        #expect(!SmartPriceStatusFilter.low.matches(makeProduct(statusText: "preço alto, venda lenta")))
    }

    @Test("cápsulas na ordem preço atual, alto, baixo e todos — preço atual é o padrão")
    func ordemEPadrao() {
        #expect(SmartPriceStatusFilter.allCases == [.current, .high, .low, .all])
        #expect(SmartPriceStatusFilter.defaultFilter == .current)
    }

    @Test("raw value e chave por conta, pro filtro sobreviver a trocar de conta e voltar")
    func guardadoPorConta() throws {
        #expect(SmartPriceStatusFilter.allCases.map(\.rawValue) == ["current", "high", "low", "all"])
        #expect(SmartPriceStatusFilter(rawValue: "high") == .high)
        let accountID = try #require(UUID(uuidString: "DE300000-0000-0000-0000-00000000000A"))
        #expect(SmartPriceStatusFilter.storageKey(for: accountID) == "accountDetail.smartPriceFilter.\(accountID)")
        #expect(SmartPriceStatusFilter.storageKey(for: accountID) != AccountProductFilter.storageKey(for: accountID))
    }

    @Test("contagem de cada cápsula")
    func contagemPorFiltro() {
        let products = [
            makeProduct(id: 1, statusText: "preço atual"),
            makeProduct(id: 2, statusText: "preço atual"),
            makeProduct(id: 3, statusText: "preço alto, venda lenta"),
            makeProduct(id: 4, statusText: nil)
        ]

        #expect(SmartPriceStatusFilter.current.count(in: products) == 2)
        #expect(SmartPriceStatusFilter.high.count(in: products) == 1)
        #expect(SmartPriceStatusFilter.low.count(in: products) == 0)
        #expect(SmartPriceStatusFilter.all.count(in: products) == 4)
    }

    @Test("bolinha na cor que o enjoei manda pro status; \"todos\" e status sem produto ficam sem")
    func corDaBolinha() {
        let products = [
            makeProduct(id: 1, statusText: "preço atual", statusColor: nil),
            makeProduct(id: 2, statusText: "preço atual", statusColor: "#1A7F37"),
            makeProduct(id: 3, statusText: "preço alto, venda lenta", statusColor: "#FF4D00")
        ]

        #expect(SmartPriceStatusFilter.current.dotColorHex(in: products) == "#1A7F37")
        #expect(SmartPriceStatusFilter.high.dotColorHex(in: products) == "#FF4D00")
        #expect(SmartPriceStatusFilter.low.dotColorHex(in: products) == nil)
        #expect(SmartPriceStatusFilter.all.dotColorHex(in: products) == nil)
    }

    @Test("quem acabou de ganhar o preço esperto sai da contagem; quem falhou continua")
    func contaSoQuemAindaNaoTem() {
        let products = [
            makeProduct(id: 1, statusText: "preço atual"),
            makeProduct(id: 2, statusText: "preço atual"),
            makeProduct(id: 3, statusText: "preço atual"),
            makeProduct(id: 4, statusText: "preço atual", smartPriceEnabled: true)
        ]

        let remaining = SmartPriceStatusFilter.stillWithoutSmartPrice(
            products,
            activationStatuses: [1: .succeeded, 2: .failed("erro"), 3: .megaphoning]
        )

        #expect(remaining.map(\.id) == [2, 3])
    }
}
