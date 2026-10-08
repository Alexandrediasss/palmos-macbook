# Handoff: Arquitetura iOS e Motor Háptico (V7)

Este documento centraliza todas as regras que o agente do iOS (iPhone) deve seguir para interpretar o `HapticPayload` enviado pelo Mac.

## 1. Contrato de Rede (HapticPayload)
O Payload recebido do Mac é a única fonte de verdade.

```swift
struct HapticPayload: Codable {
    let type: String       // "frame" (v2/v3/v4), "transient", "continuous"
    let intensity: Float   // O Mac envia em escala 0...1 (força bruta)
    let sharpness: Float   // (Ignorado para ondas contínuas no iOS, usado para legado)
    let bass: Float?       // Energia 20–250 Hz
    let mid: Float?        // Energia 250 Hz–2 kHz
    let treble: Float?     // Energia > 2 kHz
    let pitch: Float?      // Nota dominante dos médios (0 grave … 1 agudo)
    let spike: Bool?       // true se for um ataque súbito nos agudos
    let bassTransient: Bool? // true se o grave for um impacto
    let midTransient: Bool? // true se houver um ataque repentino nos médios (Efeito Martelo)
    let semanticClass: String? // ex: "Speech", "Explosion", "Music" via IA
}
```

## 2. Papel do iOS (Single Source of Truth de UX)
Na versão 7, o Mac atua apenas como um "Cérebro Matemático". Ele não controla volume e não sabe o modo em que o usuário está. **O iPhone é o ditador da interface de usuário.**
- O slider de **Intensidade Geral** na interface do iPhone deve multiplicar as variáveis recebidas (`intensity`, `bass`, `mid`, `treble`) antes que elas cheguem no `CHHapticAdvancedPatternPlayer`.
- O iPhone abriga as chaves lógicas de modos e filtros visuais (ex: mutar melodia, mutar textura).

## 3. Modos de Uso

### Modo Música / Padrão
Toca todas as camadas simultaneamente, mesclando sons contínuos e impactos.
- **Graves (Ritmo):** Uma onda contínua que responde ao `bass`. Se `bassTransient == true`, toca um evento `.hapticTransient` e reinicia o jogador contínuo.
- **Médios (Melodia):** Uma onda contínua que responde ao `mid`. 
  - **Expansão Absoluta de Textura:** O parâmetro `hapticSharpness` da onda contínua da Melodia (e do Efeito Martelo) deve mapear o `pitch` diretamente ou em curva severa, garantindo que vá de **`0.0` cravado** (grave macio) até **`1.0` cravado** (agudo seco). Sem rodinhas de apoio.
  - **Efeito Martelo:** Se `midTransient == true`, dispara instantaneamente um `.hapticTransient` de intensidade alta e sharpness mapeado pelo `pitch`. (O Mac já zera a onda contínua do seu lado aplicando o Silêncio Tático).
- **Agudos (Textura):** Dispara `CHHapticEvent` do tipo `.hapticTransient` se `spike == true` (sharpness alto, duração curta).

*(Nota: O Mac já intercepta e zera a fala humana `semanticClass == "Speech"`, deixando passar apenas os impactos.)*

### Modo Cinema (Ação Pura / Wall of Sound)
Cenas de filmes embolam a Taptic Engine por excesso de estímulo. O "Modo Cinema" (ligado via chave na interface do iOS) aplica uma lógica **Subtracionista**:
- O `HapticManager` do iOS deve **ignorar totalmente** a reprodução das ondas contínuas de fundo (`bass`, `mid`, `treble`).
- O motor só deve vibrar em silêncio mortal disparando apenas `.hapticTransient` se receber `bassTransient == true`, `midTransient == true` ou `spike == true`.
- Resultado: Explosões cristalinas sem o zumbido de trilha sonora embolada.

## 4. IA Semântica (Overrides)
O Mac envia o que está tocando no parâmetro `semanticClass`.
O iOS pode ter lógicas especiais (Overrides) dependendo desse valor.
Exemplo:
- `"Explosion"`: O iOS pode ignorar a intensidade enviada e tocar um arquivo estático `.ahap` de explosão para efeito máximo, ou apenas aumentar brutalmente o multiplicador de intensidade para causar um tranco memorável.
