# Design e Experiência de Uso (HCI): Palmos (Cérebro macOS)

## 1. O Paradigma "Invisível" (Menu Bar App)
O Palmos para macOS adota a filosofia de design de um utilitário de sistema. Ele não deve competir pela atenção do usuário com o filme ou jogo que está sendo reproduzido. 
- **Sem Presença no Dock:** O aplicativo não terá janela principal nem ícone no Dock.
- **Acesso Rápido (1-Click):** Toda a interação ocorre através de um menu suspenso (dropdown) acionado pelo ícone na barra de menus superior do Mac.

## 2. Anatomia Visual e Feedback de Status
A interface deve parecer uma extensão nativa do próprio macOS, utilizando os materiais translúcidos do sistema.
- **Ícone Dinâmico (SF Symbols):** O ícone da barra de menus será o principal indicador visual de saúde do sistema:
  - `waveform.slash`: Inativo / Sem permissão.
  - `waveform.badge.magnifyingglass`: Buscando o iPhone na rede local.
  - `waveform` (com AccentColor): Conectado e capturando áudio ativamente.
- **O Menu Suspenso:**
  - **Header:** Status da conexão em destaque (ex: "Palmos: Conectado a iPhone de Carlos") e botão circular para Desconectar.
  - **Calibração Visual:** Sliders nativos (`Slider` do SwiftUI) para ajustar o "Filtro de Ruído/Graves" e a "Intensidade Global".
  - **Mini-Espectrômetro (Opcional):** Um pequeno medidor de volume visual (VU meter) embutido no menu apenas para confirmar que o Mac está, de fato, "ouvindo" o sistema.

## 3. Onboarding e Fluxo de Permissões Críticas
O maior obstáculo de UX no macOS é a segurança. O `ScreenCaptureKit` exige a permissão de "Gravação de Tela e Áudio do Sistema" (Screen Recording).
- Se a permissão não for detectada na inicialização, o menu suspenso será substituído por uma interface de bloqueio (State: Unauthorized).
- **Redução de Fricção:** Em vez de apenas dizer "Vá para as configurações", a interface deve possuir um botão de ação proeminente ("Abrir Ajustes do Sistema") que utilize `NSWorkspace` para levar o usuário exatamente para a tela de *Privacy & Security*, acompanhado de uma instrução clara sobre qual chave ativar.

## 4. Acessibilidade (macOS HIG)
- **VoiceOver:** Como o público primário envolve pessoas com deficiência auditiva (que podem ou não ter limitações visuais associadas) e o app visa acessibilidade universal, todos os sliders e botões do menu devem ter `accessibilityLabel` definindo sua função exata ("Ajustar sensibilidade de graves") e seu valor atual.
- **Navegação por Teclado:** O menu suspenso deve ser totalmente operável através das setas do teclado e da tecla `Tab`, respeitando o padrão de "Full Keyboard Access" do macOS.