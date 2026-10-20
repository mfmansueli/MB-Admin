import Foundation

/// Extrai da página HTML do Enjoei os dados que não existem em nenhuma API JSON.
nonisolated enum EnjoeiHTMLScraper {
    /// Token CSRF que o Rails renderiza em `<meta name="csrf-token" content="...">`.
    ///
    /// É o mesmo token que o site manda no header `X-CSRF-Token` ao megafonar. Para visitante o
    /// atributo vem vazio, e nesse caso tratamos como ausente.
    static func csrfToken(inHTML html: String) -> String? {
        guard let content = metaContent(name: "csrf-token", inHTML: html), !content.isEmpty else {
            return nil
        }
        return content
    }

    /// Apelido da loja a partir de uma URL do tipo `https://www.enjoei.com.br/@antonia-40d0aa`.
    ///
    /// Usado como plano B para descobrir quem está logado: `/minha-loja` redireciona para a loja
    /// do próprio usuário quando há sessão.
    static func storeNickname(inURL url: URL) -> String? {
        guard let segment = url.pathComponents.first(where: { $0.hasPrefix("@") }) else { return nil }
        let nickname = String(segment.dropFirst())
        guard !nickname.isEmpty, nickname != "minha-loja" else { return nil }
        return nickname
    }

    private static func metaContent(name: String, inHTML html: String) -> String? {
        let patterns = [
            "name=[\"']\(name)[\"'][^>]*content=[\"']([^\"']*)[\"']",
            "content=[\"']([^\"']*)[\"'][^>]*name=[\"']\(name)[\"']"
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                continue
            }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            guard let match = regex.firstMatch(in: html, range: range),
                  let contentRange = Range(match.range(at: 1), in: html) else { continue }
            return String(html[contentRange])
        }
        return nil
    }
}
