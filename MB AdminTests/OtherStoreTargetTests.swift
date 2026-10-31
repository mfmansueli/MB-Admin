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

    private func target(duplicates: Int, percent: Int?) -> OtherStoreTarget {
        OtherStoreTarget(
            accountID: EnjoeiAccountID(),
            name: "loja C",
            nickname: "lojac-77a1",
            possibleDuplicateCount: duplicates,
            highestSimilarityPercent: percent
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
        #expect(targets.allSatisfy { $0.possibleDuplicateCount == 0 && $0.highestSimilarityPercent == nil })
    }

    @Test("a última comparação diz quantos já podem existir lá e o par mais parecido")
    func avisoDeDuplicado() {
        let current = makeAccount(name: "antonia")
        let storeB = makeAccount(name: "loja B")
        let storeC = makeAccount(name: "loja C")
        let memory = ComparisonMatchMemory()
        memory.record(
            [
                ProductMatch(productA: EnjoeiFixtures.product(id: 1), productB: EnjoeiFixtures.product(id: 90), similarity: 0.82),
                ProductMatch(productA: EnjoeiFixtures.product(id: 2), productB: EnjoeiFixtures.product(id: 91), similarity: 0.6)
            ],
            accountA: current.id,
            accountB: storeC.id
        )

        let targets = OtherStoreTarget.candidates(
            for: [1, 2, 3],
            from: current.id,
            among: [current, storeB, storeC],
            matches: memory
        )

        #expect(targets.first { $0.name == "loja B" }?.possibleDuplicateCount == 0)
        let lojaC = targets.first { $0.name == "loja C" }
        #expect(lojaC?.possibleDuplicateCount == 2)
        #expect(lojaC?.highestSimilarityPercent == 82)
    }

    @Test("sem risco, a linha de baixo é o @nick")
    func subtituloSemRisco() {
        #expect(target(duplicates: 0, percent: nil).subtitle(productCount: 1) == "@lojac-77a1")
        #expect(target(duplicates: 0, percent: nil).subtitle(productCount: 3) == "@lojac-77a1")
    }

    @Test("com risco, um produto mostra o percentual e vários mostram quantos")
    func subtituloComRisco() {
        #expect(target(duplicates: 1, percent: 82).subtitle(productCount: 1) == "pode já ter esse produto · 82%")
        #expect(target(duplicates: 1, percent: 82).subtitle(productCount: 3) == "1 pode já existir lá")
        #expect(target(duplicates: 2, percent: 90).subtitle(productCount: 3) == "2 podem já existir lá")
    }
}
