import SwiftUI

/// Uma linha da fila de ações: produto, de qual conta pra qual, e o status na ponta — relógio
/// esperando a vez, girando em voo, triângulo vermelho quando falhou (abre o detalhe do erro, com
/// "tentar de novo"), "visualizar" quando o anúncio novo já tem link. Tirar da fila fica no menu de
/// contexto (toque longo / clique direito).
struct PostQueueRowView: View {
    let item: PostQueueItem
    let status: MegaphoneStatus
    /// Diagnóstico completo por trás de `status`, quando ela é `.failed` — `nil` em qualquer
    /// outro status. Ver `PostQueue.failureDetail(for:)`.
    let failureDetail: MegaphoneFailureDetail?
    /// Link do anúncio novo, quando a resposta da criação trouxer como identificar ele.
    let productURL: URL?
    let onRemove: () -> Void
    let onRetry: () -> Void

    @State private var isShowingErrorDetail = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 12) {
            ProductPhotoView(product: item.product, size: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.product.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                Text(item.originDestinationLine)
                    .font(.subheadline)
                    .foregroundStyle(item.kind == .delete ? AnyShapeStyle(Color.statusFailure) : AnyShapeStyle(Color.supportingText))
                statusLine
            }
            Spacer(minLength: 8)
            trailingStatus
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        // Fundo sólido pro scroll do mouse/trackpad funcionar em qualquer área da row no Mac
        // Catalyst, não só em cima da foto — ver o mesmo comentário em `MegaphoneRowView`.
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .contentShape(.rect)
        .contextMenu {
            if status.failureMessage != nil {
                Button(action: onRetry) {
                    Label("tentar de novo", systemImage: "arrow.clockwise")
                }
            }
            Button(role: .destructive, action: onRemove) {
                Label("tirar da fila", systemImage: "xmark.circle")
            }
        }
        .accessibilityAction(named: "tirar da fila", onRemove)
        .sheet(isPresented: $isShowingErrorDetail) {
            if case .failed(let message) = status {
                MegaphoneErrorDetailSheet(
                    product: item.product,
                    message: message,
                    detail: failureDetail,
                    onRetry: onRetry
                )
            }
        }
    }

    /// Verbo no gerúndio/particípio — só muda a palavra, o resto (cor, ícone) é igual pros quatro
    /// tipos de ação.
    private var actionVerb: (inProgress: String, done: String) {
        switch item.kind {
        case .post: ("postando…", "postado")
        case .delete: ("apagando…", "apagado")
        case .inactivate: ("inativando…", "inativado")
        case .activate: ("ativando…", "ativado")
        }
    }

    /// Terceira linha só quando tem o que dizer além do ícone: em voo, o verbo; com erro, a
    /// mensagem (tocar abre o detalhe); feito, o particípio. Esperando a vez, o relógio já basta.
    @ViewBuilder
    private var statusLine: some View {
        switch status {
        case .pending:
            EmptyView()
        case .megaphoning:
            Text(actionVerb.inProgress)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.statusInProgress)
        case .succeeded:
            Text(actionVerb.done)
                .font(.subheadline)
                .foregroundStyle(.statusSuccess)
        case .failed(let message):
            Button {
                isShowingErrorDetail = true
            } label: {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.statusFailure)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var trailingStatus: some View {
        switch status {
        case .pending:
            Image(systemName: "clock")
                .font(.title3)
                .foregroundStyle(.supportingText)
                .accessibilityLabel("esperando a vez")
        case .megaphoning:
            ProgressView()
                .tint(.statusInProgress)
                .accessibilityLabel("em andamento")
        case .succeeded:
            if let productURL {
                Button("visualizar") {
                    openURL(productURL)
                }
                .font(.subheadline.weight(.semibold))
                .glassButtonStyle()
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.statusSuccess)
                    .accessibilityLabel("feito")
            }
        case .failed:
            Button {
                isShowingErrorDetail = true
            } label: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(.statusFailure)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("falhou, ver detalhe do erro")
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
        failureDetail: nil,
        productURL: nil,
        onRemove: {},
        onRetry: {}
    )
    .padding()
}
