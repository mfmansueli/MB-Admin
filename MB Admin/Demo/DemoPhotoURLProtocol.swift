#if DEBUG
import Foundation

/// Responde as URLs de foto do `DemoMode` (`…/demo-<vendedor>-<posição>-<foto>`) com imagens geradas
/// na hora (`DemoPhotoCatalog`) — as miniaturas da tela e a comparação por foto passam pela mesma
/// `URLSession.productPhotos` de sempre, sem rede. Só registrado com `-demo-mode`.
nonisolated final class DemoPhotoURLProtocol: URLProtocol, @unchecked Sendable {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-demo-mode")
    }

    override static func canInit(with request: URLRequest) -> Bool {
        request.url?.lastPathComponent.hasPrefix("demo-") == true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else { return }
        guard let data = DemoPhotoCatalog.photoData(publicID: url.lastPathComponent),
              let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "image/jpeg", "Content-Length": "\(data.count)"]
              ) else {
            let notFound = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)
            if let notFound { client?.urlProtocol(self, didReceive: notFound, cacheStoragePolicy: .notAllowed) }
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
#endif
