import SwiftUI

/// Row compacta de uma conta na lista: quem é, e como anda o megafone dela — ao vivo enquanto está
/// rodando, ou o resumo da última rodada quando está parado.
struct AccountRowView: View {
    let account: AccountSession

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
