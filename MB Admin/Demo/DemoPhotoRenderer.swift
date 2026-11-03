#if DEBUG
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Desenha "fotos de produto" sintéticas (peça de joia num fundo de estúdio) a partir de uma
/// descrição determinística — usado pelo `DemoMode` (servido como se viesse de photos.enjoei.com.br,
/// ver `DemoPhotoURLProtocol`) e pelos testes da comparação por foto, que precisam de pares
/// controlados: a mesma foto recomprimida/redimensionada, variantes de cor, objeto pequeno em muito
/// branco, imagens lisas. **Não substitui** a validação com anúncios reais.
nonisolated enum DemoPhotoRenderer {
    nonisolated struct Color: Hashable, Sendable {
        var red: Double
        var green: Double
        var blue: Double

        static let white = Color(red: 1, green: 1, blue: 1)
        static let silver = Color(red: 0.78, green: 0.78, blue: 0.80)
        static let gold = Color(red: 0.85, green: 0.68, blue: 0.25)
        static let crystal = Color(red: 0.95, green: 0.95, blue: 0.98)

        func scaled(_ factor: Double) -> Color {
            Color(red: red * factor, green: green * factor, blue: blue * factor)
        }
    }

    nonisolated struct Spec: Hashable, Sendable {
        nonisolated enum Shape: Hashable, Sendable, CaseIterable {
            case ring, pendant, earrings, bracelet, chain
        }

        var shape: Shape
        /// Muda os detalhes (pedras, elos, posição dos enfeites) — dois `seed` diferentes da mesma
        /// forma são "produtos diferentes que se parecem".
        var seed: Int
        var metal = Color.silver
        var stone = Color.crystal
        /// Tamanho do objeto em fração do quadro.
        var scale = 0.6
        var centerX = 0.5
        var centerY = 0.5
        var background = Color.white
        /// Gradiente leve de estúdio no fundo (não deixa a borda perfeitamente lisa).
        var backgroundGradient = 0.0
        var rotation = 0.0
    }

    /// Imagem lisa de uma cor só — o caso "foto toda branca".
    static func blank(side: Int, gray: Double = 1) -> CGImage? {
        context(width: side, height: side) { context in
            context.setFillColor(red: gray, green: gray, blue: gray, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    static func image(_ spec: Spec, width: Int, height: Int? = nil) -> CGImage? {
        let height = height ?? width
        return context(width: width, height: height) { context in
            draw(spec, in: context, width: Double(width), height: Double(height))
        }
    }

    /// JPEG com a qualidade pedida — `orientation` grava o EXIF (6 = girar 90° no sentido horário pra
    /// exibir) com os pixels já girados ao contrário, então a imagem exibida é a mesma.
    static func jpeg(_ spec: Spec, side: Int, quality: Double = 0.85, orientation: Int = 1) -> Data? {
        guard let upright = image(spec, width: side),
              let stored = orientation == 6 ? rotatedCounterClockwise(upright) : upright else { return nil }
        return encode(stored, type: .jpeg, quality: quality, orientation: orientation)
    }

    static func encode(_ image: CGImage, type: UTType, quality: Double = 0.85, orientation: Int = 1) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImagePropertyOrientation: orientation
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// Recodifica uma imagem já pronta, num outro tamanho — o "mesmo arquivo enviado de novo" que o
    /// servidor de outra loja redimensionou e recomprimiu.
    static func reencode(_ data: Data, side: Int, quality: Double) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let original = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let resized = context(width: side, height: side, draw: { context in
                  context.interpolationQuality = .high
                  context.draw(original, in: CGRect(x: 0, y: 0, width: side, height: side))
              }) else { return nil }
        return encode(resized, type: .jpeg, quality: quality)
    }

    // MARK: - Desenho

    private static func context(width: Int, height: Int, draw: (CGContext) -> Void) -> CGImage? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        draw(context)
        return context.makeImage()
    }

    private static func rotatedCounterClockwise(_ image: CGImage) -> CGImage? {
        context(width: image.height, height: image.width) { context in
            // Giro de 90° no sentido anti-horário (espaço do CoreGraphics tem y pra cima).
            context.translateBy(x: CGFloat(image.height), y: 0)
            context.rotate(by: .pi / 2)
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
    }

    private static func draw(_ spec: Spec, in context: CGContext, width: Double, height: Double) {
        drawBackground(spec, in: context, width: width, height: height)
        var random = SplitMix(seed: UInt64(bitPattern: Int64(spec.seed &* 7919 &+ spec.shape.hashSeed)))
        let size = min(width, height) * spec.scale
        let pen = Pen(context: context, metal: spec.metal, stone: spec.stone)

        context.saveGState()
        context.translateBy(x: width * spec.centerX, y: height * (1 - spec.centerY))
        context.rotate(by: spec.rotation)
        // Sombra suave embaixo da peça.
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 0.08)
        context.fillEllipse(in: CGRect(x: -size * 0.45, y: -size * 0.55, width: size * 0.9, height: size * 0.12))
        pen.useMetal()

        switch spec.shape {
        case .ring: drawRing(pen: pen, size: size, random: &random)
        case .pendant: drawPendant(pen: pen, size: size, random: &random)
        case .earrings: drawEarrings(pen: pen, size: size, random: &random)
        case .bracelet: drawBracelet(pen: pen, size: size, random: &random)
        case .chain: drawChain(pen: pen, size: size, random: &random)
        }

        // Enfeites pequenos que dependem do `seed`: dois produtos da mesma forma não ficam iguais.
        let ornaments = 2 + Int(random.unit() * 4)
        for _ in 0..<ornaments {
            let point = CGPoint(x: (random.unit() - 0.5) * size * 0.7, y: (random.unit() - 0.5) * size * 0.7)
            pen.stone(at: point, radius: size * (0.02 + random.unit() * 0.03))
        }
        context.restoreGState()
    }

    private static func drawBackground(_ spec: Spec, in context: CGContext, width: Double, height: Double) {
        let background = spec.background
        context.setFillColor(red: background.red, green: background.green, blue: background.blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard spec.backgroundGradient > 0 else { return }
        for step in 0..<24 {
            let progress = Double(step) / 24
            let shade = background.scaled(1 - spec.backgroundGradient * progress)
            context.setFillColor(red: shade.red, green: shade.green, blue: shade.blue, alpha: 0.05)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height * (1 - progress)))
        }
    }

    private static func drawRing(pen: Pen, size: Double, random: inout SplitMix) {
        pen.context.setLineWidth(size * (0.07 + random.unit() * 0.05))
        pen.context.strokeEllipse(in: CGRect(x: -size * 0.4, y: -size * 0.45, width: size * 0.8, height: size * 0.8))
        let stones = 1 + Int(random.unit() * 3)
        for index in 0..<stones {
            let angle = Double.pi / 2 + (Double(index) - Double(stones - 1) / 2) * 0.35
            let point = CGPoint(x: cos(angle) * size * 0.4, y: sin(angle) * size * 0.4 - size * 0.05)
            pen.stone(at: point, radius: size * (0.07 + random.unit() * 0.06))
        }
    }

    private static func drawPendant(pen: Pen, size: Double, random: inout SplitMix) {
        pen.context.setLineWidth(max(1, size * 0.015))
        pen.context.addArc(center: CGPoint(x: 0, y: size * 0.55), radius: size * 0.5, startAngle: .pi * 1.1, endAngle: .pi * 1.9, clockwise: false)
        pen.context.strokePath()
        let dropRadius = size * (0.12 + random.unit() * 0.1)
        let dropCenter = CGPoint(x: 0, y: -size * (0.05 + random.unit() * 0.15))
        pen.context.fillEllipse(in: CGRect(
            x: dropCenter.x - dropRadius,
            y: dropCenter.y - dropRadius * 1.4,
            width: dropRadius * 2,
            height: dropRadius * 2.8
        ))
        pen.stone(at: dropCenter, radius: dropRadius * 0.6)
    }

    private static func drawEarrings(pen: Pen, size: Double, random: inout SplitMix) {
        for side in [-1.0, 1.0] {
            let offset = side * size * (0.22 + random.unit() * 0.1)
            pen.context.setLineWidth(size * 0.04)
            pen.context.strokeEllipse(in: CGRect(x: offset - size * 0.15, y: -size * 0.2, width: size * 0.3, height: size * 0.3))
            pen.stone(at: CGPoint(x: offset, y: -size * 0.32), radius: size * (0.05 + random.unit() * 0.05))
        }
    }

    private static func drawBracelet(pen: Pen, size: Double, random: inout SplitMix) {
        pen.context.setLineWidth(size * 0.03)
        pen.context.strokeEllipse(in: CGRect(x: -size * 0.5, y: -size * 0.3, width: size, height: size * 0.6))
        let beads = 5 + Int(random.unit() * 6)
        for index in 0..<beads {
            let angle = Double(index) / Double(beads) * 2 * .pi + random.unit() * 0.3
            pen.stone(at: CGPoint(x: cos(angle) * size * 0.5, y: sin(angle) * size * 0.3), radius: size * 0.05)
        }
    }

    private static func drawChain(pen: Pen, size: Double, random: inout SplitMix) {
        pen.context.setLineWidth(max(1, size * 0.02))
        let links = 8 + Int(random.unit() * 8)
        for index in 0..<links {
            let progress = Double(index) / Double(links - 1)
            let linkX = (progress - 0.5) * size
            let linkY = sin(progress * .pi * (1 + random.unit())) * size * 0.25
            pen.context.strokeEllipse(in: CGRect(x: linkX - size * 0.04, y: linkY - size * 0.025, width: size * 0.08, height: size * 0.05))
        }
    }

    /// Cores do metal e da pedra de uma peça, já aplicadas no contexto.
    private nonisolated struct Pen {
        let context: CGContext
        let metal: Color
        let stone: Color

        func useMetal() {
            context.setStrokeColor(red: metal.red, green: metal.green, blue: metal.blue, alpha: 1)
            context.setFillColor(red: metal.red, green: metal.green, blue: metal.blue, alpha: 1)
            context.setLineCap(.round)
        }

        func stone(at point: CGPoint, radius: Double) {
            let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            context.setFillColor(red: stone.red, green: stone.green, blue: stone.blue, alpha: 1)
            context.fillEllipse(in: rect)
            let rim = metal.scaled(0.7)
            context.setStrokeColor(red: rim.red, green: rim.green, blue: rim.blue, alpha: 1)
            context.setLineWidth(max(1, radius * 0.25))
            context.strokeEllipse(in: rect)
            useMetal()
        }
    }

    /// Gerador pseudoaleatório determinístico (SplitMix64) — a mesma `Spec` sempre desenha igual.
    private nonisolated struct SplitMix {
        var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func unit() -> Double {
            state &+= 0x9E37_79B9_7F4A_7C15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            mixed ^= mixed >> 31
            return Double(mixed >> 11) / Double(1 << 53)
        }
    }
}

nonisolated extension DemoPhotoRenderer.Spec.Shape {
    fileprivate var hashSeed: Int {
        switch self {
        case .ring: 11
        case .pendant: 23
        case .earrings: 37
        case .bracelet: 41
        case .chain: 59
        }
    }
}
#endif
