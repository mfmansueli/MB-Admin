import SwiftUI
import WebKit

/// Mantém a WebView de bastidores de UMA conta viva dentro da hierarquia de views.
///
/// Sem estar na tela, o WebKit suspende a página e as chamadas do megafone param no meio. Com
/// várias contas, cada uma precisa da própria WKWebView montada ao mesmo tempo — é isso que garante
/// que o megafone de mais de uma conta continua rodando em paralelo mesmo fora da tela de detalhe.
struct AccountWebSessionHost: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
