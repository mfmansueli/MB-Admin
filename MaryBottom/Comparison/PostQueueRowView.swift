import SwiftUI

/// Uma linha da fila de ações: produto, de qual conta pra qual, o status, e um botão pra
/// tirar da fila.
struct PostQueueRowView: View {
    let item: PostQueueItem
    let status: MegaphoneStatus
    /// Link do anúncio novo, quando a resposta da criação trouxer como identificar ele.
    let productURL: URL?
    let onRemove: () -> Void

    @State private var isShowingErrorDetail = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 12) {
            ProductPhotoView(product: item.product, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.product.title)
                    .font(.subheadline)
                    .lineLimit(2)
                Text(item.originDestinationLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                statusText
            }
            Spacer(minLength: 8)
            if status == .succeeded, let productURL {
                Button("visualizar") {
                    openURL(productURL)
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
        .sheet(isPresented: $isShowingErrorDetail) {
            if case .failed(let message) = status {
                MegaphoneErrorDetailSheet(product: item.product, message: message)
            }
        }
    }

    /// Verbo no gerúndio/particípio pro `statusText` — só muda a palavra, o resto do layout (cor,
    /// ícone) é igual pros quatro tipos de ação.
    private var actionVerb: (inProgress: String, done: String) {
        switch item.kind {
        case .post: ("postando…", "postado")
        case .delete: ("apagando…", "apagado")
        case .inactivate: ("inativando…", "inativado")
        case .activate: ("ativando…", "ativado")
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch status {
        case .pending:
            Label("esperando a vez", systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.tertiary)
        case .megaphoning:
            Label(actionVerb.inProgress, systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.blue)
        case .succeeded:
            Label(actionVerb.done, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed(let message):
            Button {
                isShowingErrorDetail = true
            } label: {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    PostQueueRowView(
        item: PostQueueItem(
            id: UUID(),
            product: EnjoeiProduct(
                id: 1,
                title: "brinco argola estrela 50mm",
                path: "brinco-argola-estrela-1",
                photoPublicID: nil,
                currentPrice: 273,
                originalPrice: 399
            ),
            sourceAccountID: UUID(),
            sourceAccountName: "loja A",
            destinationAccountID: UUID(),
            destinationAccountName: "loja B"
        ),
        status: .pending,
        productURL: nil,
        onRemove: {}
    )
    .padding()
}
