import Foundation

/// Filtro da lista de publicados, em `AccountPublishedTabView` — "todos os anúncios" ou só os que
/// o megafone está sugerindo desconto.
enum AccountProductFilter {
    case all
    case discountOnly
}
