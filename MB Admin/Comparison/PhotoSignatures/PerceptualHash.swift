import Foundation

/// pHash clássico: DCT-II de uma luminância 32×32, os 8×8 coeficientes de frequência mais baixa sem o
/// DC (63 bits), cada bit dizendo se o coeficiente está acima da mediana. Resiste a recompressão,
/// redimensionamento e pequenas mudanças de brilho; **não** distingue sozinho dois objetos parecidos —
/// por isso nunca é o único critério (ver `PhotoPairComparison`).
nonisolated enum PerceptualHash {
    private static let inputSide = 32
    private static let frequencySide = 8

    /// `cosines[frequency * 32 + sample] = cos(π (2·sample + 1) · frequency / 64)`.
    private static let cosines: [Double] = {
        var table = [Double](repeating: 0, count: frequencySide * inputSide)
        for frequency in 0..<frequencySide {
            for sample in 0..<inputSide {
                table[frequency * inputSide + sample] = cos(
                    Double.pi * Double(2 * sample + 1) * Double(frequency) / Double(2 * inputSide)
                )
            }
        }
        return table
    }()

    static func hash(luma: [UInt8]) -> UInt64 {
        precondition(luma.count == inputSide * inputSide, "pHash espera 32×32")
        // Linhas primeiro (só as 8 frequências usadas), depois colunas.
        var rows = [Double](repeating: 0, count: inputSide * frequencySide)
        for row in 0..<inputSide {
            for horizontal in 0..<frequencySide {
                var sum = 0.0
                for column in 0..<inputSide {
                    sum += Double(luma[row * inputSide + column]) * cosines[horizontal * inputSide + column]
                }
                rows[row * frequencySide + horizontal] = sum
            }
        }
        var coefficients: [Double] = []
        coefficients.reserveCapacity(frequencySide * frequencySide - 1)
        for vertical in 0..<frequencySide {
            for horizontal in 0..<frequencySide where !(horizontal == 0 && vertical == 0) {
                var sum = 0.0
                for row in 0..<inputSide {
                    sum += rows[row * frequencySide + horizontal] * cosines[vertical * inputSide + row]
                }
                coefficients.append(sum)
            }
        }
        let median = coefficients.sorted()[coefficients.count / 2]
        var hash: UInt64 = 0
        for (index, coefficient) in coefficients.enumerated() where coefficient > median {
            hash |= 1 << UInt64(index)
        }
        return hash
    }

    static func distance(_ first: UInt64, _ second: UInt64) -> Int {
        (first ^ second).nonzeroBitCount
    }
}
