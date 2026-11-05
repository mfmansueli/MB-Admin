import Foundation

/// Intervalo entre um megafone e o próximo.
///
/// Existe um piso de 0,1s. Abaixo de 0,3s a chance de o Enjoei tratar a sequência como abuso — e
/// bloquear a conta — cresce; 0,1s e 0,2s ficam no menu como opção consciente, o padrão continua
/// 0,9s.
nonisolated struct MegaphoneSpeed: Equatable, Hashable, Identifiable, Sendable {
    static let minimumMilliseconds = 100

    let milliseconds: Int

    init(milliseconds: Int) {
        self.milliseconds = max(Self.minimumMilliseconds, milliseconds)
    }

    var id: Int { milliseconds }
    var duration: Duration { .milliseconds(milliseconds) }
    var seconds: Double { Double(milliseconds) / 1000 }

    static let fastest = MegaphoneSpeed(milliseconds: minimumMilliseconds)
    static let standard = MegaphoneSpeed(milliseconds: 900)

    /// Opções oferecidas no menu, da mais rápida para a mais cautelosa.
    static let presets: [MegaphoneSpeed] = [
        .fastest,
        MegaphoneSpeed(milliseconds: 200),
        MegaphoneSpeed(milliseconds: 300),
        MegaphoneSpeed(milliseconds: 500),
        .standard,
        MegaphoneSpeed(milliseconds: 1_500),
        MegaphoneSpeed(milliseconds: 3_000)
    ]

    var label: String {
        "\(seconds.formatted(.number.precision(.fractionLength(1))))s"
    }
}
