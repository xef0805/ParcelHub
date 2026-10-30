import Foundation
import Combine
import Network

@MainActor
final class NetworkStatus: ObservableObject {
    @Published private(set) var isOffline = false
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "ParcelHub.network-status")
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let offline = path.status != .satisfied
            Task { @MainActor [weak self] in self?.isOffline = offline }
        }
        monitor.start(queue: queue)
    }
    deinit { monitor.cancel() }
}

/// 仅在 App 前台刷新已接入的官方网页；不申请短信、定位或后台常驻权限。
@MainActor
final class OfficialSyncController: ObservableObject {
    let session = OfficialPickupSession()
    @Published private(set) var isRefreshing = false
    @Published private(set) var status = "正在等待刷新"
    @Published private(set) var needsLogin = false
    @Published private(set) var isAuthenticating = false
    private let store: ParcelStore
    private let network: NetworkStatus
    private var subscriptions = Set<AnyCancellable>()
    private var timer: Timer?
    private var active = false
    private var lastAttempt: Date?
    private var watchdog: Task<Void, Never>?

    init(store: ParcelStore, network: NetworkStatus) {
        self.store = store
        self.network = network
        network.$isOffline.removeDuplicates().dropFirst().sink { [weak self] offline in
            guard let self else { return }
            if offline {
                self.session.stop(); self.finish(); self.status = AppServiceIssue.offline.message
            } else if self.active && self.store.autoSyncEnabled && !self.needsLogin {
                self.refresh(force: true)
            } else if self.needsLogin { self.status = AppServiceIssue.login.message }
            else if !self.store.autoSyncEnabled { self.status = "自动刷新已关闭，可下拉刷新" }
        }.store(in: &subscriptions)
        session.$readResult.sink { [weak self] result in
            guard let self, self.active, let result else { return }
            self.finish()
            if result.state == "ready" {
                let previousIDs = Set(self.store.parcels.map(\.id))
                if let error = self.store.importOfficial(result) { self.status = error }
                else {
                    let added = self.store.pending.filter { !previousIDs.contains($0.id) }.count
                    self.status = added > 0 ? "已同步淘宝 · 新增 \(added) 件到站包裹" : "已同步淘宝待取清单"
                    self.needsLogin = false
                }
            } else {
                self.needsLogin = result.state == "login_required"
                self.status = self.needsLogin ? AppServiceIssue.login.message
                    : result.state == "filtered_empty" ? AppServiceIssue.phoneFilter.message : AppServiceIssue.incomplete.message
            }
        }.store(in: &subscriptions)
        session.$hasError.sink { [weak self] failed in
            guard let self, failed, self.active else { return }
            self.finish()
            if self.session.failure == .login { self.needsLogin = true }
            self.status = self.session.status
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
        guard !isAuthenticating else { return }
        guard store.autoSyncEnabled else { session.stop(); finish(); status = "自动刷新已关闭，可下拉刷新"; return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh(force: Bool = false) {
        guard active, !isRefreshing, !isAuthenticating else { return }
        guard !network.isOffline else { status = AppServiceIssue.offline.message; return }
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
            self.status = AppServiceIssue.timeout.message
        }
    }

    func refreshAndWait() async {
        refresh(force: true)
        while isRefreshing {
            do { try await Task.sleep(nanoseconds: 150_000_000) } catch { return }
        }
    }

    func beginAuthentication() {
        isAuthenticating = true
        timer?.invalidate(); timer = nil
        session.stop(); session.load(URL(string: "about:blank")!); finish()
        needsLogin = true
        status = "请在此页重新登录淘宝，完成后将返回取件页面。"
    }

    func endAuthentication() {
        isAuthenticating = false
        lastAttempt = nil
        needsLogin = false
        setActive(active)
    }

    private func finish() {
        isRefreshing = false
        watchdog?.cancel()
        watchdog = nil
    }
}
