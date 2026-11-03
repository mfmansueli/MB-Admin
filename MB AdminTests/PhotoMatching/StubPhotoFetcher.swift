import Foundation
@testable import MB_Admin

/// `PhotoBytesFetching` de teste: devolve bytes registrados por id público (normalmente fotos
/// sintéticas do `DemoPhotoRenderer`), falha os ids marcados, conta chamadas e quantas estão em voo
/// ao mesmo tempo.
actor StubPhotoFetcher: PhotoBytesFetching {
    private var photos: [String: Data]
    /// Falhas restantes por id antes de começar a responder (`Int.max` = sempre falha).
    private var failuresRemaining: [String: Int]
    private let delay: Duration
    private(set) var requests: [(publicID: String, forceRefresh: Bool)] = []
    private(set) var maxConcurrent = 0
    private var current = 0

    init(photos: [String: Data] = [:], failing: [String: Int] = [:], delay: Duration = .zero) {
        self.photos = photos
        failuresRemaining = failing
        self.delay = delay
    }

    func setPhoto(_ data: Data?, for publicID: String) {
        photos[publicID] = data
    }

    func setFailures(_ count: Int, for publicID: String) {
        failuresRemaining[publicID] = count
    }

    func requestCount(for publicID: String) -> Int {
        requests.count { $0.publicID == publicID }
    }

    func photoData(publicID: String, forceRefresh: Bool) async throws(PhotoSignatureError) -> Data {
        requests.append((publicID, forceRefresh))
        current += 1
        maxConcurrent = max(maxConcurrent, current)
        defer { current -= 1 }
        if delay > .zero { try? await Task.sleep(for: delay) }
        if let remaining = failuresRemaining[publicID], remaining > 0 {
            failuresRemaining[publicID] = remaining == .max ? .max : remaining - 1
            throw .downloadFailed("HTTP 503")
        }
        guard let data = photos[publicID] else { throw .downloadFailed("HTTP 404") }
        return data
    }
}
