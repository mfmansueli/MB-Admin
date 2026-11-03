import Foundation
import SwiftData
import Testing
@testable import MB_Admin

@Suite("persistência da comparação em SwiftData")
struct ComparisonStoresTests {
    private typealias Fixtures = ComparisonFixtures

    /// Container em memória, isolado por teste — nunca o banco de verdade do app.
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([PhotoSignatureRecord.self, ComparisonDecisionRecord.self, ProductListingDetailsRecord.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    private func key(_ seller: Int, _ product: Int) -> ListingKey {
        ListingKey(sellerID: seller, productID: product)
    }

    private func fingerprint(_ cover: String) -> ListingFingerprint {
        ListingFingerprint(coverPublicID: cover, normalizedTitle: "anel")
    }

    // MARK: - Assinaturas

    @Test("assinatura sai do disco igual entrou, inclusive o hash com o bit mais alto ligado")
    func assinaturaIdaEVolta() async throws {
        let container = try makeContainer()
        let store = SwiftDataPhotoSignatureStore(modelContainer: container)
        let base = Fixtures.signature(Fixtures.ring(1))
        let highBit = PhotoSignature(
            algorithmVersion: base.algorithmVersion, contentSHA256: "abc", byteCount: base.byteCount,
            pixelWidth: base.pixelWidth, pixelHeight: base.pixelHeight, isInformative: base.isInformative,
            hasUniformBackground: base.hasUniformBackground, contentBox: base.contentBox,
            contentAspectRatio: base.contentAspectRatio, contentHash: UInt64.max - 7,
            contentLuma: base.contentLuma, fullLuma: base.fullLuma, contentColor: base.contentColor
        )
        let verifiedAt = Date(timeIntervalSince1970: 1_700_000_000)
        await store.save([
            StoredPhotoSignature(publicID: "anel", signature: base, verifiedAt: verifiedAt),
            StoredPhotoSignature(publicID: "bit", signature: highBit, verifiedAt: verifiedAt)
        ])

        let loaded = await store.signatures(for: ["anel", "bit", "nenhuma"])
        #expect(loaded["anel"]?.signature == base)
        #expect(loaded["anel"]?.verifiedAt == verifiedAt)
        #expect(loaded["bit"]?.signature.contentHash == UInt64.max - 7)
        #expect(loaded["nenhuma"] == nil)
    }

    @Test("gravar de novo o mesmo id atualiza a linha em vez de duplicar")
    func assinaturaAtualiza() async throws {
        let container = try makeContainer()
        let store = SwiftDataPhotoSignatureStore(modelContainer: container)
        await store.save([StoredPhotoSignature(publicID: "anel", signature: Fixtures.signature(Fixtures.ring(1)), verifiedAt: Date(timeIntervalSince1970: 0))])
        let newer = Fixtures.signature(Fixtures.ring(2))
        await store.save([StoredPhotoSignature(publicID: "anel", signature: newer, verifiedAt: Date(timeIntervalSince1970: 10))])

        #expect(await store.signatures(for: ["anel"])["anel"]?.signature == newer)
        let count = try ModelContext(container).fetchCount(FetchDescriptor<PhotoSignatureRecord>())
        #expect(count == 1)
    }

    @Test("lê e grava mais ids do que cabem num pedaço do predicado")
    func assinaturaEmPedacos() async throws {
        let store = SwiftDataPhotoSignatureStore(modelContainer: try makeContainer())
        let signature = Fixtures.signature(Fixtures.ring(3))
        let entries = (0..<900).map { StoredPhotoSignature(publicID: "foto-\($0)", signature: signature, verifiedAt: Date()) }
        await store.save(entries)
        #expect(await store.signatures(for: entries.map(\.publicID)).count == 900)
    }

    // MARK: - Revisões

    @Test("revisão salva volta nas duas ordens de loja, e só pro par de lojas certo")
    @MainActor
    func revisaoIdaEVolta() throws {
        let store = SwiftDataComparisonDecisionStore(container: try makeContainer())
        let decision = ComparisonDecision(
            (key(2002, 9), fingerprint("b")), (key(1001, 1), fingerprint("a")),
            verdict: .sameProduct, decidedAt: Date(timeIntervalSince1970: 50)
        )
        store.save(decision)

        #expect(store.decisions(betweenSeller: 1001, andSeller: 2002) == [decision])
        #expect(store.decisions(betweenSeller: 2002, andSeller: 1001) == [decision])
        #expect(store.decisions(betweenSeller: 1001, andSeller: 3003).isEmpty)
    }

    @Test("corrigir uma revisão substitui a anterior; desfazer apaga")
    @MainActor
    func revisaoCorrigeEDesfaz() throws {
        let store = SwiftDataComparisonDecisionStore(container: try makeContainer())
        let one = (key: key(1001, 1), fingerprint: fingerprint("a"))
        let other = (key: key(2002, 9), fingerprint: fingerprint("b"))
        store.save(ComparisonDecision(one, other, verdict: .sameProduct, decidedAt: Date()))
        store.save(ComparisonDecision(other, one, verdict: .differentProducts, decidedAt: Date()))

        let saved = store.decisions(betweenSeller: 1001, andSeller: 2002)
        #expect(saved.map(\.verdict) == [.differentProducts])

        store.removeDecision(for: ListingPairKey(other.key, one.key))
        #expect(store.decisions(betweenSeller: 1001, andSeller: 2002).isEmpty)
    }

    // MARK: - Templates

    @Test("template salvo volta com as fotos na ordem, categoria, tamanho e descrição")
    @MainActor
    func templateIdaEVolta() throws {
        let persistence = SwiftDataListingDetailsPersistence(container: try makeContainer())
        let details = ProductListingDetails(
            productID: 7, coverPublicID: "capa", photoPublicIDs: ["capa", "lado", "caixa"],
            categoryID: 327, size: "17", brand: "vivara", description: "anel\ncom quebra de linha",
            fetchedAt: Date(timeIntervalSince1970: 99)
        )
        persistence.upsert(details)

        #expect(persistence.details(for: [7, 8]) == [7: details])
        #expect(persistence.count == 1)

        let updated = ProductListingDetails(
            productID: 7, coverPublicID: "nova", photoPublicIDs: ["nova"], categoryID: nil, size: nil,
            brand: nil, description: "", fetchedAt: Date(timeIntervalSince1970: 100)
        )
        persistence.upsert(updated)
        #expect(persistence.details(for: [7])[7] == updated)
        #expect(persistence.count == 1)
    }
}
