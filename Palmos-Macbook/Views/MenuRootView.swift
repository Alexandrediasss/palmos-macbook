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

    // Locais por enquanto; serão migrados para @AppStorage (bassThreshold / globalIntensity).
    @State private var bassFilter: Double = 0.3
    @State private var globalIntensity: Double = 1.0

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

            VStack(alignment: .leading, spacing: 14) {
                SliderRow(title: "Filtro de Graves",
                          accessibilityHint: "Ajustar sensibilidade de graves",
                          value: $bassFilter)
                SliderRow(title: "Intensidade Global",
                          accessibilityHint: "Ajustar intensidade global da vibração",
                          value: $globalIntensity)
                          
                Button("Testar Vibração") {
                    let payload = HapticPayload(type: "transient", intensity: Float(globalIntensity), sharpness: 0.8)
                    networkManager.send(payload: payload)
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
        .onChange(of: bassFilter) { newValue in
            audioManager.currentBassThreshold = Float(newValue)
        }
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
