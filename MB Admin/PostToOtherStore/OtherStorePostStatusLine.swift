import SwiftUI

/// A linha embaixo do preço de uma row de publicados enquanto (e depois que) a fila posta o
/// produto numa outra loja. O anúncio daqui continua publicado, então a row não apaga — só ganha
/// esta linha. Com erro, tocar abre o detalhe do erro.
struct OtherStorePostStatusLine: View {
    let state: OtherStorePostState
    var onShowFailure: () -> Void = {}

    var body: some View {
        if state.failureMessage != nil {
            Button(action: onShowFailure) {
                content
            }
            .buttonStyle(.plain)
            .accessibilityHint("abre o detalhe do erro")
        } else {
            content
        }
    }

    private var content: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: state.systemImage)
                .font(.caption)
                .symbolEffect(.pulse, isActive: state.isPosting)
                .accessibilityHidden(true)
            Text(state.text)
                .font(.subheadline)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch state.phase {
        case .queued: .supportingText
        case .posting: .statusInProgress
        case .posted: .statusSuccess
        case .failed: .statusFailure
        }
    }
}
