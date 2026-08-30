import Foundation
import WebKit

/// A WebView de bastidores, onde rodam as chamadas que exigem sessão.
///
/// O Enjoei recusa os cookies replicados para fora do navegador (responde 401 e ainda derruba o
/// `remember_user_token`), então identificação e megafone acontecem de dentro de uma página dele.
/// Esta WebView e a do login usam o mesmo `WKWebsiteDataStore.default()` — que persiste em disco —,
/// então o login feito lá vale aqui, e sobrevive ao fechamento do app.
@MainActor
final class EnjoeiWebSession: EnjoeiSessionClearing {
    static let shared = EnjoeiWebSession()

    let webView: WKWebView
    private let navigationDelegate = WebSessionNavigationDelegate()

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
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

    private func evaluate(_ script: String, arguments: [String: Any]) async throws -> Any? {
        try await webView.callAsyncJavaScript(
            script,
            arguments: arguments,
            in: nil,
            contentWorld: .page
        )
    }

    /// Apaga cookies e dados do Enjoei — o logout de verdade.
    func clearSession() async {
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
}
