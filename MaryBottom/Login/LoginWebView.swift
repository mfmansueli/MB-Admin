import SwiftUI
import WebKit

/// WebView do login do Enjoei — instância própria da tela de login.
///
/// É separada da WebView de sessão de propósito: compartilhar uma única `WKWebView` entre duas
/// telas faz o UIKit derrubar o app quando ela troca de lugar no meio de um toque. As duas usam o
/// mesmo `WKWebsiteDataStore.default()`, então o login feito aqui vale para a outra também.
struct LoginWebView: UIViewRepresentable {
    let onNavigationFinished: (URL?) -> Void

    func makeCoordinator() -> LoginWebViewCoordinator {
        LoginWebViewCoordinator(onNavigationFinished: onNavigationFinished)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: EnjoeiAPI.loginURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onNavigationFinished = onNavigationFinished
    }
}
