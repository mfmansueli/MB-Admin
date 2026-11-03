import Foundation

/// Union-find simples (com compressão de caminho) sobre índices `0..<count` — agrupa fotos/anúncios
/// ligados por "a mesma foto".
nonisolated struct DisjointSet: Sendable {
    private var parent: [Int]

    init(count: Int) {
        parent = Array(0..<count)
    }

    mutating func find(_ element: Int) -> Int {
        var root = element
        while parent[root] != root { root = parent[root] }
        var current = element
        while parent[current] != root {
            let next = parent[current]
            parent[current] = root
            current = next
        }
        return root
    }

    mutating func union(_ first: Int, _ second: Int) {
        let rootFirst = find(first)
        let rootSecond = find(second)
        if rootFirst != rootSecond { parent[rootSecond] = rootFirst }
    }

    /// Os grupos com pelo menos `minimumSize` elementos, cada um em ordem crescente, ordenados pelo
    /// primeiro elemento.
    mutating func groups(minimumSize: Int = 2) -> [[Int]] {
        var byRoot: [Int: [Int]] = [:]
        for element in parent.indices {
            byRoot[find(element), default: []].append(element)
        }
        return byRoot.values.filter { $0.count >= minimumSize }.sorted { $0[0] < $1[0] }
    }
}
