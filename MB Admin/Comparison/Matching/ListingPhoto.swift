import Foundation

/// Uma das fotos de um anúncio que entra na comparação, com o que deu pra tirar dela.
nonisolated struct ListingPhoto: Equatable, Sendable {
    let publicID: String
    /// Posição entre as fotos do anúncio (0 = a primeira). A comparação usa todas sem dar peso à
    /// posição — uma loja pode pôr a foto de fundo branco em primeiro e a outra, em terceiro.
    let position: Int
    let signature: PhotoSignature?
    let failure: PhotoSignatureError?

    /// Tem assinatura com conteúdo (não é foto lisa/inválida).
    var isUsable: Bool { signature?.isInformative == true }
    /// Nem analisada nem falhou — a análise não chegou nela.
    var wasNotAnalyzed: Bool { signature == nil && failure == nil }
}
