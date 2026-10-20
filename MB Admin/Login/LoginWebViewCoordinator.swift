import Foundation
import WebKit

/// Avisa a tela de login cada vez que a WebView termina de carregar uma página, para o app conferir
/// se a sessão do Enjoei já foi criada.
final class LoginWebViewCoordinator: NSObject, WKNavigationDelegate {
    var onNavigationFinished: (URL?) -> Void

    init(onNavigationFinished: @escaping (URL?) -> Void) {
        self.onNavigationFinished = onNavigationFinished
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onNavigationFinished(webView.url)
    }
}
