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
    /// destino — "já tem" só com a mesma foto (ou confirmado por você); "pode já ter" quando ficou
    /// pra revisar. O intervalo (`pace`, ex. "1 a cada minuto") só aparece com mais de um — é aí que
    /// a fila demora.
    static func confirmationMessage(productCount: Int, target: OtherStoreTarget, pace: String) -> String {
        let store = target.name
        if productCount == 1 {
            if target.existingCount > 0 {
                return "\(store) já tem esse produto, pela última comparação (a mesma foto). "
                    + "se postar, vira um anúncio repetido lá, com o mesmo título, descrição, preço e fotos."
            }
            if target.possibleCount > 0 {
                return "\(store) pode já ter esse produto — a última comparação deixou um par pra revisar. "
                    + "se postar, vira um anúncio novo lá, com o mesmo título, descrição, preço e fotos."
            }
            return "vira um anúncio novo em \(store), com o mesmo título, descrição, preço e fotos, "
                + "e entra na fila de ações. o anúncio daqui continua como está."
        }
        let message = "cada um vira um anúncio novo em \(store), com título, descrição, preço e fotos, "
            + "e entra na fila de ações (\(pace)). os anúncios daqui continuam como estão."
        var risks: [String] = []
        switch target.existingCount {
        case 0: break
        case 1: risks.append("1 deles já existe em \(store)")
        case let count: risks.append("\(count) deles já existem em \(store)")
        }
        switch target.possibleCount {
        case 0: break
        case 1: risks.append(target.existingCount > 0 ? "1 pode existir" : "1 deles pode existir em \(store)")
        case let count: risks.append(target.existingCount > 0 ? "\(count) podem existir" : "\(count) deles podem existir em \(store)")
        }
        guard !risks.isEmpty else { return message }
        return "\(risks.joined(separator: " e ")), pela última comparação. \(message)"
    }
}
