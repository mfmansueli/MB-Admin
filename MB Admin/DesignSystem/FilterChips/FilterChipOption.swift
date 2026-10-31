import SwiftUI

/// Um filtro da fileira de cápsulas (`FilterChipBar`) — o valor que ele escolhe, o nome, quantos
/// produtos caem nele e, opcionalmente, a bolinha com a cor do status ("pedem desconto", "preço
/// atual"…).
struct FilterChipOption<Value: Hashable>: Identifiable {
    let value: Value
    let label: String
    let count: Int
    var dotColor: Color?

    var id: Value { value }
}
