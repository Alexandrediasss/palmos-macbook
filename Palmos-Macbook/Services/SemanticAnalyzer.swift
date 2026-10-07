import Foundation
import SoundAnalysis
import AVFoundation

final class SemanticAnalyzer: NSObject, SNResultsObserving {
    private var streamAnalyzer: SNAudioStreamAnalyzer?
    private let request: SNClassifySoundRequest
    
    private let lock = NSLock()
    private var _currentClass: String? = nil
    
    var currentClass: String? {
        lock.lock()
        defer { lock.unlock() }
        return _currentClass
    }
    
    private let analysisQueue = DispatchQueue(label: "com.palmos.semanticQueue", qos: .userInitiated)
    private var framePosition: AVAudioFramePosition = 0
    private var lastClearTime: Date = Date()
    
    override init() {
        do {
            request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        } catch {
            fatalError("SoundAnalysis não disponível: \(error)")
        }
        super.init()
    }
    
    func reset(format: AVAudioFormat) {
        streamAnalyzer = SNAudioStreamAnalyzer(format: format)
        do {
            try streamAnalyzer?.add(request, withObserver: self)
            framePosition = 0
            lock.lock()
            _currentClass = nil
            lock.unlock()
        } catch {
            print("[Semantic] Erro ao adicionar request de áudio semântico: \(error)")
        }
    }
    
    func process(mono: [Float], sampleRate: Double) {
        // Limpa a tag atual após 1 segundo sem nova detecção confiável
        if Date().timeIntervalSince(lastClearTime) > 1.0 {
            lock.lock()
            if _currentClass != nil {
                print("[Semantic] limpando tag antiga (\(_currentClass!))")
                _currentClass = nil
            }
            lock.unlock()
        }
        
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        if streamAnalyzer == nil {
            reset(format: format)
        }
        
        let frameCount = AVAudioFrameCount(mono.count)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        pcmBuffer.frameLength = frameCount
        
        if let channelData = pcmBuffer.floatChannelData?[0] {
            mono.withUnsafeBufferPointer { src in
                channelData.update(from: src.baseAddress!, count: mono.count)
            }
        }
        
        analysisQueue.async {
            self.streamAnalyzer?.analyze(pcmBuffer, atAudioFramePosition: self.framePosition)
            self.framePosition += AVAudioFramePosition(frameCount)
        }
    }
    
    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classificationResult = result as? SNClassificationResult else { return }
        guard let best = classificationResult.classifications.first else { return }
        
        // Exige 80% de confiança mínima para não espamar o log.
        if best.confidence > 0.8 && best.identifier != "Silence" {
            lock.lock()
            if _currentClass != best.identifier {
                print("[Semantic] Novo Som Detectado: \(best.identifier) (confiança: \(String(format: "%.2f", best.confidence)))")
            }
            _currentClass = best.identifier
            lastClearTime = Date()
            lock.unlock()
        }
    }
    
    func request(_ request: SNRequest, didFailWithError error: Error) {
        print("[Semantic] Erro: \(error)")
    }
}
