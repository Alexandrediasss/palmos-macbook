# Palmos (macOS Cérebro) 🧠

## 🛑 O Problema
O consumo de mídia moderna (filmes, jogos, música) é uma experiência profundamente audiovisual. Para pessoas surdas ou com deficiência auditiva, uma camada inteira de emoção e imersão (como o peso de uma explosão, a tensão de uma trilha sonora ou os passos em um jogo) é infelizmente perdida.

## 💡 A Solução
O **Palmos** é a ponte sensorial para essa lacuna. Ele transforma som em tato. Utilizando o ecossistema Apple, o Palmos converte o iPhone do usuário em um "subwoofer tátil" de alta fidelidade, traduzindo o áudio do Mac em respostas físicas ricas, dinâmicas e em tempo real, sem a necessidade de comprar hardwares caros e dedicados. Basta o Mac que está rodando a mídia e o iPhone que ele já tem no bolso.

## ⚙️ Sobre o Programa
O aplicativo para macOS atua como o **Cérebro** da operação. Ele roda discretamente como um Utilitário de Barra de Menus (Menu Bar App) e opera em etapas de altíssima performance:
1. **Ouvir:** Captura todo o áudio do sistema do Mac em tempo real, sem delay.
2. **Entender (DSP + IA):** Analisa as frequências do áudio, separando o som em Graves, Médios e Agudos, detectando a Nota Dominante (Pitch) e extraindo Impactos Secos (Transients). Em paralelo, uma Inteligência Artificial tenta classificar os sons (Ex: fala humana, explosões, música).
3. **Refinar (Ducking & Expansão):** Aplica regras matemáticas avançadas (Noise Gate Rigoroso e Expansão Exponencial) para ignorar ruídos inúteis e silêncios, priorizando os verdadeiros impactos. Se a IA detectar fala, a vibração é fortemente atenuada para evitar distrações na conversa.
4. **Comandar:** Envia pacotes ultrarrápidos via rede local sem fio (~30 frames por segundo) para o app **Palmos (iOS)**, ordenando que a Taptic Engine crie a simulação física.

## 🚀 Tecnologias Usadas
O projeto utiliza um stack de frameworks nativos para garantir performance próxima ao metal no ecossistema Apple:
- **Swift / SwiftUI:** Para a construção da arquitetura reativa orientada a serviços e da interface na barra de menus. O app aproveita intensamente o *Swift Concurrency* (`async/await` e `Actors`).
- **ScreenCaptureKit:** Framework oficial para capturar fluxos de mídia no nível do sistema, com latência nula.
- **Accelerate (vDSP):** Processamento Digital de Sinais (DSP) utilizando aceleração de hardware matemático vetorial da Apple para cálculos complexos da Transformada Rápida de Fourier (FFT), aliviando a CPU principal.
- **SoundAnalysis (CoreML):** Machine Learning (Inteligência Artificial) rodando nativamente via modelo CoreML (implementado pelo `SNClassifySoundRequest`) para classificação semântica instantânea do áudio capturado.
- **MultipeerConnectivity:** Transmissão de pacotes na rede local em modo equivalente ao UDP (`.unreliable`), focando em velocidade máxima de entrega e não retenção de pacotes (prevenindo *lag* acumulado).

## 📥 Como Baixar o Repositório
Para fazer o download, clonar e inspecionar o projeto localmente, execute os seguintes comandos no seu terminal:

```bash
# 1. Clone o repositório
git clone https://github.com/Alexandrediasss/palmos-macbook.git

# 2. Acesse a pasta do projeto
cd palmos-macbook

# 3. Abra o projeto no Xcode
xed .
```
*(Nota: Lembre-se de configurar sua equipe de desenvolvimento (Development Team) na aba de "Signing & Capabilities" no Xcode antes de compilar o aplicativo no seu próprio Mac).*
