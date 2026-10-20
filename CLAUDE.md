# MB Admin

Projeto novo. Convenções gerais de workflow (um tipo por arquivo, sempre escrever testes) já vêm do
`~/.claude/CLAUDE.md` global e valem aqui também — não repetidas neste arquivo.

Abaixo, técnicas específicas trazidas do RainbowMatch (outro app iOS) que valem a pena reaproveitar
*quando/se* a necessidade surgir aqui. Ainda não implementadas neste projeto.

## Localização (String Catalog) — se o app for multi-idioma

- Um único String Catalog (`.xcstrings`) com `sourceLanguage: "en"`; adicionar os idiomas alvo em
  `knownRegions` no `project.pbxproj`.
- A extração automática do SwiftUI (`SWIFT_EMIT_LOC_STRINGS`, `LOCALIZATION_PREFERS_STRING_CATALOGS`)
  só funciona para literais passados **diretamente** a uma API tipada como `LocalizedStringKey`
  (`Text("...")`, `Button("...")`, `.navigationTitle("...")` etc.) — só quando o literal é argumento
  direto, não uma variável.
- Qualquer string que passe por uma `String` computada (label de enum, `String(format:)`, título
  montado em switch) **não** é extraída automaticamente — precisa envolver com
  `String(localized: "...")` no próprio código Swift.
- Strings interpoladas: o `LocalizedStringKey` normaliza `\(algumaString)` → `%@` e `\(algumInt)` →
  `%lld` como chave real no catálogo — não o texto bruto com nome de variável.
- A extração automática do Xcode ("Extract from Code") só funciona pelo editor gráfico — não roda
  via `xcodebuild build` puro na linha de comando.

## Proteção contra screenshot (estilo Grindr) — se houver conteúdo sensível a proteger

Técnica confirmada funcionando em iPhone real (iOS 26.6) usando o mecanismo de exclusão de captura
do `UITextField(isSecureTextEntry: true)`:

```swift
// dentro de UIViewRepresentable.makeUIView, ANTES de o campo entrar em qualquer window
let secureTextField = UITextField()
secureTextField.isSecureTextEntry = true
secureTextField.isUserInteractionEnabled = false
guard let secureView = secureTextField.subviews.first else { /* fallback */ }
secureView.removeFromSuperview()
secureView.subviews.forEach { $0.removeFromSuperview() }
// adicionar o conteúdo real (image view / hosting controller view) como subview de `secureView`,
// fixado via Auto Layout
return secureView // secureView vira a root view do UIViewRepresentable
```

- Crítico: checar `subviews.first` **imediatamente** no `makeUIView`, antes do campo entrar em
  qualquer hierarquia de window. Se checar depois (campo já numa window ativa), o iOS insere um
  `_UITouchPassthroughView` vazio no índice 0, empurrando o canvas real (`_UITextLayoutCanvasView`)
  pro índice 1 — pegar o índice 0 nesse contexto pega a view errada, sem proteção nenhuma.
- **Nunca validar essa feature específica no Simulator** — ele não emula esse comportamento do OS e
  vai sempre mostrar o conteúdo sem proteção no screenshot, mesmo quando a técnica está correta.
  Validar só em dispositivo real.

## Deixado de fora por enquanto

Padrões de arquitetura Firebase (albums, chat, contadores premium, etc.) do RainbowMatch não estão
aqui porque este projeto ainda não usa Firebase. Se/quando o MB Admin adotar Firebase, vale trazer
os padrões relevantes daquele projeto (ex.: snapshot de dados compartilhados em vez de referência
viva, checagem de premium via listener no próprio documento do usuário em vez de estado local
otimista) na hora, olhando o app real primeiro.
