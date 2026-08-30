import Foundation

/// Situação de autenticação de uma conta específica na lista.
nonisolated enum AccountSessionStatus: Equatable, Sendable {
    case active
    /// O cookie da conta venceu — precisa logar de novo, sem afetar as outras contas da lista.
    case sessionExpired
}
