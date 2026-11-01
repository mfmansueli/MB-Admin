import Foundation
import Testing
@testable import MB_Admin

@Suite("sessão de uma conta")
struct AccountSessionTests {
    private func makeAccount(
        user: EnjoeiUser = .stub,
        lastRoundSummary: MegaphoneRoundSummary? = nil,
        client: EnjoeiClientProtocol = StubEnjoeiClient(),
        sessionClearer: EnjoeiSessionClearing = FakeSessionClearer()
    ) -> AccountSession {
        AccountSession(
            id: EnjoeiAccountID(),
            user: user,
            lastRoundSummary: lastRoundSummary,
            dependencies: AccountDependencies(client: client, sessionClearer: sessionClearer, webView: nil)
        )
    }

    @Test("nasce ativa, com o usuário e o resumo passados no init")
    func nasceAtiva() {
        let summary = MegaphoneRoundSummary(succeeded: 3, failed: 1, finishedAt: .now)
        let account = makeAccount(lastRoundSummary: summary)

        #expect(account.status == .active)
        #expect(account.user == .stub)
        #expect(account.lastRoundSummary == summary)
        #expect(account.record == AccountRecord(id: account.id, user: .stub, lastRoundSummary: summary))
    }

    @Test("markSessionExpired marca a conta como sessão vencida")
    func marcaSessaoVencida() {
        let account = makeAccount()

        account.markSessionExpired()

        #expect(account.status == .sessionExpired)
    }

    @Test("markCheckFailed marca a conta como falha passageira, sem confundir com sessão vencida")
    func marcaCheckFailed() {
        let account = makeAccount()

        account.markCheckFailed()

        #expect(account.status == .checkFailed)
    }

    @Test("refreshUser atualiza o usuário e volta a conta para ativa, mesmo vindo de sessão vencida")
    func refreshUserVoltaAAtiva() {
        let account = makeAccount()
        account.markSessionExpired()
        let refreshedUser = EnjoeiUser(
            id: EnjoeiUser.stub.id,
            nickname: EnjoeiUser.stub.nickname,
            name: "nome atualizado",
            avatarPublicID: nil,
            availableProductsCount: 42
        )

        account.refreshUser(refreshedUser)

        #expect(account.status == .active)
        #expect(account.user == refreshedUser)
        #expect(account.record.user == refreshedUser)
    }

    @Test("applyRoundFinished guarda o resumo mais recente, sem mexer no status")
    func applyRoundFinishedGuardaResumo() {
        let account = makeAccount()
        account.markCheckFailed()
        let summary = MegaphoneRoundSummary(succeeded: 5, failed: 2, finishedAt: .now)

        account.applyRoundFinished(summary)

        #expect(account.lastRoundSummary == summary)
        #expect(account.status == .checkFailed)
    }

    @Test("recarregar busca publicados (com o que pede desconto), inativos e preço esperto, tudo junto")
    func recarregarBuscaTodasAsAbas() async {
        let client = StubEnjoeiClient(
            pages: [EnjoeiFixtures.page(ids: [1, 2], endCursor: nil)],
            exposuresByProductID: [
                1: MegaphoneExposure(
                    productID: 1, kind: .maximumAfterDiscount, priceToIncreaseExposure: 100, discountLabel: "- 20%"
                )
            ],
            inactivePagesByNumber: [
                1: InactiveProductsPage(
                    products: [
                        InactiveProduct(
                            id: 3, path: "produto-3", title: "produto 3", price: 80, photoPublicID: nil, inactiveSince: nil
                        )
                    ],
                    maxPage: 1
                )
            ],
            smartPricePagesByNumber: [
                1: SmartPriceProductsPage(
                    products: [
                        SmartPriceProduct(
                            id: 2, price: 100, minPrice: 70, maxPrice: 150, blocked: false, smartPriceEnabled: false,
                            statusText: nil, statusColor: nil, photoPublicID: nil
                        )
                    ],
                    currentPage: 1,
                    totalPages: 1
                )
            ]
        )
        let account = makeAccount(client: client)
        defer { PerAccountModelContainer.destroy(for: account.id) }

        account.reloadAllProducts()
        await waitForReloadToFinish(account)

        #expect(account.runner.items.map(\.id) == [1, 2])
        #expect(account.runner.items.filter(\.needsDiscountDecision).map(\.id) == [1])
        #expect(account.inactiveProductsLoader.items.map(\.id) == [3])
        #expect(account.smartPriceProductsLoader.items.map(\.id) == [2])
        #expect(await client.requestedInactivePages == [1])
        #expect(await client.requestedSmartPricePages.map(\.page) == [1])
    }

    @Test("recarregar guarda a hora do toque, no record também, e avisa quem persiste")
    func recarregarGuardaAHora() async {
        let account = makeAccount()
        defer { PerAccountModelContainer.destroy(for: account.id) }
        var notifications = 0
        account.onCatalogRefreshed = { notifications += 1 }
        let tappedAt = Date(timeIntervalSince1970: 1_793_000_000)

        #expect(account.lastCatalogRefresh == nil)

        account.reloadAllProducts(now: tappedAt)

        #expect(account.lastCatalogRefresh == tappedAt)
        #expect(account.record.lastCatalogRefresh == tappedAt)
        #expect(notifications == 1)
        await waitForReloadToFinish(account)
    }

    @Test("a hora do último recarregar volta do record salvo")
    func horaDoRecarregarVoltaDoRecord() {
        let tappedAt = Date(timeIntervalSince1970: 1_793_000_000)
        let account = AccountSession(
            id: EnjoeiAccountID(),
            user: .stub,
            lastCatalogRefresh: tappedAt,
            dependencies: AccountDependencies(client: StubEnjoeiClient(), sessionClearer: FakeSessionClearer(), webView: nil)
        )

        #expect(account.lastCatalogRefresh == tappedAt)
        #expect(account.record.lastCatalogRefresh == tappedAt)
    }

    @Test("record salvo antes de existir a hora do recarregar continua abrindo, sem hora")
    func recordAntigoSemHora() throws {
        let id = EnjoeiAccountID()
        let old = AccountRecord(id: id, user: .stub, lastRoundSummary: nil)
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        json.removeValue(forKey: "lastCatalogRefresh")
        let data = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(AccountRecord.self, from: data)

        #expect(decoded.id == id)
        #expect(decoded.lastCatalogRefresh == nil)
    }

    @Test("clearSession delega para o sessionClearer da conta")
    func clearSessionDelegaParaOClearer() async {
        let clearer = FakeSessionClearer()
        let account = makeAccount(sessionClearer: clearer)

        await account.clearSession()

        #expect(clearer.clearCallCount == 1)
    }

    /// Os carregamentos de inativos e preço esperto rodam numa `Task` solta, sem devolver algo pra
    /// esperar direto. Esperar também antes de apagar o arquivo da conta no fim do teste — senão
    /// um carregamento ainda em voo grava num arquivo recém-apagado.
    private func waitForReloadToFinish(_ account: AccountSession) async {
        await account.runner.waitUntilFinished()
        for _ in 0..<10_000 where
            account.inactiveProductsLoader.phase != .finished || account.smartPriceProductsLoader.phase != .finished {
            await Task.yield()
        }
    }
}
