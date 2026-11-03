import Foundation
import Testing
@testable import MB_Admin

/// A leitura dos atributos de variante (aro/tamanho, banho, cor da pedra, medida) do texto do
/// anúncio, e as regras de prioridade (template > título > descrição; "prata" é o banho mais fraco).
@Suite("atributos de variante lidos do anúncio")
struct ListingAttributesTests {
    private func attributes(
        _ title: String,
        description: String? = nil,
        size: String? = nil,
        brand: String? = nil,
        price: Double = 100
    ) -> ListingAttributes {
        let product = EnjoeiProduct(
            id: 1, title: title, path: "p", photoPublicID: "capa", currentPrice: price, originalPrice: price, description: description
        )
        let details = ProductListingDetails(
            productID: 1, coverPublicID: "capa", photoPublicIDs: ["capa"], categoryID: 327, size: size,
            brand: brand, description: description ?? "", fetchedAt: Date()
        )
        return ListingAttributes(product: product, details: details)
    }

    private func value(_ attributes: ListingAttributes, _ dimension: VariantDimension) -> String? {
        attributes.reading(dimension)?.decisiveValue?.display
    }

    // MARK: - Tamanho

    @Test("aro escrito de vários jeitos dá o mesmo tamanho", arguments: [
        "anel solitário aro 16", "anel solitário Aro: 16", "anel solitário aro16", "anel solitário tamanho 16",
        "anel solitário nº 16", "anel solitário n° 16", "anel solitário tam. 16"
    ])
    func aroDeVariosJeitos(title: String) {
        #expect(attributes(title).reading(.size)?.decisiveValue?.canonical == "16")
    }

    @Test("faixa de tamanhos ou dois aros não decide nada")
    func faixaDeTamanhos() {
        #expect(attributes("anel ajustável aro 14 ao 20").reading(.size)?.decisiveValue == nil)
        #expect(attributes("anel aro 16/18").reading(.size)?.decisiveValue == nil)
        #expect(attributes("vestido tamanho p e m").reading(.size)?.decisiveValue == nil)
    }

    @Test("tamanho de roupa por letra, só depois de 'tamanho'")
    func tamanhoPorLetra() {
        #expect(value(attributes("vestido midi tamanho M"), .size) == "tam. M")
        #expect(attributes("brinco m de prata").reading(.size) == nil)
    }

    @Test("número seguido de unidade não é tamanho; 'tamanho grande' também não")
    func numeroComUnidadeNaoETamanho() {
        #expect(attributes("corrente tamanho 45cm").reading(.size) == nil)
        #expect(attributes("anel tamanho grande").reading(.size) == nil)
    }

    @Test("o campo de tamanho do template vale mais que o título; 'único' não diz nada")
    func tamanhoDoTemplate() {
        #expect(attributes("anel aro 18", size: "16").reading(.size)?.decisiveValue?.canonical == "16")
        #expect(value(attributes("anel aro 18", size: "16"), .size) == "aro 16")
        #expect(value(attributes("anel", size: "Único"), .size) == nil)
        #expect(value(attributes("vestido", size: "G"), .size) == "tam. G")
    }

    // MARK: - Banho

    @Test("banho de ouro, ródio, rosé e ródio negro", arguments: [
        ("anel banhado a ouro 18k", "ouro"), ("anel folheado a ouro", "ouro"), ("anel dourado", "ouro"),
        ("anel banho de ródio", "rodio"), ("anel rodinado", "rodio"), ("anel ouro rosé", "ouro rose"),
        ("anel rose gold", "ouro rose"), ("anel ródio negro", "rodio negro"), ("anel prateado", "prateado"),
        ("anel prata 925", "prata")
    ])
    func banhos(title: String, canonical: String) {
        #expect(attributes(title).reading(.finish)?.decisiveValue?.canonical == canonical)
    }

    @Test("prata 925 com banho: vale o banho")
    func prataComBanho() {
        #expect(attributes("anel prata 925 banhado a ouro").reading(.finish)?.decisiveValue?.canonical == "ouro")
    }

    @Test("o 'prata 925' do título perde pra um banho dito na descrição — o título igual em todas as versões")
    func banhoNaDescricao() {
        let gold = attributes("anel coração prata 925", description: "anel coração. banho de ouro 18k.")
        #expect(gold.reading(.finish)?.decisiveValue?.canonical == "ouro")
        let plain = attributes("anel coração prata 925", description: "peça linda, acompanha caixinha.")
        #expect(plain.reading(.finish)?.decisiveValue?.canonical == "prata")
    }

    @Test("o banho dito no título vale mais que o da descrição")
    func banhoDoTituloPrimeiro() {
        let listing = attributes("anel ródio", description: "também temos em banho de ouro")
        #expect(listing.reading(.finish)?.decisiveValue?.canonical == "rodio")
    }

    @Test("ródio e prata são do mesmo tom: não conflitam; ouro e ródio, sim")
    func tonsDoBanho() {
        let rhodium = VariantValue(canonical: "rodio", display: "ródio")
        let silver = VariantValue(canonical: "prata", display: "prata")
        let gold = VariantValue(canonical: "ouro", display: "ouro")
        #expect(!VariantDimension.finish.conflicts(rhodium, silver))
        #expect(VariantDimension.finish.conflicts(rhodium, gold))
        #expect(AttributeRelation.between(.decisive(rhodium), .decisive(silver), dimension: .finish) == .compatible)
        #expect(AttributeRelation.between(.decisive(rhodium), .decisive(gold), dimension: .finish) == .conflicts)
        #expect(AttributeRelation.between(.decisive(rhodium), nil, dimension: .finish) == .unknown)
    }

    // MARK: - Cor e medida

    @Test("cor da pedra no título; 'rosa' de ouro rosa é banho, não cor")
    func corDaPedra() {
        #expect(value(attributes("anel solitário zircônia rosa"), .stoneColor) == "rosa")
        #expect(value(attributes("brinco zircônias brancas"), .stoneColor) == "branca")
        let roseGold = attributes("anel ouro rosa zircônia branca")
        #expect(roseGold.reading(.finish)?.decisiveValue?.canonical == "ouro rose")
        #expect(value(roseGold, .stoneColor) == "branca")
    }

    @Test("duas cores não decidem; na descrição, só cor perto de pedra conta")
    func corAmbiguaOuSemContexto() {
        #expect(attributes("brinco zircônia branca e rosa").reading(.stoneColor)?.decisiveValue == nil)
        #expect(attributes("anel", description: "acompanha caixinha azul").reading(.stoneColor) == nil)
        #expect(value(attributes("anel", description: "pedra verde natural"), .stoneColor) == "verde")
    }

    @Test("medidas em cm e mm, comparadas na mesma unidade")
    func medidas() {
        let chain = attributes("corrente veneziana 45cm")
        #expect(value(chain, .measure) == "45 cm")
        #expect(chain.reading(.measure)?.decisiveValue == attributes("corrente veneziana 450 mm").reading(.measure)?.decisiveValue)
        #expect(value(attributes("argola 2,5mm"), .measure) == "2,5 mm")
        #expect(attributes("pulseira", description: "pingente de 2cm").reading(.measure) == nil)
        #expect(value(attributes("colar", description: "corrente com 60 cm de comprimento"), .measure) == "60 cm")
    }

    // MARK: - Base, marca, preço

    @Test("o título base tira as palavras de versão: aro 16 e aro 18 têm o mesmo título base")
    func tituloBase() {
        let first = attributes("anel coração vazado aro 16 ródio")
        let second = attributes("anel coração vazado aro 18 banho de ouro")
        #expect(first.baseTitleWords == ["anel", "coracao", "vazado"])
        #expect(first.baseTitleWords == second.baseTitleWords)
    }

    @Test("título base parecido é o mesmo produto (talvez outra versão); sem nada em comum, outro produto")
    func mesmoTituloBase() {
        #expect(attributes("anel coração vazado aro 16 ródio").sharesBaseTitle(with: attributes("anel coração vazado aro 18 banho de ouro")))
        #expect(!attributes("anel coração vazado").sharesBaseTitle(with: attributes("brinco argola grande")))
        // Só palavras de versão de um lado: não dá pra dizer que não.
        #expect(attributes("aro 16").sharesBaseTitle(with: attributes("brinco argola grande")))
    }

    @Test("marca normalizada; 'sem marca' é marca nenhuma")
    func marca() {
        #expect(attributes("anel", brand: " Vivara ").brand == "vivara")
        #expect(attributes("anel", brand: "Vivara").brandDisplay == "Vivara")
        #expect(attributes("anel", brand: "sem marca").brand == nil)
    }

    @Test("o preço é o inicial (sem desconto)")
    func precoInicial() {
        let product = EnjoeiProduct(id: 1, title: "anel", path: "p", photoPublicID: nil, currentPrice: 80, originalPrice: 120)
        #expect(ListingAttributes(product: product, details: nil).price == 120)
        #expect(PriceRelation.between(100, 100.5) == .same)
        #expect(PriceRelation.between(100, 110) == .close)
        #expect(PriceRelation.between(100, 150) == .different)
        #expect(PriceRelation.areFarApart(100, 130))
        #expect(!PriceRelation.areFarApart(100, 120))
    }
}
