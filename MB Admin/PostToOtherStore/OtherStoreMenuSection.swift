import SwiftUI

/// A lista de lojas de "postar em outra loja", com o cabeçalho ("postar em" / "postar 3 em") — o
/// submenu do "..." de uma row e o menu da ação "postar em" da barra da seleção. Cada loja mostra o
/// nome e, embaixo, o "@nick" ou o risco de o produto já existir lá (ver `OtherStoreTarget.subtitle`).
struct OtherStoreMenuSection: View {
    let targets: [OtherStoreTarget]
    let productCount: Int
    let onSelect: (OtherStoreTarget) -> Void

    var body: some View {
        Section(PostToOtherStoreCopy.menuTitle(productCount: productCount)) {
            ForEach(targets) { target in
                Button {
                    onSelect(target)
                } label: {
                    // Dois `Text` no rótulo de um botão de menu viram título e subtítulo.
                    Text(target.name)
                    Text(target.subtitle(productCount: productCount))
                }
            }
        }
    }
}
