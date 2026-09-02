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
                HStack(spacing: 4) {
                    // O ícone marca visualmente que essa linha é sobre o megafone — sem ele
                    // (e com o "última rodada:" que existia antes), a origem do resumo não ficava
                    // clara à primeira vista.
                    if showsMegaphoneIcon {
                        // Pulsa só enquanto o megafone está de fato rodando (não enquanto pausado)
                        // — é o único sinal, nessa lista compacta, de que uma conta está ativa sem
                        // precisar entrar nela.
                        // `.primary`/`.secondary`, não `.accentColor` — numa row selecionada (fundo
                        // azul da seleção) um ícone azul fixo desaparecia por cima do próprio
                        // destaque; as cores semânticas se invertem certo em cima da seleção.
                        Image(systemName: "megaphone.fill")
                            .font(.caption)
                            .foregroundStyle(isMegaphoneRunning ? Color.primary : Color.secondary)
                            .symbolEffect(.pulse, options: .repeating, isActive: isMegaphoneRunning)
                    }
                    Text(statusLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Mesma condição dos primeiros `if`s de `statusLine` — sessão expirada ou não conferida ainda
    /// não são sobre o megafone, então não levam o ícone.
    private var showsMegaphoneIcon: Bool {
        account.status == .active && crossAccountPostLine == nil
    }

    /// Diferente de `MegaphonePhase.isActive`: pausado (pelo usuário ou em segundo plano) não conta
    /// como "rodando" pra esse pulso — a intenção é sinalizar trabalho acontecendo agora, não só
    /// uma rodada em aberto.
    private var isMegaphoneRunning: Bool {
        switch account.runner.phase {
        case .loadingProducts, .checkingExposure, .megaphoning: true
        case .idle, .paused, .finished, .cancelled, .failed: false
        }
    }

    /// Postagem (ou exclusão) entre contas mexe com origem e destino ao mesmo tempo — mostra em
    /// qualquer uma das duas rows envolvidas, mesmo com a tela de comparação fechada.
    private var crossAccountPostLine: String? {
        guard let currentItem = accountsStore.postQueue.currentItem else { return nil }
        switch currentItem.kind {
        case .delete:
            guard currentItem.sourceAccountID == account.id else { return nil }
            return "apagando \"\(currentItem.product.title)\"…"
        case .inactivate:
            guard currentItem.sourceAccountID == account.id else { return nil }
            return "inativando \"\(currentItem.product.title)\"…"
        case .activate:
            guard currentItem.sourceAccountID == account.id else { return nil }
            return "ativando \"\(currentItem.product.title)\"…"
        case .post:
            break
        }
        if currentItem.sourceAccountID == currentItem.destinationAccountID, currentItem.sourceAccountID == account.id {
            return "republicando \"\(currentItem.product.title)\"…"
        }
        if currentItem.sourceAccountID == account.id {
            return "postando \"\(currentItem.product.title)\" para \(currentItem.destinationAccountName)…"
        }
        if currentItem.destinationAccountID == account.id {
            return "recebendo \"\(currentItem.product.title)\" de \(currentItem.sourceAccountName)…"
        }
        return nil
    }

    private var statusLine: String {
        if account.status == .sessionExpired {
            return "sessão expirada — toque para entrar de novo"
        }
        if account.status == .checkFailed {
            return "não deu pra conferir a sessão — toque para tentar de novo"
        }
        if let crossAccountPostLine {
            return crossAccountPostLine
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
