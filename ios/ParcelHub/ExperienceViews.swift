import SwiftUI
import UIKit

@MainActor
enum AppFeedback {
    static var enabled: Bool { UserDefaults.standard.object(forKey: "parcelhub.haptics.v1") as? Bool ?? true }
    static func success() { if enabled { UINotificationFeedbackGenerator().notificationOccurred(.success) } }
    static func selection() { if enabled { UISelectionFeedbackGenerator().selectionChanged() } }
}

struct LastSuccessfulSyncView: View {
    let date: Date?
    @Environment(\.locale) private var locale
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            HStack(spacing: 4) {
                Image(systemName: "clock")
                Text("上次成功同步：")
                if let date {
                    Text(verbatim: relative(date, now: timeline.date))
                } else { Text("尚未同步") }
            }.font(.caption2).foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
        }
    }
    private func relative(_ date: Date, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: min(date, now), relativeTo: now)
    }
}

struct ParcelNoteView: View {
    let parcel: Parcel
    @EnvironmentObject private var store: ParcelStore
    @Environment(\.dismiss) private var dismiss
    @State private var note: String
    init(parcel: Parcel) { self.parcel = parcel; _note = State(initialValue: parcel.note ?? "") }
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(parcel.title).foregroundStyle(.secondary) }
                Section {
                    TextField("例如：鞋子、帮家人取", text: $note, axis: .vertical).lineLimit(3...5)
                        .onChange(of: note) { _, value in if value.count > 120 { note = String(value.prefix(120)) } }
                } header: { Text("包裹备注") } footer: { Text("最多120字，自动同步不会覆盖。") }
            }.navigationTitle("包裹备注").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { store.saveNote(note, for: parcel.id); dismiss() } }
                }
        }
    }
}

struct StationEditorView: View {
    let station: String
    @EnvironmentObject private var store: ParcelStore
    @Environment(\.dismiss) private var dismiss
    @State private var alias = ""
    @State private var pinned = false
    var body: some View {
        NavigationStack {
            Form {
                Section("原地点") { Text(station).foregroundStyle(.secondary) }
                Section {
                    TextField("显示名称（可选）", text: $alias)
                        .onChange(of: alias) { _, value in if value.count > 40 { alias = String(value.prefix(40)) } }
                    Toggle("置顶此地点", isOn: $pinned)
                } footer: { Text("只修改显示名称，不影响包裹同步和身份码绑定。") }
            }.navigationTitle("地点管理").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { store.saveStation(station, alias: alias, pinned: pinned); dismiss() }
                    }
                }.onAppear { alias = store.stationPreferences[station]?.alias ?? ""; pinned = store.stationPreferences[station]?.pinned ?? false }
        }
    }
}

struct StationSelection: Identifiable { let id: String }
struct StationManagementView: View {
    @EnvironmentObject private var store: ParcelStore
    @State private var selected: StationSelection?
    var body: some View {
        List {
            let stations = store.sortedStations(store.parcels.filter { !$0.isDemo && $0.deletedAt == nil }.map(\.station)
                + Array(store.stationPreferences.keys) + Array(store.stationCredentials.keys)).filter { !$0.isEmpty }
            if stations.isEmpty { Text("有包裹地点后，可在这里设置。").foregroundStyle(.secondary) }
            ForEach(stations, id: \.self) { station in
                Button { selected = StationSelection(id: station) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.stationName(station)).foregroundStyle(.primary)
                            if store.stationName(station) != station { Text(station).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        if store.stationPreferences[station]?.pinned == true { Image(systemName: "pin.fill") }
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }.navigationTitle("地点管理").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selected) { StationEditorView(station: $0.id) }
    }
}

struct BatchCollectionView: View {
    let station: String
    @EnvironmentObject private var store: ParcelStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected = Set<UUID>()
    private var rows: [Parcel] { store.pending.filter { $0.station == station } }
    private var validSelection: Set<UUID> { selected.intersection(Set(rows.map(\.id))) }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(rows) { parcel in
                        Button {
                            if selected.contains(parcel.id) { selected.remove(parcel.id) } else { selected.insert(parcel.id) }
                            AppFeedback.selection()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selected.contains(parcel.id) ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(parcel.title).foregroundStyle(.primary)
                                    Text(parcel.pickupCode).font(.headline.monospaced())
                                    if let note = parcel.note, !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary) }
                                }
                            }.padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.accessibilityAddTraits(selected.contains(parcel.id) ? [.isSelected] : [])
                    }
                } header: { Text(store.stationName(station)) } footer: { Text("勾选实际取走的包裹，完成后可撤销。") }
                if rows.isEmpty { Text("此地点暂无待取包裹") }
            }.navigationTitle("批量取件").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("标记已取（\(validSelection.count)）") { store.collect(validSelection, at: station); dismiss() }
                            .disabled(validSelection.isEmpty)
                    }
                }
        }
    }
}

// 独立的非主窗口覆盖同一场景中的 sheet/全屏官方网页，避免只遮住首页。
struct PrivacyShield: UIViewRepresentable {
    var enabled: Bool
    final class Anchor: UIView {
        var didMove: ((UIWindowScene?) -> Void)?
        override func didMoveToWindow() { super.didMoveToWindow(); didMove?(window?.windowScene) }
    }
    @MainActor final class Coordinator: NSObject {
        var enabled = true
        weak var scene: UIWindowScene?
        var cover: UIWindow?
        override init() {
            super.init()
            NotificationCenter.default.addObserver(self, selector: #selector(hideContent), name: UIApplication.willResignActiveNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(showContent), name: UIApplication.didBecomeActiveNotification, object: nil)
        }
        @objc func hideContent() {
            guard enabled, cover == nil, let scene else { return }
            let window = UIWindow(windowScene: scene)
            window.windowLevel = .alert + 1
            window.isUserInteractionEnabled = false
            let controller = UIViewController()
            controller.view.backgroundColor = .systemGroupedBackground
            let label = UILabel()
            label.text = UserDefaults.standard.string(forKey: "parcelhub.language.v1") == "en" ? "Tutu Pickup" : "涂涂取件"
            label.font = .preferredFont(forTextStyle: .title2)
            label.textColor = .secondaryLabel
            label.translatesAutoresizingMaskIntoConstraints = false
            controller.view.addSubview(label)
            NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: controller.view.centerXAnchor), label.centerYAnchor.constraint(equalTo: controller.view.centerYAnchor)])
            window.rootViewController = controller
            cover = window
            window.isHidden = false
        }
        @objc func showContent() { cover?.isHidden = true; cover = nil }
        func update(_ enabled: Bool) {
            self.enabled = enabled
            if !enabled || UIApplication.shared.applicationState == .active { showContent() }
            else { hideContent() }
        }
        func stop() { NotificationCenter.default.removeObserver(self); showContent() }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> Anchor {
        let view = Anchor()
        view.didMove = { [weak coordinator = context.coordinator] scene in coordinator?.scene = scene; coordinator?.update(coordinator?.enabled ?? true) }
        return view
    }
    func updateUIView(_ view: Anchor, context: Context) { context.coordinator.update(enabled) }
    static func dismantleUIView(_ view: Anchor, coordinator: Coordinator) { coordinator.stop(); view.didMove = nil }
}
