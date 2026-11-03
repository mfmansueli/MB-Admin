import Foundation

/// Por que uma foto não virou assinatura — sempre tratado como "não deu pra verificar", nunca como
/// evidência de que o produto não existe na outra loja.
nonisolated enum PhotoSignatureError: Error, Equatable, Sendable {
    /// Os bytes não são uma imagem que o ImageIO consiga abrir.
    case undecodable
    /// Decodificou, mas é pequena demais pra identificar uma fotografia.
    case tooSmall
    /// O download falhou (rede, HTTP, resposta vazia).
    case downloadFailed(String)

    var userFacingText: String {
        switch self {
        case .undecodable: "imagem inválida"
        case .tooSmall: "imagem pequena demais"
        case .downloadFailed(let message): "não carregou (\(message))"
        }
    }
}
