import Foundation
import Testing
@testable import MaryBottom

@Suite("estado de login do app")
struct AppSessionTests {
    @Test("sem ninguém logado o app abre deslogado e sem alarme na tela")
    func abreDeslogado() async {
        let session = AppSession(
            client: StubEnjoeiClient(currentUserError: .notIdentified(detail: "current_user: 401")),
            sessionClearer: FakeSessionClearer()
        )

        await session.restoreSession()

        #expect(session.state == .loggedOut)
        // Ninguém logado é situação normal, não defeito.
        #expect(session.errorMessage == nil)
    }

    @Test("com sessão guardada na webview o app abre logado")
    func abreLogado() async {
        let client = StubEnjoeiClient(user: .stub)
        let session = AppSession(client: client, sessionClearer: FakeSessionClearer())

        await session.restoreSession()

        #expect(session.state == .loggedIn(.stub))
        // Na abertura a página de bastidores serve como está; recarregar é só depois do login.
        #expect(await client.reloadingPageCalls == [false])
    }

    @Test("erro inesperado do enjoei aparece na tela principal")
    func erroDoServidorViraMensagem() async {
        let session = AppSession(
            client: StubEnjoeiClient(currentUserError: .http(status: 500, message: "o enjoei caiu")),
            sessionClearer: FakeSessionClearer()
        )

        await session.restoreSession()

        #expect(session.state == .loggedOut)
        #expect(session.errorMessage == "o enjoei caiu")
    }

    @Test("login identificado fecha a tela de login")
    func loginPelaWebViewFechaOModal() async {
        let client = StubEnjoeiClient(user: .stub)
        let session = AppSession(client: client, sessionClearer: FakeSessionClearer())
        session.startLogin()

        let logou = await session.checkLoginFromWebView(triggeredByUser: true)

        #expect(logou)
        #expect(session.state == .loggedIn(.stub))
        #expect(session.isPresentingLogin == false)
        #expect(session.loginFeedback == nil)
        // Depois do login a página de bastidores precisa recarregar para enxergar a sessão nova.
        #expect(await client.reloadingPageCalls == [true])
    }

    @Test("conferência automática antes do login é silenciosa")
    func navegacaoSemLoginMantemAModal() async {
        let session = AppSession(
            client: StubEnjoeiClient(currentUserError: .notIdentified(detail: "")),
            sessionClearer: FakeSessionClearer()
        )
        session.startLogin()

        let logou = await session.checkLoginFromWebView()

        #expect(logou == false)
        #expect(session.isPresentingLogin)
        #expect(session.loginFeedback == nil)
    }

    @Test("apertar já entrei sem ter logado explica o que houve")
    func botaoJaEntreiSemLoginAvisa() async {
        let session = AppSession(
            client: StubEnjoeiClient(currentUserError: .notIdentified(detail: "")),
            sessionClearer: FakeSessionClearer()
        )
        session.startLogin()

        let logou = await session.checkLoginFromWebView(triggeredByUser: true)

        #expect(logou == false)
        #expect(session.isPresentingLogin)
        #expect(session.loginFeedback == AppSession.notLoggedInYetFeedback)
    }

    @Test("o diagnóstico da página entra no recado do login")
    func feedbackMostraDiagnostico() async {
        let session = AppSession(
            client: StubEnjoeiClient(currentUserError: .notIdentified(detail: "current_user: 401")),
            sessionClearer: FakeSessionClearer()
        )
        session.startLogin()

        _ = await session.checkLoginFromWebView(triggeredByUser: true)

        #expect(session.loginFeedback?.contains("current_user: 401") == true)
    }

    @Test("sair apaga a sessão da webview")
    func logoutLimpaSessao() async {
        let clearer = FakeSessionClearer()
        let session = AppSession(client: StubEnjoeiClient(user: .stub), sessionClearer: clearer)
        await session.restoreSession()

        await session.logout()

        #expect(session.state == .loggedOut)
        #expect(clearer.clearCallCount == 1)
    }
}
