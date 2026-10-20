import Foundation

/// Por que o megafone está parado.
///
/// A distinção importa: voltar do segundo plano retoma sozinho, mas não pode desfazer uma pausa
/// que o usuário pediu.
nonisolated enum MegaphonePauseReason: Equatable, Sendable {
    case user
    case background
}
