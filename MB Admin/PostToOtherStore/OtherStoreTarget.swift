import Foundation

/// Uma loja pra onde dá pra mandar produtos da loja aberta em "postar em outra loja" — e o que a
/// última comparação entre as duas diz sobre eles já existirem lá.
nonisolated struct OtherStoreTarget: Identifiable, Equatable, Sendable {
    let accountID: EnjoeiAccountID
    let name: String
    let nickname: String
    /// Quantos dos produtos a postar a última comparação entre as duas lojas casou com um de lá.
    let possibleDuplicateCount: Int
    /// O par mais parecido entre eles, de 0 a 100 — `nil` quando nenhum casou.
    let highestSimilarityPercent: Int?

    var id: EnjoeiAccountID { accountID }

    /// A linha de baixo de cada loja no menu: o "@nick", ou o risco de duplicar quando a última
    /// comparação achou o produto lá.
    func subtitle(productCount: Int) -> String {
        guard possibleDuplicateCount > 0 else { return "@\(nickname)" }
        if productCount == 1, let highestSimilarityPercent {
            return "pode já ter esse produto · \(highestSimilarityPercent)%"
        }
        return possibleDuplicateCount == 1
            ? "1 pode já existir lá"
            : "\(possibleDuplicateCount) podem já existir lá"
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
                let similarities = productIDs.compactMap {
                    matches.similarity(of: $0, from: sourceAccountID, to: account.id)
                }
                return OtherStoreTarget(
                    accountID: account.id,
                    name: account.user.name,
                    nickname: account.user.nickname,
                    possibleDuplicateCount: similarities.count,
                    highestSimilarityPercent: similarities.max().map { Int(($0 * 100).rounded()) }
                )
            }
    }
}
