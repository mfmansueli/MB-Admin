import SwiftUI

/// Uma linha da fila de publicação: produto, de qual conta pra qual, o status, e um botão pra
/// tirar da fila.
struct PostQueueRowView: View {
    let item: PostQueueItem
    let status: MegaphoneStatus
    /// Link do anúncio novo, quando a resposta da criação trouxer como identificar ele.
    let productURL: URL?
    let onRemove: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 12) {
            ProductPhotoView(product: item.product, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.product.title)
                    .font(.subheadline)
                    .lineLimit(2)
                Text(originDestinationLine)
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
    }

    /// Republicar na mesma conta (origem == destino) fica "republicando X" — "de X para X" é
    /// tecnicamente certo, mas confuso de ler.
    private var originDestinationLine: String {
        if item.sourceAccountID == item.destinationAccountID {
            "republicando em \(item.sourceAccountName)"
        } else {
            "de \(item.sourceAccountName) para \(item.destinationAccountName)"
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
            Label("postando…", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.blue)
        case .succeeded:
            Label("postado", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
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
