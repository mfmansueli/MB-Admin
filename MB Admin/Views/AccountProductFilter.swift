import Foundation

/// Filtro da lista de publicados, em `AccountPublishedTabView` — "todos os anúncios" ou só os que
/// o megafone está sugerindo desconto. `String` (não só `Equatable`): guardado por conta em
/// `@AppStorage`, em `AccountDetailView` — sem raw value compatível, a escolha não sobreviveria a
/// trocar de conta e voltar.
enum AccountProductFilter: String {
    case all
    case discountOnly
}
