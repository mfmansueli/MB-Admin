import Foundation

/// O que a última comparação concluiu sobre um produto na outra loja — o que "postar em outra loja"
/// usa pra avisar. `present` e `possible` viram aviso de duplicata; `otherVersion` só informa (lá tem
/// o produto em outra versão — postar esta não duplica nada); `possiblyMissing`/`unverified` não
/// dizem que o produto existe lá (e `unverified` também não diz que não existe).
nonisolated enum ComparisonPresence: Int, Comparable, Sendable {
    case possiblyMissing = 0
    /// Possivelmente ausente nesta versão, mas a loja tem outra versão (a mesma foto com aro, banho,
    /// cor ou medida diferente).
    case otherVersion = 1
    case unverified = 2
    /// Há um indício (par em revisão).
    case possible = 3
    /// Correspondência forte ou confirmada.
    case present = 4

    static func < (lhs: ComparisonPresence, rhs: ComparisonPresence) -> Bool { lhs.rawValue < rhs.rawValue }
}
