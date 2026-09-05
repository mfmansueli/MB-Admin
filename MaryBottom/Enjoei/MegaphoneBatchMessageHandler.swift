import Foundation
import WebKit

/// Recebe o progresso do laço de megafone em lote rodando em JS (ver
/// `EnjoeiJavaScript.megaphoneBatch`) — cada produto processado chega aqui via `postMessage`,
/// enquanto o `callAsyncJavaScript` do lote inteiro ainda está em andamento (ver
/// `EnjoeiWebSession.runBatch(_:arguments:onProgress:)`).
@MainActor
final class MegaphoneBatchMessageHandler: NSObject, WKScriptMessageHandler {
    private let onProgress: (Int, MegaphoneWebResponse) -> Void

    init(onProgress: @escaping (Int, MegaphoneWebResponse) -> Void) {
        self.onProgress = onProgress
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard
            let dictionary = message.body as? [String: Any],
            let productID = (dictionary["productID"] as? NSNumber)?.intValue
        else { return }
        onProgress(productID, MegaphoneWebResponse(javaScriptResult: dictionary))
    }
}
