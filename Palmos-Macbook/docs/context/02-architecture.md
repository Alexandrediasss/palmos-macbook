# Arquitetura Técnica: Palmos (Cérebro macOS)

## 1. Pipeline de Dados (O Fluxo em Tempo Real)
A arquitetura do Palmos no macOS é desenhada para operar como um funil de processamento de altíssima velocidade e baixa latência. O sistema não armazena áudio; ele reage a ele no momento exato da reprodução.

1. **Captura (Ingestão):** O app cria um *tap* invisível no sistema de áudio do Mac. Todo som que iria para os alto-falantes é copiado para um buffer de memória (`CMSampleBuffer`).
2. **Processamento Digital de Sinais (DSP) — v2:** O buffer é convertido para mono e analisado por uma FFT de 2048 amostras (hop 1024) em **3 bandas** (graves 20–250 Hz, médios 250 Hz–2 kHz, agudos 2–8 kHz), mais **nota dominante** (`pitch`) e **ataques** (`spike`, via spectral flux dos agudos). Detalhes e parâmetros finais em `05-dsp-v2.md`.
3. **Normalização Adaptativa (AGC):** No lugar do antigo `bassThreshold` fixo, cada banda é normalizada pelo seu próprio pico recente (com decaimento), mantendo apenas um piso de ruído pequeno. Assim músicas calmas também geram vibração relativa, e o silêncio não vibra.
4. **Transmissão (Egressão):** Um `HapticPayload` de `type: "frame"` é serializado (`JSONEncoder`) e enviado a **~30 Hz** (throttle de ~32 ms) via `MultipeerConnectivity` `.unreliable`, somente com `connectedPeers` não vazio. Entre envios, o Mac acumula o **máximo** de cada banda e o OU dos spikes.

## 2. Tecnologias e Frameworks Core
- **ScreenCaptureKit (SCK):** A API moderna e oficial da Apple para interceptar mídia. Substitui antigas extensões de kernel (como Soundflower) garantindo segurança, privacidade e zero impacto na performance do sistema operacional.
- **Accelerate (vDSP):** Framework de matemática vetorial nativo da Apple. Será utilizado para realizar a Transformada Rápida de Fourier (FFT), permitindo calcular as frequências de áudio utilizando aceleração de hardware, poupando a CPU do Mac.
- **MultipeerConnectivity:** Gerencia a descoberta do iPhone na rede local (`MCNearbyServiceBrowser`) e estabelece a sessão (`MCSession`). A transmissão dos comandos táteis será feita com o modo `.unreliable` (equivalente ao UDP), priorizando a velocidade extrema e entrega imediata, ignorando pacotes perdidos para evitar atrasos (lag).
- **SwiftUI (MenuBarExtra):** Responsável exclusivamente pela interface reativa na barra de menus, isolando a complexidade do motor de áudio.

## 3. Padrão Arquitetural e Concorrência
O projeto adotará o padrão **MV (Model-View) orientado a Serviços**, potencializado pelo Swift Concurrency (`async/await` e `Actors`):
- **Isolamento de Threads:** A captura de áudio (SCK) e a matemática (FFT) ocorrerão estritamente em *background threads* (via Actors), garantindo que o processamento pesado de áudio nunca cause engasgos (stutters) na interface visual ou no próprio Mac do usuário.
- **Estado Reativo:** Os serviços publicarão apenas mudanças cruciais de estado (ex: "Conectado", "Permissão Negada") para a Main Thread via `@Observable` ou `@Published`, atualizando a View instantaneamente.

## 4. Estrutura de Diretórios (real)
- `Palmos_MacbookApp.swift`: Ponto de entrada configurado como `MenuBarExtra`.
- `/Services`
  - `AudioCaptureManager.swift`: `ScreenCaptureKit` (áudio + stream de vídeo dummy 2×2 a 1 FPS para evitar o erro `stream output NOT found`), extração para mono, throttle de 30 Hz e envio.
  - `SpectralAnalyzer.swift`: DSP puro (`Accelerate/vDSP`): FFT, bandas, AGC, pitch e spike. Classe `nonisolated`, usada apenas na `audioQueue`.
  - `MacNetworkManager.swift`: `MCNearbyServiceBrowser`/`MCSession` (`serviceType: "palmos-haptic"`), envio `.unreliable`.
- `/Models`
  - `HapticPayload.swift`: contrato de rede v2 (idêntico ao do iPhone).
- `/Views`
  - `MenuRootView.swift`: status, 3 barras de banda, nota atual, indicador de spike, slider de intensidade, botões de teste.

## 5. Concorrência
O projeto usa `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (Swift 5). Por isso o analisador DSP é marcado `nonisolated`. O `AudioCaptureManager` publica telemetria para a UI via `DispatchQueue.main.async` a ~15 Hz.