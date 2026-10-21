import SwiftUI

/// Row compacta de uma conta na lista: quem é, e como anda o megafone dela — ao vivo enquanto está
/// rodando (com o anel de progresso em volta da foto), ou o resumo da última rodada quando está
/// parado, junto de quantos produtos pedem desconto.
struct AccountRowView: View {
    let account: AccountSession

    @Environment(AccountsStore.self) private var accountsStore
    /// `.increased` numa row selecionada da barra lateral do iPad (fundo no destaque da seleção) —
    /// ali as cores de papel somem em cima do destaque, então tudo vira branco — o destaque
    /// (`SidebarSelection`, ver `AccountsListView`) é escuro nos dois modos justamente pra isso. No
    /// Mac Catalyst o SwiftUI não marca a row selecionada assim; lá o próprio sistema já escreve em
    /// branco, e quem garante a leitura é a cor do destaque.
    @Environment(\.backgroundProminence) private var backgroundProminence

    var body: some View {
        HStack(spacing: 12) {
            // O andamento fica num anel em volta da foto, não num anel à parte no canto — assim o
            // texto do status ("rodada 2 de 100 · 721 de 1.493") fica com a largura toda da row, em
            // vez de quebrar em três linhas e ainda cortar no fim.
            AccountAvatarView(
                user: account.user,
                isDimmed: account.status == .sessionExpired,
                progress: statusLine.progress,
                progressStyle: ringStyle
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(account.user.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isProminent ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                statusLabel
                // Linha própria embaixo do status em todo lugar, inclusive na barra lateral do
                // iPad/Mac — um selo "🏷 94" no canto roubava largura do status, que no tamanho de
                // letra do app chegava a hifenizar em três linhas ("megafon-ado").
                if showsDiscountLine {
                    Label(discountLineText, systemImage: "tag.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(style(for: .statusDecision))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    // `progressSnapshot`, não `MegaphoneStatusText` montado direto dos campos do runner: ler
    // `runner.items`/`processedCount` aqui faria essa row recalcular a cada produto megafonado (até
    // 1500+ vezes por rodada, em cada conta rodando ao mesmo tempo) — ver
    // `MegaphoneProgressSnapshot`.
    private var statusLine: AccountStatusLine {
        AccountStatusLine(
            sessionStatus: account.status,
            crossAccountActivity: crossAccountActivity,
            snapshot: account.runner.progressSnapshot,
            lastRoundSummary: account.lastRoundSummary
        )
    }

    private var statusLabel: some View {
        let line = statusLine
        return HStack(alignment: .firstTextBaseline, spacing: 5) {
            if let symbol = line.symbol {
                Image(systemName: symbolName(symbol))
                    .font(.caption)
                    .symbolEffect(.pulse, options: .repeating, isActive: line.isAnimating)
            }
            Text(line.text)
                .lineLimit(3)
        }
        .font(.subheadline)
        .foregroundStyle(style(for: line.role))
    }

    private var isProminent: Bool { backgroundProminence == .increased }

    private var discountCount: Int { account.runner.progressSnapshot.discountDecisionCount }

    /// Só com a conta parada e em dia — rodando, a row já fala do andamento; com a sessão caída,
    /// o que importa é entrar de novo.
    private var showsDiscountLine: Bool {
        account.status == .active
            && crossAccountActivity == nil
            && !account.runner.progressSnapshot.phase.isActive
            && discountCount > 0
    }

    private var discountLineText: String {
        discountCount == 1 ? "1 pede desconto" : "\(discountCount) pedem desconto"
    }

    private func symbolName(_ symbol: AccountStatusLine.Symbol) -> String {
        switch symbol {
        case .megaphone: "megaphone.fill"
        case .clock: "clock"
        case .pause: "pause.fill"
        case .warning: "exclamationmark.triangle.fill"
        }
    }

    private func style(for role: AccountStatusLine.Role) -> AnyShapeStyle {
        switch role {
        case .inProgress: style(for: .statusInProgress)
        case .supporting: style(for: .supportingText)
        case .failure: style(for: .statusFailure)
        }
    }

    private func style(for color: Color) -> AnyShapeStyle {
        isProminent ? AnyShapeStyle(Color.white.opacity(0.8)) : AnyShapeStyle(color)
    }

    /// Mesma cor do texto do status: em andamento quando está megafonando de verdade, texto de apoio
    /// pausado.
    private var ringStyle: AnyShapeStyle {
        if isProminent { return AnyShapeStyle(Color.white) }
        return statusLine.isAnimating ? AnyShapeStyle(Color.statusInProgress) : AnyShapeStyle(Color.supportingText)
    }

    /// Postagem (ou exclusão) entre contas mexe com origem e destino ao mesmo tempo — mostra em
    /// qualquer uma das duas rows envolvidas, mesmo com a tela de comparação fechada.
    private var crossAccountActivity: String? {
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
}
