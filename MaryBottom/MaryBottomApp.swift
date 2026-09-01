import SwiftUI

@main
struct MaryBottomApp: App {
    @State private var accountsStore = AccountsStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(accountsStore)
                // O app inteiro usa estilos de fonte do sistema (headline, caption etc.), então
                // isso escala todo o texto de uma vez, sem mexer view por view. `.xxxLarge` é o
                // maior tamanho antes das categorias de acessibilidade (que exigiriam revisar
                // layouts mais apertados, tipo o segmented picker e os badges de desconto).
                //
                // No Mac (idiom otimizado) esse modificador não tem efeito nenhum — testado com
                // `.xSmall`, `.accessibility1` e `.accessibility5` e o texto saiu bit-a-bit igual
                // nas três vezes. O Mac idiom do Catalyst simplesmente ignora Dynamic Type; não é
                // bug daqui, é limitação da plataforma quando "Optimize Interface for Mac" está
                // ligado.
                .dynamicTypeSize(.xxxLarge)
        }
    }
}
