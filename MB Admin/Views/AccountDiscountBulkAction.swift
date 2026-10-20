import SwiftUI

/// Mesma ideia de `AccountBulkAction`, com uma opção a mais: no filtro "pede desconto" de
/// `AccountPublishedTabView`, cada produto selecionado já tem um preço sugerido pelo megafone,
/// então aplicar o desconto em massa faz sentido aqui (e só aqui — por isso um enum à parte, em
/// vez de crescer `AccountBulkAction`).
enum AccountDiscountBulkAction: BulkActionOption {
    case applyDiscount
    case repost
    case inactivate
    case delete

    var label: String {
        switch self {
        case .applyDiscount: "aplicar desconto"
        case .repost: "repostar"
        case .inactivate: "inativar"
        case .delete: "apagar"
        }
    }

    var systemImage: String {
        switch self {
        case .applyDiscount: "tag.fill"
        case .repost: "doc.on.doc.fill"
        case .inactivate: "archivebox.fill"
        case .delete: "trash.fill"
        }
    }

    var tint: Color {
        switch self {
        case .applyDiscount: .orange
        case .repost: .accentColor
        case .inactivate: .secondary
        case .delete: .red
        }
    }
}
