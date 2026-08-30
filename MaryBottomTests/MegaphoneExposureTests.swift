import Foundation
import Testing
@testable import MaryBottom

@Suite("decodificação da exposição do megafone")
struct MegaphoneExposureTests {
    /// Recorte real da resposta de `GET /api/megaphones/v2`, do spec do Enjoei.
    static let exposureJSON = """
    {
      "product_id": 142963399,
      "original_price": 799,
      "price": 799,
      "price_to_increase_exposure": 351,
      "discount": "- 56%",
      "exposure": "reduced_for_free_or_maximum_after_discount",
      "plan_is_megaphoneable": true,
      "upgradeable_plan_id": 1,
      "should_offer_smart_price": null,
      "smart_price": { "lower_price": null, "upper_price": null }
    }
    """

    @Test("lê os campos que a aba de desconto usa, ignorando o resto")
    func decodificaExposicao() throws {
        let exposure = try JSONDecoder().decode(MegaphoneExposure.self, from: Data(Self.exposureJSON.utf8))

        #expect(exposure.productID == 142963399)
        #expect(exposure.kind == .reducedForFreeOrMaximumAfterDiscount)
        #expect(exposure.priceToIncreaseExposure == 351)
        #expect(exposure.discountLabel == "- 56%")
    }

    @Test("decodifica o envelope de vários produtos")
    func decodificaEnvelope() throws {
        let json = #"{"products": [\#(Self.exposureJSON)], "messages": [], "smart_price_content": null}"#

        let payload = try JSONDecoder().decode(MegaphoneExposuresPayload.self, from: Data(json.utf8))

        #expect(payload.products.count == 1)
        #expect(payload.products.first?.productID == 142963399)
    }
}
