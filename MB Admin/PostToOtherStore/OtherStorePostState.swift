import Foundation

/// Onde está a postagem de um produto da loja aberta numa outra loja, pela fila de ações — o que
/// a linha embaixo do preço mostra ("na fila pra loja B", "postando em loja B…", "postado em loja
/// B", "não deu pra postar em loja B").
nonisolated struct OtherStorePostState: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case queued
        case posting
        case posted
        case failed(String)
    }

    let item: PostQueueItem
    let phase: Phase

    var storeName: String { item.destinationAccountName }

    var text: String {
        switch phase {
        case .queued: "na fila pra \(storeName)"
        case .posting: "postando em \(storeName)…"
        case .posted: "postado em \(storeName)"
        case .failed: "não deu pra postar em \(storeName)"
        }
    }

    var systemImage: String {
        switch phase {
        case .queued: "clock"
        case .posting: "paperplane.fill"
        case .posted: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var isPosting: Bool { phase == .posting }

    var failureMessage: String? {
        if case .failed(let message) = phase { return message }
        return nil
    }

    /// A postagem mais recente desse produto da loja `sourceAccountID` pra qualquer outra loja —
    /// repostar na própria loja (origem = destino) não conta, tem a própria linha no menu.
    /// `nil` quando o produto não passou pela fila pra outra loja (ou a fila foi limpa).
    static func latest(
        productID: Int,
        sourceAccountID: EnjoeiAccountID,
        in items: [PostQueueItem],
        status: (PostQueueItem) -> MegaphoneStatus
    ) -> OtherStorePostState? {
        guard let item = items.last(where: { (candidate: PostQueueItem) -> Bool in
            guard candidate.kind == .post, candidate.product.id == productID else { return false }
            return candidate.sourceAccountID == sourceAccountID && candidate.destinationAccountID != sourceAccountID
        }) else { return nil }
        let phase: Phase = switch status(item) {
        case .pending: .queued
        case .megaphoning: .posting
        case .succeeded: .posted
        case .failed(let message): .failed(message)
        }
        return OtherStorePostState(item: item, phase: phase)
    }
}
