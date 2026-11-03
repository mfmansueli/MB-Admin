import Foundation

/// A última comparação num arquivo só, em Application Support — escrito uma vez por comparação
/// terminada e lido uma vez ao reabrir a tela (não é lista que muda item a item, então não vai pro
/// SwiftData). Codificar, decodificar e mexer no arquivo roda fora do MainActor; cada operação espera a
/// anterior terminar, então "apagar" pedido depois de "gravar" nunca deixa o arquivo velho pra trás.
final class FileComparisonSnapshotStore: ComparisonSnapshotStoring {
    private let url: URL
    private var lastOperation: Task<Void, Never>?
    /// O que as operações na fila vão deixar — `hasSnapshot` responde certo antes delas terminarem.
    private var pendingExists: Bool?

    init(url: URL = URL.applicationSupportDirectory.appending(path: "Comparison/last-comparison.json")) {
        self.url = url
    }

    var hasSnapshot: Bool {
        pendingExists ?? FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    func load() async -> ComparisonSnapshot? {
        await lastOperation?.value
        return await Self.read(url)
    }

    func save(_ snapshot: ComparisonSnapshot) async {
        pendingExists = true
        await enqueue { [url] in await Self.write(snapshot, to: url) }
    }

    func delete() async {
        pendingExists = false
        await enqueue { [url] in await Self.remove(url) }
    }

    private func enqueue(_ operation: @escaping @Sendable () async -> Void) async {
        let previous = lastOperation
        let task = Task {
            await previous?.value
            await operation()
        }
        lastOperation = task
        await task.value
    }

    @concurrent
    private nonisolated static func read(_ url: URL) async -> ComparisonSnapshot? {
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(ComparisonSnapshot.self, from: data),
              snapshot.format == ComparisonSnapshot.currentFormat else { return nil }
        return snapshot
    }

    @concurrent
    private nonisolated static func write(_ snapshot: ComparisonSnapshot, to url: URL) async {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    @concurrent
    private nonisolated static func remove(_ url: URL) async {
        try? FileManager.default.removeItem(at: url)
    }
}
