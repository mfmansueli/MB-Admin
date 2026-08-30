import Foundation

/// Intervalo entre um megafone e o próximo.
///
/// Existe um piso de 0,3s: abaixo disso a chance de o Enjoei tratar a sequência como abuso — e
/// bloquear a conta — deixa de compensar o tempo economizado.
nonisolated struct MegaphoneSpeed: Equatable, Hashable, Identifiable, Sendable {
    static let minimumMilliseconds = 300

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
        MegaphoneSpeed(milliseconds: 500),
        .standard,
        MegaphoneSpeed(milliseconds: 1_500),
        MegaphoneSpeed(milliseconds: 3_000)
    ]

    var label: String {
        "\(seconds.formatted(.number.precision(.fractionLength(1))))s"
    }
}
