# Amostras reais de fotos (calibração da comparação por foto)

Esta pasta guarda fotos **reais** de anúncios, rotuladas à mão, para medir e calibrar a comparação
de produtos entre lojas (`PhotoMatchingParameters`). As imagens **ficam só nesta máquina**: tudo
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
        a/title.txt           (opcional: título do anúncio; sem ele a decisão fica só com as fotos)
        b/title.txt           (opcional)
    different/     ← produtos DIFERENTES que se parecem (variante de cor, outro tamanho, foto parecida)
      <caso>/a/…, <caso>/b/…
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
- Divida mais ou menos 60% dos casos em `tuning` e 40% em `evaluation`, sorteando, para o mesmo tipo
  de caso aparecer nas duas.

## Como rodar

```sh
xcodebuild test -project "MB Admin.xcodeproj" -scheme "MB Admin" \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -only-testing:"MB AdminTests/PhotoSampleEvaluationTests" -parallel-testing-enabled NO
```

Cada divisão vira uma comparação só (A = todos os `a/`, B = todos os `b/`), como duas lojas de
verdade. O log mostra a tabela de confusão (esperado × o que saiu: forte, revisar, possivelmente
ausente, não verificado), quantas revisões, os **pares falsos** (par forte ligando produtos
diferentes, ou ligando ao `b/` de outro caso) e os **presentes dados como ausentes** (o erro que
faria postar um anúncio duplicado).

- `tuning` nunca falha: é o relatório para ajustar `PhotoMatchingParameters`.
- `evaluation` falha se houver qualquer par falso.
- Sem amostras, os dois testes aparecem como pulados.

Se mudar algum parâmetro de **normalização** (a parte que entra na assinatura), suba
`PhotoMatchingParameters.signatureVersion`, para o cache do app recalcular as assinaturas.
