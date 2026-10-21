import Foundation
import Testing
@testable import MB_Admin

@Suite("seções da fila de ações")
struct PostQueueSectionsTests {
    private func item(_ productID: Int) -> PostQueueItem {
        PostQueueItem(
            id: UUID(),
            product: EnjoeiFixtures.product(id: productID),
            sourceAccountID: UUID(),
            sourceAccountName: "loja A",
            destinationAccountID: UUID(),
            destinationAccountName: "loja B"
        )
    }

    @Test("cada item entra numa seção só, pelo status, mantendo a ordem da fila")
    func separaPorStatus() {
        let items = [item(1), item(2), item(3), item(4), item(5)]
        let statuses: [Int: MegaphoneStatus] = [
            1: .succeeded,
            2: .megaphoning,
            3: .pending,
            4: .failed("o enjoei respondeu com erro 504."),
            5: .pending
        ]

        let sections = PostQueueSections(items: items) { statuses[$0.product.id] ?? .pending }

        #expect(sections.items(in: .now).map(\.product.id) == [2])
        #expect(sections.items(in: .waiting).map(\.product.id) == [3, 5])
        #expect(sections.items(in: .failed).map(\.product.id) == [4])
        #expect(sections.items(in: .done).map(\.product.id) == [1])
    }

    @Test("só as seções com alguma coisa aparecem, na ordem agora → na fila → com erro → feitos")
    func secoesVisiveis() {
        let items = [item(1), item(2)]
        let statuses: [Int: MegaphoneStatus] = [1: .succeeded, 2: .pending]

        let sections = PostQueueSections(items: items) { statuses[$0.product.id] ?? .pending }

        #expect(sections.visibleKinds == [.waiting, .done])
    }

    @Test("cabeçalhos com a contagem — \"agora\" sem, é sempre um item só")
    func cabecalhos() {
        #expect(PostQueueSections.Kind.now.header(count: 1) == "agora")
        #expect(PostQueueSections.Kind.waiting.header(count: 3) == "na fila · 3")
        #expect(PostQueueSections.Kind.failed.header(count: 1) == "com erro · 1")
        #expect(PostQueueSections.Kind.done.header(count: 2) == "feitos · 2")
    }
}
