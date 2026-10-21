import Foundation

/// O papel de uma ação da barra da seleção, que decide a cor dela (ver `SelectionActionBar`): as
/// comuns no texto padrão, a que pede decisão de desconto em amarelo/laranja, a irreversível em
/// vermelho — os mesmos papéis de cor do resto do app.
nonisolated enum SelectionBarActionRole: Sendable {
    case standard
    case decision
    case destructive
}
