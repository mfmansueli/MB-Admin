import Foundation

/// Um produto da aba "sem preço esperto" já com nome e link resolvidos, cruzando `SmartPriceProduct`
/// (que só tem id/preço — a API de listagem não devolve título nem link, ver
/// `~/Downloads/enjoeiprecoespertoapi.md`) com o `EnjoeiProduct` correspondente de
/// `MegaphoneRunner.items` (os produtos publicados), pelo `id`. `matched == nil` quando a aba
/// "publicados" ainda não carregou esse produto — acontece só na janela entre a tela abrir e as
/// duas buscas (publicados e preço esperto), que rodam em paralelo, terminarem: título genérico e
/// sem link pra compartilhar até lá, sem travar a listagem por causa disso.
nonisolated struct SmartPriceListItem: Identifiable, Equatable, Sendable {
    let product: SmartPriceProduct
    let matched: EnjoeiProduct?

    var id: Int { product.id }

    var title: String {
        matched?.title ?? "produto #\(product.id)"
    }

    var storePageURL: URL? {
        guard let path = matched?.path else { return nil }
        return EnjoeiAPI.productURL(path: path)
    }

    var photoURL: URL? {
        product.thumbnailURL ?? matched?.photoURL
    }

    var largePhotoURL: URL? {
        product.largePhotoURL ?? matched?.largePhotoURL
    }
}
