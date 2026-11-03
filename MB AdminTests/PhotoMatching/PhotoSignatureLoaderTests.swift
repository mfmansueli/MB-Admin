import Foundation
import Testing
@testable import MB_Admin

@Suite("cache e download das assinaturas de foto")
struct PhotoSignatureLoaderTests {
    private typealias Fixtures = ComparisonFixtures

    private static let ringBytes = DemoPhotoRenderer.jpeg(Fixtures.ring(1), side: 300) ?? Data()
    private static let otherRingBytes = DemoPhotoRenderer.jpeg(Fixtures.ring(2), side: 300) ?? Data()
    private static let pendantBytes = DemoPhotoRenderer.jpeg(DemoPhotoRenderer.Spec(shape: .pendant, seed: 3), side: 300) ?? Data()

    private func loader(
        _ fetcher: StubPhotoFetcher,
        store: PhotoSignatureStoring = InMemoryPhotoSignatureStore(),
        policy: PhotoRefreshPolicy = .never,
        attempts: Int = 2,
        now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_000_000) }
    ) -> PhotoSignatureLoader {
        PhotoSignatureLoader(fetcher: fetcher, store: store, policy: policy, attempts: attempts, retryDelay: .zero, now: now)
    }

    @Test("baixa, assina e grava no cache; a segunda vez não baixa nada")
    func reaproveitaOCache() async {
        let fetcher = StubPhotoFetcher(photos: ["anel": Self.ringBytes, "pingente": Self.pendantBytes])
        let store = InMemoryPhotoSignatureStore()
        let first = await loader(fetcher, store: store).analyze(["anel", "pingente"])
        #expect(first.signatures.keys.sorted() == ["anel", "pingente"])
        #expect(first.downloadedCount == 2)
        #expect(await store.all.count == 2)

        let second = await loader(fetcher, store: store).analyze(["anel", "pingente"])
        #expect(second.signatures == first.signatures)
        #expect(second.downloadedCount == 0)
        #expect(await fetcher.requests.count == 2)
    }

    @Test("a mesma foto pedida por vários anúncios é baixada uma vez só")
    func deduplica() async {
        let fetcher = StubPhotoFetcher(photos: ["anel": Self.ringBytes])
        let batch = await loader(fetcher).analyze(["anel", "anel", "", "anel"])
        #expect(batch.signatures.count == 1)
        #expect(await fetcher.requestCount(for: "anel") == 1)
    }

    @Test("assinatura de outra versão do algoritmo é refeita")
    func versaoDiferenteRefaz() async throws {
        let current = try PhotoSignatureGenerator.makeSignature(from: Self.ringBytes)
        let old = PhotoSignature(
            algorithmVersion: PhotoMatchingParameters.signatureVersion - 1,
            contentSHA256: current.contentSHA256, byteCount: current.byteCount,
            pixelWidth: current.pixelWidth, pixelHeight: current.pixelHeight,
            isInformative: current.isInformative, hasUniformBackground: current.hasUniformBackground,
            contentBox: current.contentBox, contentAspectRatio: current.contentAspectRatio,
            contentHash: current.contentHash, contentLuma: current.contentLuma,
            fullLuma: current.fullLuma, contentColor: current.contentColor
        )
        let store = InMemoryPhotoSignatureStore(entries: [StoredPhotoSignature(publicID: "anel", signature: old, verifiedAt: Date())])
        let fetcher = StubPhotoFetcher(photos: ["anel": Self.ringBytes])

        let batch = await loader(fetcher, store: store).analyze(["anel"])

        #expect(batch.signatures["anel"]?.algorithmVersion == PhotoMatchingParameters.signatureVersion)
        #expect(await fetcher.requestCount(for: "anel") == 1)
    }

    @Test("vencida: baixa de novo sem cache; bytes iguais mantêm a assinatura e só a data anda")
    func reconfereVencidaIgual() async throws {
        let signature = try PhotoSignatureGenerator.makeSignature(from: Self.ringBytes)
        let verifiedAt = Date(timeIntervalSince1970: 0)
        let store = InMemoryPhotoSignatureStore(entries: [StoredPhotoSignature(publicID: "anel", signature: signature, verifiedAt: verifiedAt)])
        let fetcher = StubPhotoFetcher(photos: ["anel": Self.ringBytes])
        let now = Date(timeIntervalSince1970: PhotoMatchingParameters.signatureMaxAge * 3)

        let batch = await loader(fetcher, store: store, policy: .standard, now: { now }).analyze(["anel"])

        #expect(batch.signatures["anel"] == signature)
        #expect(await fetcher.requests.first?.forceRefresh == true)
        #expect(await store.all.first?.verifiedAt == now)
    }

    @Test("vencida e a foto mudou por trás do mesmo id: a assinatura é refeita")
    func reconfereVencidaMudou() async throws {
        let oldSignature = try PhotoSignatureGenerator.makeSignature(from: Self.ringBytes)
        let store = InMemoryPhotoSignatureStore(entries: [
            StoredPhotoSignature(publicID: "anel", signature: oldSignature, verifiedAt: Date(timeIntervalSince1970: 0))
        ])
        let fetcher = StubPhotoFetcher(photos: ["anel": Self.otherRingBytes])
        let now = Date(timeIntervalSince1970: PhotoMatchingParameters.signatureMaxAge * 3)

        let batch = await loader(fetcher, store: store, policy: .standard, now: { now }).analyze(["anel"])

        #expect(batch.signatures["anel"]?.contentSHA256 == PhotoSignatureGenerator.sha256Hex(Self.otherRingBytes))
        #expect(batch.signatures["anel"] != oldSignature)
    }

    @Test("reconferência que falha mantém a assinatura antiga — nunca vira 'foto com problema'")
    func reconferenciaQueFalhaMantemAAntiga() async throws {
        let signature = try PhotoSignatureGenerator.makeSignature(from: Self.ringBytes)
        let store = InMemoryPhotoSignatureStore(entries: [
            StoredPhotoSignature(publicID: "anel", signature: signature, verifiedAt: Date(timeIntervalSince1970: 0))
        ])
        let fetcher = StubPhotoFetcher(failing: ["anel": .max])
        let now = Date(timeIntervalSince1970: PhotoMatchingParameters.signatureMaxAge * 3)

        let batch = await loader(fetcher, store: store, policy: .standard, now: { now }).analyze(["anel"])

        #expect(batch.signatures["anel"] == signature)
        #expect(batch.failures.isEmpty)
    }

    @Test("falha de rede é tentada de novo até o limite; depois vira falha com o motivo")
    func tentaDeNovo() async {
        let fetcher = StubPhotoFetcher(photos: ["anel": Self.ringBytes, "pingente": Self.pendantBytes], failing: ["anel": 1, "pingente": .max])

        let batch = await loader(fetcher, attempts: 2).analyze(["anel", "pingente"])

        #expect(batch.signatures["anel"] != nil)
        #expect(batch.failures["pingente"] == .downloadFailed("HTTP 503"))
        #expect(await fetcher.requestCount(for: "anel") == 2)
        #expect(await fetcher.requestCount(for: "pingente") == 2)
        // A segunda tentativa já pula o cache do URLSession.
        #expect(await fetcher.requests.filter { $0.publicID == "anel" }.map(\.forceRefresh) == [false, true])
    }

    @Test("bytes que não são imagem não são tentados de novo")
    func naoDecodificaNaoRepete() async {
        let fetcher = StubPhotoFetcher(photos: ["lixo": Data("não é jpeg".utf8)])
        let batch = await loader(fetcher, attempts: 3).analyze(["lixo"])
        #expect(batch.failures["lixo"] == .undecodable)
        #expect(await fetcher.requestCount(for: "lixo") == 1)
    }

    @Test("no máximo 4 downloads ao mesmo tempo")
    func concorrenciaLimitada() async {
        var photos: [String: Data] = [:]
        for index in 0..<12 { photos["foto-\(index)"] = Self.ringBytes }
        let fetcher = StubPhotoFetcher(photos: photos, delay: .milliseconds(30))

        let batch = await PhotoSignatureLoader(fetcher: fetcher, store: InMemoryPhotoSignatureStore(), policy: .never, retryDelay: .zero)
            .analyze(Array(photos.keys))

        #expect(batch.signatures.count == 12)
        let peak = await fetcher.maxConcurrent
        #expect(peak <= PhotoMatchingParameters.photoDownloadConcurrency)
        #expect(peak > 1)
    }

    @Test("cancelada no meio: o que terminou fica no cache, o resto não conta como falha")
    func cancelada() async throws {
        var photos: [String: Data] = [:]
        for index in 0..<20 { photos["foto-\(index)"] = Self.ringBytes }
        let fetcher = StubPhotoFetcher(photos: photos, delay: .milliseconds(40))
        let store = InMemoryPhotoSignatureStore()
        let loader = loader(fetcher, store: store)
        let ids = (0..<20).map { "foto-\($0)" }

        let task = Task { await loader.analyze(ids) }
        while await fetcher.requests.count < 6 {
            try await Task.sleep(for: .milliseconds(5))
        }
        task.cancel()
        let batch = await task.value

        #expect(batch.wasCancelled)
        #expect(batch.failures.isEmpty)
        #expect(batch.signatures.count < 20)
        #expect(await store.all.count == batch.signatures.count)

        // Continuar: só baixa o que faltou.
        let before = await fetcher.requests.count
        let resumed = await self.loader(fetcher, store: store).analyze(ids)
        #expect(resumed.signatures.count == 20)
        #expect(!resumed.wasCancelled)
        #expect(await fetcher.requests.count - before == 20 - batch.signatures.count)
    }

    @Test("o progresso chega ao total")
    func progresso() async {
        let fetcher = StubPhotoFetcher(photos: ["anel": Self.ringBytes, "pingente": Self.pendantBytes])
        let progress = ProgressRecorder()
        _ = await loader(fetcher).analyze(["anel", "pingente"]) { done, total in
            progress.record(done, total)
        }
        #expect(progress.last?.done == 2)
        #expect(progress.last?.total == 2)
    }

    /// Junta os avisos de progresso (chamados fora do MainActor).
    private nonisolated final class ProgressRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [(done: Int, total: Int)] = []

        func record(_ done: Int, _ total: Int) {
            lock.withLock { values.append((done, total)) }
        }

        var last: (done: Int, total: Int)? { lock.withLock { values.last } }
    }
}
