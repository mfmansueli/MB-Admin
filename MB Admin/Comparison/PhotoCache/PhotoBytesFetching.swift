import Foundation

/// De onde vêm os bytes de uma foto pela `image_public_id` — o CDN de fotos do Enjoei em produção,
/// imagens geradas na hora nos testes.
nonisolated protocol PhotoBytesFetching: Sendable {
    /// - Parameter forceRefresh: ignora qualquer cache local — usado na reconferência periódica
    ///   (`PhotoRefreshPolicy`), onde o ponto é justamente ver se o conteúdo mudou.
    func photoData(publicID: String, forceRefresh: Bool) async throws(PhotoSignatureError) -> Data
}
