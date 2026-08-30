import Foundation

/// Resposta das APIs de usuário do Enjoei (`/api/v3/current_user.json` e
/// `/api/v3/users/{nickname}.json`).
///
/// Todos os campos são opcionais de propósito: as duas rotas devolvem recortes diferentes do mesmo
/// usuário, e o app só precisa do que der para aproveitar.
nonisolated struct EnjoeiUserPayload: Decodable, Equatable, Sendable {
    let id: Int?
    let nickname: String?
    let name: String?
    let avatar: Photo?
    let counters: Counters?

    struct Photo: Decodable, Equatable, Sendable {
        let imagePublicID: String?

        private enum CodingKeys: String, CodingKey {
            case imagePublicID = "image_public_id"
        }
    }

    struct Counters: Decodable, Equatable, Sendable {
        let availableProductsCount: Int?

        private enum CodingKeys: String, CodingKey {
            case availableProductsCount = "available_products_count"
        }
    }

    /// Converte para o modelo do app. Devolve `nil` quando a resposta não identifica ninguém —
    /// é o caso do corpo vazio que a API manda para visitante.
    func makeUser() -> EnjoeiUser? {
        guard let id, let nickname, !nickname.isEmpty else { return nil }
        return EnjoeiUser(
            id: id,
            nickname: nickname,
            name: name ?? nickname,
            avatarPublicID: avatar?.imagePublicID,
            availableProductsCount: counters?.availableProductsCount
        )
    }
}
