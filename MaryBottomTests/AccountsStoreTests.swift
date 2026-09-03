import Foundation
import Testing
@testable import MaryBottom

@Suite("contas do Enjoei")
struct AccountsStoreTests {
    private let otherUser = EnjoeiUser(
        id: 2,
        nickname: "outra-conta",
        name: "outra conta",
        avatarPublicID: nil,
        availableProductsCount: nil
    )

    private func makeStore(
        clientsByID: [EnjoeiAccountID: StubEnjoeiClient] = [:],
        clearersByID: [EnjoeiAccountID: FakeSessionClearer] = [:],
        persistence: InMemoryAccountsPersistence? = nil,
        megaphoneItemsPersistence: MegaphoneItemsPersisting? = nil,
        inactiveProductsPersistence: InactiveProductsPersisting? = nil
    ) -> AccountsStore {
        let persistence = persistence ?? InMemoryAccountsPersistence()
        return AccountsStore(
            dependenciesFactory: { id in
                AccountDependencies(
                    client: clientsByID[id] ?? StubEnjoeiClient(),
                    sessionClearer: clearersByID[id] ?? FakeSessionClearer(),
                    webView: nil
                )
            },
            persistence: persistence,
            megaphoneItemsPersistence: megaphoneItemsPersistence ?? InMemoryMegaphoneItemsPersistence(),
            inactiveProductsPersistence: inactiveProductsPersistence ?? InMemoryInactiveProductsPersistence()
        )
    }

    @Test("restaura todas as contas salvas, na ordem persistida")
    func restauraContasSalvas() async {
        let idA = EnjoeiAccountID()
        let idB = EnjoeiAccountID()
        let persistence = InMemoryAccountsPersistence(stored: [
            AccountRecord(id: idA, user: .stub, lastRoundSummary: nil),
            AccountRecord(id: idB, user: otherUser, lastRoundSummary: nil)
        ])
        let store = makeStore(
            clientsByID: [idA: StubEnjoeiClient(user: .stub), idB: StubEnjoeiClient(user: otherUser)],
            persistence: persistence
        )

        await store.restoreAccounts()

        #expect(store.accounts.map(\.id) == [idA, idB])
        #expect(store.accounts.map(\.user) == [.stub, otherUser])
        #expect(store.accounts.allSatisfy { $0.status == .active })
        #expect(store.isRestoring == false)
    }

    @Test("sessão vencida de uma conta não derruba as outras")
    func sessaoVencidaNaoDerrubaAsOutras() async {
        let idA = EnjoeiAccountID()
        let idB = EnjoeiAccountID()
        let persistence = InMemoryAccountsPersistence(stored: [
            AccountRecord(id: idA, user: .stub, lastRoundSummary: nil),
            AccountRecord(id: idB, user: otherUser, lastRoundSummary: nil)
        ])
        let store = makeStore(
            clientsByID: [
                idA: StubEnjoeiClient(currentUserError: .notAuthenticated),
                idB: StubEnjoeiClient(user: otherUser)
            ],
            persistence: persistence
        )

        await store.restoreAccounts()

        #expect(store.accounts.first { $0.id == idA }?.status == .sessionExpired)
        #expect(store.accounts.first { $0.id == idB }?.status == .active)
        #expect(store.accounts.count == 2)
    }

    @Test("restaura contas em paralelo, publicando na ordem persistida mesmo quando a mais lenta é a primeira")
    func restauraContasForaDeOrdemDeConclusao() async {
        let idA = EnjoeiAccountID()
        let idB = EnjoeiAccountID()
        let idC = EnjoeiAccountID()
        let persistence = InMemoryAccountsPersistence(stored: [
            AccountRecord(id: idA, user: .stub, lastRoundSummary: nil),
            AccountRecord(id: idB, user: otherUser, lastRoundSummary: nil),
            AccountRecord(id: idC, user: .stub, lastRoundSummary: nil)
        ])
        // A primeira conta persistida é de propósito a mais lenta a responder — sem a reordenação
        // por índice original em `restoreAccounts`, ela apareceria por último na lista publicada.
        let store = makeStore(
            clientsByID: [
                idA: StubEnjoeiClient(user: .stub, currentUserDelay: .milliseconds(60)),
                idB: StubEnjoeiClient(user: otherUser),
                idC: StubEnjoeiClient(user: .stub)
            ],
            persistence: persistence
        )

        await store.restoreAccounts()

        #expect(store.accounts.map(\.id) == [idA, idB, idC])
    }

    @Test("erro que não é sessão vencida vira checkFailed, sem tirar a conta da lista")
    func erroTransitorioViraCheckFailed() async {
        let id = EnjoeiAccountID()
        let persistence = InMemoryAccountsPersistence(
            stored: [AccountRecord(id: id, user: .stub, lastRoundSummary: nil)]
        )
        let store = makeStore(
            clientsByID: [id: StubEnjoeiClient(currentUserError: .http(status: 503, message: "fora do ar"))],
            persistence: persistence
        )

        await store.restoreAccounts()

        #expect(store.accounts.count == 1)
        #expect(store.accounts.first?.status == .checkFailed)
    }

    @Test("retryCheckingSession confere de novo só a conta pedida, sem mexer nas outras")
    func retryCheckingSessionConfereDeNovo() async {
        let id = EnjoeiAccountID()
        let otherID = EnjoeiAccountID()
        let persistence = InMemoryAccountsPersistence(stored: [
            AccountRecord(id: id, user: .stub, lastRoundSummary: nil),
            AccountRecord(id: otherID, user: otherUser, lastRoundSummary: nil)
        ])
        let client = StubEnjoeiClient(currentUserError: .http(status: 503, message: "fora do ar"))
        let store = makeStore(
            clientsByID: [id: client, otherID: StubEnjoeiClient(user: otherUser)],
            persistence: persistence
        )
        await store.restoreAccounts()
        #expect(store.accounts.first { $0.id == id }?.status == .checkFailed)

        await client.setCurrentUserError(nil)
        store.retryCheckingSession(for: id)
        await waitUntil { store.accounts.first { $0.id == id }?.status == .active }

        #expect(store.accounts.first { $0.id == id }?.status == .active)
        #expect(store.accounts.first { $0.id == otherID }?.status == .active)
    }

    @Test("retryCheckingSession que ainda falha com sessão vencida marca sessionExpired de verdade")
    func retryCheckingSessionComSessaoVencidaDeVerdade() async {
        let id = EnjoeiAccountID()
        let persistence = InMemoryAccountsPersistence(
            stored: [AccountRecord(id: id, user: .stub, lastRoundSummary: nil)]
        )
        let client = StubEnjoeiClient(currentUserError: .http(status: 503, message: "fora do ar"))
        let store = makeStore(clientsByID: [id: client], persistence: persistence)
        await store.restoreAccounts()
        #expect(store.accounts.first?.status == .checkFailed)

        await client.setCurrentUserError(.notAuthenticated)
        store.retryCheckingSession(for: id)
        await waitUntil { store.accounts.first?.status == .sessionExpired }

        #expect(store.accounts.first?.status == .sessionExpired)
    }

    @Test("login de conta nova, sem duplicata, entra na lista e persiste")
    func loginContaNovaEntraNaLista() async {
        let id = EnjoeiAccountID()
        let persistence = InMemoryAccountsPersistence()
        let store = makeStore(clientsByID: [id: StubEnjoeiClient(user: .stub)], persistence: persistence)

        let outcome = await store.checkLoginFromWebView(accountID: id)

        #expect(outcome == .loggedIn)
        #expect(store.accounts.map(\.id) == [id])
        #expect(persistence.saveCalls.last == [AccountRecord(id: id, user: .stub, lastRoundSummary: nil)])
        #expect(store.isPresentingLogin == false)
    }

    @Test("login de conta já logada em outro id do enjoei não duplica a lista")
    func loginDuplicataNaoDuplica() async {
        let existingID = EnjoeiAccountID()
        let newID = EnjoeiAccountID()
        let refreshedUser = EnjoeiUser(
            id: EnjoeiUser.stub.id,
            nickname: EnjoeiUser.stub.nickname,
            name: "nome atualizado",
            avatarPublicID: nil,
            availableProductsCount: 10
        )
        let persistence = InMemoryAccountsPersistence(
            stored: [AccountRecord(id: existingID, user: .stub, lastRoundSummary: nil)]
        )
        let newAccountClearer = FakeSessionClearer()
        let store = makeStore(
            clientsByID: [existingID: StubEnjoeiClient(user: .stub), newID: StubEnjoeiClient(user: refreshedUser)],
            clearersByID: [newID: newAccountClearer],
            persistence: persistence
        )
        await store.restoreAccounts()

        let outcome = await store.checkLoginFromWebView(accountID: newID)

        #expect(outcome == .loggedIn)
        #expect(store.accounts.map(\.id) == [existingID])
        #expect(store.accounts.first?.user.name == "nome atualizado")
        #expect(newAccountClearer.clearCallCount == 1)
    }

    @Test("recuperar conta já existente reusa o client dela, sem criar dependências novas")
    func recuperarSessaoReusaClientExistente() async {
        let id = EnjoeiAccountID()
        let persistence = InMemoryAccountsPersistence(
            stored: [AccountRecord(id: id, user: .stub, lastRoundSummary: nil)]
        )
        var factoryCallCount = 0
        let store = AccountsStore(
            dependenciesFactory: { _ in
                factoryCallCount += 1
                return AccountDependencies(
                    client: StubEnjoeiClient(user: .stub),
                    sessionClearer: FakeSessionClearer(),
                    webView: nil
                )
            },
            persistence: persistence
        )
        await store.restoreAccounts()
        #expect(factoryCallCount == 1)

        let outcome = await store.checkLoginFromWebView(accountID: id)

        #expect(outcome == .loggedIn)
        #expect(factoryCallCount == 1)
    }

    @Test("falha ao logar não mexe na lista de contas")
    func falhaAoLogarNaoMexeNaLista() async {
        let id = EnjoeiAccountID()
        let store = makeStore(clientsByID: [id: StubEnjoeiClient(currentUserError: .notIdentified(detail: ""))])

        let outcome = await store.checkLoginFromWebView(accountID: id)

        guard case .pending(let feedback) = outcome else {
            Issue.record("esperava .pending, veio \(outcome)")
            return
        }
        #expect(feedback == EnjoeiLoginFeedback.notLoggedInYetFeedback)
        #expect(store.accounts.isEmpty)
    }

    @Test("logout remove só a conta pedida e preserva as demais")
    func logoutRemoveSoAContaPedida() async {
        let idA = EnjoeiAccountID()
        let idB = EnjoeiAccountID()
        let persistence = InMemoryAccountsPersistence(stored: [
            AccountRecord(id: idA, user: .stub, lastRoundSummary: nil),
            AccountRecord(id: idB, user: otherUser, lastRoundSummary: nil)
        ])
        let clearerA = FakeSessionClearer()
        let clearerB = FakeSessionClearer()
        let store = makeStore(
            clientsByID: [idA: StubEnjoeiClient(user: .stub), idB: StubEnjoeiClient(user: otherUser)],
            clearersByID: [idA: clearerA, idB: clearerB],
            persistence: persistence
        )
        await store.restoreAccounts()

        await store.logout(accountID: idA)

        #expect(store.accounts.map(\.id) == [idB])
        #expect(clearerA.clearCallCount == 1)
        #expect(clearerB.clearCallCount == 0)
        #expect(persistence.stored.map(\.id) == [idB])
    }

    @Test("logout limpa produtos do megafone e inativos persistidos da conta")
    func logoutLimpaDadosLocaisDaConta() async {
        let idA = EnjoeiAccountID()
        let idB = EnjoeiAccountID()
        let megaphoneItemsPersistence = InMemoryMegaphoneItemsPersistence()
        let inactiveProductsPersistence = InMemoryInactiveProductsPersistence()
        let productA = EnjoeiProduct(
            id: 1, title: "produto a", path: "produto-a", photoPublicID: "foto-a",
            currentPrice: 100, originalPrice: 150
        )
        let productB = EnjoeiProduct(
            id: 2, title: "produto b", path: "produto-b", photoPublicID: "foto-b",
            currentPrice: 100, originalPrice: 150
        )
        megaphoneItemsPersistence.saveItems([MegaphoneItem(product: productA)], accountID: idA)
        megaphoneItemsPersistence.saveItems([MegaphoneItem(product: productB)], accountID: idB)
        let inactiveA = InactiveProduct(
            id: 1, path: "produto-a", title: "produto a", price: nil, photoPublicID: nil, inactiveSince: nil
        )
        let inactiveB = InactiveProduct(
            id: 2, path: "produto-b", title: "produto b", price: nil, photoPublicID: nil, inactiveSince: nil
        )
        inactiveProductsPersistence.saveItems([inactiveA], accountID: idA)
        inactiveProductsPersistence.saveItems([inactiveB], accountID: idB)
        UserDefaults.standard.set(3, forKey: "megaphone.rounds.\(idA)")
        UserDefaults.standard.set(1.5, forKey: "megaphone.speed.\(idA)")
        UserDefaults.standard.set("inativos", forKey: "accountDetail.selectedTab.\(idA)")
        UserDefaults.standard.set("discountOnly", forKey: "accountDetail.filter.\(idA)")
        let persistence = InMemoryAccountsPersistence(stored: [
            AccountRecord(id: idA, user: .stub, lastRoundSummary: nil),
            AccountRecord(id: idB, user: otherUser, lastRoundSummary: nil)
        ])
        let store = makeStore(
            clientsByID: [idA: StubEnjoeiClient(user: .stub), idB: StubEnjoeiClient(user: otherUser)],
            persistence: persistence,
            megaphoneItemsPersistence: megaphoneItemsPersistence,
            inactiveProductsPersistence: inactiveProductsPersistence
        )
        await store.restoreAccounts()

        await store.logout(accountID: idA)

        #expect(megaphoneItemsPersistence.loadItems(accountID: idA).isEmpty)
        #expect(megaphoneItemsPersistence.loadItems(accountID: idB).map(\.id) == [2])
        #expect(inactiveProductsPersistence.loadItems(accountID: idA).isEmpty)
        #expect(inactiveProductsPersistence.loadItems(accountID: idB).map(\.id) == [2])
        #expect(UserDefaults.standard.object(forKey: "megaphone.rounds.\(idA)") == nil)
        #expect(UserDefaults.standard.object(forKey: "megaphone.speed.\(idA)") == nil)
        #expect(UserDefaults.standard.object(forKey: "accountDetail.selectedTab.\(idA)") == nil)
        #expect(UserDefaults.standard.object(forKey: "accountDetail.filter.\(idA)") == nil)
    }

    @Test("fim de rodada do megafone preenche e persiste o resumo da conta")
    func fimDeRodadaPersisteResumo() async {
        let id = EnjoeiAccountID()
        let persistence = InMemoryAccountsPersistence()
        let client = StubEnjoeiClient(
            user: .stub,
            pages: [EnjoeiFixtures.page(ids: [1, 2], endCursor: nil)]
        )
        let store = makeStore(clientsByID: [id: client], persistence: persistence)
        await store.checkLoginFromWebView(accountID: id)
        let account = store.accounts.first!
        account.runner.delayBetweenProducts = .zero

        account.runner.start(sellerID: EnjoeiUser.stub.id)
        await account.runner.waitUntilFinished()

        #expect(account.lastRoundSummary?.succeeded == 2)
        #expect(account.lastRoundSummary?.failed == 0)
        #expect(persistence.stored.first?.lastRoundSummary?.succeeded == 2)
    }

    /// Espera uma condição sem prender o teste pra sempre se algo der errado — `retryCheckingSession`
    /// dispara a checagem numa `Task` solta, sem devolver algo pra esperar direto.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<10_000 where !condition() {
            await Task.yield()
        }
    }
}
