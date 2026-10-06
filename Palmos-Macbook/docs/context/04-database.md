# Modelagem de Dados e Rede: Palmos (Cérebro macOS)

## 1. Estratégia de Persistência (Armazenamento Local)
O aplicativo do Mac não armazenará histórico de mídia, logs de áudio ou dados relacionais complexos, tornando o uso de ferramentas como CoreData ou SwiftData desnecessário. O estado do sistema é baseado puramente em calibrações de hardware e fluxo de dados voláteis. Toda a persistência será gerenciada de forma leve via `@AppStorage` (UserDefaults).

## 2. Dicionário de Configurações (AppStorage)
As seguintes chaves serão salvas em disco para garantir que o usuário não precise recalibrar a experiência sempre que abrir o Mac:
- `autoConnectToLastDevice` (Bool): Define se o Mac deve tentar reconexão automática silenciosa com o último iPhone pareado ao iniciar (Padrão: `true`).
- `lastDevicePeerID` (String): Armazena o identificador de rede do último dispositivo utilizado.
- `bassThreshold` (Double): O "filtro de ruído" (Noise Gate). Varia de 0.0 a 1.0. Frequências graves capturadas com força abaixo deste limiar são descartadas para evitar que o iPhone fique vibrando com ruídos de fundo (Padrão: `0.3`).
- `globalIntensity` (Double): Multiplicador de força master (Padrão: `1.0`).
- `hasSeenPermissions` (Bool): Flag que controla se o usuário já passou pelo onboarding e autorizou a captura de tela/áudio, evitando telas de bloqueio desnecessárias.

## 3. Contrato de Comunicação (O Payload de Rede)
O modelo de dados mais crítico do projeto não é salvo em disco, mas sim disparado pelo ar. Para garantir a latência próxima a zero requerida por uma resposta háptica, o pacote de dados enviado via `MultipeerConnectivity` (usando o envio `unreliable` tipo UDP) deve ser o menor possível, serializado via `Codable`.

```swift
struct HapticPayload: Codable {
    /// Define o padrão háptico: "transient" (impacto rápido, ex: estalo) ou "continuous" (prolongado, ex: motor).
    let type: String 
    /// A força da vibração (0.0 a 1.0).
    let intensity: Float 
    /// A "agudeza" física (0.0 a 1.0) - dita se o toque é seco (vidro) ou surdo (borracha).
    let sharpness: Float 
}