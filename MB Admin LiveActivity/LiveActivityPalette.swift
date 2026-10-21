import SwiftUI

/// Cores da Live Activity — a extensão não tem o catálogo de cores do app, e a atividade fica
/// sempre num fundo escuro (tela bloqueada e Dynamic Island), então os valores são fixos, os
/// mesmos do board do redesign.
enum LiveActivityPalette {
    /// O coral da marca, no megafone da Dynamic Island.
    static let brandCoral = Color(red: 254 / 255, green: 120 / 255, blue: 114 / 255)
    /// O quadradinho do megafone na tela bloqueada.
    static let iconTileBackground = Color(red: 1, green: 227 / 255, blue: 225 / 255)
    static let iconTileForeground = Color(red: 168 / 255, green: 50 / 255, blue: 44 / 255)
    /// "parar", na versão do escuro do vermelho de falha do app.
    static let stop = Color(red: 1, green: 105 / 255, blue: 97 / 255)
    static let supportingText = Color(red: 174 / 255, green: 174 / 255, blue: 178 / 255)
    static let lockScreenBackground = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255).opacity(0.72)
    static let buttonFill = Color.white.opacity(0.16)
}
