import Foundation

/// Os textos de "postar em outra loja" — menu, confirmação e a linha da row — puros, pra tela só
/// escolher qual mostrar.
nonisolated enum PostToOtherStoreCopy {
    /// O item do menu "..." da row quando há mais de uma loja (abre o submenu) ou nenhuma.
    static let menuItemLabel = "postar em outra loja"
    /// Embaixo do item desabilitado, quando nenhuma outra loja está com a sessão aberta.
    static let noCandidateReason = "nenhuma outra loja com sessão aberta"
    static let systemImage = "paperplane"

    /// Cabeçalho da lista de lojas: "postar em" pra um produto, "postar 3 em" na seleção.
    static func menuTitle(productCount: Int) -> String {
        productCount == 1 ? "postar em" : "postar \(productCount) em"
    }

    /// O item direto, sem submenu, quando só uma loja serve — e o botão de confirmar.
    static func postLabel(storeName: String) -> String {
        "postar em \(storeName)"
    }

    /// O item do menu enquanto o produto está sendo postado.
    static func postingLabel(storeName: String) -> String {
        "postando em \(storeName)…"
    }

    static func confirmationTitle(productCount: Int, storeName: String) -> String {
        switch productCount {
        case 1: "postar este produto em \(storeName)?"
        default: "postar \(productCount) produtos em \(storeName)?"
        }
    }

    /// Começa pelo risco quando a última comparação achou o produto (ou alguns deles) na loja de
    /// destino. O intervalo (`pace`, ex. "1 a cada minuto") só aparece com mais de um — é aí que
    /// a fila demora.
    static func confirmationMessage(productCount: Int, target: OtherStoreTarget, pace: String) -> String {
        let store = target.name
        if productCount == 1 {
            if let percent = target.highestSimilarityPercent, target.possibleDuplicateCount > 0 {
                return "\(store) pode já ter esse produto (\(percent)% parecido). "
                    + "se postar, vira um anúncio novo lá, com o mesmo título, descrição, preço e fotos."
            }
            return "vira um anúncio novo em \(store), com o mesmo título, descrição, preço e fotos, "
                + "e entra na fila de ações. o anúncio daqui continua como está."
        }
        let message = "cada um vira um anúncio novo em \(store), com título, descrição, preço e fotos, "
            + "e entra na fila de ações (\(pace)). os anúncios daqui continuam como estão."
        switch target.possibleDuplicateCount {
        case 0: return message
        case 1: return "1 deles pode já existir em \(store), pela última comparação. \(message)"
        case let count: return "\(count) deles podem já existir em \(store), pela última comparação. \(message)"
        }
    }
}
