import Foundation

nonisolated extension URLSession {
    /// Sessão usada nas chamadas ao Enjoei: compartilha os cookies com a WebView de login e se
    /// apresenta como o Safari do iPhone, igual ao que a WebView faz.
    static let enjoeiShared: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) "
                + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            "Accept-Language": "pt-BR,pt;q=0.9"
        ]
        return URLSession(configuration: configuration)
    }()
}
