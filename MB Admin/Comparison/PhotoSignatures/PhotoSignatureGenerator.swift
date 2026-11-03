import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

/// Bytes de uma foto → `PhotoSignature`. Puro e síncrono, sem estado — quem chama decide em que
/// thread roda (`PhotoSignatureLoader` sempre roda fora do MainActor) e nada da imagem decodificada
/// sobrevive à chamada.
///
/// Passos:
/// 1. Decodifica com o ImageIO já reduzindo pra `workingMaxSide` e **aplicando a orientação EXIF**
///    (`kCGImageSourceCreateThumbnailWithTransform`) — a mesma foto girada pelos metadados vira a
///    mesma imagem.
/// 2. Estima o fundo pela borda e, se for uniforme, recorta a margem com folga
///    (`ContentBoxDetector`).
/// 3. Desenha o recorte e o quadro inteiro em quadrados com a proporção preservada e extrai luminância,
///    cor e pHash de cada um.
nonisolated enum PhotoSignatureGenerator {
    private typealias Limits = PhotoMatchingParameters

    static func makeSignature(from data: Data) throws(PhotoSignatureError) -> PhotoSignature {
        let image = try decode(data)
        guard let raster = PhotoRaster(image: image) else { throw .undecodable }

        let detection = ContentBoxDetector.detect(in: raster)
        let fullRegion = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let contentRegion = detection.box.map {
            CGRect(x: $0.minX, y: $0.minY, width: $0.width, height: $0.height)
        } ?? fullRegion
        let contentBox = PhotoSignature.NormalizedBox(
            left: contentRegion.minX / Double(image.width),
            top: contentRegion.minY / Double(image.height),
            width: contentRegion.width / Double(image.width),
            height: contentRegion.height / Double(image.height)
        )

        guard let contentRaster = PhotoRaster.letterboxed(
            image, region: contentRegion, side: Limits.contentRenderSide, fill: detection.background
        ), let fullRaster = PhotoRaster.letterboxed(
            image, region: fullRegion, side: Limits.fullRenderSide, fill: detection.background
        ) else { throw .undecodable }

        let contentLuma = contentRaster.averagedLuma(outputSide: Limits.contentLumaSide)
        return PhotoSignature(
            algorithmVersion: Limits.signatureVersion,
            contentSHA256: sha256Hex(data),
            byteCount: data.count,
            pixelWidth: image.width,
            pixelHeight: image.height,
            isInformative: isInformative(detection: detection, raster: raster),
            hasUniformBackground: detection.hasUniformBackground,
            contentBox: contentBox,
            contentAspectRatio: contentRegion.width / contentRegion.height,
            contentHash: PerceptualHash.hash(luma: contentLuma),
            contentLuma: contentLuma,
            fullLuma: fullRaster.averagedLuma(outputSide: Limits.fullLumaSide),
            contentColor: contentRaster.averagedColor(outputSide: Limits.colorGridSide)
        )
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Decodifica já reduzida e orientada — nunca a imagem no tamanho original.
    private static func decode(_ data: Data) throws(PhotoSignatureError) -> CGImage {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { throw .undecodable }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: Limits.workingMaxSide,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw .undecodable
        }
        guard image.width >= Limits.minimumDecodedSide, image.height >= Limits.minimumDecodedSide else { throw .tooSmall }
        return image
    }

    /// Imagem lisa (só fundo), recorte minúsculo ou luminância praticamente constante não identificam
    /// produto nenhum — duas fotos todas brancas não são "o mesmo produto".
    private static func isInformative(detection: ContentBoxDetector.Detection, raster: PhotoRaster) -> Bool {
        guard let box = detection.box,
              box.width >= Limits.minimumContentSide,
              box.height >= Limits.minimumContentSide else { return false }
        var sum = 0.0
        var sumOfSquares = 0.0
        for row in box.minY...box.maxY {
            for column in box.minX...box.maxX {
                let luma = raster.luma(x: column, y: row)
                sum += luma
                sumOfSquares += luma * luma
            }
        }
        let count = Double(box.width * box.height)
        let mean = sum / count
        let variance = max(0, sumOfSquares / count - mean * mean)
        return variance.squareRoot() >= Limits.minimumLumaStandardDeviation
    }
}
