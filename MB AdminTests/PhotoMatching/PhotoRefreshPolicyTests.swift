import Foundation
import Testing
@testable import MB_Admin

@Suite("quando reconferir uma foto já analisada")
struct PhotoRefreshPolicyTests {
    private let verifiedAt = Date(timeIntervalSince1970: 0)

    @Test("antes do prazo mínimo nunca reconfere; depois do máximo, sempre")
    func prazos() {
        let policy = PhotoRefreshPolicy(maxAge: 1_000, jitterFraction: 0.25)
        for publicID in ["a", "foto-1", "czM6Ly9waG90b3M", "x/y/z"] {
            #expect(!policy.needsRefresh(publicID: publicID, verifiedAt: verifiedAt, now: Date(timeIntervalSince1970: 749)))
            #expect(policy.needsRefresh(publicID: publicID, verifiedAt: verifiedAt, now: Date(timeIntervalSince1970: 1_251)))
        }
    }

    @Test("a folga é a mesma pra mesma foto e espalha fotos diferentes entre −1 e 1")
    func folgaDeterministica() {
        #expect(PhotoRefreshPolicy.unitJitter(for: "foto-1") == PhotoRefreshPolicy.unitJitter(for: "foto-1"))
        let values = (0..<200).map { PhotoRefreshPolicy.unitJitter(for: "foto-\($0)") }
        #expect(values.allSatisfy { (-1...1).contains($0) })
        #expect(Set(values).count > 150)
        #expect(values.contains { $0 < -0.5 } && values.contains { $0 > 0.5 })
    }

    @Test("a política 'nunca' não reconfere nem depois de anos")
    func nunca() {
        #expect(!PhotoRefreshPolicy.never.needsRefresh(publicID: "a", verifiedAt: verifiedAt, now: Date(timeIntervalSince1970: 1e10)))
    }
}
