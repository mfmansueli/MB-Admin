import SwiftUI

/// No Mac Catalyst, uma `.sheet` sem frame explícito é dimensionada pelo tamanho intrínseco do
/// conteúdo — pra uma tela de verdade (fila de ações, histórico, comparar contas), isso abre
/// pequeno e centralizado em vez de aproveitar a janela. Mede o tamanho de quem chama (a tela ou
/// sheet que está abrindo a próxima) e usa isso como base pra abrir a nova sheet como uma fração
/// generosa desse tamanho, com um mínimo decente pra janela pequena — mesma ideia já usada pela
/// sheet de "comparar contas" em `AccountsListView`, só que reaproveitável. No iPhone/iPad, `.sheet`
/// já se comporta bem sozinha, então o frame extra não entra.
struct MacCatalystSizedSheet<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder let sheetContent: () -> SheetContent

    @State private var containerSize: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { newSize in
                containerSize = newSize
            }
            .sheet(isPresented: $isPresented) {
                #if targetEnvironment(macCatalyst)
                sheetContent()
                    .frame(
                        minWidth: 900,
                        idealWidth: max(containerSize.width * 0.9, 900),
                        minHeight: 700,
                        idealHeight: max(containerSize.height * 0.9, 700)
                    )
                #else
                sheetContent()
                #endif
            }
    }
}

extension View {
    /// Ver `MacCatalystSizedSheet` — substituto de `.sheet(isPresented:content:)` pras telas
    /// grandes que precisam aproveitar o tamanho da janela no Mac Catalyst.
    func macCatalystSizedSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        modifier(MacCatalystSizedSheet(isPresented: isPresented, sheetContent: content))
    }
}
