import SwiftUI

/// O alerta de apagar produto da loja de verdade (ver `PermanentDeleteCopy`), com a vibração de
/// alarme (`AlarmHaptic`) no instante em que ele aparece. Alerta no meio da tela, não a folha de
/// baixo de `confirmationDialog`: é a ação mais perigosa do app, tem que parar o usuário.
struct PermanentDeleteConfirmation: ViewModifier {
    @Binding var isPresented: Bool
    let productCount: Int
    /// Frase a mais no fim da mensagem — o ritmo da fila, quando são vários produtos.
    let note: String?
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content
            .alert(PermanentDeleteCopy.title(productCount: productCount), isPresented: $isPresented) {
                Button("cancelar", role: .cancel) {}
                Button(PermanentDeleteCopy.confirmButtonLabel, role: .destructive, action: onConfirm)
            } message: {
                Text([PermanentDeleteCopy.message(productCount: productCount), note].compactMap(\.self).joined(separator: " "))
            }
            .onChange(of: isPresented) { _, isShowing in
                if isShowing { AlarmHaptic.shared.play() }
            }
    }
}

extension View {
    /// Ver `PermanentDeleteConfirmation`.
    func permanentDeleteConfirmation(
        isPresented: Binding<Bool>,
        productCount: Int,
        note: String? = nil,
        onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(
            PermanentDeleteConfirmation(isPresented: isPresented, productCount: productCount, note: note, onConfirm: onConfirm)
        )
    }
}
