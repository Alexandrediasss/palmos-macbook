//
//  MacNetworkManager.swift
//  Palmos-Macbook
//
//  Serviço de rede do "Cérebro" macOS: descobre o iPhone na rede local
//  via MultipeerConnectivity e abre a sessão para envio dos comandos táteis.
//

import Combine
import Foundation
import MultipeerConnectivity

final class MacNetworkManager: NSObject, ObservableObject {

    // MARK: - Singleton

    static let shared = MacNetworkManager()

    // MARK: - Constantes

    /// Deve coincidir exatamente com o serviceType anunciado pelo app iOS.
    /// (1–15 caracteres: minúsculas, números e hífen.)
    static let serviceType = "palmos-haptic"

    // MARK: - Estado publicado (consumido pela UI na Main Thread)

    enum ConnectionState: Equatable {
        case idle
        case searching
        case connecting(peerName: String)
        case connected(peerName: String)
    }

    @Published private(set) var connectionState: ConnectionState = .idle

    // MARK: - Multipeer

    private let peerID: MCPeerID
    private let session: MCSession
    private let browser: MCNearbyServiceBrowser

    // MARK: - Init

    private override init() {
        let peerID = MCPeerID(displayName: Host.current().localizedName ?? "Mac")
        self.peerID = peerID
        self.session = MCSession(peer: peerID,
                                 securityIdentity: nil,
                                 encryptionPreference: .optional)
        self.browser = MCNearbyServiceBrowser(peer: peerID,
                                              serviceType: MacNetworkManager.serviceType)
        super.init()
        session.delegate = self
        browser.delegate = self
    }

    // MARK: - API pública

    /// Inicia a busca pelo iPhone na rede local.
    func startBrowsing() {
        guard connectionState == .idle else { return }
        browser.startBrowsingForPeers()
        connectionState = .searching
    }

    /// Interrompe a busca e encerra a sessão atual.
    func stopBrowsing() {
        browser.stopBrowsingForPeers()
        session.disconnect()
        connectionState = .idle
    }

    /// Envia um comando tátil para o iPhone conectado.
    func send(payload: HapticPayload) {
        guard case .connected = connectionState else { return }
        guard !session.connectedPeers.isEmpty else { return }
        
        do {
            let data = try JSONEncoder().encode(payload)
            try session.send(data, toPeers: session.connectedPeers, with: .unreliable)
        } catch {
            print("Erro ao enviar payload: \(error)")
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MacNetworkManager: MCNearbyServiceBrowserDelegate {

    nonisolated func browser(_ browser: MCNearbyServiceBrowser,
                             foundPeer peerID: MCPeerID,
                             withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            // Evita convites duplicados enquanto já há conexão em andamento.
            switch self.connectionState {
            case .connecting, .connected: return
            case .idle, .searching: break
            }
            self.connectionState = .connecting(peerName: peerID.displayName)
            browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 10)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        // O estado real da conexão é tratado em `session(_:peer:didChange:)`.
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser,
                             didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            self.connectionState = .idle
        }
    }
}

// MARK: - MCSessionDelegate

extension MacNetworkManager: MCSessionDelegate {

    nonisolated func session(_ session: MCSession,
                             peer peerID: MCPeerID,
                             didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                self.connectionState = .connected(peerName: peerID.displayName)
            case .connecting:
                self.connectionState = .connecting(peerName: peerID.displayName)
            case .notConnected:
                // Volta a procurar (convite recusado, timeout ou iPhone desconectou).
                self.connectionState = .searching
            @unknown default:
                break
            }
        }
    }

    // O Mac é apenas emissor: os callbacks abaixo são exigidos pelo protocolo, mas não usados.

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {}

    nonisolated func session(_ session: MCSession,
                             didReceive stream: InputStream,
                             withName streamName: String,
                             fromPeer peerID: MCPeerID) {}

    nonisolated func session(_ session: MCSession,
                             didStartReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID,
                             with progress: Progress) {}

    nonisolated func session(_ session: MCSession,
                             didFinishReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID,
                             at localURL: URL?,
                             withError error: Error?) {}
}
