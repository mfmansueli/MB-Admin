import Foundation

/// Anúncio (índice na loja) → o grupo de repetidos **certo** dele (repetido sem dúvida, ou confirmado
/// por você). O `ComparisonResolver` usa pra um repetido de um anúncio que tem par na outra loja não
/// ficar em revisão com esse par nem virar "possivelmente ausente" — é o mesmo produto cadastrado de
/// novo. "Talvez repetidos" não entram.
nonisolated struct DuplicateGroupIndex: Sendable {
    private var groupOf: [Int: Int] = [:]

    init() {}

    init(_ groups: [StoreDuplicateGroup], side: ComparisonSide) {
        let indexByKey = Dictionary(side.listings.enumerated().map { ($1.key, $0) }, uniquingKeysWith: { first, _ in first })
        for (number, group) in groups.enumerated() where group.isCertain {
            for key in group.keys {
                if let index = indexByKey[key] { groupOf[index] = number }
            }
        }
    }

    /// Os pares já feitos (`here` deste lado × `other` da outra loja), pelo grupo de `here`.
    func paired(_ matches: [(here: Int, other: Int)]) -> Paired {
        Paired(groupOf: groupOf, pairs: Set(matches.compactMap { match in groupOf[match.here].map { Pair(group: $0, other: match.other) } }))
    }

    /// Os anúncios dados mais os repetidos (do mesmo grupo certo) de cada um.
    func expanding(_ listings: Set<Int>) -> Set<Int> {
        let groups = Set(listings.compactMap { groupOf[$0] })
        guard !groups.isEmpty else { return listings }
        return listings.union(groupOf.filter { groups.contains($0.value) }.keys)
    }

    nonisolated struct Paired: Sendable {
        fileprivate let groupOf: [Int: Int]
        fileprivate let pairs: Set<Pair>

        /// `here` é repetido de um anúncio que já tem par com `other`: A1 = B1 e B2 repetido de B1
        /// explicam A1 × B2.
        func explains(_ here: Int, with other: Int) -> Bool {
            guard let group = groupOf[here] else { return false }
            return pairs.contains(Pair(group: group, other: other))
        }
    }

    fileprivate nonisolated struct Pair: Hashable, Sendable {
        let group: Int
        let other: Int
    }
}
