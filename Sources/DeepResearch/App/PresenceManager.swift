import Foundation
import SwiftUI
import SwiftData
import UserNotifications

/// Gerencia a presença do app: progresso no Dock e notificações quando
/// o app está em segundo plano. Observa o coordinator via modelo SwiftData.
@MainActor
final class PresenceManager: NSObject, ObservableObject, @preconcurrency UNUserNotificationCenterDelegate {
    private let coordinator: ResearchCoordinator
    private let notificationCenter: UNUserNotificationCenter?
    private var hasBundle: Bool { Bundle.main.bundleIdentifier != nil }

    /// Snapshot do status das sessões no último tick — detecta transições.
    private var lastStatusSnapshot: [PersistentIdentifier: Status] = [:]

    /// Permissão de notificação já requisitada nesta sessão.
    private var permissionRequested = false

    init(coordinator: ResearchCoordinator) {
        self.coordinator = coordinator
        // UNUserNotificationCenter exige .app bundle — binário solto crasha.
        if Bundle.main.bundleIdentifier != nil {
            self.notificationCenter = UNUserNotificationCenter.current()
        } else {
            self.notificationCenter = nil
        }
        super.init()
        notificationCenter?.delegate = self
    }

    // MARK: - Dock

    /// Atualiza dockTile badge com a contagem de sessões ativas.
    func updateDockProgress() {
        let activeCount = coordinator.activeSessionCount
        let tile = NSApplication.shared.dockTile

        if activeCount > 0 {
            tile.badgeLabel = "\(activeCount)"
        } else {
            tile.badgeLabel = ""
        }
        tile.display()
    }

    // MARK: - Notificações

    /// Requer permissão na primeira pesquisa (não no launch).
    func requestPermissionIfNeeded() {
        guard !permissionRequested else { return }
        permissionRequested = true
        notificationCenter?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Posta notificação SOMENTE se o app não está ativo.
    func postNotificationIfNeeded(
        title: String,
        body: String,
        sessionID: PersistentIdentifier
    ) {
        guard !NSApp.isActive else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "research-\(sessionID.hashValue)",
            content: content,
            trigger: nil
        )
        notificationCenter?.add(request)
    }

    // MARK: - Ciclo de vida (chamado pelo timer no App)

    /// Verifica mudanças de estado e dispara dock/notificações conforme necessário.
    func tick() {
        let activeCount = coordinator.activeSessionCount
        updateDockProgress()

        // Pedir permissão na primeira pesquisa (não no launch).
        if activeCount > 0 {
            requestPermissionIfNeeded()
        }

        // Detecta sessões que terminaram desde o último tick.
        let currentSnapshot = coordinator.terminalTransitions
        for (id, status) in currentSnapshot {
            guard let previousStatus = lastStatusSnapshot[id],
                  previousStatus != status else { continue }
            if status.isTerminal {
                notifyTerminal(status: status, sessionID: id)
            }
        }

        // Atualiza snapshot.
        for (id, status) in currentSnapshot {
            lastStatusSnapshot[id] = status
        }
        // Remove sessões que saíram do snapshot (deletadas do modelo).
        for id in lastStatusSnapshot.keys where currentSnapshot[id] == nil {
            lastStatusSnapshot.removeValue(forKey: id)
        }
    }

    private func notifyTerminal(status: Status, sessionID: PersistentIdentifier) {
        let title: String
        let body: String

        switch status {
        case .completed:
            title = String(localized: "notification.completed.title", bundle: .module)
            body = String(localized: "notification.completed.body", bundle: .module)
        case .failed:
            title = String(localized: "notification.failed.title", bundle: .module)
            body = String(localized: "notification.failed.body", bundle: .module)
        case .cancelled:
            title = String(localized: "notification.cancelled.title", bundle: .module)
            body = String(localized: "notification.cancelled.body", bundle: .module)
        default:
            return
        }

        postNotificationIfNeeded(title: title, body: body, sessionID: sessionID)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Clique na notificação abre a janela do app (activationPolicy padrão).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        NSApp.activate()
        completionHandler()
    }
}
