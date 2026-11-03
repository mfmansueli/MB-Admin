import Foundation
import Testing
@testable import MB_Admin

/// O texto padrão que a loja repete em toda descrição sai da comparação de texto — senão duas lojas
/// do mesmo dono teriam toda descrição "quase igual".
@Suite("texto padrão da descrição")
struct DescriptionBoilerplateTests {
    typealias Fixtures = ComparisonFixtures

    private static let standard = "joia em prata 925 legítima, acompanha certificado e caixinha. envio em 24h."

    @Test("palavra em metade ou mais das descrições é texto padrão; com poucas descrições, nada é")
    func palavrasComuns() {
        let standard: Set = ["prata", "925", "envio", "24h"]
        let descriptions = (0..<6).map { standard.union(["peca\($0)"]) }
        #expect(DescriptionBoilerplate.common(in: descriptions) == standard)
        #expect(DescriptionBoilerplate.common(in: Array(descriptions.prefix(5))).isEmpty)
        let half = (0..<6).map { $0 < 3 ? standard : ["peca\($0)"] }
        #expect(DescriptionBoilerplate.common(in: half) == standard)
    }

    @Test("sem o texto padrão, a descrição continua dando os atributos de versão")
    func atributosContinuam() {
        let listings = (1...6).map {
            Fixtures.listing(seller: Fixtures.sellerA, id: $0, title: "anel \($0)", photos: [], description: "aro 16. \(Self.standard)")
        }
        let sides = DescriptionBoilerplate.removing(from: Fixtures.side(Fixtures.sellerA, listings), Fixtures.side(Fixtures.sellerB, []))
        let listing = sides.a.listings[0]
        #expect(listing.attributes.reading(.size)?.decisiveValue?.canonical == "16")
        #expect(listing.attributes.descriptionWords?.isEmpty == true)
        #expect(!listing.words.contains("certificado"))
        #expect(listing.words.contains("anel"))
        // Rodar de novo não tira mais nada.
        let again = DescriptionBoilerplate.removing(from: sides.a, sides.b)
        #expect(again.a.listings[0].words == listing.words)
    }

    @Test("o mesmo texto padrão nas duas lojas não deixa título só parecido virar 'texto quase idêntico'")
    func lojasDoMesmoDono() {
        func fillers(_ seller: Int, from id: Int) -> [ComparableListing] {
            (id..<id + 5).map { Fixtures.listing(seller: seller, id: $0, title: "peca\($0)", photos: [], description: Self.standard) }
        }
        let earrings = Fixtures.signature(DemoPhotoRenderer.Spec(shape: .earrings, seed: 1))
        let chain = Fixtures.signature(DemoPhotoRenderer.Spec(shape: .chain, seed: 2))
        let listingA = Fixtures.listing(
            seller: Fixtures.sellerA, id: 1, title: "brinco pérola shell linha infantil", photos: [("a1", earrings)], description: Self.standard
        )
        let listingB = Fixtures.listing(
            seller: Fixtures.sellerB, id: 11, title: "brinco pérola shell", photos: [("b11", chain)], description: Self.standard
        )
        let result = Fixtures.compare([listingA] + fillers(Fixtures.sellerA, from: 2), [listingB] + fillers(Fixtures.sellerB, from: 12))
        #expect(result.reviews.isEmpty)
        #expect(result.possiblyMissingInB.contains { $0.id == 1 })
        #expect(result.possiblyMissingInA.contains { $0.id == 11 })
    }
}
