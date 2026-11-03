import Foundation

/// O que `PhotoSignatureLoader.analyze` conseguiu: assinatura de cada foto que deu certo, o erro
/// de cada uma que falhou, e se a rodada foi interrompida (aí as que faltaram não estão em nenhum
/// dos dois — não foram analisadas, o que é diferente de ter falhado).
nonisolated struct PhotoAnalysisBatch: Sendable {
    var signatures: [String: PhotoSignature] = [:]
    var failures: [String: PhotoSignatureError] = [:]
    var wasCancelled = false
    /// Quantas foram baixadas agora (o resto veio do cache).
    var downloadedCount = 0

    mutating func merge(_ other: PhotoAnalysisBatch) {
        signatures.merge(other.signatures) { $1 }
        for (publicID, error) in other.failures where signatures[publicID] == nil {
            failures[publicID] = error
        }
        for publicID in other.signatures.keys {
            failures.removeValue(forKey: publicID)
        }
        wasCancelled = wasCancelled || other.wasCancelled
        downloadedCount += other.downloadedCount
    }
}
