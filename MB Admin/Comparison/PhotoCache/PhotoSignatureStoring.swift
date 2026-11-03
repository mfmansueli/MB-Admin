import Foundation

/// Cache persistente de `PhotoSignature` por `image_public_id`. Compartilhado entre todas as contas:
/// a mesma foto usada em duas lojas (ou em dois anúncios) é analisada uma vez só.
nonisolated protocol PhotoSignatureStoring: Sendable {
    func signatures(for publicIDs: [String]) async -> [String: StoredPhotoSignature]
    /// Insere ou substitui pelo id público.
    func save(_ entries: [StoredPhotoSignature]) async
}
