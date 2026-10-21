import Foundation

/// Quantas vezes a lista inteira de produtos será percorrida.
nonisolated struct MegaphoneRounds: Equatable, Hashable, Identifiable, Sendable {
    /// Zero significa repetir sem parar, até o usuário interromper.
    let rawValue: Int

    var id: Int { rawValue }
    var isUnlimited: Bool { rawValue <= 0 }

    static let unlimited = MegaphoneRounds(rawValue: 0)
    static let once = MegaphoneRounds(rawValue: 1)

    static func times(_ count: Int) -> MegaphoneRounds {
        MegaphoneRounds(rawValue: max(1, count))
    }

    /// Opções oferecidas no menu.
    static let presets: [MegaphoneRounds] = [
        .once, .times(5), .times(10), .times(20), .times(50), .times(100), .unlimited
    ]

    var label: String {
        switch rawValue {
        case ...0: "infinito"
        case 1: "1 vez"
        default: "\(rawValue) vezes"
        }
    }

    /// Versão curta pro botão da barra de baixo no iPhone ("5× · 0,9s"), onde `label` não cabe.
    var shortLabel: String {
        rawValue <= 0 ? "∞" : "\(rawValue)×"
    }

    /// A rodada `round` ainda faz parte do combinado?
    func includes(round: Int) -> Bool {
        isUnlimited || round <= rawValue
    }
}
