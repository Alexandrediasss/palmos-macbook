import Foundation
import Combine
import ScreenCaptureKit
import CoreMedia
import AudioToolbox

final class AudioCaptureManager: NSObject, ObservableObject, SCStreamDelegate, SCStreamOutput {
    static let shared = AudioCaptureManager()
    
    @Published var isCapturing = false
    @Published var permissionDenied = false
    
    // Telemetria para a UI de depuração (0...1), atualizada ~15 Hz
    @Published var bassLevel: Float = 0
    @Published var midLevel: Float = 0
    @Published var trebleLevel: Float = 0
    @Published var pitchLevel: Float = 0.5
    /// Frequência da nota dominante (Hz); 0 = sem nota
    @Published var pitchFrequency: Float = 0
    @Published var spikeActive = false
    
    private var stream: SCStream?
    private let audioQueue = DispatchQueue(label: "com.palmos.audioQueue", qos: .userInteractive)
    
    // MARK: - Envio (throttle ~30 Hz)
    
    /// Intervalo mínimo entre frames de rede (~30 Hz). NUNCA reduzir muito: derruba a sessão Multipeer.
    private let sendInterval: TimeInterval = 0.032
    private var lastSendTime: Date = Date.distantPast
    private var silentFrames = 0
    private var framesSent = 0
    private var uiTick = 0
    
    /// Intensidade global do Mac (injetada pela UI). Multiplica com o slider do iPhone (50% × 50% = 25%).
    var currentIntensity: Float = 1.0
    
    // DSP (acessado somente na audioQueue)
    private let analyzer = SpectralAnalyzer()
    
    // IA Semântica
    private let semanticAnalyzer = SemanticAnalyzer()

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
                config.sampleRate = 48000
                config.channelCount = 2
                config.width = 2
                config.height = 2
                config.showsCursor = false
                config.minimumFrameInterval = CMTime(value: 1, timescale: 1) // Throttle dummy video to 1 FPS
                
                let newStream = SCStream(filter: filter, configuration: config, delegate: self)
                // Adiciona o output de áudio (o que realmente queremos)
                try newStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
                // Adiciona um output de vídeo dummy para evitar os erros do SCStream ("stream output NOT found")
                try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: audioQueue)
                
                analyzer.reset()
                silentFrames = 0
                
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
                self.publishLevels(AnalysisFrame())
            }
        }
    }
    
    // MARK: - SCStreamOutput
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return } // Ignora os frames de vídeo dummy
        
        // 1) Áudio → mono Float32 → FFT / bandas / pitch / spike (hop de 1024 samples)
        if let (mono, sampleRate) = extractMono(from: sampleBuffer) {
            analyzer.process(mono: mono, sampleRate: sampleRate)
            semanticAnalyzer.process(mono: mono, sampleRate: sampleRate)
        }
        
        // 2) Throttle: 1 frame de rede por ~33 ms (acumulou o máximo das bandas no intervalo)
        let now = Date()
        guard now.timeIntervalSince(lastSendTime) >= sendInterval else { return }
        guard let frame = analyzer.takeFrame() else { return }
        lastSendTime = now
        
        publishLevelsThrottled(frame)
        
        // Silêncio: manda alguns frames zerados (para o iPhone desligar as camadas) e depois para de enviar.
        if frame.isSilent {
            silentFrames += 1
            if silentFrames > 5 { return }
        } else {
            silentFrames = 0
        }
        
        // Filtro de IA: reduz drasticamente a intensidade (para 15%) se for detectado Speech (voz)
        let isSpeech = semanticAnalyzer.currentClass == "Speech"
        
        // Haptic Ducking: Se for som contínuo (sem impacto), abafa para criar contraste. Se for impacto, libera 100%.
        let isImpact = frame.spike || frame.bassTransient
        let duckingFactor: Float = isImpact ? 1.0 : 0.4
        
        let g = currentIntensity * duckingFactor * (isSpeech ? 0.15 : 1.0)
        
        let bass = min(frame.bass * g, 1)
        let mid = min(frame.mid * g, 1)
        let treble = min(frame.treble * g, 1)
        
        let payload = HapticPayload(
            type: "frame",
            intensity: max(bass, mid, treble),
            sharpness: 0.3,
            bass: bass,
            mid: mid,
            treble: treble,
            pitch: frame.pitch,
            spike: frame.spike,
            bassTransient: frame.bassTransient,
            semanticClass: semanticAnalyzer.currentClass
        )
        
        framesSent += 1
        if framesSent % 100 == 1 {
            let semLog = semanticAnalyzer.currentClass ?? "none"
            print(String(format: "[Mac] frame #%d b=%.2f m=%.2f t=%.2f p=%.2f spike=%@ bassT=%@ sem=%@",
                         framesSent, bass, mid, treble, frame.pitch, 
                         frame.spike ? "T" : "F", frame.bassTransient ? "T" : "F", semLog))
        }
        
        MacNetworkManager.shared.send(payload: payload)
    }
    
    // MARK: - UI
    
    private func publishLevelsThrottled(_ frame: AnalysisFrame) {
        uiTick += 1
        // ~15 Hz para a UI; spikes sempre passam para não perder o "flash".
        guard uiTick % 2 == 0 || frame.spike else { return }
        DispatchQueue.main.async { self.publishLevels(frame) }
    }
    
    private func publishLevels(_ frame: AnalysisFrame) {
        bassLevel = frame.bass
        midLevel = frame.mid
        trebleLevel = frame.treble
        pitchLevel = frame.pitch
        pitchFrequency = frame.frequency
        if frame.spike {
            spikeActive = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.spikeActive = false
            }
        }
    }
    
    // MARK: - Extração de áudio
    
    /// Converte o CMSampleBuffer (Float32, planar ou intercalado) em mono (média dos canais).
    private func extractMono(from sampleBuffer: CMSampleBuffer) -> ([Float], Double)? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else { return nil }
        let asbd = asbdPtr.pointee
        guard asbd.mFormatID == kAudioFormatLinearPCM,
              asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              asbd.mBitsPerChannel == 32 else { return nil }
        
        let channels = max(1, Int(asbd.mChannelsPerFrame))
        let nonInterleaved = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        
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
        guard bufferListSize > 0, let bufferListMemory = malloc(bufferListSize) else { return nil }
        defer { free(bufferListMemory) }
        
        let bufferList = bufferListMemory.bindMemory(to: AudioBufferList.self, capacity: 1)
        
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
        
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        guard let first = buffers.first, first.mData != nil else { return nil }
        
        if nonInterleaved {
            let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size
            guard frames > 0 else { return nil }
            var mono = [Float](repeating: 0, count: frames)
            var used = 0
            for buf in buffers {
                guard let data = buf.mData else { continue }
                let count = min(frames, Int(buf.mDataByteSize) / MemoryLayout<Float>.size)
                let p = data.assumingMemoryBound(to: Float.self)
                for i in 0..<count { mono[i] += p[i] }
                used += 1
            }
            if used > 1 {
                let inv = 1 / Float(used)
                for i in 0..<frames { mono[i] *= inv }
            }
            return (mono, asbd.mSampleRate)
        } else {
            let frames = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * channels)
            guard frames > 0, let data = first.mData else { return nil }
            let p = data.assumingMemoryBound(to: Float.self)
            var mono = [Float](repeating: 0, count: frames)
            let inv = 1 / Float(channels)
            for i in 0..<frames {
                var s: Float = 0
                for c in 0..<channels { s += p[i * channels + c] }
                mono[i] = s * inv
            }
            return (mono, asbd.mSampleRate)
        }
    }
}
