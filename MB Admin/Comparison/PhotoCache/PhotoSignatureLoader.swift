import Foundation

/// Garante uma `PhotoSignature` pra cada foto pedida, reaproveitando o cache (`PhotoSignatureStoring`)
/// e baixando só o que falta, o que mudou de versão ou o que venceu (`PhotoRefreshPolicy`).
///
/// - Tudo fora do MainActor (`@concurrent`): download, decodificação e assinatura. Nenhuma imagem
///   decodificada sobrevive à análise da própria foto — só a assinatura (~2 KB) fica.
/// - No máximo `concurrency` fotos ao mesmo tempo; cada foto que falha por rede é tentada de novo
///   até `attempts` vezes. Foto que não decodifica não é repetida (não vai mudar).
/// - Cada id é processado uma vez por chamada, por mais anúncios que usem a mesma foto.
/// - Grava no cache em lotes, inclusive quando a rodada é cancelada — retomar continua de onde parou.
nonisolated final class PhotoSignatureLoader: Sendable {
    private typealias Limits = PhotoMatchingParameters

    private let fetcher: PhotoBytesFetching
    private let store: PhotoSignatureStoring
    private let policy: PhotoRefreshPolicy
    private let concurrency: Int
    private let attempts: Int
    private let retryDelay: Duration
    private let now: @Sendable () -> Date
    private static let saveBatchSize = 32
    private static let cancelled = PhotoSignatureError.downloadFailed("cancelado")

    init(
        fetcher: PhotoBytesFetching,
        store: PhotoSignatureStoring,
        policy: PhotoRefreshPolicy = .standard,
        concurrency: Int = PhotoMatchingParameters.photoDownloadConcurrency,
        attempts: Int = PhotoMatchingParameters.photoDownloadAttempts,
        retryDelay: Duration = PhotoMatchingParameters.photoRetryDelay,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fetcher = fetcher
        self.store = store
        self.policy = policy
        self.concurrency = max(1, concurrency)
        self.attempts = max(1, attempts)
        self.retryDelay = retryDelay
        self.now = now
    }

    private struct Job: Sendable {
        let publicID: String
        /// A assinatura salva, quando é só uma reconferência — vale de novo se o download falhar.
        let previous: StoredPhotoSignature?
        var forceRefresh: Bool { previous != nil }
    }

    private enum Outcome: Sendable {
        case analyzed(publicID: String, signature: PhotoSignature)
        case failed(publicID: String, error: PhotoSignatureError, previous: StoredPhotoSignature?)
    }

    /// - Parameter onProgress: (prontas, total) — chamado do executor global, nunca do MainActor;
    ///   quem atualiza tela pula pro MainActor por conta própria.
    @concurrent
    func analyze(
        _ publicIDs: [String],
        onProgress: @escaping @Sendable (_ done: Int, _ total: Int) -> Void = { _, _ in }
    ) async -> PhotoAnalysisBatch {
        var seen: Set<String> = []
        let unique = publicIDs.filter { !$0.isEmpty && seen.insert($0).inserted }
        guard !unique.isEmpty else { return PhotoAnalysisBatch() }

        let (ready, jobs) = plan(unique, stored: await store.signatures(for: unique))
        var batch = PhotoAnalysisBatch(signatures: ready)
        let total = unique.count
        var done = ready.count
        onProgress(done, total)
        guard !jobs.isEmpty else { return batch }

        var pendingSaves: [StoredPhotoSignature] = []
        await withTaskGroup(of: Outcome.self) { group in
            var nextJob = 0
            // Janela deslizante: começa `concurrency` e põe a próxima a cada uma que termina.
            while nextJob < min(concurrency, jobs.count) {
                let job = jobs[nextJob]
                nextJob += 1
                group.addTask { [self] in await self.process(job) }
            }
            while let outcome = await group.next() {
                if let saved = record(outcome, in: &batch) { pendingSaves.append(saved) }
                done += 1
                onProgress(done, total)
                if pendingSaves.count >= Self.saveBatchSize {
                    await store.save(pendingSaves)
                    pendingSaves.removeAll()
                }
                if nextJob < jobs.count, !Task.isCancelled {
                    let job = jobs[nextJob]
                    nextJob += 1
                    group.addTask { [self] in await self.process(job) }
                }
            }
        }
        if !pendingSaves.isEmpty { await store.save(pendingSaves) }
        if Task.isCancelled {
            // Interrompida: o que não terminou não "falhou" — só não foi analisado.
            batch.failures = batch.failures.filter { $0.value != Self.cancelled }
            batch.wasCancelled = batch.signatures.count + batch.failures.count < total
        }
        return batch
    }

    /// O que já está pronto no cache e o que precisa ser baixado (novo, de outra versão, ou vencido).
    private func plan(_ publicIDs: [String], stored: [String: StoredPhotoSignature]) -> (ready: [String: PhotoSignature], jobs: [Job]) {
        let currentDate = now()
        var ready: [String: PhotoSignature] = [:]
        var jobs: [Job] = []
        for publicID in publicIDs {
            guard let entry = stored[publicID], entry.signature.algorithmVersion == Limits.signatureVersion else {
                jobs.append(Job(publicID: publicID, previous: nil))
                continue
            }
            if policy.needsRefresh(publicID: publicID, verifiedAt: entry.verifiedAt, now: currentDate) {
                jobs.append(Job(publicID: publicID, previous: entry))
            } else {
                ready[publicID] = entry.signature
            }
        }
        return (ready, jobs)
    }

    /// Junta o resultado de uma foto no lote; devolve o que precisa ir pro cache.
    private func record(_ outcome: Outcome, in batch: inout PhotoAnalysisBatch) -> StoredPhotoSignature? {
        switch outcome {
        case .analyzed(let publicID, let signature):
            batch.signatures[publicID] = signature
            batch.downloadedCount += 1
            return StoredPhotoSignature(publicID: publicID, signature: signature, verifiedAt: now())
        case .failed(let publicID, let error, let previous):
            if let previous {
                batch.signatures[publicID] = previous.signature
            } else {
                batch.failures[publicID] = error
            }
            return nil
        }
    }

    private func process(_ job: Job) async -> Outcome {
        var lastError = PhotoSignatureError.downloadFailed("sem tentativa")
        for attempt in 0..<attempts {
            if Task.isCancelled { return .failed(publicID: job.publicID, error: Self.cancelled, previous: nil) }
            if attempt > 0 { try? await Task.sleep(for: retryDelay) }
            let data: Data
            do {
                data = try await fetcher.photoData(publicID: job.publicID, forceRefresh: job.forceRefresh || attempt > 0)
            } catch {
                lastError = error
                continue
            }
            if let previous = job.previous, Self.sha256Matches(data, previous.signature) {
                return .analyzed(publicID: job.publicID, signature: previous.signature)
            }
            do {
                return .analyzed(publicID: job.publicID, signature: try PhotoSignatureGenerator.makeSignature(from: data))
            } catch {
                // Bytes que não decodificam não melhoram tentando de novo.
                return .failed(publicID: job.publicID, error: error, previous: job.previous)
            }
        }
        return .failed(publicID: job.publicID, error: lastError, previous: job.previous)
    }

    /// Reconferência barata: mesmos bytes, mesma assinatura — sem decodificar de novo.
    private static func sha256Matches(_ data: Data, _ signature: PhotoSignature) -> Bool {
        data.count == signature.byteCount && PhotoSignatureGenerator.sha256Hex(data) == signature.contentSHA256
    }
}
