import Foundation
import Combine
import ScreenCaptureKit
import CoreMedia
import Accelerate

final class AudioCaptureManager: NSObject, ObservableObject, SCStreamDelegate, SCStreamOutput {
    static let shared = AudioCaptureManager()
    
    @Published var isCapturing = false
    @Published var permissionDenied = false
    
    private var stream: SCStream?
    private let audioQueue = DispatchQueue(label: "com.palmos.audioQueue", qos: .userInteractive)
    
    // Configurações de análise
    private var lastSendTime: Date = Date.distantPast
    
    // Estas variáveis serão injetadas da UI (MenuRootView)
    var currentBassThreshold: Float = 0.3
    var currentIntensity: Float = 1.0
    
    // Variáveis para FFT
    private let fftSize = 1024
    private lazy var log2n = vDSP_Length(log2(Float(fftSize)))
    private lazy var setup: vDSP_DFT_Setup? = {
        vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftSize), vDSP_DFT_Direction.FORWARD)
    }()

    func startCapture() {
        Task {
            do {
                // Solicita a permissão de gravação de tela, necessária para capturar o áudio do sistema
                guard CGPreflightScreenCaptureAccess() else {
                    CGRequestScreenCaptureAccess()
                    DispatchQueue.main.async { self.permissionDenied = true }
                    return
                }
                
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard let display = content.displays.first else { return }
                
                let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                
                let config = SCStreamConfiguration()
                config.capturesAudio = true
                config.width = 2
                config.height = 2
                config.showsCursor = false
                config.minimumFrameInterval = CMTime(value: 1, timescale: 1) // Throttle dummy video to 1 FPS
                
                let newStream = SCStream(filter: filter, configuration: config, delegate: self)
                // Adiciona o output de áudio (o que realmente queremos)
                try newStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
                // Adiciona um output de vídeo dummy para evitar os erros do SCStream ("stream output NOT found")
                try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: audioQueue)
                
                try await newStream.startCapture()
                
                DispatchQueue.main.async {
                    self.stream = newStream
                    self.isCapturing = true
                    self.permissionDenied = false
                }
            } catch {
                print("Erro ao iniciar captura de áudio: \(error)")
                DispatchQueue.main.async { self.isCapturing = false }
            }
        }
    }
    
    func stopCapture() {
        Task {
            try? await stream?.stopCapture()
            DispatchQueue.main.async {
                self.isCapturing = false
                self.stream = nil
            }
        }
    }
    
    // MARK: - SCStreamOutput
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return } // Ignora os frames de vídeo dummy
        
        // Limita a taxa de eventos a 10 Hz máximo absoluto para nunca afogar a rede
        let now = Date()
        guard now.timeIntervalSince(lastSendTime) > 0.10 else { return }
        
        if let bassPower = analyzeBass(sampleBuffer: sampleBuffer) {
            // Verifica se a potência dos graves passou do threshold definido pelo usuário
            if bassPower > currentBassThreshold {
                lastSendTime = now
                
                // Mapeia a força do grave para a intensidade do haptic (multiplicado pelo volume global)
                let intensity = min(bassPower * 1.5, 1.0) * currentIntensity
                
                let payload = HapticPayload(type: "continuous", intensity: intensity, sharpness: 0.2)
                
                // LOG PARA PROVAR QUE O THROTTLE FUNCIONA E NÃO ESTÁ FLOODANDO
                print("[Mac] Enviando pacote continuous: \(intensity). Tempo desde o último: \(now.timeIntervalSince(lastSendTime))s")
                
                MacNetworkManager.shared.send(payload: payload)
            }
        }
    }
    
    // MARK: - Processamento DSP
    
    private func analyzeBass(sampleBuffer: CMSampleBuffer) -> Float? {
        var blockBuffer: CMBlockBuffer?
        var bufferListSize: Int = 0
        
        // Primeira chamada para descobrir o tamanho necessário para a AudioBufferList
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &bufferListSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        )
        
        guard bufferListSize > 0 else { return nil }
        
        // Aloca a memória dinamicamente
        let bufferListMemory = malloc(bufferListSize)
        guard let bufferListMemory = bufferListMemory else { return nil }
        defer { free(bufferListMemory) }
        
        let bufferList = bufferListMemory.bindMemory(to: AudioBufferList.self, capacity: 1)
        
        // Segunda chamada para preencher a AudioBufferList alocada
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: bufferList,
            bufferListSize: bufferListSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        
        guard status == noErr else { return nil }
        
        let buffers = UnsafeBufferPointer<AudioBuffer>(start: &bufferList.pointee.mBuffers, count: Int(bufferList.pointee.mNumberBuffers))
        guard let data = buffers.first?.mData else { return nil }
        
        let byteSize = Int(buffers.first?.mDataByteSize ?? 0)
        let frameCount = byteSize / MemoryLayout<Float32>.size
        
        // Evita crash de log2(0) e garante um mínimo de amostras
        guard frameCount >= 128 else { return nil }
        
        // Se o buffer for menor que o fftSize, usamos o tamanho que der (potência de 2 menor)
        let actualFFTSize = frameCount < fftSize ? (1 << Int(log2(Double(frameCount)))) : fftSize
        
        let ptr = data.bindMemory(to: Float32.self, capacity: actualFFTSize)
        var realIn = [Float](UnsafeBufferPointer(start: ptr, count: actualFFTSize))
        var imagIn = [Float](repeating: 0.0, count: actualFFTSize)
        var realOut = [Float](repeating: 0.0, count: actualFFTSize)
        var imagOut = [Float](repeating: 0.0, count: actualFFTSize)
        
        // Usa setup temporário se o tamanho for menor que o fftSize padrão
        let currentSetup = actualFFTSize == fftSize ? setup : vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(actualFFTSize), vDSP_DFT_Direction.FORWARD)
        guard let validSetup = currentSetup else { return nil }
        defer {
            if actualFFTSize != fftSize { vDSP_DFT_DestroySetup(validSetup) }
        }
        
        vDSP_DFT_Execute(validSetup, &realIn, &imagIn, &realOut, &imagOut)
        
        // Calcula as magnitudes complexas
        var magnitudes = [Float](repeating: 0.0, count: actualFFTSize / 2)
        realOut.withUnsafeMutableBufferPointer { realPtr in
            imagOut.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(actualFFTSize / 2))
            }
        }
        
        // Frequência de amostragem padrão costuma ser 48000Hz.
        // A resolução é 48000 / actualFFTSize por bin.
        let resolution = 48000.0 / Float(actualFFTSize)
        // Graves (aprox 20Hz a ~150Hz)
        let maxBassBin = max(1, Int(150.0 / resolution))
        
        var bassSum: Float = 0
        for i in 1...maxBassBin {
            bassSum += magnitudes[i]
        }
        
        // Normaliza o resultado empiricamente
        let bassPower = min(sqrt(bassSum) / 50.0, 1.0)
        
        return bassPower
    }
}
