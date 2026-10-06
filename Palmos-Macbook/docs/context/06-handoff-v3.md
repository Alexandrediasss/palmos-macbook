# Handoff v3: Alta Fidelidade (Mensagem para o iPhone)

> **Antigravity do iPhone, preste atenção:** O motor do Mac (Cérebro) foi atualizado para a versão 3 (v3), que busca alta fidelidade tátil. O payload de rede mudou e precisamos que você implemente duas novidades arquiteturais cruciais no app do iPhone: um **Jitter Buffer** e a separação entre **Bass Contínuo vs Transiente**.

## 1. O Novo Contrato de Rede (HapticPayload)
O `HapticPayload` recebeu um novo campo booleano opcional: `bassTransient`.

```swift
struct HapticPayload: Codable {
    let type: String       // "frame" (v2/v3) | "transient" | "continuous" (v1)
    let intensity: Float 
    let sharpness: Float 
    let bass: Float?       
    let mid: Float?        
    let treble: Float?     
    let pitch: Float?      
    let spike: Bool?       
    
    // NOVO NA V3:
    let bassTransient: Bool? // true se o grave atual for um impacto seco (ex: bumbo). false se for grave contínuo (ex: baixo, motor).
}
```

## 2. Jitter Buffer (Obrigatório)
A rede local tem *jitter* (atrasos inconstantes). Se você tocar a Taptic Engine assim que o pacote chega, o resultado é picotado e áspero.
Você deve implementar um pequeno buffer (atraso intencional) no iOS:
- Assim que o pacote chegar, guarde-o em uma fila (array).
- Atraso alvo: **50 a 60 milissegundos**.
- Uma Task separada (um loop `while !Task.isCancelled`) rodando a ~30 Hz vai ler os pacotes dessa fila e enviá-los para a Taptic Engine com um tempo de reprodução fluido e constante (`AHAP` paramétrico).
- Se a fila secar, zere a vibração. Se a fila acumular muito, descarte pacotes velhos (mantenha a latência sob controle).

## 3. Tratamento dos Graves (Continuous vs Transient)
No seu interpretador do CoreHaptics (`CHHapticAdvancedPatternPlayer` ou similar), mude a forma como os graves são tocados:
- **`bassTransient == true`:** Pare o motor contínuo e dispare um toque imediato forte e fechado (como um *Transient* event na API do CoreHaptics, focado na frequência grave e intensidade alta).
- **`bassTransient == false` ou `nil`:** Atualize os parâmetros dinâmicos (`CHHapticDynamicParameter`) de um padrão *Continuous* rodando em background (o "zumbido").

## O que você (Antigravity do iPhone) deve fazer:
1. Atualizar o arquivo `HapticPayload.swift` no seu projeto.
2. Criar uma classe ou Ator `JitterBuffer` para empilhar os pacotes de rede.
3. Atualizar o `HapticManager` para ler desse buffer e modificar a lógica de graves para respeitar o `bassTransient`.
4. Avisar o usuário quando terminar para fazermos o teste final.
