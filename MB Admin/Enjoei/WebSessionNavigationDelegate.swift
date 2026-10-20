import Foundation
import WebKit

/// Delegate da WebView de bastidores: avisa quem estiver esperando o fim de um carregamento.
@MainActor
final class WebSessionNavigationDelegate: NSObject, WKNavigationDelegate {
    private var pendingLoad: CheckedContinuation<Void, Never>?

    func waitForLoad() async {
        await withCheckedContinuation { continuation in
            // Um carregamento novo cancela a espera do anterior — só o último interessa.
            pendingLoad?.resume()
            pendingLoad = continuation
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishPendingLoad()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        finishPendingLoad()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        finishPendingLoad()
    }

    private func finishPendingLoad() {
        pendingLoad?.resume()
        pendingLoad = nil
    }
}
