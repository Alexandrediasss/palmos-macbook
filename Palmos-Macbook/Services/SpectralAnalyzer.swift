//
//  SpectralAnalyzer.swift
//  Palmos-Macbook
//
//  DSP da "Tradução Sinestésica" (v2): FFT em 3 bandas, normalização adaptativa (AGC),
//  nota dominante (pitch) e detecção de ataques nos agudos (spectral flux).
//
//  NÃO é thread-safe: use sempre da mesma fila (audioQueue do AudioCaptureManager).
//

import Accelerate
import Foundation

/// Resultado acumulado entre dois envios de rede (valores lineares 0...1, sem curva de compressão).
nonisolated struct AnalysisFrame {
    var bass: Float = 0
    var mid: Float = 0
    var treble: Float = 0
    /// 0 (grave) … 1 (agudo), escala log em 3 oitavas (250 Hz → 2 kHz). 0.5 quando não há nota.
    var pitch: Float = 0.5
    /// Frequência (Hz) da nota dominante dos médios; 0 quando não há nota.
    var frequency: Float = 0
    var spike: Bool = false
    var bassTransient: Bool = false
    var midTransient: Bool = false

    var isSilent: Bool { bass == 0 && mid == 0 && treble == 0 && !spike && !bassTransient && !midTransient }
}

nonisolated final class SpectralAnalyzer {

    // MARK: - Parâmetros finais (documentados em docs/context/05-dsp-v2.md)

    static let fftSize = 2048
    static let hopSize = 1024

    /// Piso de ruído (RMS da banda, amplitude relativa ao fundo de escala): abaixo disso = silêncio.
    static let noiseFloor: Float = 0.002
    /// Pico mínimo do AGC: impede que ruído inaudível seja amplificado até 1.0 (Expansão).
    static let minPeak: Float = 0.06
    /// Decaimento do pico por hop (~47 hops/s ⇒ constante de tempo ≈ 4 s).
    static let peakDecay: Float = 0.995

    static let pitchSmoothing: Float = 0.3
    /// Abaixo deste valor normalizado de `mid`, a nota não é confiável ⇒ pitch = 0.5.
    static let pitchMidGate: Float = 0.03

    static let trebleSpikeRatio: Float = 1.5
    static let midSpikeRatio: Float = 1.3
    static let bassSpikeRatio: Float = 1.15
    static let spikeRefractory: Double = 0.040
    static let fluxAverageSmoothing: Float = 0.1

    // MARK: - Estado

    private let n = SpectralAnalyzer.fftSize
    private let setup: vDSP_DFT_Setup
    private var window: [Float]
    private var windowSum: Float = 1

    private var fifo: [Float] = []
    private var realIn: [Float]
    private var imagIn: [Float]
    private var realOut: [Float]
    private var imagOut: [Float]
    private var amp: [Float]            // amplitude por bin (n/2)
    private var prevTreble: [Float]     // amplitudes dos agudos no hop anterior
    private var prevMid: [Float]        // amplitudes dos médios no hop anterior
    private var prevBass: [Float]       // amplitudes dos graves no hop anterior

    private var sampleRate: Double = 0
    private var bassRange = 1..<2
    private var midRange = 2..<3
    private var trebleRange = 3..<4

    private var peaks: [Float] = [SpectralAnalyzer.minPeak, SpectralAnalyzer.minPeak, SpectralAnalyzer.minPeak]
    private var pitchSmoothed: Float = 0.5
    private var fluxAverage: Float = 0
    private var midFluxAverage: Float = 0
    private var bassFluxAverage: Float = 0
    private var clock: Double = 0       // relógio em segundos de áudio processado
    private var lastSpikeTime: Double = -1
    private var lastMidSpikeTime: Double = -1
    private var lastBassSpikeTime: Double = -1

    private var acc = AnalysisFrame()
    private var accHops = 0

    // MARK: - Init

    init() {
        let n = SpectralAnalyzer.fftSize
        guard let s = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(n), .FORWARD) else {
            fatalError("Não foi possível criar o setup da DFT")
        }
        setup = s
        window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_DENORM))
        vDSP_sve(window, 1, &windowSum, vDSP_Length(n))
        realIn = [Float](repeating: 0, count: n)
        imagIn = [Float](repeating: 0, count: n)
        realOut = [Float](repeating: 0, count: n)
        imagOut = [Float](repeating: 0, count: n)
        amp = [Float](repeating: 0, count: n / 2)
        prevTreble = [Float](repeating: 0, count: n / 2)
        prevMid = [Float](repeating: 0, count: n / 2)
        prevBass = [Float](repeating: 0, count: n / 2)
    }

    deinit {
        vDSP_DFT_DestroySetup(setup)
    }

    // MARK: - API

    func reset() {
        fifo.removeAll(keepingCapacity: true)
        peaks = [Self.minPeak, Self.minPeak, Self.minPeak]
        pitchSmoothed = 0.5
        fluxAverage = 0
        midFluxAverage = 0
        bassFluxAverage = 0
        clock = 0
        lastSpikeTime = -1
        lastMidSpikeTime = -1
        lastBassSpikeTime = -1
        for i in prevTreble.indices { prevTreble[i] = 0 }
        for i in prevMid.indices { prevMid[i] = 0 }
        for i in prevBass.indices { prevBass[i] = 0 }
        acc = AnalysisFrame()
        accHops = 0
    }

    /// Alimenta o analisador com amostras mono (Float32) e processa todos os hops completos.
    func process(mono: [Float], sampleRate: Double) {
        guard sampleRate > 8000 else { return }
        if sampleRate != self.sampleRate {
            self.sampleRate = sampleRate
            configureBands()
        }
        fifo.append(contentsOf: mono)
        // Proteção contra acúmulo caso o processamento atrase.
        if fifo.count > n * 8 { fifo.removeFirst(fifo.count - n * 2) }

        while fifo.count >= n {
            analyzeWindow()
            fifo.removeFirst(Self.hopSize)
        }
    }

    /// Devolve o acumulado desde a última chamada (máximo das bandas, última nota, OU dos spikes).
    /// `nil` se nenhum hop foi processado no intervalo.
    func takeFrame() -> AnalysisFrame? {
        guard accHops > 0 else { return nil }
        let out = acc
        acc.bass = 0
        acc.mid = 0
        acc.treble = 0
        acc.spike = false
        acc.bassTransient = false
        acc.midTransient = false
        accHops = 0
        return out
    }

    // MARK: - DSP

    private func configureBands() {
        let res = Float(sampleRate) / Float(n)
        let half = n / 2
        let bassLo = max(1, Int((20 / res).rounded(.up)))
        let midLo = max(bassLo + 1, Int((250 / res).rounded(.up)))
        let trebleLo = max(midLo + 2, Int((2000 / res).rounded(.up)))
        let trebleHi = min(half - 1, Int((8000 / res).rounded(.down)))
        bassRange = bassLo..<midLo
        midRange = midLo..<trebleLo
        trebleRange = trebleLo..<max(trebleLo + 1, trebleHi + 1)
    }

    private func bandRMS(_ range: Range<Int>) -> Float {
        var sum: Float = 0
        for k in range { sum += amp[k] * amp[k] }
        return (sum * 0.5).squareRoot() // RMS de senoides de amplitude `amp`
    }

    /// AGC por banda: peak = max(x, peak*0.995); valor = clamp((x - piso) / (peak - piso)).
    private func normalize(_ x: Float, band: Int) -> Float {
        peaks[band] = max(x, peaks[band] * Self.peakDecay, Self.minPeak)
        let floor = Self.noiseFloor
        let v = (x - floor) / max(peaks[band] - floor, 1e-6)
        return min(max(v, 0), 1)
    }

    private func analyzeWindow() {
        let half = n / 2

        // Janela de Hann sobre os primeiros n samples do FIFO.
        fifo.withUnsafeBufferPointer { src in
            vDSP_vmul(src.baseAddress!, 1, window, 1, &realIn, 1, vDSP_Length(n))
        }
        vDSP_DFT_Execute(setup, realIn, imagIn, &realOut, &imagOut)

        // Amplitude por bin (escala: senoide de amplitude A ⇒ A).
        let scale = 2 / windowSum
        for k in 0..<half {
            amp[k] = (realOut[k] * realOut[k] + imagOut[k] * imagOut[k]).squareRoot() * scale
        }

        // 1) Energia por banda (RMS) → 2) normalização adaptativa.
        let rawBass = bandRMS(bassRange)
        let rawMid = bandRMS(midRange)
        let rawTreble = bandRMS(trebleRange)
        let bass = normalize(rawBass, band: 0)
        let mid = normalize(rawMid, band: 1)
        let treble = normalize(rawTreble, band: 2)

        // 3) Nota dominante dos médios.
        var targetPitch: Float = 0.5
        var freq: Float = 0
        if mid >= Self.pitchMidGate, let f = dominantFrequency() {
            freq = f
            targetPitch = min(max(log2(f / 250) / 3, 0), 1)
        }
        pitchSmoothed += Self.pitchSmoothing * (targetPitch - pitchSmoothed)

        // 4) Spectral flux dos agudos e graves → spike / bassTransient.
        var flux: Float = 0
        for k in trebleRange {
            let d = amp[k] - prevTreble[k]
            if d > 0 { flux += d }
            prevTreble[k] = amp[k]
        }
        
        var midFlux: Float = 0
        for k in midRange {
            let d = amp[k] - prevMid[k]
            if d > 0 { midFlux += d }
            prevMid[k] = amp[k]
        }
        
        var bassFlux: Float = 0
        for k in bassRange {
            let d = amp[k] - prevBass[k]
            if d > 0 { bassFlux += d }
            prevBass[k] = amp[k]
        }

        clock += Double(Self.hopSize) / sampleRate
        
        var spike = false
        if rawTreble > Self.noiseFloor * 2,
           flux > Self.trebleSpikeRatio * max(fluxAverage, 1e-5),
           clock - lastSpikeTime >= Self.spikeRefractory {
            spike = true
            lastSpikeTime = clock
        }
        
        var midSpike = false
        if rawMid > Self.noiseFloor * 2,
           midFlux > Self.midSpikeRatio * max(midFluxAverage, 1e-5),
           clock - lastMidSpikeTime >= Self.spikeRefractory {
            midSpike = true
            lastMidSpikeTime = clock
        }
        
        var bassSpike = false
        if rawBass > Self.noiseFloor * 2,
           bassFlux > Self.bassSpikeRatio * max(bassFluxAverage, 1e-5),
           clock - lastBassSpikeTime >= Self.spikeRefractory {
            bassSpike = true
            lastBassSpikeTime = clock
        }

        fluxAverage += Self.fluxAverageSmoothing * (flux - fluxAverage)
        midFluxAverage += Self.fluxAverageSmoothing * (midFlux - midFluxAverage)
        bassFluxAverage += Self.fluxAverageSmoothing * (bassFlux - bassFluxAverage)

        // Acumula até o próximo envio de rede.
        acc.bass = max(acc.bass, bass)
        acc.mid = max(acc.mid, mid)
        acc.treble = max(acc.treble, treble)
        acc.pitch = pitchSmoothed
        acc.frequency = freq
        acc.spike = acc.spike || spike
        acc.bassTransient = acc.bassTransient || bassSpike
        acc.midTransient = acc.midTransient || midSpike
        accHops += 1
    }

    /// Bin de maior magnitude em 250–2000 Hz, refinado por interpolação parabólica (em log).
    private func dominantFrequency() -> Float? {
        var bestK = midRange.lowerBound
        var bestV: Float = 0
        for k in midRange where amp[k] > bestV {
            bestV = amp[k]
            bestK = k
        }
        guard bestV > Self.noiseFloor else { return nil }

        var delta: Float = 0
        if bestK > 0 && bestK + 1 < amp.count {
            let a = log(amp[bestK - 1] + 1e-12)
            let b = log(amp[bestK] + 1e-12)
            let c = log(amp[bestK + 1] + 1e-12)
            let denom = a - 2 * b + c
            if abs(denom) > 1e-9 {
                delta = min(max(0.5 * (a - c) / denom, -0.5), 0.5)
            }
        }
        return (Float(bestK) + delta) * Float(sampleRate) / Float(n)
    }
}
