import Foundation
import Testing
@testable import MB_Admin

@Suite("classificação de exposição do megafone")
struct MegaphoneExposureKindTests {
    private func decode(_ raw: String) throws -> MegaphoneExposureKind {
        try JSONDecoder().decode(MegaphoneExposureKind.self, from: Data("\"\(raw)\"".utf8))
    }

    @Test("decodifica os cinco valores documentados pelo enjoei")
    func decodificaValoresConhecidos() throws {
        #expect(try decode("maximum_for_free") == .maximumForFree)
        #expect(try decode("maximum_after_discount") == .maximumAfterDiscount)
        #expect(try decode("reduced_for_free_or_maximum_after_discount") == .reducedForFreeOrMaximumAfterDiscount)
        #expect(try decode("reduced_for_free") == .reducedForFree)
        #expect(try decode("maximum_for_free_after_change_plan") == .maximumForFreeAfterChangePlan)
    }

    @Test("valor desconhecido não quebra a decodificação")
    func valorDesconhecidoViraOther() throws {
        #expect(try decode("algo_novo_do_enjoei") == .other("algo_novo_do_enjoei"))
    }

    @Test("só os dois casos do spec pedem a decisão de desconto")
    func soDoisCasosPedemDesconto() {
        #expect(MegaphoneExposureKind.maximumAfterDiscount.requiresDiscountDecision)
        #expect(MegaphoneExposureKind.reducedForFreeOrMaximumAfterDiscount.requiresDiscountDecision)
        #expect(MegaphoneExposureKind.maximumForFree.requiresDiscountDecision == false)
        #expect(MegaphoneExposureKind.reducedForFree.requiresDiscountDecision == false)
        #expect(MegaphoneExposureKind.maximumForFreeAfterChangePlan.requiresDiscountDecision == false)
        #expect(MegaphoneExposureKind.other("x").requiresDiscountDecision == false)
    }
}
