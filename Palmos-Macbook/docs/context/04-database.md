# Modelagem de Dados e Rede: Palmos (Cérebro macOS)

## 1. Estratégia de Persistência (Armazenamento Local)
O aplicativo do Mac não armazenará histórico de mídia, logs de áudio ou dados relacionais complexos, tornando o uso de ferramentas como CoreData ou SwiftData desnecessário. O estado do sistema é baseado puramente em calibrações de hardware e fluxo de dados voláteis. Toda a persistência será gerenciada de forma leve via `@AppStorage` (UserDefaults).

## 2. Dicionário de Configurações (AppStorage)
As seguintes chaves serão salvas em disco para garantir que o usuário não precise recalibrar a experiência sempre que abrir o Mac:
- `autoConnectToLastDevice` (Bool): Define se o Mac deve tentar reconexão automática silenciosa com o último iPhone pareado ao iniciar (Padrão: `true`).
- `lastDevicePeerID` (String): Armazena o identificador de rede do último dispositivo utilizado.
- ~~`bassThreshold`~~ **(removido na v2):** o noise gate fixo foi substituído por normalização adaptativa (AGC) por banda, com piso de ruído constante no código (ver `05-dsp-v2.md`).
- `globalIntensity` (Double): Multiplicador de força master (Padrão: `1.0`). **Atenção:** multiplica com o slider de intensidade do iPhone (50% × 50% = 25%). Hoje é `@State` na `MenuRootView`.
- `hasSeenPermissions` (Bool): Flag que controla se o usuário já passou pelo onboarding e autorizou a captura de tela/áudio, evitando telas de bloqueio desnecessárias.

## 3. Contrato de Comunicação (O Payload de Rede)
O modelo de dados mais crítico do projeto não é salvo em disco, mas sim disparado pelo ar. Para garantir a latência próxima a zero requerida por uma resposta háptica, o pacote de dados enviado via `MultipeerConnectivity` (usando o envio `unreliable` tipo UDP) deve ser o menor possível, serializado via `Codable`.

```swift
struct HapticPayload: Codable {
    let type: String       // "frame" (v2/v3/v4) | "transient" | "continuous" (v1 legado)
    let intensity: Float   // 0...1; em frame = max(bass, mid, treble) COM ducking aplicado
    let sharpness: Float   // 0...1; em frame = 0.3 (ignorado pelo iPhone v2+)
    let bass: Float?       // 0...1  energia 20–250 Hz
    let mid: Float?        // 0...1  energia 250 Hz–2 kHz
    let treble: Float?     // 0...1  energia > 2 kHz
    let pitch: Float?      // 0...1  nota dominante dos médios (0 grave … 1 agudo)
    let spike: Bool?       // true no instante de um ataque súbito nos agudos
    let bassTransient: Bool? // true se o grave atual for um impacto (v3)
    let semanticClass: String? // "Explosion", "Speech" via IA (v4)
}
```


Exemplo de frame v2:
```json
{"type":"frame","intensity":0.62,"sharpness":0.3,"bass":0.62,"mid":0.41,"treble":0.18,"pitch":0.55,"spike":false}
```

**Regras de envio (críticas):** `.unreliable`, somente se `connectedPeers` não estiver vazio, ~30 Hz (≈32 ms). Nunca `.reliable` nem sem throttle (derruba a sessão: `Not in connected state`). Valores **lineares** 0–1: o Mac **não** aplica curva de compressão (o iPhone aplica `x^0.7`).

**Diferenças de contrato:** nenhuma. Os campos v2 são opcionais; `transient`/`continuous` continuam válidos (usados pelo botão "Testar Vibração").