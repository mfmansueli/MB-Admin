import Foundation
import Testing
@testable import MaryBottom

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

    @Test("clearSession delega para o sessionClearer da conta")
    func clearSessionDelegaParaOClearer() async {
        let clearer = FakeSessionClearer()
        let account = makeAccount(sessionClearer: clearer)

        await account.clearSession()

        #expect(clearer.clearCallCount == 1)
    }
}
