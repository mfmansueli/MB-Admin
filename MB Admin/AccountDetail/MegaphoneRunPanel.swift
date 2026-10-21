import SwiftUI

/// Painel de vidro flutuando embaixo da lista de publicados enquanto uma rodada está em aberto —
/// toma o lugar da barra de "megafonar": andamento, barra de progresso, acompanhar o produto da
/// vez, pausar e parar. Também aparece só buscando a loja (abrir a conta pela primeira vez,
/// recarregar), aí sem os controles — não tem o que pausar ainda.
///
/// iPhone: a contagem em destaque ("12 de 340") com rodada/intervalo/erros embaixo, pausar e parar
/// dividindo a largura. iPad/Mac: uma linha de status só e todos os controles numa fileira, com o
/// menu de repetições/intervalo no começo.
struct MegaphoneRunPanel: View {
    let runner: MegaphoneRunner
    @Binding var rounds: Int
    @Binding var speedMilliseconds: Int
    @Binding var isFollowing: Bool
    let isCompact: Bool

    // `runner.progressSnapshot`, não os campos do runner direto: ler `runner.items`/
    // `processedCount` aqui faria o painel recalcular a cada produto megafonado (até 1500+ vezes
    // por rodada) — ver `MegaphoneProgressSnapshot`.
    private var snapshot: MegaphoneProgressSnapshot { runner.progressSnapshot }
    private var statusText: MegaphoneStatusText { snapshot.statusText }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isCompact {
                compactHeader
            } else {
                regularHeader
            }

            if let progress = statusText.progress {
                ProgressView(value: progress)
                    .tint(.accentColor)
            }

            if hasControls {
                if isCompact {
                    HStack(spacing: 10) {
                        pauseButton
                        stopButton
                    }
                } else {
                    HStack(spacing: 10) {
                        MegaphoneSettingsMenu(rounds: $rounds, speedMilliseconds: $speedMilliseconds, isRoundsLocked: true)
                            .menuStyle(.button)
                            .buttonStyle(.neutral)
                        Spacer(minLength: 0)
                        followButton
                        pauseButton
                        stopButton
                    }
                }
            }
        }
        .padding(16)
        .glassSurface(in: .rect(cornerRadius: 32))
        .frame(maxWidth: isCompact ? .infinity : 660)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .animation(.default, value: hasControls)
    }

    /// Só faz sentido pausar/parar quando já está megafonando de verdade — buscando os produtos
    /// (seja pelo carregamento automático ou pelo recarregar), não tem o que pausar ainda.
    private var hasControls: Bool {
        switch snapshot.phase {
        case .megaphoning, .paused: true
        case .idle, .waitingInQueue, .loadingProducts, .checkingExposure, .finished, .cancelled, .failed: false
        }
    }

    private var isWorking: Bool {
        switch snapshot.phase {
        case .loadingProducts, .checkingExposure, .megaphoning: true
        case .idle, .waitingInQueue, .paused, .finished, .cancelled, .failed: false
        }
    }

    private var statusIcon: some View {
        Image(systemName: snapshot.phase == .waitingInQueue ? "clock" : "megaphone.fill")
            .font(.title2)
            .foregroundStyle(isWorking ? AnyShapeStyle(.primary) : AnyShapeStyle(.supportingText))
            .symbolEffect(.pulse, options: .repeating, isActive: isWorking)
            .frame(width: 32)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var compactHeader: some View {
        HStack(spacing: 10) {
            statusIcon
            if let count = statusText.count {
                VStack(alignment: .leading, spacing: 2) {
                    Text(count)
                        .font(.title2.bold())
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    compactDetails
                }
            } else {
                Text(statusText.headline)
                    .font(.headline)
            }
            Spacer(minLength: 0)
            if hasControls {
                followButton
            }
        }
    }

    /// "pausado · rodada 2 de 5 · 0,9s · 2 com erro" — o intervalo é um menu ali mesmo, porque
    /// no iPhone o painel não tem espaço pro menu completo e mudar o intervalo no meio da rodada
    /// continua valendo.
    private var compactDetails: some View {
        HStack(spacing: 0) {
            let prefix = [pauseLabel, statusText.roundLabel].compactMap { $0 }
            if !prefix.isEmpty {
                Text(prefix.joined(separator: " · ") + " · ")
            }
            Menu {
                Picker("intervalo", selection: $speedMilliseconds) {
                    ForEach(MegaphoneSpeed.presets) { option in
                        Text(option.label).tag(option.milliseconds)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 2) {
                    Text(MegaphoneSpeed(milliseconds: speedMilliseconds).label)
                        .monospacedDigit()
                    Image(systemName: "chevron.up.chevron.down")
                        .imageScale(.small)
                }
                .foregroundStyle(.supportingText)
            }
            .accessibilityLabel("intervalo entre megafones")
            if snapshot.totalFailed > 0 {
                Text(" · \(snapshot.totalFailed) com erro")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.supportingText)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private var regularHeader: some View {
        HStack(spacing: 10) {
            statusIcon
            Text(statusText.headline)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
            Spacer(minLength: 0)
            if snapshot.totalFailed > 0 {
                Text("\(snapshot.totalFailed) com erro")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.supportingText)
            }
        }
    }

    private var pauseLabel: String? {
        guard case .paused(_, _, let reason) = snapshot.phase else { return nil }
        return switch reason {
        case .user: "pausado"
        case .background: "pausado em segundo plano"
        }
    }

    @ViewBuilder
    private var followButton: some View {
        let button = Button {
            isFollowing.toggle()
        } label: {
            Image(systemName: isFollowing ? "location.fill" : "location")
        }
        .accessibilityLabel("acompanhar produto atual")
        .accessibilityAddTraits(isFollowing ? .isSelected : [])

        if isFollowing {
            button.buttonStyle(.tinted(.accentColor, shape: .circle, size: 48))
        } else {
            button.buttonStyle(.neutral(isCircle: true))
        }
    }

    private var pauseButton: some View {
        Button {
            if runner.isPaused { runner.resume() } else { runner.pause() }
        } label: {
            Label(runner.isPaused ? "continuar" : "pausar", systemImage: runner.isPaused ? "play.fill" : "pause.fill")
                .frame(maxWidth: isCompact ? .infinity : nil)
        }
        .buttonStyle(.neutral)
    }

    private var stopButton: some View {
        Button {
            runner.cancel()
        } label: {
            Label("parar", systemImage: "stop.fill")
                .frame(maxWidth: isCompact ? .infinity : nil)
        }
        .buttonStyle(.tinted(.statusFailure, size: 48))
    }
}
