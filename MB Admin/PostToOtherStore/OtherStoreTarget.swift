import Foundation

/// Uma loja pra onde dá pra mandar produtos da loja aberta em "postar em outra loja" — e o que a
/// última comparação entre as duas diz sobre eles já existirem lá.
nonisolated struct OtherStoreTarget: Identifiable, Equatable, Sendable {
    let accountID: EnjoeiAccountID
    let name: String
    let nickname: String
    /// Quantos dos produtos a postar a última comparação achou lá com certeza (mesma foto, ou
    /// confirmado por você).
    let existingCount: Int
    /// Quantos ficaram "pra revisar" com algum anúncio de lá — pode ser o mesmo produto.
    let possibleCount: Int
    /// Quantos não estão lá nesta versão, mas lá tem outra versão deles (mesma foto, outro aro/banho/
    /// cor/medida) — informação, não risco de duplicar.
    var otherVersionCount = 0

    var id: EnjoeiAccountID { accountID }

    /// Algum dos produtos pode já existir lá (certo ou provável).
    var possibleDuplicateCount: Int { existingCount + possibleCount }

    /// A linha de baixo de cada loja no menu: o "@nick", ou o risco de duplicar quando a última
    /// comparação achou o produto (ou um indício dele) lá.
    func subtitle(productCount: Int) -> String {
        guard possibleDuplicateCount > 0 else {
            guard otherVersionCount > 0 else { return "@\(nickname)" }
            if productCount == 1 { return "tem outra versão desse produto" }
            return otherVersionCount == 1 ? "1 tem outra versão lá" : "\(otherVersionCount) têm outra versão lá"
        }
        if productCount == 1 {
            return existingCount > 0 ? "já tem esse produto" : "pode já ter esse produto"
        }
        var parts: [String] = []
        if existingCount > 0 {
            parts.append(existingCount == 1 ? "1 já existe lá" : "\(existingCount) já existem lá")
        }
        if possibleCount > 0 {
            parts.append(possibleCount == 1 ? "1 pode existir lá" : "\(possibleCount) podem existir lá")
        }
        return parts.joined(separator: " · ")
    }

    /// As outras lojas com sessão aberta agora, na ordem da lista de contas. Sessão vencida ou não
    /// confirmada fica de fora (a lista de contas já pede pra entrar de novo nelas); uma loja
    /// megafonando continua valendo — a fila de ações roda por conta própria.
    @MainActor
    static func candidates(
        for productIDs: [Int],
        from sourceAccountID: EnjoeiAccountID,
        among accounts: [AccountSession],
        matches: ComparisonMatchMemory
    ) -> [OtherStoreTarget] {
        accounts
            .filter { $0.id != sourceAccountID && $0.status == .active }
            .map { account in
                let presences = productIDs.compactMap {
                    matches.presence(of: $0, from: sourceAccountID, to: account.id)
                }
                return OtherStoreTarget(
                    accountID: account.id,
                    name: account.user.name,
                    nickname: account.user.nickname,
                    existingCount: presences.count { $0 == .present },
                    possibleCount: presences.count { $0 == .possible },
                    otherVersionCount: presences.count { $0 == .otherVersion }
                )
            }
    }
}
