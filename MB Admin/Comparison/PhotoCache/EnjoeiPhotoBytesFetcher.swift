import Foundation

/// Baixa a foto de 300×300 do Enjoei pela mesma `URLSession.productPhotos` das miniaturas da tela —
/// quem já viu a foto na lista não baixa de novo (cache HTTP em disco), e vice-versa. É o CDN de
/// fotos, não a API: não passa pela WebView nem pela sessão logada.
nonisolated struct EnjoeiPhotoBytesFetcher: PhotoBytesFetching {
    var session: URLSession = .productPhotos
    var timeout: TimeInterval = 20

    func photoData(publicID: String, forceRefresh: Bool) async throws(PhotoSignatureError) -> Data {
        guard let url = EnjoeiPhoto.url(publicID: publicID, size: .thumbnail) else {
            throw .downloadFailed("id de foto vazio")
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.cachePolicy = forceRefresh ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw .downloadFailed("cancelado")
        } catch {
            throw .downloadFailed(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw .downloadFailed("HTTP \(http.statusCode)")
        }
        guard !data.isEmpty else { throw .downloadFailed("resposta vazia") }
        return data
    }
}
