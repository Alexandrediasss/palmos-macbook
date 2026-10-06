# Visão do Produto: Palmos (macOS)

## 1. O Pitch: A Dor e a Solução
O consumo de mídia moderna (filmes, jogos, música) é uma experiência profundamente audiovisual. Para pessoas surdas ou com deficiência auditiva, uma camada inteira de emoção e imersão (como o peso de uma explosão, a tensão de uma trilha sonora ou os passos em um jogo) é perdida. 

**O Palmos é a ponte sensorial para essa lacuna.** Ele transforma som em tato. Utilizando o ecossistema Apple, o Palmos converte o iPhone do usuário em um "subwoofer tátil" de alta fidelidade, traduzindo o áudio do Mac em respostas físicas ricas e em tempo real, sem a necessidade de comprar hardwares caros e dedicados.

## 2. A Proposta de Valor
- **Acessibilidade e Imersão Sensorial:** Permite que usuários surdos sintam a dinâmica do som de filmes e jogos através de vibrações texturizadas (graves pesados, agudos secos).
- **Zero Fricção (Foco no Usuário):** O usuário não precisa de equipamentos extras. Basta o Mac que está rodando a mídia e o iPhone que ele já tem no bolso.
- **Universalidade (System-Wide):** Diferente de soluções que dependem de arquivos específicos, o Palmos escuta o Mac globalmente. Funciona perfeitamente com Netflix, YouTube, Spotify, jogos da Steam ou qualquer som reproduzido no sistema.

## 3. O Papel do macOS no Ecossistema
Enquanto o iPhone atua apenas como o "motor" (recebendo comandos e vibrando), o aplicativo do Mac é o **Cérebro**. 
O macOS é o único ambiente sem as restrições severas de "sandbox" do iOS, permitindo interceptar o áudio do sistema de forma nativa e legal (via `ScreenCaptureKit`).

O fluxo de valor funciona assim:
1. **Ouvir:** O Mac captura o áudio que está indo para os alto-falantes em tempo real.
2. **Entender:** O Cérebro separa o som em 3 camadas — **Ritmo** (graves), **Melodia** (médios + nota dominante) e **Textura** (agudos/ataques) — normalizando cada uma dinamicamente (músicas calmas também vibram).
3. **Comandar:** O Mac envia *frames* a ~30 Hz pela rede local; o iPhone toca as 3 camadas simultaneamente na Taptic Engine.

> **v2 — Tradução Sinestésica:** na v1 o iPhone era só um "subwoofer tátil". Na v2 transmitimos também emoção e textura. Limite físico honesto: a Taptic Engine não toca notas; a melodia é *sugerida* (a nota dominante vira *sharpness* no iPhone).

## 4. Público-Alvo e Casos de Uso
- **Público Primário:** Pessoas surdas ou com deficiência auditiva (PCD) buscando autonomia e imersão no consumo de conteúdo digital.
- **Público Secundário:** Gamers e cinéfilos que desejam uma camada extra de imersão física (feedback tátil) ao jogar ou assistir a filmes de ação no Mac.
- **Caso de Uso Principal:** O usuário senta na frente do Mac para ver um filme, abre o Palmos na barra de menus, conecta ao iPhone com um clique e segura o celular (ou o coloca no colo/bolso) para sentir o áudio do filme enquanto assiste.