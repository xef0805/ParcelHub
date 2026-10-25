import Foundation
import Combine

/// 仅在 App 前台刷新已接入的官方网页；不申请短信、定位或后台常驻权限。
@MainActor
final class OfficialSyncController: ObservableObject {
    let session = OfficialPickupSession()
    @Published private(set) var isRefreshing = false
    @Published private(set) var status = "正在等待刷新"
    @Published private(set) var needsLogin = false
    private let store: ParcelStore
    private var subscriptions = Set<AnyCancellable>()
    private var timer: Timer?
    private var active = false
    private var lastAttempt: Date?
    private var watchdog: Task<Void, Never>?

    init(store: ParcelStore) {
        self.store = store
        session.$readResult.sink { [weak self] result in
            guard let self, self.active, let result else { return }
            self.finish()
            if result.state == "ready" {
                if let error = self.store.importOfficial(result) { self.status = error }
                else { self.status = "已同步淘宝待取清单"; self.needsLogin = false }
            } else {
                self.needsLogin = result.state == "login_required"
                self.status = self.needsLogin ? "请到“我的 → 设置”登录淘宝" : "未完整读取，原有包裹已保留"
            }
        }.store(in: &subscriptions)
        session.$hasError.sink { [weak self] failed in
            guard let self, failed, self.active else { return }
            self.finish()
            self.needsLogin = self.session.status.contains("登录")
            self.status = self.needsLogin ? "请到“我的 → 设置”登录淘宝" : "自动刷新未完成，可下拉重试"
        }.store(in: &subscriptions)
    }

    func setActive(_ value: Bool) {
        active = value
        timer?.invalidate()
        timer = nil
        guard value else {
            if isRefreshing { lastAttempt = nil }
            session.stop(); finish(); return
        }
        guard store.autoSyncEnabled else { session.stop(); finish(); status = "自动刷新已关闭，可下拉刷新"; return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh(force: Bool = false) {
        guard active, !isRefreshing else { return }
        guard force || (store.autoSyncEnabled && !needsLogin) else { return }
        guard force || (lastAttempt.map { Date().timeIntervalSince($0) >= 60 } ?? true) else { return }
        lastAttempt = Date()
        needsLogin = false
        isRefreshing = true
        status = "正在自动检查待取包裹…"
        session.load(OfficialPickupSession.parcels)
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 40_000_000_000) } catch { return }
            guard let self, self.isRefreshing else { return }
            self.session.stop()
            self.finish()
            self.status = "本次刷新超时，原有包裹已保留"
        }
    }

    func refreshAndWait() async {
        refresh(force: true)
        while isRefreshing {
            do { try await Task.sleep(nanoseconds: 150_000_000) } catch { return }
        }
    }

    private func finish() {
        isRefreshing = false
        watchdog?.cancel()
        watchdog = nil
    }
}
