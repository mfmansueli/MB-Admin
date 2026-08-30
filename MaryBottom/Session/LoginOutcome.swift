import Foundation

/// Resultado de uma conferência de login. Carrega o recado junto (em vez de morar numa propriedade
/// separada) porque várias contas podem estar em processo de login ao mesmo tempo.
nonisolated enum LoginOutcome: Equatable {
    case loggedIn
    case pending(feedback: String)
}
