import Foundation

/// Onde fica a última comparação (`ComparisonSnapshot`) — uma só, a mais recente. Gravar e apagar
/// rodam na ordem em que foram pedidos.
protocol ComparisonSnapshotStoring: AnyObject {
    /// Há uma comparação guardada (barato: pode ser lido a cada abertura da tela).
    var hasSnapshot: Bool { get }
    func load() async -> ComparisonSnapshot?
    /// Substitui a que estava guardada.
    func save(_ snapshot: ComparisonSnapshot) async
    func delete() async
}
