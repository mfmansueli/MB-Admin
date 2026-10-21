import Foundation
import WebKit

/// A WebView de bastidores, onde rodam as chamadas que exigem sessão — uma instância por conta,
/// isolada por `WKWebsiteDataStore(forIdentifier:)` para várias contas ficarem logadas ao mesmo
/// tempo sem misturar cookies.
///
/// O Enjoei recusa os cookies replicados para fora do navegador (responde 401 e ainda derruba o
/// `remember_user_token`), então identificação e megafone acontecem de dentro de uma página dele.
/// Esta WebView e a do login da mesma conta usam o mesmo `identifier`, que persiste em disco —
/// então o login feito lá vale aqui, e sobrevive ao fechamento do app.
@MainActor
final class EnjoeiWebSession: EnjoeiSessionClearing {
    // Sem `WKProcessPool` compartilhado: desde o iOS 15 todas as WebViews do app já usam o mesmo
    // pool (a API foi deprecada — criar/atribuir um não tem mais efeito nenhum).

    let webView: WKWebView
    private let navigationDelegate = WebSessionNavigationDelegate()
    /// Quantas chamadas (`run`/`clearSession`) estão em andamento agora — a rede de segurança de
    /// `releaseMemoryIfIdle()`: nunca libera memória no meio de uma chamada real, não importa qual
    /// subsistema a disparou (todos passam por `run`/`runBatch`, que delega pra `run`).
    private var inFlightCallCount = 0

    init(dataStoreIdentifier: EnjoeiAccountID) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: dataStoreIdentifier)
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: configuration)
        webView.navigationDelegate = navigationDelegate
    }

    private var isOnEnjoeiPage: Bool {
        webView.url?.host()?.hasSuffix(EnjoeiAPI.cookieDomainSuffix) == true
    }

    func load(_ url: URL) async {
        webView.load(URLRequest(url: url))
        await navigationDelegate.waitForLoad()
    }

    /// Roda um script numa página do Enjoei.
    ///
    /// - Parameter reloadingPage: recarrega antes de rodar. Necessário depois do login: a página
    ///   aberta aqui é anterior à sessão nova e ainda se acha deslogada.
    func run(
        _ script: String,
        arguments: [String: Any] = [:],
        reloadingPage: Bool = false
    ) async throws -> Any? {
        inFlightCallCount += 1
        defer { inFlightCallCount -= 1 }
        if reloadingPage || !isOnEnjoeiPage {
            await load(EnjoeiAPI.webBaseURL)
        }
        do {
            return try await evaluate(script, arguments: arguments)
        } catch {
            // Em segundo plano o WebKit pode derrubar o processo da página; recarregar ressuscita.
            await load(EnjoeiAPI.webBaseURL)
            return try await evaluate(script, arguments: arguments)
        }
    }

    /// Roda um script de lote (ver `EnjoeiJavaScript.megaphoneBatch`) que reporta o progresso de
    /// cada item por um `WKScriptMessageHandler` enquanto o `callAsyncJavaScript` do lote inteiro
    /// ainda está em andamento. Registra o handler antes de rodar e desregistra depois — só um
    /// megafone roda por vez por conta (o `task` do `MegaphoneRunner` garante isso), então não tem
    /// risco de duas mensagens de lotes diferentes se cruzarem.
    func runBatch(
        _ script: String,
        arguments: [String: Any] = [:],
        onProgress: @escaping (Int, MegaphoneWebResponse) -> Void
    ) async throws -> Any? {
        let controller = webView.configuration.userContentController
        controller.add(MegaphoneBatchMessageHandler(onProgress: onProgress), name: EnjoeiJavaScript.megaphoneBatchHandlerName)
        defer { controller.removeScriptMessageHandler(forName: EnjoeiJavaScript.megaphoneBatchHandlerName) }
        return try await run(script, arguments: arguments)
    }

    private func evaluate(_ script: String, arguments: [String: Any]) async throws -> Any? {
        try await webView.callAsyncJavaScript(
            script,
            arguments: arguments,
            in: nil,
            contentWorld: .page
        )
    }

    /// Libera o heap JS/DOM que a página acumula numa sessão muito longa (centenas de chamadas,
    /// várias rodadas de megafone) navegando pra uma página em branco — bem mais leve que a real,
    /// sem recriar `WKWebView`/`WKWebsiteDataStore` (essa área já teve um crash real do WebKit, ver
    /// `AccountsStore.swift`). Os cookies/sessão continuam intocados, vivem no data store, não na
    /// página. `inFlightCallCount == 0` garante que isso nunca acontece no meio de uma chamada real;
    /// `run()` já detecta sozinho (`!isOnEnjoeiPage`) que precisa recarregar a página de verdade na
    /// próxima chamada, sem nenhum código adicional nesse caminho.
    func releaseMemoryIfIdle() async {
        guard inFlightCallCount == 0, isOnEnjoeiPage else { return }
        await load(URL(string: "about:blank")!)
    }

    /// Apaga cookies e dados do Enjoei — o logout de verdade.
    func clearSession() async {
        inFlightCallCount += 1
        defer { inFlightCallCount -= 1 }
        let dataStore = webView.configuration.websiteDataStore
        let cookies = await dataStore.httpCookieStore.allCookies()
        for cookie in cookies where cookie.domain.hasSuffix(EnjoeiAPI.cookieDomainSuffix) {
            await dataStore.httpCookieStore.deleteCookie(cookie)
        }
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await dataStore.dataRecords(ofTypes: types)
        await dataStore.removeData(
            ofTypes: types,
            for: records.filter { $0.displayName.contains("enjoei") }
        )
        await load(EnjoeiAPI.webBaseURL)
    }

    /// Monta as dependências de uma conta a partir do id dela — factory padrão do `AccountsStore`.
    static func makeDependencies(for accountID: EnjoeiAccountID) -> AccountDependencies {
        let session = EnjoeiWebSession(dataStoreIdentifier: accountID)
        return AccountDependencies(
            client: WebViewEnjoeiClient(webSession: session),
            sessionClearer: session,
            webView: session.webView
        )
    }
}
