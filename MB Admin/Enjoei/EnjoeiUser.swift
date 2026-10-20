import Foundation

/// Usuário logado no Enjoei, do ponto de vista do app.
nonisolated struct EnjoeiUser: Identifiable, Equatable, Sendable, Codable {
    let id: Int
    let nickname: String
    let name: String
    let avatarPublicID: String?
    let availableProductsCount: Int?

    var storeURL: URL { EnjoeiAPI.storeURL(nickname: nickname) }

    var avatarURL: URL? {
        guard let avatarPublicID else { return nil }
        // `.bigAvatar`, não `.avatar`: o avatar aparece maior na tela, e uma foto de origem maior
        // evita ela ficar borrada ao esticar.
        return EnjoeiPhoto.url(publicID: avatarPublicID, size: .bigAvatar)
    }
}
