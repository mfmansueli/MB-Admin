import SwiftUI

/// Cor a partir de um hex `"#RRGGBB"` (ou sem o `#`) — usado pelo rótulo colorido que o Enjoei já
/// calcula pra cada produto na aba "sem preço esperto" (`SmartPriceProduct.statusColor`).
extension Color {
    init?(hex: String?) {
        guard var hex else { return nil }
        hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
