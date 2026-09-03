import SwiftUI

/// Uma linha do histórico: produto, de qual conta pra qual, o resultado final e quando terminou.
struct PostHistoryRowView: View {
    let entry: PostHistoryEntry

    @State private var isShowingErrorDetail = false

    var body: some View {
        HStack(spacing: 12) {
            ProductPhotoView(product: entry.product, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.product.title)
                    .font(.subheadline)
                    .lineLimit(2)
                Text(entry.originDestinationLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                outcomeText
            }
            Spacer(minLength: 8)
            Text(entry.completedAt, format: .relative(presentation: .named))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .sheet(isPresented: $isShowingErrorDetail) {
            if case .failed(let message) = entry.outcome {
                MegaphoneErrorDetailSheet(product: entry.product, message: message, detail: entry.failureDetail)
            }
        }
    }

    /// Verbo no particípio pro rótulo do resultado — mesma ideia de
    /// `PostQueueRowView.actionVerb.done`, só que aqui a ação já terminou (uma entrada de
    /// histórico nunca está "megafonando"/pendente).
    private var actionVerbDone: String {
        switch entry.kind {
        case .post: "postado"
        case .delete: "apagado"
        case .inactivate: "inativado"
        case .activate: "ativado"
        }
    }

    @ViewBuilder
    private var outcomeText: some View {
        switch entry.outcome {
        case .succeeded:
            Label(actionVerbDone, systemImage: "checkmark.circle.fill")
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
    PostHistoryRowView(
        entry: PostHistoryEntry(
            id: UUID(),
            product: EnjoeiProduct(
                id: 1,
                title: "brinco argola estrela 50mm",
                path: "brinco-argola-estrela-1",
                photoPublicID: nil,
                currentPrice: 273,
                originalPrice: 399
            ),
            kind: .post,
            sourceAccountID: UUID(),
            sourceAccountName: "loja A",
            destinationAccountID: UUID(),
            destinationAccountName: "loja B",
            outcome: .succeeded,
            completedAt: .now
        )
    )
    .padding()
}
