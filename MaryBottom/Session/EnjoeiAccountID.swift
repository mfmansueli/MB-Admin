import Foundation

/// Id local de uma conta logada — é também o `identifier` do `WKWebsiteDataStore` isolado dela,
/// então não existe mapeamento entre "id local" e "id do data store": é o mesmo UUID.
typealias EnjoeiAccountID = UUID
