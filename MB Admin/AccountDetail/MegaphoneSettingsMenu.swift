import SwiftUI

/// Repetições + intervalo num menu só ("5× · 0,9s") — o botão à esquerda da barra de baixo quando
/// parado, e o primeiro do painel do megafone no iPad. Durante a rodada as repetições ficam
/// travadas (o combinado já está valendo), mas o intervalo continua mudando: o laço lê o valor a
/// cada produto.
///
/// Não impõe estilo de botão — na toolbar o vidro vem do sistema, dentro do painel quem usa aplica
/// `.neutral`.
struct MegaphoneSettingsMenu: View {
    @Binding var rounds: Int
    @Binding var speedMilliseconds: Int
    var isRoundsLocked = false
    /// "5×" em vez de "5 vezes" — no iPhone o rótulo longo não cabe ao lado da busca e do botão
    /// de megafonar.
    var usesShortLabel = false

    private var currentRounds: MegaphoneRounds { MegaphoneRounds(rawValue: rounds) }
    private var currentSpeed: MegaphoneSpeed { MegaphoneSpeed(milliseconds: speedMilliseconds) }

    var body: some View {
        Menu {
            Section("repetições") {
                // Sem `.inline`, o Menu trata o Picker como um submenu à parte (com seta), exigindo
                // um segundo toque pra ver as opções.
                Picker("repetições", selection: $rounds) {
                    ForEach(MegaphoneRounds.presets) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .disabled(isRoundsLocked)
            }
            Section("intervalo entre megafones") {
                Picker("intervalo", selection: $speedMilliseconds) {
                    ForEach(MegaphoneSpeed.presets) { option in
                        Text(option.label).tag(option.milliseconds)
                    }
                }
                .pickerStyle(.inline)
            }
        } label: {
            HStack(spacing: 6) {
                Text("\(usesShortLabel ? currentRounds.shortLabel : currentRounds.label) · \(currentSpeed.label)")
                    .monospacedDigit()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.supportingText)
            }
            .fontWeight(.medium)
            .fixedSize()
        }
        .accessibilityLabel("repetições e intervalo")
        .accessibilityValue("\(currentRounds.label), \(currentSpeed.label)")
    }
}
