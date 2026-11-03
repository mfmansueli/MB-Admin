import Foundation

/// O resultado de comparar duas fotos — as medidas cruas e o nível que elas dão, segundo
/// `PhotoMatchingParameters`. As medidas ficam guardadas pra explicar a decisão na revisão e pra
/// avaliação com amostras reais; nenhuma delas é uma probabilidade.
nonisolated struct PhotoPairEvidence: Equatable, Sendable {
    nonisolated enum Level: Int, Comparable, Sendable {
        /// Nada que ligue as duas fotos.
        case different = 0
        /// Parecidas (mesma composição, ou só o quadro inteiro bate) — candidato pra revisão, nunca
        /// confirmação sozinho.
        case similar = 1
        /// Todas as conferências de "mesma fotografia" passaram.
        case samePhoto = 2
        /// Mesmo `image_public_id` ou mesmos bytes.
        case identical = 3

        static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    let level: Level
    /// Mesmo id público nas duas lojas (ex.: anúncio postado pelo próprio app em outra loja).
    let isSamePublicID: Bool
    /// SHA-256 dos bytes iguais.
    let isSameFile: Bool
    let contentHashDistance: Int
    let contentCorrelation: Double
    let fullCorrelation: Double
    let meanColorDifference: Double
    let maxColorDifference: Double
    let framingDifference: Double
    let aspectDifference: Double
    /// A estrutura bate como "mesma foto" mas a cor não — provável variante (outra cor do mesmo
    /// modelo), que vai pra revisão com esse motivo.
    let colorsDiffer: Bool

    /// Mesmo id público, sem precisar (nem poder, se o download falhou) olhar os pixels.
    static let samePublicID = PhotoPairEvidence(
        level: .identical,
        isSamePublicID: true,
        isSameFile: true,
        contentHashDistance: 0,
        contentCorrelation: 1,
        fullCorrelation: 1,
        meanColorDifference: 0,
        maxColorDifference: 0,
        framingDifference: 0,
        aspectDifference: 0,
        colorsDiffer: false
    )

    /// Ordena evidências do mesmo nível — maior correlação do recorte primeiro.
    func isStronger(than other: PhotoPairEvidence) -> Bool {
        if level != other.level { return level > other.level }
        return contentCorrelation > other.contentCorrelation
    }
}
