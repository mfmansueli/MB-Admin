import Foundation
import Testing
@testable import MB_Admin

/// Mede o comparador com fotos **reais** de anúncios, rotuladas à mão, guardadas só nesta máquina
/// em `PhotoSamples/` na raiz do repositório (fora do git — ver `PhotoSamples/README.md`):
///
/// ```
/// PhotoSamples/<tuning|evaluation>/<same|different|variant|missing>/<caso>/a/*.jpg   (loja A)
///                                                                      /b/*.jpg   (loja B; não existe em missing)
///                                                                      /a/title.txt, description.txt, price.txt,
///                                                                         brand.txt, size.txt (opcionais; idem em b/)
/// ```
///
/// - `same`: o mesmo produto nas duas lojas (fotos podem ter sido recomprimidas, recortadas, em
///   outra ordem). Esperado: par forte (ou revisão); **nunca** possivelmente ausente.
/// - `different`: produtos diferentes que se parecem (variante de cor, mesma peça em outro tamanho,
///   foto quase igual). Esperado: **nunca** par forte.
/// - `variant`: outra **versão** do mesmo produto (aro, banho, cor, medida), muitas vezes com a
///   mesma foto — a diferença no título, na descrição, no tamanho do template ou no preço. Esperado:
///   **nunca** par forte; o ideal é "outra versão" (possivelmente ausente com a nota da versão de lá).
/// - `missing`: produto só da loja A. Esperado: possivelmente ausente; nunca par forte.
///
/// Todos os casos de uma divisão entram juntos numa comparação só (A = todos os `a/`, B = todos os
/// `b/`), como duas lojas de verdade — então um caso também pode errar casando com o `b/` de outro.
/// Ajuste os limites de `PhotoMatchingParameters` olhando **só** o relatório de `tuning`; rode
/// `evaluation` no fim, sem mexer depois de ver o resultado. Sem amostras, os dois testes são pulados.
@Suite("avaliação com amostras reais de fotos")
struct PhotoSampleEvaluationTests {
    nonisolated enum Kind: String, CaseIterable, Sendable {
        case same, different, variant, missing
    }

    nonisolated enum Outcome: String, CaseIterable, Sendable {
        case strong = "forte"
        case review = "revisar"
        case otherVersion = "outra versão"
        case missing = "possivelmente ausente"
        case unverified = "não verificado"
    }

    /// O texto opcional de um lado do caso (`title.txt`, `description.txt`, `price.txt`,
    /// `brand.txt`, `size.txt`).
    nonisolated struct SideText: Sendable {
        var title: String?
        var description: String?
        var price: Double?
        var brand: String?
        var size: String?
    }

    nonisolated struct SampleCase: Sendable {
        let kind: Kind
        let name: String
        let photosA: [URL]
        let photosB: [URL]
        let textA: SideText
        let textB: SideText
    }

    nonisolated struct Report: Sendable {
        var table: [Kind: [Outcome: Int]] = [:]
        /// Casos em que um par forte ligou produtos diferentes (ou versões diferentes, ou o produto ao
        /// `b/` de outro caso).
        var falseMatches: [String] = []
        /// Casos `same` que saíram como possivelmente ausentes — o erro que faria postar duplicado.
        var presentAsMissing: [String] = []
        var reviewCount = 0
        var photoFailures: [String] = []
        /// Índice de correspondência de cada par forte/revisão com o `b/` do próprio caso, por tipo —
        /// pra ver se o índice separa `same` de `variant`/`different`.
        var indexes: [Kind: [Int]] = [:]

        var text: String {
            var lines = ["", "| esperado \\ saiu | " + Outcome.allCases.map(\.rawValue).joined(separator: " | ") + " |"]
            lines.append("|---|" + Outcome.allCases.map { _ in "---" }.joined(separator: "|") + "|")
            for kind in Kind.allCases {
                let row = Outcome.allCases.map { "\(table[kind]?[$0] ?? 0)" }.joined(separator: " | ")
                lines.append("| \(kind.rawValue) | \(row) |")
            }
            lines.append("revisões: \(reviewCount)")
            for kind in Kind.allCases {
                guard let values = indexes[kind], !values.isEmpty else { continue }
                lines.append("índice (\(kind.rawValue)): \(values.sorted().map(String.init).joined(separator: ", "))")
            }
            lines.append("pares falsos (\(falseMatches.count)): \(falseMatches.joined(separator: ", "))")
            lines.append("presentes dados como ausentes (\(presentAsMissing.count)): \(presentAsMissing.joined(separator: ", "))")
            if !photoFailures.isEmpty { lines.append("fotos que não abriram: \(photoFailures.joined(separator: ", "))") }
            return lines.joined(separator: "\n")
        }
    }

    private static let sellerA = 1001
    private static let sellerB = 2002
    private static let imageExtensions: Set = ["jpg", "jpeg", "png", "heic", "webp"]

    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // PhotoMatching
        .deletingLastPathComponent() // MB AdminTests
        .deletingLastPathComponent() // raiz do repositório
        .appendingPathComponent("PhotoSamples")

    static func hasSamples(split: String) -> Bool { !cases(split: split).isEmpty }

    @Test("amostras de ajuste: relatório pra calibrar os limites", .enabled(if: hasSamples(split: "tuning")))
    func tuning() {
        let report = Self.evaluate(split: "tuning")
        print("[PhotoSamples/tuning]\(report.text)")
    }

    @Test("amostras de avaliação: nenhum par falso", .enabled(if: hasSamples(split: "evaluation")))
    func evaluation() {
        let report = Self.evaluate(split: "evaluation")
        print("[PhotoSamples/evaluation]\(report.text)")
        #expect(report.falseMatches.isEmpty, "pares falsos: \(report.falseMatches.joined(separator: ", "))")
    }

    @Test("o próprio harness: lê a estrutura de pastas e monta o relatório (com fotos sintéticas)")
    func harnessComFotosSinteticas() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoSamples-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        var gold = ComparisonFixtures.ring(1)
        gold.metal = .gold
        let photos: [(path: String, spec: DemoPhotoRenderer.Spec, quality: Double)] = [
            ("same/anel/a/1.jpg", ComparisonFixtures.ring(1), 0.9),
            ("same/anel/b/1.jpg", ComparisonFixtures.ring(1), 0.6),
            ("different/anel-dourado/a/1.jpg", DemoPhotoRenderer.Spec(shape: .bracelet, seed: 4), 0.9),
            ("different/anel-dourado/b/1.jpg", DemoPhotoRenderer.Spec(shape: .chain, seed: 8), 0.6),
            ("missing/pingente/a/1.jpg", DemoPhotoRenderer.Spec(shape: .pendant, seed: 3), 0.9),
            ("variant/anel-aro/a/1.jpg", ComparisonFixtures.ring(7), 0.9),
            ("variant/anel-aro/b/1.jpg", ComparisonFixtures.ring(7), 0.6)
        ]
        for photo in photos {
            let url = root.appendingPathComponent("tuning").appendingPathComponent(photo.path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try #require(DemoPhotoRenderer.jpeg(photo.spec, side: 300, quality: photo.quality)).write(to: url)
        }
        try Data("não é imagem".utf8).write(to: root.appendingPathComponent("tuning/missing/pingente/a/notas.txt"))
        // A mesma foto; só a descrição e o preço dizem que é outro aro.
        try Data("anel solitário, aro 16".utf8).write(to: root.appendingPathComponent("tuning/variant/anel-aro/a/description.txt"))
        try Data("anel solitário, aro 18".utf8).write(to: root.appendingPathComponent("tuning/variant/anel-aro/b/description.txt"))
        try Data("149,90".utf8).write(to: root.appendingPathComponent("tuning/variant/anel-aro/b/price.txt"))

        let cases = Self.cases(root: root, split: "tuning")
        #expect(cases.map(\.name) == ["anel", "anel-dourado", "anel-aro", "pingente"])
        #expect(cases.first { $0.name == "anel-aro" }?.textB.price == 149.9)
        #expect(Self.cases(root: root, split: "evaluation").isEmpty)
        let report = Self.evaluate(root: root, split: "tuning")
        #expect(report.table[.same]?[.strong] == 1)
        #expect(report.table[.different]?[.strong] == nil)
        #expect(report.table[.missing]?[.missing] == 1)
        #expect(report.table[.variant]?[.otherVersion] == 1)
        #expect(report.falseMatches.isEmpty)
        #expect(report.presentAsMissing.isEmpty)
        #expect(report.text.contains("| same | 1 | 0 | 0 | 0 | 0 |"))
        #expect(report.indexes[.same]?.count == 1)
    }

    // MARK: - Leitura das amostras

    static func cases(root: URL = root, split: String) -> [SampleCase] {
        let fileManager = FileManager.default
        var result: [SampleCase] = []
        for kind in Kind.allCases {
            let kindURL = root.appendingPathComponent(split).appendingPathComponent(kind.rawValue)
            let names = ((try? fileManager.contentsOfDirectory(atPath: kindURL.path)) ?? [])
                .filter { !$0.hasPrefix(".") }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            for name in names {
                let caseURL = kindURL.appendingPathComponent(name)
                let photosA = photos(in: caseURL.appendingPathComponent("a"))
                let photosB = kind == .missing ? [] : photos(in: caseURL.appendingPathComponent("b"))
                guard !photosA.isEmpty, kind == .missing || !photosB.isEmpty else { continue }
                result.append(SampleCase(
                    kind: kind, name: name, photosA: photosA, photosB: photosB,
                    textA: sideText(in: caseURL.appendingPathComponent("a")),
                    textB: sideText(in: caseURL.appendingPathComponent("b"))
                ))
            }
        }
        return result
    }

    private static func photos(in folder: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static func sideText(in folder: URL) -> SideText {
        func read(_ name: String) -> String? {
            guard let text = try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8) else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        // "149,90", "R$ 149,90" ou "149.90".
        let price = read("price.txt").flatMap { raw in
            Double(raw.replacingOccurrences(of: "R$", with: "").replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        }
        return SideText(
            title: read("title.txt"), description: read("description.txt"), price: price, brand: read("brand.txt"), size: read("size.txt")
        )
    }

    // MARK: - Avaliação

    static func evaluate(root: URL = root, split: String) -> Report {
        let cases = cases(root: root, split: split)
        var report = Report()
        var listingsA: [ComparableListing] = []
        var listingsB: [ComparableListing] = []
        for (index, sample) in cases.enumerated() {
            let productID = index + 1
            listingsA.append(listing(seller: sellerA, id: productID, side: "a", sample: sample, report: &report))
            if sample.kind != .missing {
                listingsB.append(listing(seller: sellerB, id: productID, side: "b", sample: sample, report: &report))
            }
        }
        let result = AccountProductMatcher.compare(
            ComparisonSide(sellerID: sellerA, name: "loja A", listings: listingsA, status: .complete),
            ComparisonSide(sellerID: sellerB, name: "loja B", listings: listingsB, status: .complete),
            decisions: []
        )
        report.reviewCount = result.reviews.count

        for (index, sample) in cases.enumerated() {
            let productID = index + 1
            let label = "\(sample.kind.rawValue)/\(sample.name)"
            let strongWith = Set(result.matches.filter { $0.productA.id == productID }.map(\.productB.id))
            let outcome: Outcome
            if !strongWith.isEmpty {
                outcome = .strong
            } else if result.reviews.contains(where: { $0.productA.id == productID }) {
                outcome = .review
            } else if result.possiblyMissingInB.contains(where: { $0.id == productID }) {
                let hasOtherVersion = result.otherVersions[ListingKey(sellerID: sellerA, productID: productID)]?.isEmpty == false
                outcome = hasOtherVersion ? .otherVersion : .missing
            } else {
                outcome = .unverified
            }
            let ownPair = (result.matches + result.reviews).first { $0.productA.id == productID && $0.productB.id == productID }
            if let ownPair { report.indexes[sample.kind, default: []].append(ownPair.index.score) }
            report.table[sample.kind, default: [:]][outcome, default: 0] += 1
            let wrongPartner = strongWith.contains { $0 != productID }
            if wrongPartner || (sample.kind != .same && !strongWith.isEmpty) {
                report.falseMatches.append(label)
            }
            if sample.kind == .same, outcome == .missing {
                report.presentAsMissing.append(label)
            }
        }
        return report
    }

    /// Um anúncio com as fotos e o texto do lado dado. Ids públicos únicos por arquivo (nunca o atalho
    /// de "mesmo id") e, sem `title.txt`, um título de uma palavra só que não lembra nenhum outro — a
    /// decisão fica com as fotos (e com descrição/preço/marca/tamanho, quando houver); em `variant`,
    /// o mesmo título neutro dos dois lados do caso. Sem `price.txt`, R$ 100 dos dois lados.
    private static func listing(seller: Int, id: Int, side: String, sample: SampleCase, report: inout Report) -> ComparableListing {
        let urls = Array((side == "a" ? sample.photosA : sample.photosB).prefix(PhotoMatchingParameters.comparisonPhotoCount))
        let publicIDs = urls.map { "\(sample.kind.rawValue)/\(sample.name)/\(side)/\($0.lastPathComponent)" }
        var signatures: [String: PhotoSignature] = [:]
        var failures: [String: PhotoSignatureError] = [:]
        for (url, publicID) in zip(urls, publicIDs) {
            do {
                signatures[publicID] = try PhotoSignatureGenerator.makeSignature(from: try Data(contentsOf: url))
            } catch let error as PhotoSignatureError {
                failures[publicID] = error
                report.photoFailures.append(publicID)
            } catch {
                failures[publicID] = .downloadFailed(error.localizedDescription)
                report.photoFailures.append(publicID)
            }
        }
        let text = side == "a" ? sample.textA : sample.textB
        // Versões costumam ter o mesmo título: em `variant`, os dois lados ganham o mesmo título neutro.
        let title = text.title ?? (sample.kind == .variant ? "variante\(id)" : "amostra\(side)\(id)")
        let price = text.price ?? 100
        let product = EnjoeiProduct(id: id, title: title, path: "amostra-\(id)", photoPublicID: publicIDs.first, currentPrice: price, originalPrice: price)
        let details = ProductListingDetails(
            productID: id, coverPublicID: publicIDs.first, photoPublicIDs: publicIDs, categoryID: nil,
            size: text.size, brand: text.brand, description: text.description ?? "", fetchedAt: Date()
        )
        return ComparableListing(sellerID: seller, product: product, details: details, signatures: signatures, failures: failures)
    }
}
