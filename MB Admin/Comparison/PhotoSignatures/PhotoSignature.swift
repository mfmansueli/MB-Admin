import Foundation

/// O que guardamos de uma foto pra reconhecer a mesma fotografia em outro anúncio — nunca a imagem
/// em si. Gerada uma vez por `image_public_id` (`PhotoSignatureGenerator`) e salva em cache
/// (`PhotoSignatureRecord`); a comparação entre duas assinaturas é `PhotoPairComparison`.
///
/// Duas representações, comparadas juntas:
/// - **recorte**: só a região do produto quando o fundo é uniforme (margem lisa removida com
///   folga), desenhada num quadrado com a proporção preservada. É o que impede dois objetos pequenos
///   diferentes num fundo branco enorme de parecerem iguais só porque o branco domina a imagem.
/// - **quadro inteiro**: a foto toda, também com proporção preservada — conferência independente do
///   recorte, pra um recorte instável nunca virar "mesma foto" sozinho nem fazer um par sumir.
nonisolated struct PhotoSignature: Equatable, Sendable, Codable {
    /// Região do produto, em fração da imagem (0–1, origem no canto superior esquerdo).
    nonisolated struct NormalizedBox: Equatable, Sendable, Codable {
        let left: Double
        let top: Double
        let width: Double
        let height: Double

        static let full = NormalizedBox(left: 0, top: 0, width: 1, height: 1)

        /// Maior deslocamento entre as bordas das duas regiões.
        func maximumEdgeDifference(to other: NormalizedBox) -> Double {
            max(
                abs(left - other.left),
                abs(top - other.top),
                abs((left + width) - (other.left + other.width)),
                abs((top + height) - (other.top + other.height))
            )
        }
    }

    /// `PhotoMatchingParameters.signatureVersion` de quando foi gerada.
    let algorithmVersion: Int
    /// SHA-256 dos bytes baixados — atalho de "mesmo arquivo" e base da política de atualização
    /// (se o conteúdo mudou sob o mesmo id, a assinatura é refeita).
    let contentSHA256: String
    let byteCount: Int
    /// Tamanho da imagem de trabalho, já orientada.
    let pixelWidth: Int
    let pixelHeight: Int
    /// `false` pra imagem lisa (toda branca, cor única) ou com produto pequeno demais — não serve de
    /// evidência nem de presença nem de ausência.
    let isInformative: Bool
    /// Se a margem uniforme foi detectada (e recortada). Sem fundo uniforme, `contentBox` é a imagem
    /// inteira.
    let hasUniformBackground: Bool
    let contentBox: NormalizedBox
    /// Largura/altura do recorte, em pixels.
    let contentAspectRatio: Double
    /// pHash (DCT 32×32, 63 bits) do recorte — a chave da busca de candidatos.
    let contentHash: UInt64
    /// Luminância 32×32 do recorte, linha a linha.
    let contentLuma: [UInt8]
    /// Luminância 16×16 do quadro inteiro.
    let fullLuma: [UInt8]
    /// Cor média (sRGB) de cada célula de uma grade 8×8 do recorte, `[r, g, b, r, g, b, …]`.
    let contentColor: [UInt8]

    /// Menor lado do recorte em pixels da imagem de trabalho — quanto detalhe real a miniatura tem.
    var contentPixelSide: Double {
        min(contentBox.width * Double(pixelWidth), contentBox.height * Double(pixelHeight))
    }
}
