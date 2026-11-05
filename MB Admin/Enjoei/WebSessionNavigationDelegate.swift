import Foundation
import WebKit

/// Delegate da WebView de bastidores: avisa quem estiver esperando o fim de um carregamento.
@MainActor
final class WebSessionNavigationDelegate: NSObject, WKNavigationDelegate {
    /// Prazo padrão de `waitForLoad` — depois disso a espera desiste sozinha (ver lá).
    nonisolated static let loadTimeout: Duration = .seconds(30)

    private var pendingLoad: CheckedContinuation<Void, Never>?
    /// Muda a cada espera nova, pro prazo de uma espera antiga não encerrar a seguinte.
    private var loadGeneration = 0
    /// O processo da página morreu (memória, normalmente) desde o último carregamento: a página na
    /// tela não existe mais, mesmo com `webView.url` ainda apontando pro Enjoei — quem for rodar um
    /// script precisa carregar de novo antes (ver `EnjoeiWebSession.run`).
    private(set) var contentProcessTerminated = false

    /// Espera o carregamento em andamento terminar — com sucesso, com falha, com o processo da
    /// página morrendo ou com `timeout` estourado, o que vier primeiro. Nunca espera pra sempre:
    /// quando o processo da página morre no meio de um carregamento, o WebKit só chama
    /// `webViewWebContentProcessDidTerminate` (nem `didFinish` nem `didFail`), e antes disso a
    /// espera ficava pendurada — o megafone da conta parava no meio da rodada sem erro nenhum.
    func waitForLoad(timeout: Duration = WebSessionNavigationDelegate.loadTimeout) async {
        loadGeneration += 1
        let generation = loadGeneration
        contentProcessTerminated = false
        await withCheckedContinuation { continuation in
            // Um carregamento novo cancela a espera do anterior — só o último interessa.
            pendingLoad?.resume()
            pendingLoad = continuation
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                guard let self, self.loadGeneration == generation else { return }
                self.finishPendingLoad()
            }
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

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        contentProcessTerminated = true
        finishPendingLoad()
    }

    private func finishPendingLoad() {
        pendingLoad?.resume()
        pendingLoad = nil
    }
}
