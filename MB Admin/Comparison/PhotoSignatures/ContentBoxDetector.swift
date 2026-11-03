import Foundation

/// Acha onde está o produto numa foto de fundo uniforme — a "redução cuidadosa de margens": só
/// recorta quando a borda é de fato lisa, usa uma tolerância baixa (produto claro não some), exige
/// alguns pixels por linha (ruído isolado não conta) e devolve o recorte com folga. Sem fundo
/// uniforme, devolve a imagem inteira.
nonisolated enum ContentBoxDetector {
    private typealias Limits = PhotoMatchingParameters

    nonisolated struct Detection: Equatable, Sendable {
        /// Cor estimada do fundo (mediana da borda) — também é a cor do letterbox das miniaturas.
        let background: PhotoRaster.RGB
        let hasUniformBackground: Bool
        /// Em pixels, origem no topo. `nil` = nada além do fundo (imagem lisa).
        let box: PixelBox?
    }

    nonisolated struct PixelBox: Equatable, Sendable {
        let minX: Int
        let minY: Int
        let maxX: Int
        let maxY: Int

        var width: Int { maxX - minX + 1 }
        var height: Int { maxY - minY + 1 }
    }

    static func detect(in raster: PhotoRaster) -> Detection {
        let width = raster.width
        let height = raster.height
        let band = max(1, Int((Double(min(width, height)) * Limits.borderBandFraction).rounded()))

        var border: [PhotoRaster.RGB] = []
        border.reserveCapacity(2 * band * (width + height))
        for row in 0..<height {
            let isBorderRow = row < band || row >= height - band
            for column in 0..<width where isBorderRow || column < band || column >= width - band {
                border.append(raster.color(x: column, y: row))
            }
        }
        let background = median(of: border)
        let uniformCount = border.filter { $0.maximumChannelDifference(to: background) <= Limits.borderTolerance }.count
        let isUniform = !border.isEmpty && Double(uniformCount) / Double(border.count) >= Limits.uniformBorderMinimumFraction
        let fullBox = PixelBox(minX: 0, minY: 0, maxX: width - 1, maxY: height - 1)

        guard isUniform else {
            return Detection(background: background, hasUniformBackground: false, box: fullBox)
        }

        var rowCounts = [Int](repeating: 0, count: height)
        var columnCounts = [Int](repeating: 0, count: width)
        for row in 0..<height {
            for column in 0..<width
            where raster.color(x: column, y: row).maximumChannelDifference(to: background) > Limits.contentTolerance {
                rowCounts[row] += 1
                columnCounts[column] += 1
            }
        }
        let minimum = Limits.contentMinimumPixelsPerLine
        guard let top = rowCounts.firstIndex(where: { $0 >= minimum }),
              let bottom = rowCounts.lastIndex(where: { $0 >= minimum }),
              let left = columnCounts.firstIndex(where: { $0 >= minimum }),
              let right = columnCounts.lastIndex(where: { $0 >= minimum }) else {
            return Detection(background: background, hasUniformBackground: true, box: nil)
        }

        let padding = Int((Double(max(width, height)) * Limits.contentPaddingFraction).rounded())
        let box = PixelBox(
            minX: max(0, left - padding),
            minY: max(0, top - padding),
            maxX: min(width - 1, right + padding),
            maxY: min(height - 1, bottom + padding)
        )
        return Detection(background: background, hasUniformBackground: true, box: box)
    }

    /// Mediana por canal — resiste a um pedaço do produto encostando na borda.
    private static func median(of colors: [PhotoRaster.RGB]) -> PhotoRaster.RGB {
        guard !colors.isEmpty else { return .white }
        func channelMedian(_ value: (PhotoRaster.RGB) -> UInt8) -> UInt8 {
            var histogram = [Int](repeating: 0, count: 256)
            for color in colors { histogram[Int(value(color))] += 1 }
            let half = colors.count / 2
            var accumulated = 0
            for (level, count) in histogram.enumerated() {
                accumulated += count
                if accumulated > half { return UInt8(level) }
            }
            return 255
        }
        return PhotoRaster.RGB(
            red: channelMedian(\.red),
            green: channelMedian(\.green),
            blue: channelMedian(\.blue)
        )
    }
}
