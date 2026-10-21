import Foundation

/// As seções da fila de ações, na ordem da tela: o que está em voo ("agora"), o que espera a vez
/// ("na fila"), o que falhou ("com erro") e o que já deu certo ("feitos"). Cada item entra numa
/// seção só, mantendo a ordem da fila dentro dela.
nonisolated struct PostQueueSections {
    enum Kind: CaseIterable, Hashable, Identifiable {
        case now
        case waiting
        case failed
        case done

        var id: Self { self }

        /// "agora" fica sem contagem — é sempre um item só.
        func header(count: Int) -> String {
            switch self {
            case .now: "agora"
            case .waiting: "na fila · \(count)"
            case .failed: "com erro · \(count)"
            case .done: "feitos · \(count)"
            }
        }
    }

    private var itemsByKind: [Kind: [PostQueueItem]] = [:]

    init(items: [PostQueueItem], status: (PostQueueItem) -> MegaphoneStatus) {
        for item in items {
            itemsByKind[Self.kind(for: status(item)), default: []].append(item)
        }
    }

    func items(in kind: Kind) -> [PostQueueItem] {
        itemsByKind[kind] ?? []
    }

    /// Só as seções com alguma coisa, na ordem da tela.
    var visibleKinds: [Kind] {
        Kind.allCases.filter { !items(in: $0).isEmpty }
    }

    private static func kind(for status: MegaphoneStatus) -> Kind {
        switch status {
        case .megaphoning: .now
        case .pending: .waiting
        case .failed: .failed
        case .succeeded: .done
        }
    }
}
