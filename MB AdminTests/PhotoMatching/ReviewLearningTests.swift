import Foundation
import Testing
@testable import MB_Admin

@Suite("o que as suas revisões ensinam sobre o índice")
struct ReviewLearningTests {
    private func samples(same: [Int], different: [Int]) -> [ReviewLearning.Sample] {
        same.map { .init(score: $0, verdict: .sameProduct) } + different.map { .init(score: $0, verdict: .differentProducts) }
    }

    @Test("com as duas respostas, a fronteira fica entre o menor \"mesmo\" e o maior \"diferentes\"")
    func fronteira() {
        let learning = ReviewLearning.learn(from: samples(same: [80, 70, 65], different: [20, 30, 40]))
        #expect(learning.sameFloor == 65)
        #expect(learning.differentCeiling == 40)
        #expect(learning.verdict(forScore: 65) == .sameProduct)
        #expect(learning.verdict(forScore: 90) == .sameProduct)
        #expect(learning.verdict(forScore: 50) == nil)
        #expect(learning.verdict(forScore: 40) == .differentProducts)
    }

    @Test("só uma das respostas não ensina nada: não dá pra saber onde fica a outra")
    func precisaDasDuas() {
        #expect(ReviewLearning.learn(from: samples(same: [80, 70, 65, 60], different: [])) == .none)
        #expect(ReviewLearning.learn(from: samples(same: [], different: [10, 20, 30])) == .none)
    }

    @Test("menos de três exemplos de um lado: aquele lado continua em revisão")
    func minimoDeExemplos() {
        let learning = ReviewLearning.learn(from: samples(same: [80, 70], different: [20, 30, 40]))
        #expect(learning.sameFloor == nil)
        #expect(learning.differentCeiling == 40)
        #expect(learning.verdict(forScore: 90) == nil)
    }

    @Test("respostas misturadas: só conta o que fica acima de todo \"diferentes\" e abaixo de todo \"mesmo\"")
    func misturadas() {
        // Um "diferentes" no 60 empurra o "mesmo produto" pra cima dele; um "mesmo" no 35 puxa o
        // "diferentes" pra baixo dele.
        let learning = ReviewLearning.learn(from: samples(same: [90, 85, 75, 35], different: [10, 20, 30, 60]))
        #expect(learning.sameFloor == 75)
        #expect(learning.sameDecisions == 3)
        #expect(learning.differentCeiling == 30)
        #expect(learning.differentDecisions == 3)
        #expect(learning.verdict(forScore: 60) == nil)
    }

    @Test("\"mesmo produto\" só com foto, sem par, e um candidato por anúncio; \"diferentes\" vale pra todos")
    func quemMuda() {
        let learning = ReviewLearning.learn(from: samples(same: [80, 70, 65], different: [20, 30, 40]))
        let candidate = { (id: Int, indexA: Int, indexB: Int, score: Int, photo: Bool) in
            ReviewLearning.Candidate(id: id, indexA: indexA, indexB: indexB, score: score, isPhotoLink: photo)
        }
        let verdicts = learning.verdicts(
            for: [
                candidate(1, 0, 0, 90, true),  // único dos dois lados → mesmo produto
                candidate(2, 1, 1, 90, false), // só texto → continua em revisão
                candidate(3, 2, 2, 90, true),  // A2 já tem par → continua
                candidate(4, 3, 3, 90, true),  // A3 com dois candidatos acima → os dois continuam
                candidate(5, 3, 4, 85, true),
                candidate(6, 5, 5, 50, true),  // na faixa em dúvida → continua
                candidate(7, 6, 6, 10, false), // abaixo do limite → diferentes, mesmo só texto
                candidate(8, 2, 7, 15, true)   // e mesmo com um lado já com par
            ],
            matchedA: [2],
            matchedB: []
        )
        #expect(verdicts == [1: .sameProduct, 7: .differentProducts, 8: .differentProducts])
    }
}
