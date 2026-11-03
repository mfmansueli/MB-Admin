import Foundation
import SwiftData

/// Uma `PhotoSignature` em disco, com colunas nativas (nada de JSON) — no `SharedModelContainer`,
/// porque a mesma foto vale pra qualquer conta. A chave é o `image_public_id`; a versão do
/// algoritmo fica numa coluna própria pra uma assinatura antiga nunca ser comparada com uma nova
/// (ver `PhotoMatchingParameters.signatureVersion`).
@Model
final class PhotoSignatureRecord {
    @Attribute(.unique) var publicID: String
    var algorithmVersion: Int
    var verifiedAt: Date
    var contentSHA256: String
    var byteCount: Int
    var pixelWidth: Int
    var pixelHeight: Int
    var isInformative: Bool
    var hasUniformBackground: Bool
    var boxLeft: Double
    var boxTop: Double
    var boxWidth: Double
    var boxHeight: Double
    var contentAspectRatio: Double
    /// `UInt64` não é tipo nativo do SwiftData — guardado com o mesmo padrão de bits.
    var contentHash: Int64
    var contentLuma: Data
    var fullLuma: Data
    var contentColor: Data

    init(entry: StoredPhotoSignature) {
        publicID = entry.publicID
        algorithmVersion = entry.signature.algorithmVersion
        verifiedAt = entry.verifiedAt
        contentSHA256 = entry.signature.contentSHA256
        byteCount = entry.signature.byteCount
        pixelWidth = entry.signature.pixelWidth
        pixelHeight = entry.signature.pixelHeight
        isInformative = entry.signature.isInformative
        hasUniformBackground = entry.signature.hasUniformBackground
        boxLeft = entry.signature.contentBox.left
        boxTop = entry.signature.contentBox.top
        boxWidth = entry.signature.contentBox.width
        boxHeight = entry.signature.contentBox.height
        contentAspectRatio = entry.signature.contentAspectRatio
        contentHash = Int64(bitPattern: entry.signature.contentHash)
        contentLuma = Data(entry.signature.contentLuma)
        fullLuma = Data(entry.signature.fullLuma)
        contentColor = Data(entry.signature.contentColor)
    }

    func update(from entry: StoredPhotoSignature) {
        let signature = entry.signature
        algorithmVersion = signature.algorithmVersion
        verifiedAt = entry.verifiedAt
        contentSHA256 = signature.contentSHA256
        byteCount = signature.byteCount
        pixelWidth = signature.pixelWidth
        pixelHeight = signature.pixelHeight
        isInformative = signature.isInformative
        hasUniformBackground = signature.hasUniformBackground
        boxLeft = signature.contentBox.left
        boxTop = signature.contentBox.top
        boxWidth = signature.contentBox.width
        boxHeight = signature.contentBox.height
        contentAspectRatio = signature.contentAspectRatio
        contentHash = Int64(bitPattern: signature.contentHash)
        contentLuma = Data(signature.contentLuma)
        fullLuma = Data(signature.fullLuma)
        contentColor = Data(signature.contentColor)
    }

    var entry: StoredPhotoSignature {
        StoredPhotoSignature(
            publicID: publicID,
            signature: PhotoSignature(
                algorithmVersion: algorithmVersion,
                contentSHA256: contentSHA256,
                byteCount: byteCount,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                isInformative: isInformative,
                hasUniformBackground: hasUniformBackground,
                contentBox: PhotoSignature.NormalizedBox(left: boxLeft, top: boxTop, width: boxWidth, height: boxHeight),
                contentAspectRatio: contentAspectRatio,
                contentHash: UInt64(bitPattern: contentHash),
                contentLuma: [UInt8](contentLuma),
                fullLuma: [UInt8](fullLuma),
                contentColor: [UInt8](contentColor)
            ),
            verifiedAt: verifiedAt
        )
    }
}
