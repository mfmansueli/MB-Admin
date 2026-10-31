import SwiftUI

/// "postar em outra loja" no menu "..." (e no menu de contexto) de uma row de publicados, logo
/// depois de "repostar produto": um submenu com as lojas quando há mais de uma, o item direto
/// ("postar em loja B") quando só uma serve, desabilitado com o motivo quando nenhuma serve, e
/// "postando em loja B…" enquanto a fila posta esse produto.
struct PostToOtherStoreMenuItem: View {
    let targets: [OtherStoreTarget]
    /// A postagem desse produto em outra loja, se houver — só importa se está em voo agora.
    let postState: OtherStorePostState?
    let onSelect: (OtherStoreTarget) -> Void

    var body: some View {
        if let postState, postState.isPosting {
            Button {} label: {
                Label(PostToOtherStoreCopy.postingLabel(storeName: postState.storeName), systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(true)
        } else if targets.isEmpty {
            Button {} label: {
                Text(PostToOtherStoreCopy.menuItemLabel)
                Text(PostToOtherStoreCopy.noCandidateReason)
                Image(systemName: PostToOtherStoreCopy.systemImage)
            }
            .disabled(true)
        } else if targets.count == 1, let target = targets.first {
            Button {
                onSelect(target)
            } label: {
                Text(PostToOtherStoreCopy.postLabel(storeName: target.name))
                // Só com o risco de duplicar — o "@nick" sozinho não acrescenta nada aqui.
                if target.possibleDuplicateCount > 0 {
                    Text(target.subtitle(productCount: 1))
                }
                Image(systemName: PostToOtherStoreCopy.systemImage)
            }
        } else {
            Menu {
                OtherStoreMenuSection(targets: targets, productCount: 1, onSelect: onSelect)
            } label: {
                Label(PostToOtherStoreCopy.menuItemLabel, systemImage: PostToOtherStoreCopy.systemImage)
            }
        }
    }
}
