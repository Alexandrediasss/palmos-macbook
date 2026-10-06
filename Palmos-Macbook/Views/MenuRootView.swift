//
//  MenuRootView.swift
//  Palmos-Macbook
//
//  Conteúdo do menu suspenso na barra de menus.
//

import SwiftUI

struct MenuRootView: View {

    @StateObject private var networkManager = MacNetworkManager.shared
    @StateObject private var audioManager = AudioCaptureManager.shared

    // Local por enquanto; será migrado para @AppStorage (globalIntensity).
    // Atenção: multiplica com o slider de intensidade do iPhone (50% × 50% = 25%).
    @State private var globalIntensity: Double = 1.0
    @State private var isSendingTestFrames = false

    /// Nome da nota (ex.: "A4") a partir da frequência dominante dos médios.
    private var noteText: String {
        let f = audioManager.pitchFrequency
        guard f > 0 else { return "—" }
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let midi = Int((69 + 12 * log2(Double(f) / 440)).rounded())
        let octave = midi / 12 - 1
        return "\(names[((midi % 12) + 12) % 12])\(octave) · \(Int(f)) Hz"
    }

    /// Envia ~1 s de frames fixos a 30 Hz (um frame sozinho dura só 200 ms no iPhone).
    private func sendTestFrames() {
        guard !isSendingTestFrames else { return }
        isSendingTestFrames = true
        Task {
            for i in 0..<30 {
                let payload = HapticPayload(type: "frame",
                                            intensity: 0.8,
                                            sharpness: 0.3,
                                            bass: 0.8,
                                            mid: 0.5,
                                            treble: 0.3,
                                            pitch: 0.55,
                                            spike: i % 8 == 0)
                networkManager.send(payload: payload)
                try? await Task.sleep(nanoseconds: 33_000_000)
            }
            isSendingTestFrames = false
        }
    }

    private var statusText: String {
        switch networkManager.connectionState {
        case .idle: return "Inativo"
        case .searching: return "Procurando iPhone..."
        case .connecting(let name): return "Conectando a \(name)..."
        case .connected(let name): return "Conectado a \(name)"
        }
    }

    private var isConnected: Bool {
        if case .connected = networkManager.connectionState { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(statusText)
                .font(.headline)
                
            if audioManager.permissionDenied {
                Text("Permissão de Gravação de Tela necessária para ouvir o áudio do Mac.")
                    .font(.caption)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Abrir Ajustes") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
            } else {
                HStack {
                    Circle()
                        .fill(audioManager.isCapturing ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(audioManager.isCapturing ? "Ouvindo áudio do sistema..." : "Áudio inativo")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    if !audioManager.isCapturing && isConnected {
                        Button("Iniciar") {
                            audioManager.startCapture()
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                BandMeter(title: "Graves (ritmo)", value: audioManager.bassLevel, tint: .orange)
                BandMeter(title: "Médios (melodia)", value: audioManager.midLevel, tint: .green)
                BandMeter(title: "Agudos (textura)", value: audioManager.trebleLevel, tint: .cyan)

                HStack {
                    Text("Nota")
                        .font(.subheadline)
                    Spacer()
                    Text(noteText)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Circle()
                        .fill(audioManager.spikeActive ? Color.yellow : Color.gray.opacity(0.3))
                        .frame(width: 10, height: 10)
                        .accessibilityLabel("Ataque nos agudos")
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                SliderRow(title: "Intensidade Global",
                          accessibilityHint: "Ajustar intensidade global da vibração",
                          value: $globalIntensity)
                          
                HStack {
                    Button("Testar Vibração") {
                        let payload = HapticPayload(type: "transient", intensity: Float(globalIntensity), sharpness: 0.8)
                        networkManager.send(payload: payload)
                    }
                    Button("Frame de teste") {
                        sendTestFrames()
                    }
                    .disabled(isSendingTestFrames)
                }
                .disabled(!isConnected)
            }

            Divider()

            HStack {
                Spacer()
                Button("Sair") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
                .controlSize(.regular)
                .accessibilityLabel("Sair do Palmos")
            }
        }
        .padding(14)
        .frame(width: 280)
        .onChange(of: globalIntensity) { newValue in
            audioManager.currentIntensity = Float(newValue)
        }
        .onAppear {
            // Se já estiver conectado, podemos tentar iniciar a captura (opcional)
            if isConnected && !audioManager.isCapturing {
                audioManager.startCapture()
            }
        }
    }
}

// MARK: - Barra de banda (depuração)

private struct BandMeter: View {
    let title: LocalizedStringKey
    let value: Float
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.caption)
                Spacer()
                Text(Double(value), format: .percent.precision(.fractionLength(0)))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(min(max(value, 0), 1)))
                .tint(tint)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Componente de slider

private struct SliderRow: View {
    let title: LocalizedStringKey
    let accessibilityHint: LocalizedStringKey
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text(value, format: .percent.precision(.fractionLength(0)))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: 0.0...1.0)
                .labelsHidden()
                .accessibilityLabel(accessibilityHint)
                .accessibilityValue(Text(value, format: .percent.precision(.fractionLength(0))))
        }
    }
}

#Preview {
    MenuRootView()
}
