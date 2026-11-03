import SwiftUI

/// Aviso no topo do resultado quando a comparação não ficou completa (lista que falhou ou veio
/// faltando, fotos/templates que não carregaram) ou quando revisões antigas deixaram de valer — com
/// "tentar de novo". Enquanto houver problema, o que depende dele fica em "não deu pra verificar",
/// nunca em "possivelmente ausentes".
struct ComparisonProblemsCard: View {
    let result: AccountComparisonResult
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(result.hasProblems ? "a comparação não ficou completa" : "revisões desatualizadas", systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if result.hasProblems {
                Button("tentar de novo", action: onRetry)
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var lines: [String] {
        var lines = result.storeA.problems.map { "\(result.storeA.name): \($0)" }
            + result.storeB.problems.map { "\(result.storeB.name): \($0)" }
        switch result.staleDecisionCount {
        case 0: break
        case 1: lines.append("1 revisão sua deixou de valer porque o anúncio mudou")
        case let count: lines.append("\(count) revisões suas deixaram de valer porque os anúncios mudaram")
        }
        return lines
    }
}
