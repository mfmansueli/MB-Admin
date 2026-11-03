import Foundation

/// A última comparação só na memória — testes e modo de demonstração (nada vai pro disco).
final class InMemoryComparisonSnapshotStore: ComparisonSnapshotStoring {
    private(set) var snapshot: ComparisonSnapshot?

    init(snapshot: ComparisonSnapshot? = nil) {
        self.snapshot = snapshot
    }

    var hasSnapshot: Bool { snapshot != nil }

    func load() async -> ComparisonSnapshot? { snapshot }

    func save(_ snapshot: ComparisonSnapshot) async {
        self.snapshot = snapshot
    }

    func delete() async {
        snapshot = nil
    }
}
