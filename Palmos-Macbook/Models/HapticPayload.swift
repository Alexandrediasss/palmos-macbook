import Foundation

/// Contrato de rede Mac → iPhone. DEVE ser idêntico nos dois apps.
/// - `type`: `"frame"` (v2) | `"transient"` | `"continuous"` (v1 legado)
/// - Campos v2 são opcionais; pacotes v1 continuam decodificando no iPhone.
struct HapticPayload: Codable {
    let type: String
    /// 0...1. Em `frame`: max(bass, mid, treble).
    let intensity: Float
    /// 0...1. Usado só em v1 (ignorado em `frame`).
    let sharpness: Float
    /// 0...1, energia 20–250 Hz (Ritmo)
    let bass: Float?
    /// 0...1, energia 250 Hz–2 kHz (Melodia)
    let mid: Float?
    /// 0...1, energia > 2 kHz (Textura)
    let treble: Float?
    /// 0...1, nota dominante dos médios (0 grave … 1 agudo, escala log)
    let pitch: Float?
    /// true no instante de um ataque súbito nos agudos
    let spike: Bool?
    /// true se o grave atual for um impacto (transient) em vez de contínuo
    let bassTransient: Bool?
    /// true se houver um ataque repentino nos médios (Efeito Martelo / Piano)
    let midTransient: Bool?
    /// Classe semântica detectada via Machine Learning (ex: "Explosion", "Laughter")
    let semanticClass: String?

    init(type: String,
         intensity: Float,
         sharpness: Float,
         bass: Float? = nil,
         mid: Float? = nil,
         treble: Float? = nil,
         pitch: Float? = nil,
         spike: Bool? = nil,
         bassTransient: Bool? = nil,
         midTransient: Bool? = nil,
         semanticClass: String? = nil) {
        self.type = type
        self.intensity = intensity
        self.sharpness = sharpness
        self.bass = bass
        self.mid = mid
        self.treble = treble
        self.pitch = pitch
        self.spike = spike
        self.bassTransient = bassTransient
        self.midTransient = midTransient
        self.semanticClass = semanticClass
    }
}
