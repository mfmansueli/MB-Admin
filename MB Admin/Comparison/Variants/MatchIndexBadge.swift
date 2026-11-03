import SwiftUI

/// O índice de correspondência de um par, pequeno, na linha da lista — "82" sobre "índice", com a
/// cor da faixa (alto/médio/baixo). O detalhe do par mostra as parcelas.
struct MatchIndexBadge: View {
    let index: MatchIndex

    var body: some View {
        VStack(spacing: 0) {
            Text("\(index.score)")
                .font(.subheadline.weight(.bold).monospacedDigit())
            Text("índice")
                .font(.caption2)
        }
        .foregroundStyle(color)
        .frame(minWidth: 38)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("índice de correspondência \(index.score) de 100, \(index.levelText)")
    }

    private var color: Color {
        switch index.level {
        case .high: .statusSuccess
        case .medium: .statusInProgress
        case .low: .secondary
        }
    }
}
