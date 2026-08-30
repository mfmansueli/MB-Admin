import Foundation

/// Identificador estável de "navegador" exigido pelo GraphQL de busca do Enjoei.
///
/// O site gera um por navegador e reaproveita; aqui geramos um por instalação e guardamos, para as
/// buscas do app parecerem sempre o mesmo cliente.
nonisolated enum BrowserIdentifier {
    static let defaultsKey = "enjoei.browser_id"

    static func current(defaults: UserDefaults = .standard) -> String {
        if let stored = defaults.string(forKey: defaultsKey), !stored.isEmpty { return stored }
        let generated = make()
        defaults.set(generated, forKey: defaultsKey)
        return generated
    }

    /// Mesmo formato do site: um UUID minúsculo seguido do instante de criação em milissegundos.
    static func make(now: Date = Date()) -> String {
        let milliseconds = Int(now.timeIntervalSince1970 * 1000)
        return "\(UUID().uuidString.lowercased())-\(milliseconds)"
    }
}
