import Foundation

/// Todos os parâmetros da comparação por foto num lugar só — normalização da imagem, limites de
/// "mesma foto"/"foto parecida", busca de candidatos e resolução de conflitos. Os pesos do índice de
/// correspondência (foto + título + descrição + atributos de versão + marca + preço inicial) e a
/// separação de versões que dividem a mesma foto ficam em `MatchIndexParameters`.
///
/// **Nada aqui é probabilidade.** Distância de hash (bits diferentes, de 0 a 63), correlação das
/// miniaturas (−1 a 1) e diferença de cor (ΔE76 médio entre células, em unidades CIELAB) são medidas
/// geométricas; os limites dizem só "a partir daqui tratamos como a mesma fotografia". Eles foram
/// escolhidos de forma conservadora com transformações sintéticas (recompressão JPEG, redimensionamento,
/// variações de cor, objeto pequeno em muito fundo branco — ver `PhotoSignatureTests`) e **ainda não
/// foram calibrados com anúncios reais**: a calibração final depende das amostras rotuladas lidas por
/// `PhotoSampleEvaluationTests` (como montar: `PhotoSamples/README.md`). Mudou qualquer coisa que
/// altere a assinatura gerada? Suba `signatureVersion` — o cache inteiro é recalculado na próxima
/// comparação.
///
/// **Por que não Vision.** `VNGenerateImageFeaturePrintRequest` foi avaliado e ficou de fora:
/// - é um embedding **semântico** ("que tipo de objeto é este"), não de "a mesma fotografia" — dois
///   anéis diferentes em fundo branco, ou a mesma peça em prata e em dourado, ficam próximos, que é
///   exatamente a confusão que não pode virar par; e semelhança semântica nunca pode confirmar
///   sozinha, então ele só serviria pra gerar candidatos, coisa que o hash do recorte já faz pro
///   caso que importa (a foto reaproveitada);
/// - a distância não tem escala calibrada (não é probabilidade) e muda com a `revision` do modelo
///   entre versões do sistema — o cache de assinaturas teria que ser jogado fora a cada atualização,
///   e iPhone/iPad/Mac poderiam discordar;
/// - custa bem mais CPU/GPU por foto que decodificar uma miniatura de 256 px.
/// Se amostras reais mostrarem fotos do mesmo produto que o hash não pega (refotografado, não
/// reaproveitado), dá pra somar o feature print como **candidato** que sempre vai pra revisão.
nonisolated enum PhotoMatchingParameters {
    // MARK: - Versão e normalização (entram na assinatura)

    /// Versão do algoritmo **e** dos parâmetros de normalização abaixo. Assinatura salva com outra
    /// versão nunca é comparada com uma nova — é recalculada (ver `PhotoSignatureLoader`).
    static let signatureVersion = 1

    /// Maior lado da imagem decodificada (já com a orientação EXIF aplicada) antes de qualquer
    /// análise. As fotos baixadas são as de 300×300 do Enjoei; 256 px sobra pra achar a margem e
    /// gerar as miniaturas sem guardar a imagem em lugar nenhum.
    static let workingMaxSide = 256
    /// Abaixo disso a imagem não tem detalhe suficiente pra identificar uma fotografia.
    static let minimumDecodedSide = 32

    /// Faixa da borda usada pra estimar a cor do fundo, em fração do menor lado.
    static let borderBandFraction = 1.0 / 64
    /// Quanto um pixel da borda pode se afastar da cor de fundo (maior diferença entre canais, 0–255)
    /// e ainda contar como fundo.
    static let borderTolerance = 20
    /// Fração mínima da borda que precisa ser "fundo" pra considerar o fundo uniforme e recortar a
    /// margem. Abaixo disso a imagem é usada inteira, sem recorte nenhum.
    static let uniformBorderMinimumFraction = 0.75
    /// A partir de quanto um pixel deixa de ser fundo pra delimitar o produto. Baixo de propósito
    /// (ruído de JPEG em branco fica em ±3): proteger produtos claros vale mais que um recorte
    /// apertado — a margem extra só deixa a assinatura um pouco menos focada.
    static let contentTolerance = 14
    /// Uma linha/coluna só conta como produto com pelo menos tantos pixels diferentes do fundo —
    /// filtra pontinhos de ruído isolados.
    static let contentMinimumPixelsPerLine = 2
    /// Folga em volta do recorte, em fração do maior lado — outra proteção contra cortar a borda
    /// clara de um produto.
    static let contentPaddingFraction = 0.02
    /// Recorte menor que isso (em px, na imagem de trabalho) não identifica nada.
    static let minimumContentSide = 6
    /// Desvio-padrão de luminância (0–255) abaixo do qual a imagem é praticamente lisa (toda branca,
    /// toda de uma cor só) e não serve de evidência.
    static let minimumLumaStandardDeviation = 2.0

    /// O recorte é desenhado num quadrado desse tamanho (proporção preservada, sobra preenchida com a
    /// cor do fundo) e reduzido pra `contentLumaSide`/`colorGridSide`.
    static let contentRenderSide = 64
    static let contentLumaSide = 32
    /// O quadro inteiro (sem recorte), também com proporção preservada — só pra conferência.
    static let fullRenderSide = 32
    static let fullLumaSide = 16
    static let colorGridSide = 8

    // MARK: - Busca de candidatos

    /// Só pares de fotos com o hash do recorte até essa distância chegam a ser verificados em
    /// detalhe. Folgado em relação ao limite de "mesma foto" (cópias da mesma foto ficaram em ≤ 8 nos
    /// testes): o objetivo aqui é não deixar passar candidato nenhum. O hash do **quadro inteiro não
    /// gera candidato** de propósito — com objeto pequeno em muito branco ele sai praticamente igual
    /// pra produtos diferentes (distância 0 nos testes), e cada foto viraria candidata de todas.
    static let candidateContentHashRadius = 12

    // MARK: - Mesma fotografia (todas as condições juntas)

    static let samePhotoMaxContentHashDistance = 8
    /// Correlação mínima das miniaturas 32×32 do recorte, que depende de quantos pixels o recorte
    /// tem de verdade: recorte grande (≥ `largeContentSide` px no menor lado) exige
    /// `minContentCorrelationLarge`; pequeno (≤ `smallContentSide`), `minContentCorrelationSmall`;
    /// entre os dois, interpolado. Recorte pequeno é ampliado pra 32×32 e o ruído de JPEG pesa mais
    /// (nos testes, a mesma foto de um brinco de ~36 px recomprimida ficou em 0,93; brincos
    /// diferentes do mesmo tamanho, abaixo de 0,40). Em recorte grande, a mesma pose com outro produto
    /// chegou a 0,88 e a variante de pedra rosa a 0,94 — por isso 0,95 ali.
    static let samePhotoMinContentCorrelationLarge = 0.95
    static let samePhotoMinContentCorrelationSmall = 0.90
    static let samePhotoLargeContentSide = 128.0
    static let samePhotoSmallContentSide = 48.0
    /// Correlação das miniaturas do quadro inteiro — conferência independente do recorte (pega a
    /// mesma peça fotografada de novo e deslocada, que no recorte fica quase igual).
    static let samePhotoMinFullCorrelation = 0.92
    /// ΔE76 médio entre as 64 células de cor do recorte. Abaixo de ~2 é imperceptível.
    static let samePhotoMaxMeanColorDifference = 4.0
    /// Nenhuma célula pode passar disso — pega variante que só muda uma parte do produto (a pedra).
    /// Cópias da mesma foto ficaram em ≤ 3,2 nos testes; pedra rosa × cristal, 10; vermelha × azul
    /// com a mesma luminância, 19; dourado × prateado, 44.
    static let samePhotoMaxCellColorDifference = 8.0
    /// Quanto o recorte pode ter "andado" entre as duas cópias (fração da imagem). A mesma foto tem
    /// o mesmo enquadramento.
    static let samePhotoMaxFramingDifference = 0.04
    /// |ln(proporção A / proporção B)| do recorte.
    static let samePhotoMaxAspectDifference = 0.08

    static func samePhotoMinContentCorrelation(contentSide: Double) -> Double {
        if contentSide >= samePhotoLargeContentSide { return samePhotoMinContentCorrelationLarge }
        if contentSide <= samePhotoSmallContentSide { return samePhotoMinContentCorrelationSmall }
        let progress = (contentSide - samePhotoSmallContentSide) / (samePhotoLargeContentSide - samePhotoSmallContentSide)
        return samePhotoMinContentCorrelationSmall
            + progress * (samePhotoMinContentCorrelationLarge - samePhotoMinContentCorrelationSmall)
    }

    // MARK: - Foto parecida (vai pra revisão, nunca confirma sozinha)

    /// Correlação do recorte a partir da qual duas fotos que não são a mesma ficam "parecidas". Nos
    /// testes, a mesma peça refotografada (deslocada, girada 4,5°) ficou entre 0,86 e 0,99; produtos
    /// diferentes na mesma pose, entre 0,68 e 0,88 — há sobreposição, e o limite escolhe menos ruído
    /// na revisão, contando com a premissa de que a mesma foto é reaproveitada entre as lojas.
    static let similarMinContentCorrelation = 0.85
    /// Folgas largas pra uma foto ser sequer comparada em detalhe.
    static let similarMaxAspectDifference = 0.35
    static let similarMaxFramingDifference = 0.25

    // MARK: - Resolução entre anúncios

    /// Quantas fotos de cada anúncio entram na comparação, já ordenadas pela posição do template.
    static let comparisonPhotoCount = 5
    /// Uma foto (a mesma fotografia) presente em pelo menos tantos anúncios **de cada uma** das duas
    /// lojas é tratada como genérica (embalagem, tabela de medidas, banner) e ignorada como
    /// evidência — nem confirma par, nem conta como ausência. Abaixo disso, a mesma foto em vários
    /// anúncios vira revisão ("a mesma foto aparece em N anúncios"), nunca par automático.
    static let genericPhotoMinimumListingsPerStore = 4
    /// Outro candidato de foto parecida com correlação até essa distância da melhor vira
    /// "candidatos próximos" — revisão em vez de confirmação.
    static let competitorCorrelationMargin = 0.02
    /// Pares só pelo texto: a partir daqui (Jaccard de palavras) viram candidatos. O mesmo valor de
    /// sempre da comparação por título. Também separa a "foto só parecida" que vale revisão da que
    /// não vale: foto parecida com um anúncio que **já tem par forte** só fica pra revisar se o texto
    /// também for parecido a partir daqui (senão é só uma peça parecida do catálogo).
    static let textCandidateThreshold = 0.5
    /// Texto quase idêntico continua pedindo revisão mesmo quando as fotos dos dois lados foram
    /// todas analisadas e nenhuma bate; abaixo disso, foto completa sem nenhuma em comum descarta o
    /// candidato textual.
    static let textNearIdenticalThreshold = 0.8
    /// Teto de candidatos textuais por anúncio — título genérico ("brinco prata 925") casaria com
    /// metade da loja.
    static let maximumTextCandidatesPerListing = 3
    /// Listagem que veio com menos produtos que o `total` informado pela própria busca é tratada
    /// como incompleta.
    static let listingShortfallTolerance = 0
    /// Um anúncio sem par só vira "possivelmente ausente" se nenhum anúncio **não verificado** da
    /// outra loja (fotos que falharam) tiver título pelo menos tão parecido quanto isso (Jaccard) —
    /// senão ele pode ser exatamente o par que não deu pra analisar, e fica "não foi possível
    /// verificar".
    static let unverifiedBlockingTextThreshold = 0.3

    // MARK: - Cache e ritmo

    /// URL estável não prova conteúdo igual: uma assinatura salva é baixada e conferida de novo
    /// depois desse tempo. Se os bytes não mudaram, só a data de conferência anda.
    static let signatureMaxAge: TimeInterval = 60 * 86_400
    /// Espalha as reconferências (fração de `signatureMaxAge`, determinística por foto) pra um
    /// catálogo inteiro analisado no mesmo dia não vencer todo no mesmo dia.
    static let signatureRefreshJitter = 0.25
    /// Fotos/atributos de um anúncio (template) valem por esse tempo — e só enquanto a capa da
    /// listagem continuar a mesma de quando foram buscados.
    static let listingDetailsMaxAge: TimeInterval = 30 * 86_400
    /// Downloads de foto ao mesmo tempo (CDN de fotos, não a API do Enjoei).
    static let photoDownloadConcurrency = 4
    /// Tentativas por foto (download que falhou por rede); foto que não decodifica não é repetida.
    static let photoDownloadAttempts = 2
    static let photoRetryDelay: Duration = .milliseconds(400)
    /// Tentativas por template de anúncio, já respeitando `ProductDetailsLoader.delayBetweenProducts`.
    static let detailsFetchAttempts = 2
}
