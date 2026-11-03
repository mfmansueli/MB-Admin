import Foundation

/// Compara duas `PhotoSignature` e decide se são a mesma fotografia. Não confia num hash só: "mesma
/// foto" exige, ao mesmo tempo, hash do recorte próximo, miniaturas do recorte **e** do quadro
/// inteiro quase idênticas, cor por célula batendo (variante de cor não passa) e o mesmo
/// enquadramento. Todos os limites estão em `PhotoMatchingParameters`.
nonisolated enum PhotoPairComparison {
    private typealias Limits = PhotoMatchingParameters

    /// Medidas calculadas antes de decidir o nível.
    private struct Measurements {
        var contentDistance: Int
        var isSameFile: Bool
        var framing: Double
        var aspect: Double
        var contentCorrelation = 0.0
        var fullCorrelation = 0.0
        var meanColor = Double.infinity
        var maxColor = Double.infinity

        func evidence(_ level: PhotoPairEvidence.Level, colorsDiffer: Bool = false) -> PhotoPairEvidence {
            PhotoPairEvidence(
                level: level,
                isSamePublicID: false,
                isSameFile: isSameFile,
                contentHashDistance: contentDistance,
                contentCorrelation: contentCorrelation,
                fullCorrelation: fullCorrelation,
                meanColorDifference: meanColor,
                maxColorDifference: maxColor,
                framingDifference: framing,
                aspectDifference: aspect,
                colorsDiffer: colorsDiffer
            )
        }
    }

    static func compare(_ first: PhotoSignature, _ second: PhotoSignature) -> PhotoPairEvidence {
        var measured = Measurements(
            contentDistance: PerceptualHash.distance(first.contentHash, second.contentHash),
            isSameFile: first.contentSHA256 == second.contentSHA256,
            framing: first.contentBox.maximumEdgeDifference(to: second.contentBox),
            aspect: abs(log(max(first.contentAspectRatio, 0.0001) / max(second.contentAspectRatio, 0.0001)))
        )

        // Foto lisa ou inválida não é evidência de nada, nem byte a byte (duas fotos brancas iguais
        // não fazem dois anúncios serem o mesmo produto).
        guard first.isInformative, second.isInformative else { return measured.evidence(.different) }
        if measured.isSameFile {
            measured.contentCorrelation = 1
            measured.fullCorrelation = 1
            measured.meanColor = 0
            measured.maxColor = 0
            return measured.evidence(.identical)
        }

        // Portões baratos antes das correlações — a grande maioria dos pares para aqui.
        let backgroundsAgree = first.hasUniformBackground == second.hasUniformBackground
        guard measured.contentDistance <= Limits.candidateContentHashRadius,
              measured.aspect <= Limits.similarMaxAspectDifference,
              measured.framing <= Limits.similarMaxFramingDifference || !backgroundsAgree else {
            return measured.evidence(.different)
        }
        measured.contentCorrelation = correlation(first.contentLuma, second.contentLuma)
        let contentSide = min(first.contentPixelSide, second.contentPixelSide)
        let minimumSameCorrelation = Limits.samePhotoMinContentCorrelation(contentSide: contentSide)
        guard measured.contentCorrelation >= min(minimumSameCorrelation, Limits.similarMinContentCorrelation) else {
            return measured.evidence(.different)
        }

        measured.fullCorrelation = correlation(first.fullLuma, second.fullLuma)
        (measured.meanColor, measured.maxColor) = colorDifference(first.contentColor, second.contentColor)
        return classify(measured, minimumSameCorrelation: minimumSameCorrelation, backgroundsAgree: backgroundsAgree)
    }

    private static func classify(
        _ measured: Measurements,
        minimumSameCorrelation: Double,
        backgroundsAgree: Bool
    ) -> PhotoPairEvidence {
        let structureMatches = measured.contentDistance <= Limits.samePhotoMaxContentHashDistance
            && measured.contentCorrelation >= minimumSameCorrelation
            && measured.fullCorrelation >= Limits.samePhotoMinFullCorrelation
            && measured.framing <= Limits.samePhotoMaxFramingDifference
            && measured.aspect <= Limits.samePhotoMaxAspectDifference
            && backgroundsAgree
        let colorMatches = measured.meanColor <= Limits.samePhotoMaxMeanColorDifference
            && measured.maxColor <= Limits.samePhotoMaxCellColorDifference

        if structureMatches && colorMatches {
            return measured.evidence(.samePhoto)
        }
        if structureMatches || measured.contentCorrelation >= Limits.similarMinContentCorrelation {
            return measured.evidence(.similar, colorsDiffer: structureMatches && !colorMatches)
        }
        return measured.evidence(.different)
    }

    /// Correlação de Pearson — insensível a brilho/contraste globais (recompressão, filtro leve).
    /// Duas miniaturas lisas não têm correlação definida: devolve 0, nunca "iguais".
    static func correlation(_ first: [UInt8], _ second: [UInt8]) -> Double {
        guard first.count == second.count, !first.isEmpty else { return 0 }
        let count = Double(first.count)
        var sumFirst = 0.0, sumSecond = 0.0
        for index in first.indices {
            sumFirst += Double(first[index])
            sumSecond += Double(second[index])
        }
        let meanFirst = sumFirst / count
        let meanSecond = sumSecond / count
        var covariance = 0.0, varianceFirst = 0.0, varianceSecond = 0.0
        for index in first.indices {
            let deltaFirst = Double(first[index]) - meanFirst
            let deltaSecond = Double(second[index]) - meanSecond
            covariance += deltaFirst * deltaSecond
            varianceFirst += deltaFirst * deltaFirst
            varianceSecond += deltaSecond * deltaSecond
        }
        guard varianceFirst > 1, varianceSecond > 1 else { return 0 }
        return covariance / (varianceFirst * varianceSecond).squareRoot()
    }

    /// ΔE76 (CIELAB, D65) célula a célula: média e maior diferença.
    static func colorDifference(_ first: [UInt8], _ second: [UInt8]) -> (mean: Double, max: Double) {
        guard first.count == second.count, first.count % 3 == 0, !first.isEmpty else { return (.infinity, .infinity) }
        var total = 0.0
        var largest = 0.0
        let cells = first.count / 3
        for cell in 0..<cells {
            let labFirst = lab(red: first[cell * 3], green: first[cell * 3 + 1], blue: first[cell * 3 + 2])
            let labSecond = lab(red: second[cell * 3], green: second[cell * 3 + 1], blue: second[cell * 3 + 2])
            let difference = labFirst - labSecond
            let delta = (difference * difference).sum().squareRoot()
            total += delta
            largest = max(largest, delta)
        }
        return (total / Double(cells), largest)
    }

    /// sRGB → CIELAB (L, a, b), iluminante D65.
    private static func lab(red: UInt8, green: UInt8, blue: UInt8) -> SIMD3<Double> {
        func linear(_ value: UInt8) -> Double {
            let channel = Double(value) / 255
            return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        let linearRed = linear(red), linearGreen = linear(green), linearBlue = linear(blue)
        // sRGB → XYZ (D65), normalizado pelo branco de referência.
        let xyzX = (0.4124 * linearRed + 0.3576 * linearGreen + 0.1805 * linearBlue) / 0.95047
        let xyzY = 0.2126 * linearRed + 0.7152 * linearGreen + 0.0722 * linearBlue
        let xyzZ = (0.0193 * linearRed + 0.1192 * linearGreen + 0.9505 * linearBlue) / 1.08883
        func compand(_ value: Double) -> Double {
            value > 0.008856 ? pow(value, 1.0 / 3) : (7.787 * value + 16.0 / 116)
        }
        let companded = SIMD3(compand(xyzX), compand(xyzY), compand(xyzZ))
        return SIMD3(
            116 * companded.y - 16,
            500 * (companded.x - companded.y),
            200 * (companded.y - companded.z)
        )
    }
}
