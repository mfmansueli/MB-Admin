import Foundation

/// Os textos da etiqueta da loja no topo do detalhe da conta ("loja Mary · 1.842 produtos") —
/// puros, pra `StoreBadge` só montar.
nonisolated enum StoreBadgeText {
    /// "loja Mary" — sem dobrar o "loja" quando o nome da conta já começa com ela ("loja B").
    static func storeName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstWord = trimmed.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
        let alreadyNamesTheStore = firstWord.compare(
            "loja",
            options: [.caseInsensitive, .diacriticInsensitive]
        ) == .orderedSame
        return alreadyNamesTheStore ? trimmed : "loja \(trimmed)"
    }

    /// Publicados mais inativos — a loja inteira, não só a aba à vista. `nil` enquanto nenhum dos
    /// dois chegou, pra não sugerir um "0" que ainda não é real; com só um deles, conta o que já se
    /// sabe (o outro chega logo em seguida, os dois carregam juntos ao abrir a conta).
    static func totalProducts(published: Int?, inactive: Int?) -> Int? {
        guard published != nil || inactive != nil else { return nil }
        return (published ?? 0) + (inactive ?? 0)
    }

    /// "1.842 produtos" / "1 produto".
    static func productCount(_ count: Int) -> String {
        count == 1 ? "1 produto" : "\(count.formatted()) produtos"
    }

    /// O VoiceOver lê a etiqueta inteira de uma vez, com de onde vem o total: "loja Mary, 1.842
    /// produtos: 1.502 publicados e 340 inativos".
    static func accessibilityLabel(name: String, published: Int?, inactive: Int?) -> String {
        let store = storeName(name)
        guard let total = totalProducts(published: published, inactive: inactive) else { return store }
        var parts: [String] = []
        if let published {
            parts.append(published == 1 ? "1 publicado" : "\(published.formatted()) publicados")
        }
        if let inactive {
            parts.append(inactive == 1 ? "1 inativo" : "\(inactive.formatted()) inativos")
        }
        return "\(store), \(productCount(total)): \(parts.joined(separator: " e "))"
    }
}
