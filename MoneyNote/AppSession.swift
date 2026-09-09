import SwiftUI
import SwiftData
import Combine
import UIKit
import CoreData

@MainActor
final class AppSession: ObservableObject {
    @Published var month = Date.now
    @Published var selection = 0
    @Published var notice: String?
    @Published var undoAction: (() -> Void)?
    @Published var cloudStatus = "等待 iCloud 同步状态"
    @Published var lastCloudSuccess: Date?
    @Published var lastSaved: Date?
    @Published var selectedRecord: PersistentIdentifier?
    private var noticeTask: Task<Void, Never>?
    private var cloudEvents: Set<UUID> = []

    func saved(_ message: String, undo: (() -> Void)? = nil) {
        noticeTask?.cancel()
        lastSaved = .now
        notice = message
        undoAction = undo
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIAccessibility.post(notification: .announcement, argument: message)
        if undo == nil {
            noticeTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(UIAccessibility.isVoiceOverRunning ? 10 : 6))
                guard !Task.isCancelled else { return }
                self?.notice = nil
            }
        }
    }
    func failed(_ message: String) {
        noticeTask?.cancel()
        notice = message; undoAction = nil
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
    @discardableResult
    func delete(_ records: [TxRecord], in context: ModelContext) -> Bool {
        guard !records.isEmpty else { return false }
        for record in records { record.deletedAt = .now }
        do {
            try context.save()
            saved("已移到最近删除 · \(records.count) 笔", undo: { [weak self] in
                for record in records { record.deletedAt = nil }
                do { try context.save(); self?.saved("已恢复账目") }
                catch { context.rollback(); self?.failed("恢复失败，请在最近删除中重试。") }
            })
            return true
        } catch { context.rollback(); failed("删除失败，原账目已保留。"); return false }
    }
    func cloudEvent(_ notification: Notification) {
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { return }
        if event.endDate == nil {
            cloudEvents.insert(event.identifier)
            cloudStatus = "iCloud 正在同步"
        } else {
            cloudEvents.remove(event.identifier)
            if event.succeeded {
                if event.type != .setup { lastCloudSuccess = event.endDate }
                cloudStatus = cloudEvents.isEmpty ? (event.type == .setup ? "iCloud 已连接，等待账目同步" : "最近一次同步已完成") : "iCloud 正在同步"
            } else {
                cloudStatus = "iCloud 同步未完成，系统会自动重试"
            }
        }
    }
}

struct SessionNotice: View {
    @EnvironmentObject private var session: AppSession
    var body: some View {
        if let notice = session.notice {
            AdaptiveRow {
                Text(notice).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                HStack {
                    if let undo = session.undoAction { Button("撤销", action: undo).fontWeight(.semibold).frame(minHeight: 44) }
                    Button { session.notice = nil; session.undoAction = nil } label: {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }.accessibilityLabel("关闭提示")
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .paperCard().padding(.horizontal, 16).padding(.bottom, 8)
            .accessibilityElement(children: .contain)
        }
    }
}
