import Foundation
import Testing
@testable import MB_Admin

@Suite("filtro de status da aba sem preço esperto")
struct SmartPriceStatusFilterTests {
    private func makeProduct(statusText: String?) -> SmartPriceProduct {
        SmartPriceProduct(
            id: 1, price: 100, minPrice: 70, maxPrice: 150, blocked: false, smartPriceEnabled: false,
            statusText: statusText, statusColor: nil, photoPublicID: nil
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
}
