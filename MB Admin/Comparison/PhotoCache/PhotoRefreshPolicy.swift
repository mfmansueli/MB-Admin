import Foundation

/// Quando uma assinatura salva precisa ser conferida de novo. URL (id público) estável não prova
/// conteúdo igual — então, depois de `maxAge` (com uma folga determinística por foto, pra não vencer
/// tudo no mesmo dia), a foto é baixada de novo ignorando o cache. Bytes iguais: só a data anda;
/// diferentes: a assinatura é refeita. Se a reconferência falhar, a assinatura antiga continua
/// valendo (ela descreve um conteúdo que de fato foi analisado).
nonisolated struct PhotoRefreshPolicy: Sendable {
    var maxAge: TimeInterval = PhotoMatchingParameters.signatureMaxAge
    var jitterFraction: Double = PhotoMatchingParameters.signatureRefreshJitter

    static let standard = PhotoRefreshPolicy()
    /// Nunca reconfere — testes que não são sobre isso.
    static let never = PhotoRefreshPolicy(maxAge: .infinity, jitterFraction: 0)

    func needsRefresh(publicID: String, verifiedAt: Date, now: Date) -> Bool {
        guard maxAge.isFinite else { return false }
        return now.timeIntervalSince(verifiedAt) >= maxAge * (1 + jitterFraction * Self.unitJitter(for: publicID))
    }

    /// Entre −1 e 1, sempre o mesmo pra mesma foto (FNV-1a; `hashValue` muda a cada execução).
    static func unitJitter(for publicID: String) -> Double {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in publicID.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return Double(hash % 2001) / 1000 - 1
    }
}
