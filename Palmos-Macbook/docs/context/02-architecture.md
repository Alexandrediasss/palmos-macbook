# Arquitetura Técnica: Palmos (Cérebro macOS)

## 1. Pipeline de Dados (O Fluxo em Tempo Real)
A arquitetura do Palmos no macOS é desenhada para operar como um funil de processamento de altíssima velocidade e baixa latência. O sistema não armazena áudio; ele reage a ele no momento exato da reprodução.

1. **Captura (Ingestão):** O app cria um *tap* invisível no sistema de áudio do Mac. Todo som que iria para os alto-falantes é copiado para um buffer de memória (`CMSampleBuffer`).
2. **Processamento Digital de Sinais (DSP):** O buffer, que representa a onda sonora pura no tempo, é convertido para o domínio da frequência. Isso revela exatamente quanto de "grave" (bass) ou "agudo" (treble) existe naquele milissegundo.
3. **Mapeamento Lógico:** Algoritmos comparam as frequências com limiares (thresholds) definidos pelo usuário. Se um pico de grave forte é detectado, o sistema gera uma instrução de "vibração contínua de intensidade alta".
4. **Transmissão (Egressão):** A instrução é serializada em um pacote de dados minúsculo e disparada via rede local para o iPhone conectado.

## 2. Tecnologias e Frameworks Core
- **ScreenCaptureKit (SCK):** A API moderna e oficial da Apple para interceptar mídia. Substitui antigas extensões de kernel (como Soundflower) garantindo segurança, privacidade e zero impacto na performance do sistema operacional.
- **Accelerate (vDSP):** Framework de matemática vetorial nativo da Apple. Será utilizado para realizar a Transformada Rápida de Fourier (FFT), permitindo calcular as frequências de áudio utilizando aceleração de hardware, poupando a CPU do Mac.
- **MultipeerConnectivity:** Gerencia a descoberta do iPhone na rede local (`MCNearbyServiceBrowser`) e estabelece a sessão (`MCSession`). A transmissão dos comandos táteis será feita com o modo `.unreliable` (equivalente ao UDP), priorizando a velocidade extrema e entrega imediata, ignorando pacotes perdidos para evitar atrasos (lag).
- **SwiftUI (MenuBarExtra):** Responsável exclusivamente pela interface reativa na barra de menus, isolando a complexidade do motor de áudio.

## 3. Padrão Arquitetural e Concorrência
O projeto adotará o padrão **MV (Model-View) orientado a Serviços**, potencializado pelo Swift Concurrency (`async/await` e `Actors`):
- **Isolamento de Threads:** A captura de áudio (SCK) e a matemática (FFT) ocorrerão estritamente em *background threads* (via Actors), garantindo que o processamento pesado de áudio nunca cause engasgos (stutters) na interface visual ou no próprio Mac do usuário.
- **Estado Reativo:** Os serviços publicarão apenas mudanças cruciais de estado (ex: "Conectado", "Permissão Negada") para a Main Thread via `@Observable` ou `@Published`, atualizando a View instantaneamente.

## 4. Topologia de Diretórios
- `/App`
  - `PalmosMacApp.swift`: Ponto de entrada configurado como `MenuBarExtra`.
- `/Core` (Mecanismos internos)
  - `/Audio`: Classes que envolvem o `ScreenCaptureKit` e o delegate de buffer.
  - `/Processing`: Isolamento da lógica matemática do `Accelerate` (FFT e analisador de espectro).
  - `/Network`: O `MacNetworkManager` responsável por buscar o serviço `_palmos-haptic._tcp`.
- `/Models`
  - Estruturas de transporte (`HapticPayload`) e configurações de estado.
- `/Views`
  - Componentes nativos da interface suspensa do menu, telas de configuração e onboarding de permissões.