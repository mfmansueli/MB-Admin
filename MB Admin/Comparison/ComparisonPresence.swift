import Foundation

/// O que a última comparação concluiu sobre um produto na outra loja — o que "postar em outra loja"
/// usa pra avisar. Só `present` e `possible` viram aviso; `possiblyMissing`/`unverified` não dizem
/// que o produto existe lá (e `unverified` também não diz que não existe).
nonisolated enum ComparisonPresence: Int, Comparable, Sendable {
    case possiblyMissing = 0
    case unverified = 1
    /// Há um indício (par em revisão).
    case possible = 2
    /// Correspondência forte ou confirmada.
    case present = 3

    static func < (lhs: ComparisonPresence, rhs: ComparisonPresence) -> Bool { lhs.rawValue < rhs.rawValue }
}
