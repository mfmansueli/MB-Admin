import Foundation

/// Pesos do **índice de correspondência** (`MatchIndex`) e os limites que separam versões do mesmo
/// produto — a parte da comparação que junta foto, título, descrição, preço inicial, marca e os
/// atributos de variante (aro/tamanho, banho, cor da pedra, medida). Os limites das fotos em si
/// continuam em `PhotoMatchingParameters`.
///
/// **O índice não é probabilidade.** É uma soma de pontos por evidência, de 0 a 100, com cada parcela
/// mostrada na revisão ("a mesma foto +55", "aro 16 × aro 18 −35"). Os pesos foram escolhidos à mão
/// pra ordem fazer sentido — mesma foto vale mais que qualquer texto; um atributo em conflito derruba
/// mais do que qualquer texto parecido sobe — e **ainda não foram calibrados com anúncios reais**
/// (ver `PhotoSamples/README.md`, casos `variant`). O estado de cada par não sai de um corte no
/// índice: sai das regras do `ComparisonResolver` (tipo de evidência, conflitos, concorrentes), e o
/// índice só entra pra desempatar versões que dividem a mesma foto.
nonisolated enum MatchIndexParameters {
    // MARK: - Fotos

    /// O mesmo `image_public_id` nas duas lojas.
    static let samePublicIDPoints = 60
    /// Todas as conferências de "mesma fotografia" (`PhotoMatchingParameters`).
    static let samePhotoPoints = 55
    /// Mesma pose, outra cor — provável outra versão.
    static let colorVariantPhotoPoints = 20
    /// Fotos parecidas, não a mesma.
    static let similarPhotoPoints = 25
    /// A melhor foto é a mesma, mas outra foto do par bate só na estrutura (outra cor).
    static let colorConflictPoints = -10
    /// Fotos dos dois lados todas analisadas e nenhuma em comum.
    static let noSharedPhotoPoints = -15

    // MARK: - Texto

    /// Até tanto pelo título **sem** as palavras de variante (aro, banho, cor, medidas, números):
    /// Jaccard × este valor. Assim "anel coração aro 16" e "anel coração aro 18" têm o mesmo título
    /// base, e a diferença aparece só no eixo do tamanho.
    static let baseTitleMaxPoints = 20
    /// Até tanto pela descrição sem as palavras de variante, quando as duas foram buscadas.
    static let descriptionMaxPoints = 10
    /// Descrição pelo menos tão parecida (Jaccard) confirma um par 1:1 com preço bem diferente.
    static let descriptionConfirmsThreshold = 0.8

    // MARK: - Atributos

    /// Por eixo em que os dois anúncios dizem o mesmo valor.
    static let attributeAgreementPoints = 5
    /// Teto da soma das concordâncias — "prata 925" em todo título não pode inflar o índice.
    static let attributeAgreementMaxPoints = 10
    /// Por eixo em conflito (aro 16 × aro 18, ouro × ródio): outra versão, nunca o mesmo produto.
    static let attributeConflictPoints = -35
    static let brandAgreementPoints = 5
    /// Marcas diferentes: o par vai pra revisão.
    static let brandConflictPoints = -25
    static let categoryConflictPoints = -15

    // MARK: - Preço inicial (sem desconto; o atual quando o original não vem)

    static let samePricePoints = 5
    static let differentPricePoints = -5
    /// Diferença até 1% (ou R$ 0,50) conta como o mesmo preço.
    static let samePriceTolerance = 0.01
    static let samePriceAbsoluteTolerance = 0.5
    /// Diferença até 15% é "parecido" (0 ponto); acima, "diferente".
    static let closePriceTolerance = 0.15
    /// Um par 1:1 com a mesma foto e um preço mais de 25% acima do outro vai pra revisão ("pode ser
    /// outra versão") — a não ser que algum atributo concorde ou a descrição seja quase igual.
    static let farPriceRatio = 1.25

    // MARK: - Faixas (só pra tela)

    static let highIndex = 75
    static let mediumIndex = 45

    // MARK: - Versões que dividem a mesma foto

    /// Entre anúncios que dividem a mesma foto, um par só vira correspondência forte se o índice
    /// dele passar o de **todo** concorrente (que divide um dos dois anúncios) por pelo menos isso, e
    /// nenhum concorrente tiver revisão manual. 10 = o preço inicial sozinho (igual × diferente)
    /// desempata; um atributo concordando contra um não informado (5) não.
    static let versionResolutionMargin = 10
    /// Capas iguais em mais anúncios que isso, numa loja só, não formam um grupo de versões — é foto
    /// genérica (banner, "foto ilustrativa").
    static let familyMaximumListings = 30
    /// Anúncios com a mesma foto só são versões um do outro (família, "outra versão") se o título
    /// base — sem tamanho, banho, cor e medida — tiver pelo menos essa fração de palavras em comum
    /// (Jaccard). A mesma foto num anúncio de outro produto (foto trocada ou reaproveitada) não é
    /// versão; o par fica pra revisar.
    static let familyMinimumTitleSimilarity = 0.5

    // MARK: - Aprendido das suas revisões

    /// Quantas revisões de cada resposta ("mesmo produto" **e** "diferentes") entre as duas lojas
    /// são precisas antes de o índice delas decidir outros pares sozinho (`ReviewLearning`). Com
    /// menos, ou só de uma resposta, não dá pra saber onde fica a fronteira — tudo continua em
    /// "precisa revisar".
    static let learnedVerdictMinimumDecisions = 3

    // MARK: - Texto padrão da loja

    /// Palavra que aparece na descrição de pelo menos essa fração dos anúncios (com descrição) de uma
    /// loja — ou das duas juntas — é texto padrão ("prata 925 legítima, envio em 24h, acompanha
    /// certificado"): igual em quase todo anúncio, não diz qual produto é, e sai da comparação de
    /// texto. Sem isso, duas lojas do mesmo dono, com o mesmo texto padrão, teriam toda descrição
    /// "quase igual" e todo título parecido viraria "texto quase idêntico".
    static let boilerplateMinimumShare = 0.5
    /// Com menos anúncios com descrição que isso, não dá pra dizer o que é texto padrão.
    static let boilerplateMinimumListings = 6
}
