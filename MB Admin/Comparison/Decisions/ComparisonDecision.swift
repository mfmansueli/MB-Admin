import Foundation

/// Uma revisão manual de um par: "mesmo produto" ou "produtos diferentes", com o estado dos dois
/// anúncios no momento da decisão (`ListingFingerprint`). Só nasce de um toque explícito do usuário —
/// uma sugestão automática nunca vira decisão sozinha.
nonisolated struct ComparisonDecision: Equatable, Sendable {
    nonisolated enum Verdict: String, Sendable, Codable {
        case sameProduct
        case differentProducts
    }

    let first: ListingKey
    let second: ListingKey
    let verdict: Verdict
    let decidedAt: Date
    let firstFingerprint: ListingFingerprint
    let secondFingerprint: ListingFingerprint

    /// Ordena os dois lados como `ListingPairKey`, pra mesma decisão sair igual não importa a ordem
    /// em que as lojas foram escolhidas.
    init(
        _ one: (key: ListingKey, fingerprint: ListingFingerprint),
        _ other: (key: ListingKey, fingerprint: ListingFingerprint),
        verdict: Verdict,
        decidedAt: Date
    ) {
        let (low, high) = one.key < other.key ? (one, other) : (other, one)
        first = low.key
        second = high.key
        firstFingerprint = low.fingerprint
        secondFingerprint = high.fingerprint
        self.verdict = verdict
        self.decidedAt = decidedAt
    }

    var pairKey: ListingPairKey { ListingPairKey(first, second) }

    func fingerprint(of key: ListingKey) -> ListingFingerprint? {
        if key == first { return firstFingerprint }
        if key == second { return secondFingerprint }
        return nil
    }

    /// Algum dos dois anúncios mudou (capa ou título) desde a decisão.
    func isStale(current: [ListingKey: ListingFingerprint]) -> Bool {
        guard let currentFirst = current[first], let currentSecond = current[second] else { return false }
        return currentFirst != firstFingerprint || currentSecond != secondFingerprint
    }
}
