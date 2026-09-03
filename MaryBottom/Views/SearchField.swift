import SwiftUI

/// Campo de busca com lupa, texto e botão de limpar — mesmo visual reaproveitado por "publicados"
/// (`AccountDetailView`), "inativos" (`InactiveProductsListView`), "comparar produtos"
/// (`AccountComparisonView`) e "histórico" (`PostHistoryView`).
struct SearchField: View {
    let placeholder: String
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.quaternary, in: .rect(cornerRadius: 10))
        .contentShape(.rect)
        .onTapGesture { isFocused = true }
    }
}
