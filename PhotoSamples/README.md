# Amostras reais de fotos (calibração da comparação por foto)

Esta pasta guarda fotos **reais** de anúncios, rotuladas à mão, para medir e calibrar a comparação
de produtos entre lojas (`PhotoMatchingParameters` para as fotos, `MatchIndexParameters` para o
índice de correspondência e as versões). As imagens **ficam só nesta máquina**: tudo
aqui, menos este README, está no `.gitignore`. Nada é enviado para servidor nenhum; o teste só lê os
arquivos do disco.

## Estrutura

```
PhotoSamples/
  tuning/          ← use para AJUSTAR os limites
  evaluation/      ← use só no fim, para CONFERIR (não ajuste nada olhando este relatório)
    same/          ← o mesmo produto nas duas lojas
      <caso>/
        a/1.jpg, a/2.jpg, …   (fotos do anúncio na loja A, na ordem do anúncio)
        b/1.jpg, …            (fotos do anúncio na loja B)
        a/title.txt           (opcional: título do anúncio; sem ele a decisão fica só com as fotos —
                               em variant/, os dois lados ganham o mesmo título neutro)
        a/description.txt     (opcional: a descrição do anúncio)
        a/price.txt           (opcional: preço inicial, ex. 149,90; sem ele, R$ 100 dos dois lados)
        a/brand.txt           (opcional: a marca, como aparece no anúncio)
        a/size.txt            (opcional: o campo de tamanho do anúncio, ex. 16 ou Único)
        b/…                   (os mesmos arquivos opcionais, do anúncio da loja B)
    different/     ← produtos DIFERENTES que se parecem (variante de cor, foto parecida)
      <caso>/a/…, <caso>/b/…
    variant/       ← OUTRA VERSÃO do mesmo produto (outro aro, banho, cor da pedra, medida),
      <caso>/a/…, <caso>/b/…   muitas vezes com a mesma foto: ponha o texto que mostra a diferença
    missing/       ← produto que só existe na loja A
      <caso>/a/…
```

- `<caso>` é qualquer nome de pasta (ex.: `anel-solitario-rosa`).
- Formatos aceitos: `.jpg`, `.jpeg`, `.png`, `.heic`, `.webp`. Só as 5 primeiras (por nome de arquivo)
  entram, como no app.
- Para pegar as fotos de um anúncio: abra o anúncio no navegador e salve as imagens (as de 300×300
  servidas pelo Enjoei são as mesmas que o app baixa). Salvar a versão maior também serve.
- **Bons casos para `same`:** a mesma foto reenviada (recomprimida), com outra capa, em outra
  posição, recortada/com margem diferente, produto claro em fundo branco, foto de ambiente.
- **Bons casos para `different`:** a mesma peça em outra cor (prata × dourado, pedra rosa × azul),
  peças da mesma linha com fotos quase iguais, embalagem/tabela de medidas genérica, fotos
  diferentes com o mesmo título.
- **Bons casos para `variant`:** o mesmo anel em aro 16 numa loja e aro 18 na outra com a mesma foto
  (o aro só na descrição ou no campo de tamanho), banho de ródio × banho de ouro com o título igual,
  corrente de 45 cm × 60 cm, a mesma peça com preço inicial bem diferente. O certo é **nunca** sair
  par forte; o ideal é "outra versão" (o produto entra como possivelmente ausente, com a nota de que a
  outra loja tem outra versão).
- Divida mais ou menos 60% dos casos em `tuning` e 40% em `evaluation`, sorteando, para o mesmo tipo
  de caso aparecer nas duas.

## Como rodar

```sh
xcodebuild test -project "MB Admin.xcodeproj" -scheme "MB Admin" \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -only-testing:"MB AdminTests/PhotoSampleEvaluationTests" -parallel-testing-enabled NO
```

Cada divisão vira uma comparação só (A = todos os `a/`, B = todos os `b/`), como duas lojas de
verdade. O log mostra a tabela de confusão (esperado × o que saiu: forte, revisar, outra versão,
possivelmente ausente, não verificado), quantas revisões, o **índice de correspondência** de cada
caso com o próprio `b/` (separado por tipo, pra ver se o índice separa `same` de `variant` e
`different`), os **pares falsos** (par forte ligando produtos diferentes, versões diferentes, ou
ligando ao `b/` de outro caso) e os **presentes dados como ausentes** (o erro que faria postar um
anúncio duplicado).

- `tuning` nunca falha: é o relatório para ajustar `PhotoMatchingParameters` e
  `MatchIndexParameters`.
- `evaluation` falha se houver qualquer par falso.
- Sem amostras, os dois testes aparecem como pulados.

Se mudar algum parâmetro de **normalização** (a parte que entra na assinatura), suba
`PhotoMatchingParameters.signatureVersion`, para o cache do app recalcular as assinaturas.

## Repetidos na mesma loja

A busca por anúncios repetidos (`StorePairEvidenceBuilder` + `StoreDuplicateFinder`) usa as mesmas
assinaturas e o mesmo `PairAssessor`, mas com regras mais estreitas, porque peças da mesma linha
numa loja de joias têm fotos parecidas e títulos que só mudam no fim:

- só liga **a mesma fotografia** (ou o mesmo arquivo), nunca "foto parecida";
- a foto tem que ser a **capa** de pelo menos um dos dois (ambiente, embalagem e mão se repetem
  entre produtos diferentes);
- foto genérica da loja (`genericPhotoMinimumListingsPerStore`, `familyMaximumListings`) não liga;
- versão (aro, banho, cor, medida) nunca é repetido; preço bem diferente, outra cor numa outra
  foto, marca ou categoria diferente, ou template não buscado deixam em "talvez repetidos".

Essas regras foram conferidas só com as fotos sintéticas da demonstração e os testes
(`StoreDuplicateFinderTests`); este harness ainda não tem uma divisão para casos de dentro da
mesma loja.
