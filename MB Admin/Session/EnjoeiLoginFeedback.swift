import Foundation

/// Recados da tela de login a partir do que o Enjoei respondeu — reaproveitado tanto para logar uma
/// conta nova quanto para recuperar a sessão de uma conta que expirou.
nonisolated enum EnjoeiLoginFeedback {
    /// Recado padrão quando a conferência não achou sessão — o login ainda não terminou.
    static let notLoggedInYetFeedback =
        "ainda não te encontrei logado. termine o login no enjoei e toque de novo em já entrei."

    static func isGuestFailure(_ error: Error) -> Bool {
        switch error as? EnjoeiError {
        case .notAuthenticated, .notIdentified: true
        default: false
        }
    }

    static func message(for failure: Error?) -> String {
        guard let failure else { return notLoggedInYetFeedback }
        guard isGuestFailure(failure) else { return failure.localizedDescription }
        // Nos casos de "não identifiquei", o detalhe técnico ajuda a entender o que a página disse.
        if case .notIdentified(let detail) = failure as? EnjoeiError, !detail.isEmpty {
            return "\(notLoggedInYetFeedback)\n(\(detail))"
        }
        return notLoggedInYetFeedback
    }
}
