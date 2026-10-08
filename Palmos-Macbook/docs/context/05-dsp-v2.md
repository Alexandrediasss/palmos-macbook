# DSP v2 — Tradução Sinestésica (Mac)

Implementação em `Services/SpectralAnalyzer.swift` (DSP) e `Services/AudioCaptureManager.swift` (captura, throttle e envio).

## Pipeline
```
SCStream (48 kHz, 2 canais, Float32)
 → mono (média dos canais; suporta planar e intercalado)
 → FIFO → janela de Hann 2048, hop 1024 (~47 análises/s)
 → DFT (vDSP_DFT_zop) → amplitude por bin
 → 3 bandas (RMS) → AGC por banda → bass/mid/treble
 → pitch (pico 250–2000 Hz + interp. parabólica + EMA)
 → spike (agudos) e bassTransient (graves) via spectral flux
 → acumulador (máx das bandas, notas, spikes)
 → Haptic Ducking: Abafa o sinal contínuo em 60% se não houver spike/impacto
 → Filtro Semântico (SoundAnalysis): Silencia totalmente (0%) a onda contínua se for fala humana ("Speech"), mas protege/deixa passar picos de impactos.
 → a cada ≥32 ms: HapticPayload(type:"frame") → .unreliable
```

## Parâmetros finais
| Parâmetro | Valor |
|---|---|
| Janela / hop | 2048 / 1024 amostras (48 kHz ⇒ resolução ≈ 23,4 Hz/bin) |
| Graves | 20–250 Hz |
| Médios | 250–2000 Hz |
| Agudos | 2000–8000 Hz |
| Energia da banda | RMS: `sqrt(Σ amp² / 2)`, amplitude calibrada (senoide A ⇒ A) |
| `noiseFloor` | 0.002 (RMS da banda, atua como Noise Gate primário) |
| `minPeak` (piso do pico do AGC) | 0.06 (evita amplificar ruído fraco e impõe headroom) |
| `peakDecay` | 0.995 por hop (constante de tempo ≈ 4 s) |
| AGC | `peak = max(x, peak*0.995, minPeak)`; `v = clamp((x - floor)/max(peak - floor, 1e-6))` |
| Pitch | `clamp(log2(f/250)/3)`; EMA 0.3; se `mid < 0.03` ⇒ alvo 0.5 e sem frequência |
| Spike | `flux > 1.5 × média(flux)` (EMA 0.1), `rawTreble > 2×floor`, refratário 40 ms (relógio de áudio) |
| Envio | intervalo mínimo 32 ms (~30 Hz), `.unreliable`, só com peers conectados |
| Silêncio | 5 frames zerados (para o iPhone desligar as camadas) e depois para de enviar |
| Compressão no Mac | **Expansão Exponencial (`pow(x, 1.5)`)** para esmagar sons fracos contra o silêncio. + Noise Gate final (<3% zera). |

## Decisões e observações
- O `mid < 0.03` do gate do pitch usa o valor **normalizado** (mesmo corte que o iPhone usa para desligar a melodia), em vez do piso absoluto.
- Entre dois envios o Mac manda o **máximo** de cada banda (não a média) para não perder picos curtos.
- A intensidade global do Mac foi delegada inteiramente ao app do iPhone (V7). O Mac envia o payload com `1.0` de ganho mestre fixo.
- `noiseFloor`/`minPeak` são calibrações empíricas em amplitude relativa ao fundo de escala; ajustar se o silêncio vibrar (subir) ou música muito baixa não vibrar (descer `minPeak`).
- Log no console do Mac: `[Mac] frame #N b=… m=… t=… p=… spike=…` (1º frame e a cada 100).

## Validação
- iPhone loga: `[Rede] Pacote #N: frame b=0.62 m=0.41 t=0.18 p=0.55 spike=false`.
- Música calma (voz/violão): barra de médios ativa, vibração suave. Bateria/eletrônica: graves contínuos + cliques (indicador de spike na UI do Mac).
- "Frame de teste" na UI do Mac envia ≈1 s de frames fixos para validar a camada de 3 pistas sem áudio.
