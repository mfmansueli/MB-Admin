import Foundation

/// Usuário logado no Enjoei, do ponto de vista do app.
nonisolated struct EnjoeiUser: Identifiable, Equatable, Sendable {
    let id: Int
    let nickname: String
    let name: String
    let avatarPublicID: String?
    let availableProductsCount: Int?

    var storeURL: URL { EnjoeiAPI.storeURL(nickname: nickname) }

    var avatarURL: URL? {
        guard let avatarPublicID else { return nil }
        return EnjoeiPhoto.url(publicID: avatarPublicID, size: .avatar)
    }
}
