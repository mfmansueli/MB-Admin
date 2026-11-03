import Foundation
import WebKit

/// Ponte entre `AccountsStore` (abstrato, testável) e o WebKit de verdade por trás de uma conta.
/// `webView` fica `nil` nos testes, que não sobem WebKit nenhum.
struct AccountDependencies {
    let client: EnjoeiClientProtocol
    let sessionClearer: EnjoeiSessionClearing
    let webView: WKWebView?
    /// Ritmo entre um template e outro na comparação (`ProductDetailsLoader.delayBetweenProducts`);
    /// `nil` mantém o padrão. Só o modo de demonstração muda — lá não há Enjoei pra poupar.
    var detailsPacing: Duration?
}

typealias AccountDependenciesFactory = @MainActor (EnjoeiAccountID) -> AccountDependencies
