import Foundation
import SwiftData

/// `PhotoSignatureStoring` em SwiftData, num `ModelActor` próprio — ler/gravar milhares de
/// assinaturas nunca passa pelo MainActor. Usa o mesmo `SharedModelContainer` do resto do app
/// (nunca um container próprio: ver o aviso em `SharedModelContainer`).
@ModelActor
actor SwiftDataPhotoSignatureStore: PhotoSignatureStoring {
    /// Predicados com `contains` sobre listas enormes viram SQL enorme — busca em pedaços.
    private static let chunkSize = 400

    func signatures(for publicIDs: [String]) async -> [String: StoredPhotoSignature] {
        var result: [String: StoredPhotoSignature] = [:]
        for chunk in Self.chunks(of: Array(Set(publicIDs))) {
            let descriptor = FetchDescriptor<PhotoSignatureRecord>(predicate: #Predicate { chunk.contains($0.publicID) })
            for record in (try? modelContext.fetch(descriptor)) ?? [] {
                result[record.publicID] = record.entry
            }
        }
        return result
    }

    func save(_ entries: [StoredPhotoSignature]) async {
        guard !entries.isEmpty else { return }
        let byID = Dictionary(entries.map { ($0.publicID, $0) }, uniquingKeysWith: { $1 })
        for chunk in Self.chunks(of: Array(byID.keys)) {
            let descriptor = FetchDescriptor<PhotoSignatureRecord>(predicate: #Predicate { chunk.contains($0.publicID) })
            var existing: [String: PhotoSignatureRecord] = [:]
            for record in (try? modelContext.fetch(descriptor)) ?? [] {
                existing[record.publicID] = record
            }
            for publicID in chunk {
                guard let entry = byID[publicID] else { continue }
                if let record = existing[publicID] {
                    record.update(from: entry)
                } else {
                    modelContext.insert(PhotoSignatureRecord(entry: entry))
                }
            }
        }
        try? modelContext.save()
    }

    private static func chunks(of ids: [String]) -> [[String]] {
        stride(from: 0, to: ids.count, by: chunkSize).map { Array(ids[$0..<min($0 + chunkSize, ids.count)]) }
    }
}
