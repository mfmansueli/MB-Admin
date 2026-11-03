import Foundation
import Testing
@testable import MB_Admin

@Suite("revisão manual de um par")
struct ComparisonDecisionTests {
    private let keyA = ListingKey(sellerID: 1001, productID: 5)
    private let keyB = ListingKey(sellerID: 2002, productID: 3)
    private let fingerprintA = ListingFingerprint(coverPublicID: "a", normalizedTitle: "anel prata")
    private let fingerprintB = ListingFingerprint(coverPublicID: "b", normalizedTitle: "anel prata")

    @Test("a mesma decisão sai igual não importa a ordem das lojas")
    func ordemNaoImporta() {
        let date = Date(timeIntervalSince1970: 1)
        let forward = ComparisonDecision((keyA, fingerprintA), (keyB, fingerprintB), verdict: .sameProduct, decidedAt: date)
        let backward = ComparisonDecision((keyB, fingerprintB), (keyA, fingerprintA), verdict: .sameProduct, decidedAt: date)
        #expect(forward == backward)
        #expect(forward.pairKey == ListingPairKey(keyB, keyA))
        #expect(forward.pairKey.storageID == "1001:5|2002:3")
        #expect(forward.fingerprint(of: keyB) == fingerprintB)
        #expect(forward.fingerprint(of: ListingKey(sellerID: 1, productID: 1)) == nil)
    }

    @Test("deixa de valer quando a capa ou o título de qualquer lado mudam")
    func desatualizada() {
        let decision = ComparisonDecision((keyA, fingerprintA), (keyB, fingerprintB), verdict: .differentProducts, decidedAt: Date())
        #expect(!decision.isStale(current: [keyA: fingerprintA, keyB: fingerprintB]))
        #expect(decision.isStale(current: [keyA: ListingFingerprint(coverPublicID: "a2", normalizedTitle: "anel prata"), keyB: fingerprintB]))
        #expect(decision.isStale(current: [keyA: fingerprintA, keyB: ListingFingerprint(coverPublicID: "b", normalizedTitle: "anel ouro")]))
        // Anúncio que não está na listagem agora: não dá pra dizer que mudou.
        #expect(!decision.isStale(current: [keyA: fingerprintA]))
    }

    @Test("o título normalizado ignora maiúsculas, acentos e ordem das palavras")
    func tituloNormalizado() {
        let one = ListingFingerprint(product: ComparisonFixtures.product(1, title: "Anel Solitário Prata", cover: "x"))
        let other = ListingFingerprint(product: ComparisonFixtures.product(2, title: "prata anel solitario", cover: "x"))
        #expect(one == other)
    }
}
