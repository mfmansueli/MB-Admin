import Foundation

nonisolated extension URLSession {
    /// Sessão só pra buscar fotos de produto (`CachedAsyncImage`) — cache HTTP em disco próprio,
    /// dimensionado pro catálogo real do app (uma conta pode ter 1500+ produtos, várias contas
    /// logadas ao mesmo tempo), diferente do `URLCache.shared` padrão do sistema (pensado pra uso
    /// genérico, cota pequena demais pra isso). Sem esse cache, todo boot frio do app — ou qualquer
    /// limpeza do `ImageMemoryCache` sob pressão real de memória, ver `SystemMemoryPressureObserver`
    /// — fazia cada foto já vista ser baixada de novo da rede.
    static let productPhotos: URLSession = {
        let cache = URLCache(memoryCapacity: 20 * 1024 * 1024, diskCapacity: 300 * 1024 * 1024, directory: nil)
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = cache
        return URLSession(configuration: configuration)
    }()
}
