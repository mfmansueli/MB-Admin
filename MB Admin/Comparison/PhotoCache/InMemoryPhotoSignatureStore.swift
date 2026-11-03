import Foundation

/// `PhotoSignatureStoring` só em memória — testes e modo de demonstração.
actor InMemoryPhotoSignatureStore: PhotoSignatureStoring {
    private var entries: [String: StoredPhotoSignature]
    private(set) var saveCount = 0

    init(entries: [StoredPhotoSignature] = []) {
        self.entries = Dictionary(entries.map { ($0.publicID, $0) }, uniquingKeysWith: { $1 })
    }

    func signatures(for publicIDs: [String]) async -> [String: StoredPhotoSignature] {
        var result: [String: StoredPhotoSignature] = [:]
        for publicID in publicIDs {
            result[publicID] = entries[publicID]
        }
        return result
    }

    func save(_ newEntries: [StoredPhotoSignature]) async {
        saveCount += 1
        for entry in newEntries {
            entries[entry.publicID] = entry
        }
    }

    var all: [StoredPhotoSignature] { Array(entries.values) }
}
