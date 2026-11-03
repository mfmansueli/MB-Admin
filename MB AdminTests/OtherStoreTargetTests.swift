import Foundation
import Testing
@testable import MB_Admin

@Suite("lojas de destino de postar em outra loja")
struct OtherStoreTargetTests {
    private func makeAccount(name: String) -> AccountSession {
        AccountSession(
            id: EnjoeiAccountID(),
            user: EnjoeiUser(
                id: Int.random(in: 1...1_000_000),
                nickname: "\(name)-nick",
                name: name,
                avatarPublicID: nil,
                availableProductsCount: nil
            ),
            dependencies: AccountDependencies(client: StubEnjoeiClient(), sessionClearer: FakeSessionClearer(), webView: nil)
        )
    }

    private func target(existing: Int = 0, possible: Int = 0) -> OtherStoreTarget {
        OtherStoreTarget(
            accountID: EnjoeiAccountID(),
            name: "loja C",
            nickname: "lojac-77a1",
            existingCount: existing,
            possibleCount: possible
        )
    }

    @Test("só as outras lojas com sessão aberta, na ordem da lista de contas")
    func soOutrasLojasAtivasNaOrdem() {
        let current = makeAccount(name: "antonia")
        let storeC = makeAccount(name: "loja C")
        let expired = makeAccount(name: "loja A")
        expired.markSessionExpired()
        let unchecked = makeAccount(name: "loja D")
        unchecked.markCheckFailed()
        let storeB = makeAccount(name: "loja B")

        let targets = OtherStoreTarget.candidates(
            for: [1],
            from: current.id,
            among: [current, storeC, expired, unchecked, storeB],
            matches: ComparisonMatchMemory()
        )

        #expect(targets.map(\.name) == ["loja C", "loja B"])
        #expect(targets.allSatisfy { $0.possibleDuplicateCount == 0 })
    }

    @Test("a última comparação diz quantos já existem lá e quantos podem existir; ausente e não verificado não contam")
    func avisoDeDuplicado() {
        let current = makeAccount(name: "antonia")
        let storeB = makeAccount(name: "loja B")
        let storeC = makeAccount(name: "loja C")
        let memory = ComparisonMatchMemory()
        memory.record(
            ComparisonFixtures.result(
                matches: [ComparisonFixtures.match(1, 90)],
                reviews: [ComparisonFixtures.match(2, 91, status: .needsReview)],
                missingInB: [EnjoeiFixtures.product(id: 3)],
                unverifiedA: [UnverifiedListing(product: EnjoeiFixtures.product(id: 4), reasons: [.detailsUnavailable])]
            ),
            accountA: current.id,
            accountB: storeC.id
        )

        let targets = OtherStoreTarget.candidates(
            for: [1, 2, 3, 4],
            from: current.id,
            among: [current, storeB, storeC],
            matches: memory
        )

        #expect(targets.first { $0.name == "loja B" }?.possibleDuplicateCount == 0)
        let lojaC = targets.first { $0.name == "loja C" }
        #expect(lojaC?.existingCount == 1)
        #expect(lojaC?.possibleCount == 1)
        #expect(lojaC?.possibleDuplicateCount == 2)
    }

    @Test("sem risco, a linha de baixo é o @nick")
    func subtituloSemRisco() {
        #expect(target().subtitle(productCount: 1) == "@lojac-77a1")
        #expect(target().subtitle(productCount: 3) == "@lojac-77a1")
    }

    @Test("com risco, um produto diz se já tem ou se pode ter; vários dizem quantos de cada")
    func subtituloComRisco() {
        #expect(target(existing: 1).subtitle(productCount: 1) == "já tem esse produto")
        #expect(target(possible: 1).subtitle(productCount: 1) == "pode já ter esse produto")
        #expect(target(existing: 1).subtitle(productCount: 3) == "1 já existe lá")
        #expect(target(existing: 2, possible: 1).subtitle(productCount: 3) == "2 já existem lá · 1 pode existir lá")
        #expect(target(possible: 2).subtitle(productCount: 3) == "2 podem existir lá")
    }
}
