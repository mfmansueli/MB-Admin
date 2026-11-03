import CoreGraphics
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import MB_Admin

/// Assinatura + comparação de fotos com imagens sintéticas (`DemoPhotoRenderer`). Transformações
/// sintéticas **não substituem** validação com anúncios reais (ver `PhotoSampleEvaluationTests`) —
/// aqui elas só garantem que os casos conhecidos continuam caindo no nível certo.
@Suite("assinatura e comparação de fotos")
struct PhotoSignatureTests {
    typealias Spec = DemoPhotoRenderer.Spec
    typealias Level = PhotoPairEvidence.Level

    private static let ring = Spec(shape: .ring, seed: 1)
    private static var smallEarrings: Spec {
        var spec = Spec(shape: .earrings, seed: 1)
        spec.scale = 0.12
        return spec
    }

    private func signature(_ data: Data?) throws -> PhotoSignature {
        let data = try #require(data)
        return try PhotoSignatureGenerator.makeSignature(from: data)
    }

    private func compare(_ first: Data?, _ second: Data?) throws -> PhotoPairEvidence {
        PhotoPairComparison.compare(try signature(first), try signature(second))
    }

    // MARK: - Mesma fotografia

    enum Transform: String, CaseIterable, CustomTestStringConvertible {
        case recompressedLowQuality, resizedHalf, resizedSmallLowQuality

        var testDescription: String { rawValue }

        func apply(to original: Data) -> Data? {
            switch self {
            case .recompressedLowQuality: DemoPhotoRenderer.reencode(original, side: 600, quality: 0.5)
            case .resizedHalf: DemoPhotoRenderer.reencode(original, side: 300, quality: 0.7)
            case .resizedSmallLowQuality: DemoPhotoRenderer.reencode(original, side: 220, quality: 0.4)
            }
        }
    }

    @Test("mesma foto recomprimida/redimensionada continua sendo a mesma foto", arguments: Transform.allCases)
    func mesmaFotoTransformada(_ transform: Transform) throws {
        let original = try #require(DemoPhotoRenderer.jpeg(Self.ring, side: 600, quality: 0.92))
        let evidence = try compare(original, transform.apply(to: original))
        #expect(evidence.level == .samePhoto)
        #expect(!evidence.colorsDiffer)
    }

    @Test("orientação EXIF é aplicada antes da assinatura")
    func orientacaoExif() throws {
        let upright = DemoPhotoRenderer.jpeg(Self.ring, side: 300)
        let rotatedByMetadata = DemoPhotoRenderer.jpeg(Self.ring, side: 300, orientation: 6)
        #expect(try compare(upright, rotatedByMetadata).level == .samePhoto)
    }

    @Test("mesmos bytes com ids/URLs diferentes são idênticos — o id não importa")
    func mesmosBytes() throws {
        let data = DemoPhotoRenderer.jpeg(Self.ring, side: 300)
        let evidence = try compare(data, data)
        #expect(evidence.level == .identical)
        #expect(evidence.isSameFile)
        #expect(!evidence.isSamePublicID)
    }

    @Test("PNG e JPEG da mesma imagem são a mesma foto")
    func formatosDiferentes() throws {
        let image = try #require(DemoPhotoRenderer.image(Self.ring, width: 300))
        let png = DemoPhotoRenderer.encode(image, type: .png)
        let jpeg = DemoPhotoRenderer.encode(image, type: .jpeg, quality: 0.6)
        #expect(try compare(png, jpeg).level == .samePhoto)
    }

    @Test("produto claro em fundo branco não é cortado e é reconhecido")
    func produtoClaro() throws {
        var light = Spec(shape: .pendant, seed: 4)
        light.metal = .init(red: 0.93, green: 0.93, blue: 0.93)
        light.stone = .init(red: 0.97, green: 0.97, blue: 0.99)
        let first = try signature(DemoPhotoRenderer.jpeg(light, side: 300, quality: 0.9))
        let second = try signature(DemoPhotoRenderer.jpeg(light, side: 300, quality: 0.5))
        #expect(first.isInformative)
        #expect(first.hasUniformBackground)
        // O pingente ocupa ~60% do lado; recorte bem menor que isso seria corte de produto.
        #expect(first.contentBox.width > 0.5)
        #expect(first.contentBox.height > 0.5)
        #expect(PhotoPairComparison.compare(first, second).level == .samePhoto)
    }

    @Test("fundo com gradiente leve e fundo escuro continuam funcionando")
    func fundosNaoBrancos() throws {
        var studio = Self.ring
        studio.backgroundGradient = 0.06
        #expect(try compare(
            DemoPhotoRenderer.jpeg(studio, side: 300, quality: 0.9),
            DemoPhotoRenderer.jpeg(studio, side: 260, quality: 0.6)
        ).level == .samePhoto)

        var dark = Self.ring
        dark.background = .init(red: 0.55, green: 0.42, blue: 0.35)
        dark.backgroundGradient = 0.5
        #expect(try compare(
            DemoPhotoRenderer.jpeg(dark, side: 300, quality: 0.9),
            DemoPhotoRenderer.jpeg(dark, side: 240, quality: 0.6)
        ).level == .samePhoto)
    }

    // MARK: - Objeto pequeno em muito branco

    @Test("objeto pequeno: a mesma foto recomprimida é reconhecida pelo recorte")
    func objetoPequenoMesmaFoto() throws {
        let original = try #require(DemoPhotoRenderer.jpeg(Self.smallEarrings, side: 600, quality: 0.9))
        let first = try signature(DemoPhotoRenderer.jpeg(Self.smallEarrings, side: 300, quality: 0.9))
        #expect(first.contentBox.width < 0.2, "o recorte deve isolar o brinco do branco")
        #expect(PhotoPairComparison.compare(
            first, try signature(DemoPhotoRenderer.jpeg(Self.smallEarrings, side: 300, quality: 0.45))
        ).level == .samePhoto)
        #expect(try compare(original, DemoPhotoRenderer.reencode(original, side: 300, quality: 0.7)).level == .samePhoto)
    }

    @Test("objeto pequeno: produtos diferentes não viram a mesma foto só porque o branco é igual",
          arguments: [2, 5])
    func objetoPequenoDiferente(seed: Int) throws {
        var other = Self.smallEarrings
        other.seed = seed
        let evidence = try compare(
            DemoPhotoRenderer.jpeg(Self.smallEarrings, side: 300),
            DemoPhotoRenderer.jpeg(other, side: 300)
        )
        #expect(evidence.level == .different)
    }

    // MARK: - Variantes e produtos parecidos

    @Test("variante de cor (dourado × prateado) fica parecida, com cor diferente — nunca a mesma foto")
    func varianteMetal() throws {
        var gold = Self.ring
        gold.metal = .gold
        let evidence = try compare(DemoPhotoRenderer.jpeg(Self.ring, side: 300), DemoPhotoRenderer.jpeg(gold, side: 300))
        #expect(evidence.level == .similar)
        #expect(evidence.colorsDiffer)
    }

    @Test("pedra de outra cor com a mesma luminância só é pega pela cor")
    func variantePedraMesmaLuminancia() throws {
        var red = Self.ring
        red.stone = .init(red: 0.85, green: 0.25, blue: 0.25)
        var blue = Self.ring
        blue.stone = .init(red: 0.35, green: 0.45, blue: 0.95)
        let evidence = try compare(DemoPhotoRenderer.jpeg(red, side: 300), DemoPhotoRenderer.jpeg(blue, side: 300))
        #expect(evidence.level == .similar)
        #expect(evidence.colorsDiffer)
        #expect(evidence.contentCorrelation > 0.99, "a estrutura é a mesma — é a cor que separa")
    }

    @Test("produtos diferentes na mesma pose não são a mesma foto", arguments: 2...6)
    func produtosDiferentesMesmaPose(seed: Int) throws {
        let evidence = try compare(
            DemoPhotoRenderer.jpeg(Self.ring, side: 300),
            DemoPhotoRenderer.jpeg(Spec(shape: .ring, seed: seed), side: 300)
        )
        #expect(evidence.level < .samePhoto)
    }

    @Test("a mesma peça fotografada de novo (deslocada) não é a mesma fotografia")
    func mesmaPecaRefotografada() throws {
        var shifted = Self.ring
        shifted.centerX = 0.53
        shifted.centerY = 0.52
        let evidence = try compare(DemoPhotoRenderer.jpeg(Self.ring, side: 300), DemoPhotoRenderer.jpeg(shifted, side: 300))
        #expect(evidence.level == .similar)
    }

    @Test("formatos diferentes de joia não se confundem", arguments: Spec.Shape.allCases)
    func formasDiferentes(shape: Spec.Shape) throws {
        let evidence = try compare(
            DemoPhotoRenderer.jpeg(Spec(shape: shape, seed: 1), side: 300),
            DemoPhotoRenderer.jpeg(Spec(shape: shape, seed: 2), side: 300)
        )
        #expect(evidence.level == .different)
    }

    // MARK: - Fotos sem informação ou inválidas

    @Test("duas fotos todas brancas não são evidência de nada, nem com bytes iguais")
    func fotosLisas() throws {
        let blank = try #require(DemoPhotoRenderer.blank(side: 300).flatMap { DemoPhotoRenderer.encode($0, type: .jpeg) })
        let gray = try #require(DemoPhotoRenderer.blank(side: 300, gray: 0.5).flatMap { DemoPhotoRenderer.encode($0, type: .jpeg) })
        let blankSignature = try signature(blank)
        #expect(!blankSignature.isInformative)
        #expect(PhotoPairComparison.compare(blankSignature, blankSignature).level == .different)
        #expect(try compare(blank, gray).level == .different)
        #expect(try !signature(gray).isInformative)
    }

    @Test("bytes que não são imagem falham como 'não decodificável'")
    func dadosInvalidos() {
        #expect(throws: PhotoSignatureError.undecodable) {
            try PhotoSignatureGenerator.makeSignature(from: Data("<html>404</html>".utf8))
        }
        #expect(throws: PhotoSignatureError.undecodable) {
            try PhotoSignatureGenerator.makeSignature(from: Data())
        }
    }

    @Test("imagem minúscula falha como 'pequena demais'")
    func imagemPequenaDemais() throws {
        let tiny = try #require(DemoPhotoRenderer.image(Self.ring, width: 20).flatMap { DemoPhotoRenderer.encode($0, type: .png) })
        #expect(throws: PhotoSignatureError.tooSmall) {
            try PhotoSignatureGenerator.makeSignature(from: tiny)
        }
    }

    // MARK: - Peças básicas

    @Test("assinatura sobrevive a encode/decode (é o que vai pro cache)")
    func codable() throws {
        let original = try signature(DemoPhotoRenderer.jpeg(Self.ring, side: 300))
        let decoded = try JSONDecoder().decode(PhotoSignature.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
        #expect(decoded.algorithmVersion == PhotoMatchingParameters.signatureVersion)
    }

    @Test("pHash: distância é a contagem de bits diferentes")
    func distanciaHash() {
        #expect(PerceptualHash.distance(0, 0) == 0)
        #expect(PerceptualHash.distance(0b1011, 0b0001) == 2)
        #expect(PerceptualHash.distance(.max, 0) == 64)
    }

    @Test("correlação de miniaturas lisas é 0 — nunca 'iguais'")
    func correlacaoLisa() {
        let flat = [UInt8](repeating: 255, count: 64)
        #expect(PhotoPairComparison.correlation(flat, flat) == 0)
        let ramp = (0..<64).map { UInt8($0 * 4) }
        #expect(abs(PhotoPairComparison.correlation(ramp, ramp) - 1) < 1e-9)
    }

    @Test("limite de correlação cresce com o tamanho do recorte")
    func limiteAdaptativo() {
        let limits = PhotoMatchingParameters.self
        #expect(limits.samePhotoMinContentCorrelation(contentSide: 20) == limits.samePhotoMinContentCorrelationSmall)
        #expect(limits.samePhotoMinContentCorrelation(contentSide: 200) == limits.samePhotoMinContentCorrelationLarge)
        let middle = limits.samePhotoMinContentCorrelation(contentSide: 88)
        #expect(middle > limits.samePhotoMinContentCorrelationSmall)
        #expect(middle < limits.samePhotoMinContentCorrelationLarge)
    }
}
