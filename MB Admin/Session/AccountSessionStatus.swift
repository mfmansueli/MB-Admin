import Foundation

/// Situação de autenticação de uma conta específica na lista.
nonisolated enum AccountSessionStatus: Equatable, Sendable {
    case active
    /// O cookie da conta venceu — precisa logar de novo, sem afetar as outras contas da lista.
    case sessionExpired
    /// Não deu pra confirmar a sessão (rede instável, Enjoei fora do ar) — diferente de
    /// `sessionExpired`: o cookie pode muito bem continuar válido, só não checou agora. Tratado
    /// como uma falha passageira, não como "precisa logar de novo".
    case checkFailed
}
