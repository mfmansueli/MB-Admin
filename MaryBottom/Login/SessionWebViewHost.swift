import SwiftUI
import WebKit

/// Mantém a WebView de bastidores viva dentro da hierarquia de views.
///
/// Sem estar na tela, o WebKit suspende a página e as chamadas do megafone param no meio.
struct SessionWebViewHost: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        EnjoeiWebSession.shared.webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
