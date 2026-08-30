import Foundation
import WebKit

/// Ponte entre `AccountsStore` (abstrato, testável) e o WebKit de verdade por trás de uma conta.
/// `webView` fica `nil` nos testes, que não sobem WebKit nenhum.
struct AccountDependencies {
    let client: EnjoeiClientProtocol
    let sessionClearer: EnjoeiSessionClearing
    let webView: WKWebView?
}

typealias AccountDependenciesFactory = @MainActor (EnjoeiAccountID) -> AccountDependencies
