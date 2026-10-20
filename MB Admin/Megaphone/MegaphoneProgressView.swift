import SwiftUI

/// Resumo do andamento do megafone.
struct MegaphoneProgressView: View {
    let runner: MegaphoneRunner

    // `runner.progressSnapshot`, não os campos do runner direto: ler `runner.items`/
    // `processedCount` aqui faria essa view recalcular a cada produto megafonado (até 1500+ vezes
    // por rodada) — ver `MegaphoneProgressSnapshot`.
    private var statusText: MegaphoneStatusText { runner.progressSnapshot.statusText }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Sem nada acontecendo ainda, o próprio botão "megafonar" já diz isso — a linha some,
            // em vez de repetir com "pronto para megafonar.".
            if runner.phase != .idle {
                Text(statusText.headline)
                    .font(.headline.weight(.medium))
            }

            if let progress = statusText.progress {
                ProgressView(value: progress)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
