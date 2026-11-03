import SwiftUI

/// Aviso no topo do resultado quando as suas revisões decidiram outros pares sozinhas
/// (`ReviewLearning`): quantos viraram "mesmo produto" e quantos "diferentes", e a partir de que
/// índice — pra você saber de onde veio a mudança nas listas e que dá pra corrigir na própria linha.
struct ComparisonLearningCard: View {
    let learning: ReviewLearning

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("suas revisões ajustaram a lista", systemImage: "wand.and.sparkles")
                .font(.subheadline.weight(.semibold))
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("learningCard")
    }

    private var lines: [String] {
        var lines: [String] = []
        if learning.learnedSame > 0, let floor = learning.sameFloor {
            let verb = learning.learnedSame == 1 ? "virou" : "viraram"
            lines.append("\(pairs(learning.learnedSame)) com índice \(floor) ou mais \(verb) \"mesmo produto\".")
        }
        if learning.learnedDifferent > 0, let ceiling = learning.differentCeiling {
            let verb = learning.learnedDifferent == 1 ? "saiu" : "saíram"
            lines.append("\(pairs(learning.learnedDifferent)) com índice até \(ceiling) \(verb) da revisão como \"diferentes\".")
        }
        lines.append("é o que os pares que você já revisou indicam. se algum estiver errado, corrija na própria linha — vale como mais uma revisão.")
        return lines
    }

    private func pairs(_ count: Int) -> String {
        count == 1 ? "1 par" : "\(count) pares"
    }
}
