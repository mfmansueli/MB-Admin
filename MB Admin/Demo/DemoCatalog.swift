#if DEBUG
import Foundation

/// Contas e produtos inventados do `DemoMode` — os mesmos nomes do mock do redesign (antonia,
/// loja A/B/C), pra comparar a tela com o desenho lado a lado. Puro dado, sem estado.
nonisolated enum DemoCatalog {
    nonisolated struct Profile: Sendable {
        let accountID: EnjoeiAccountID
        let user: EnjoeiUser
        let productCount: Int
        let isSessionExpired: Bool
        let lastRoundSummary: MegaphoneRoundSummary?
    }

    static let profiles: [Profile] = [
        Profile(
            accountID: uuid("0000000A"),
            user: EnjoeiUser(id: 1001, nickname: "antonia-40d0aa", name: "antonia", avatarPublicID: nil, availableProductsCount: 60),
            productCount: 60,
            isSessionExpired: false,
            lastRoundSummary: nil
        ),
        Profile(
            accountID: uuid("0000000B"),
            user: EnjoeiUser(id: 1002, nickname: "loja-b", name: "loja B", avatarPublicID: nil, availableProductsCount: 25),
            productCount: 25,
            isSessionExpired: false,
            lastRoundSummary: MegaphoneRoundSummary(succeeded: 120, failed: 3, finishedAt: .now.addingTimeInterval(-86_400))
        ),
        Profile(
            accountID: uuid("0000000C"),
            user: EnjoeiUser(id: 1003, nickname: "loja-c", name: "loja C", avatarPublicID: nil, availableProductsCount: 40),
            productCount: 40,
            isSessionExpired: false,
            lastRoundSummary: MegaphoneRoundSummary(succeeded: 338, failed: 2, finishedAt: .now.addingTimeInterval(-7_200))
        ),
        Profile(
            accountID: uuid("0000000D"),
            user: EnjoeiUser(id: 1004, nickname: "loja-a", name: "loja A", avatarPublicID: nil, availableProductsCount: 30),
            productCount: 30,
            isSessionExpired: true,
            lastRoundSummary: nil
        )
    ]

    static func profile(for accountID: EnjoeiAccountID) -> Profile {
        profiles.first { $0.accountID == accountID } ?? profiles[0]
    }

    private static let titles = [
        "brinco argola estrela 50mm leve moderno joia prata 925",
        "anel aro 17 entrelaçado cravejado zircônia branca",
        "colar curto pingente cravejado menino zircônia branca",
        "pingente ponto de luz prata 925 zircônia",
        "colar coração prata 925",
        "pulseira elos portugueses prata 925 18cm",
        "brinco pérola shell 8mm prata 925",
        "tornozeleira bolinhas prata 925",
        "anel solitário zircônia rosa",
        "corrente veneziana 45cm prata 925"
    ]

    /// Posições (no catálogo de cada loja) dos produtos que pedem desconto — três, como no mock.
    private static let discountPositions: [Int: Double] = [3: 0.44, 7: 0.85, 12: 0.7]

    static func products(for profile: Profile) -> [EnjoeiProduct] {
        (0..<profile.productCount).map { position in
            let base = Double([99, 149, 273, 299, 459, 799][position % 6])
            // Quem pede desconto fica sem desconto da loja, pra o preço sugerido sair abaixo do atual.
            let hasStoreDiscount = position % 4 == 0 && discountPositions[position] == nil
            return EnjoeiProduct(
                id: productID(profile: profile, position: position),
                title: titles[position % titles.count] + (position >= titles.count ? " \(position / titles.count + 1)" : ""),
                path: "produto-demo-\(position)",
                photoPublicID: nil,
                currentPrice: base,
                originalPrice: hasStoreDiscount ? (base * 1.46).rounded() : base
            )
        }
    }

    static func exposures(for profile: Profile, productIDs: [Int]) -> [MegaphoneExposure] {
        productIDs.map { productID in
            let position = productID - profile.user.id * 1000
            if let factor = discountPositions[position] {
                let product = products(for: profile)[position]
                let suggested = ((product.originalPrice ?? 100) * factor).rounded()
                let percent = Int(((1 - factor) * 100).rounded())
                return MegaphoneExposure(
                    productID: productID,
                    kind: .maximumAfterDiscount,
                    priceToIncreaseExposure: suggested,
                    discountLabel: "- \(percent)%"
                )
            }
            return MegaphoneExposure(productID: productID, kind: .maximumForFree, priceToIncreaseExposure: nil, discountLabel: nil)
        }
    }

    /// Um a cada ~20 produtos falha com 504 — o suficiente pra linha de erro aparecer na tela.
    static func megaphoneFails(productID: Int) -> Bool {
        productID % 23 == 5
    }

    static func inactiveProducts(for profile: Profile) -> [InactiveProduct] {
        (0..<8).map { position in
            InactiveProduct(
                id: profile.user.id * 1000 + 500 + position,
                path: "inativo-demo-\(position)",
                title: titles[(position + 3) % titles.count],
                price: Double([129, 89, 349, 59][position % 4]),
                photoPublicID: nil,
                inactiveSince: "1\(position)/09/2026"
            )
        }
    }

    static func smartPriceProducts(for profile: Profile) -> [SmartPriceProduct] {
        (0..<5).map { position in
            let price = Double([199, 89, 349, 129, 59][position])
            return SmartPriceProduct(
                id: productID(profile: profile, position: position + 20),
                price: price,
                minPrice: (price * 0.8).rounded(),
                maxPrice: (price * 1.1).rounded(),
                blocked: false,
                smartPriceEnabled: false,
                statusText: position.isMultiple(of: 2) ? "preço bom" : "preço acima da média",
                statusColor: position.isMultiple(of: 2) ? "#1A7F37" : "#C93400",
                photoPublicID: nil
            )
        }
    }

    private static func productID(profile: Profile, position: Int) -> Int {
        profile.user.id * 1000 + position
    }

    private static func uuid(_ suffix: String) -> UUID {
        UUID(uuidString: "DE300000-0000-0000-0000-0000\(suffix)") ?? UUID()
    }
}
#endif
