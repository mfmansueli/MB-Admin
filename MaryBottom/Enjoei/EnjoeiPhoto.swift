import Foundation

/// Monta URLs do serviço de fotos do Enjoei a partir do `image_public_id` devolvido pelas APIs.
///
/// O front-end web usa o formato `{host}/{visibilidade}/{tamanho}/{public_id}`.
nonisolated enum EnjoeiPhoto {
    enum Size: String {
        case thumbnail = "300x300"
        case card = "500x500"
        case avatar = "100x100"
        case bigAvatar = "200x200"
    }

    static func url(publicID: String, size: Size, visibility: String = "public") -> URL? {
        guard !publicID.isEmpty else { return nil }
        return EnjoeiAPI.photosBaseURL
            .appendingPathComponent(visibility)
            .appendingPathComponent(size.rawValue)
            .appendingPathComponent(publicID)
    }
}
