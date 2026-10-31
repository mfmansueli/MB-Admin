import Foundation
import Testing
@testable import MB_Admin

@Suite("dados do modo de demonstração")
struct DemoCatalogTests {
    private var products: [SmartPriceProduct] {
        DemoCatalog.smartPriceProducts(for: DemoCatalog.profiles[0])
    }

    @Test("todo produto de preço esperto cai em algum filtro de status — senão as cápsulas ficam vazias na demo")
    func todoStatusTemFiltro() {
        let statusFilters = SmartPriceStatusFilter.allCases.filter { $0 != .all }
        for product in products {
            #expect(statusFilters.contains { $0.matches(product) }, "\(product.statusText ?? "sem rótulo")")
        }
    }

    @Test("maioria preço atual, três preço alto, dois preço baixo, doze no total")
    func distribuicaoDoMock() {
        #expect(products.count == 12)
        #expect(SmartPriceStatusFilter.current.count(in: products) == 7)
        #expect(SmartPriceStatusFilter.high.count(in: products) == 3)
        #expect(SmartPriceStatusFilter.low.count(in: products) == 2)
    }

    @Test("um bloqueado, de preço atual, nas cores reais do enjoei")
    func bloqueadoECores() {
        let blocked = products.filter(\.blocked)
        #expect(blocked.count == 1)
        #expect(blocked.allSatisfy(SmartPriceStatusFilter.current.matches))
        #expect(SmartPriceStatusFilter.current.dotColorHex(in: products) == "#1A7F37")
        #expect(SmartPriceStatusFilter.high.dotColorHex(in: products) == "#FF4D00")
    }
}
