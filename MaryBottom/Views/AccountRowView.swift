import SwiftUI

/// Row compacta de uma conta na lista: quem é, e como anda o megafone dela — ao vivo enquanto está
/// rodando, ou o resumo da última rodada quando está parado.
struct AccountRowView: View {
    let account: AccountSession

    @Environment(AccountsStore.self) private var accountsStore

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: account.user.avatarURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(.quaternary)
            }
            .frame(width: 60, height: 60)
            .clipShape(.circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.user.name)
                    .font(.title3.weight(.semibold))
                Text("@\(account.user.nickname)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(statusLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusLine: String {
        if account.status == .sessionExpired {
            return "sessão expirada — toque para entrar de novo"
        }
        // Postagem entre contas (avulsa ou pela fila) mexe com origem e destino ao mesmo tempo —
        // mostra em qualquer uma das duas rows envolvidas, mesmo com a tela de comparação fechada.
        if let currentItem = accountsStore.postQueue.currentItem {
            if currentItem.sourceAccountID == currentItem.destinationAccountID, currentItem.sourceAccountID == account.id {
                return "republicando \"\(currentItem.product.title)\"…"
            }
            if currentItem.sourceAccountID == account.id {
                return "postando \"\(currentItem.product.title)\" para \(currentItem.destinationAccountName)…"
            }
            if currentItem.destinationAccountID == account.id {
                return "recebendo \"\(currentItem.product.title)\" de \(currentItem.sourceAccountName)…"
            }
        }
        if account.runner.phase.isActive {
            return MegaphoneStatusText(
                phase: account.runner.phase,
                itemsCount: account.runner.items.count,
                processedCount: account.runner.processedCount,
                totalSucceeded: account.runner.totalSucceeded,
                totalFailed: account.runner.totalFailed,
                round: account.runner.round
            ).headline
        }
        if let summary = account.lastRoundSummary {
            return summary.summaryText()
        }
        return "ainda não megafonado"
    }
}
