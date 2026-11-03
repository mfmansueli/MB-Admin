import CoreGraphics
import Foundation

/// Pixels RGBA (8 bits, sRGB, opacos — transparência é composta sobre a cor de fundo) de uma imagem
/// pequena, só durante a geração da assinatura. Nunca é guardado: some assim que
/// `PhotoSignatureGenerator` termina.
nonisolated struct PhotoRaster {
    nonisolated struct RGB: Equatable, Sendable {
        let red: UInt8
        let green: UInt8
        let blue: UInt8

        static let white = RGB(red: 255, green: 255, blue: 255)

        /// Maior diferença entre canais — barata e suficiente pra separar fundo de produto.
        func maximumChannelDifference(to other: RGB) -> Int {
            max(
                abs(Int(red) - Int(other.red)),
                abs(Int(green) - Int(other.green)),
                abs(Int(blue) - Int(other.blue))
            )
        }
    }

    let width: Int
    let height: Int
    /// `width * height * 4` bytes, linha 0 = topo da imagem.
    let pixels: [UInt8]

    /// Desenha a imagem inteira no tamanho dela, por cima de `fill`.
    init?(image: CGImage, fill: RGB = .white) {
        guard let raster = Self.render(width: image.width, height: image.height, fill: fill, draw: { context in
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }) else { return nil }
        self = raster
    }

    private init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// `region` (em pixels da imagem, origem no topo) desenhada num quadrado `side`×`side`, com a
    /// proporção preservada e a sobra preenchida com `fill` — o "letterbox" que deixa a assinatura
    /// independente de a foto ser quadrada ou não, sem distorcer o produto.
    static func letterboxed(_ image: CGImage, region: CGRect, side: Int, fill: RGB) -> PhotoRaster? {
        guard let cropped = image.cropping(to: region.integral), cropped.width > 0, cropped.height > 0 else { return nil }
        let scale = Double(side) / Double(max(cropped.width, cropped.height))
        let drawWidth = Double(cropped.width) * scale
        let drawHeight = Double(cropped.height) * scale
        let rect = CGRect(
            x: (Double(side) - drawWidth) / 2,
            y: (Double(side) - drawHeight) / 2,
            width: drawWidth,
            height: drawHeight
        )
        return render(width: side, height: side, fill: fill) { context in
            context.draw(cropped, in: rect)
        }
    }

    private static func render(width: Int, height: Int, fill: RGB, draw: (CGContext) -> Void) -> PhotoRaster? {
        guard width > 0, height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.setFillColor(
            red: CGFloat(fill.red) / 255,
            green: CGFloat(fill.green) / 255,
            blue: CGFloat(fill.blue) / 255,
            alpha: 1
        )
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        draw(context)
        guard let data = context.data else { return nil }
        let count = width * height * 4
        let buffer = UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: count)
        return PhotoRaster(width: width, height: height, pixels: Array(buffer))
    }

    func color(x column: Int, y row: Int) -> RGB {
        let offset = (row * width + column) * 4
        return RGB(red: pixels[offset], green: pixels[offset + 1], blue: pixels[offset + 2])
    }

    /// Luminância Rec. 601 sobre os valores sRGB — suficiente pra comparar duas cópias da mesma foto.
    func luma(x column: Int, y row: Int) -> Double {
        let offset = (row * width + column) * 4
        return 0.299 * Double(pixels[offset]) + 0.587 * Double(pixels[offset + 1]) + 0.114 * Double(pixels[offset + 2])
    }

    /// Média de blocos: `side` precisa ser múltiplo de `outputSide`.
    func averagedLuma(outputSide: Int) -> [UInt8] {
        let block = width / outputSide
        var result = [UInt8](repeating: 0, count: outputSide * outputSide)
        for cellY in 0..<outputSide {
            for cellX in 0..<outputSide {
                var sum = 0.0
                for row in (cellY * block)..<((cellY + 1) * block) {
                    for column in (cellX * block)..<((cellX + 1) * block) {
                        sum += luma(x: column, y: row)
                    }
                }
                result[cellY * outputSide + cellX] = UInt8(clamping: Int((sum / Double(block * block)).rounded()))
            }
        }
        return result
    }

    func averagedColor(outputSide: Int) -> [UInt8] {
        let block = width / outputSide
        var result = [UInt8](repeating: 0, count: outputSide * outputSide * 3)
        for cellY in 0..<outputSide {
            for cellX in 0..<outputSide {
                var sums = (0, 0, 0)
                for row in (cellY * block)..<((cellY + 1) * block) {
                    for column in (cellX * block)..<((cellX + 1) * block) {
                        let offset = (row * width + column) * 4
                        sums.0 += Int(pixels[offset])
                        sums.1 += Int(pixels[offset + 1])
                        sums.2 += Int(pixels[offset + 2])
                    }
                }
                let count = block * block
                let index = (cellY * outputSide + cellX) * 3
                result[index] = UInt8((sums.0 + count / 2) / count)
                result[index + 1] = UInt8((sums.1 + count / 2) / count)
                result[index + 2] = UInt8((sums.2 + count / 2) / count)
            }
        }
        return result
    }
}
