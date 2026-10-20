import SwiftUI

/// Um caso de ação em massa (repostar/inativar/apagar, repostar/ativar etc.) pro seletor genérico
/// `BulkActionSelector` — cada tela com seleção múltipla define seu próprio enum conforme esse
/// protocolo, só com as ações que fazem sentido ali.
protocol BulkActionOption: CaseIterable, Hashable {
    var label: String { get }
    var systemImage: String { get }
    var tint: Color { get }
}
