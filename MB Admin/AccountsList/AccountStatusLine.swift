import Foundation

/// O que a row de uma conta na lista diz sobre ela, e em que papel de cor — extraído de
/// `AccountRowView` pra a regra (sessão > ação da fila > megafone > última rodada) ser testável sem
/// montar a view.
nonisolated struct AccountStatusLine: Equatable, Sendable {
    /// Papel de cor do redesign — cada um com um significado só (ver `Assets.xcassets`).
    enum Role: Equatable, Sendable {
        case inProgress
        case supporting
        case failure
    }

    enum Symbol: Equatable, Sendable {
        case megaphone
        case clock
        case pause
        case warning
    }

    let text: String
    let role: Role
    let symbol: Symbol?
    /// Anel de progresso no canto da row — só com uma rodada em aberto e fração conhecida.
    let progress: Double?
    /// Pulsa o ícone só com trabalho de verdade acontecendo agora — pausado ou esperando a vez na
    /// fila (`MegaphoneQueue`) têm uma rodada em aberto, mas nada rodando.
    let isAnimating: Bool

    init(text: String, role: Role, symbol: Symbol? = nil, progress: Double? = nil, isAnimating: Bool = false) {
        self.text = text
        self.role = role
        self.symbol = symbol
        self.progress = progress
        self.isAnimating = isAnimating
    }

    /// - Parameter crossAccountActivity: texto da ação da fila em voo envolvendo esta conta (ver
    ///   `AccountRowView.crossAccountActivity`), quando houver.
    /// - Parameter now: parâmetro (em vez de `Date.now` direto) pro teste ser determinístico.
    init(
        sessionStatus: AccountSessionStatus,
        crossAccountActivity: String?,
        snapshot: MegaphoneProgressSnapshot,
        lastRoundSummary: MegaphoneRoundSummary?,
        now: Date = .now
    ) {
        switch sessionStatus {
        case .sessionExpired:
            self.init(text: "sessão expirada — toque para entrar de novo", role: .failure, symbol: .warning)
            return
        case .checkFailed:
            self.init(text: "não deu pra conferir a sessão — toque para tentar de novo", role: .failure, symbol: .warning)
            return
        case .active:
            break
        }
        if let crossAccountActivity {
            self.init(text: crossAccountActivity, role: .inProgress)
            return
        }
        let statusText = snapshot.statusText
        switch snapshot.phase {
        case .waitingInQueue:
            self.init(text: statusText.headline, role: .supporting, symbol: .clock)
        case .paused:
            self.init(text: statusText.compactLine, role: .supporting, symbol: .pause, progress: statusText.progress)
        case .loadingProducts, .checkingExposure, .megaphoning:
            self.init(
                text: statusText.compactLine,
                role: .inProgress,
                symbol: .megaphone,
                progress: statusText.progress,
                isAnimating: true
            )
        case .idle, .finished, .cancelled, .failed:
            self.init(text: lastRoundSummary?.summaryText(now: now) ?? "ainda não megafonado", role: .supporting)
        }
    }
}
