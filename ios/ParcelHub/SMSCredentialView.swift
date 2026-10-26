import SwiftUI
import UIKit

struct SMSCredentialListView: View {
    var station: String? = nil
    @EnvironmentObject private var store: ParcelStore
    @Environment(\.dismiss) private var dismiss
    private var records: [Parcel] {
        store.smsParcels.filter { $0.isPending && (station == nil || $0.station == station || $0.pickupCredentials.contains { $0.station == station }) }
    }
    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty { ContentUnavailableView("暂无待取短信", systemImage: "message") }
                else if records.count == 1 { SMSCredentialView(parcelID: records[0].id) }
                else {
                    List(records) { parcel in
                        NavigationLink { SMSCredentialView(parcelID: parcel.id) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(parcel.title).font(.headline)
                                Text(parcel.station).font(.caption).foregroundStyle(.secondary)
                                Text(parcel.pickupCode).font(.system(.body, design: .monospaced))
                            }.padding(.vertical, 6)
                        }
                    }
                }
            }.navigationTitle(records.count == 1 ? "" : "短信身份码").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if records.count != 1 { ToolbarItem(placement: .topBarLeading) { SMSBackButton { dismiss() } } }
                }
        }
    }
}

struct SMSCredentialView: View {
    let parcelID: UUID
    @EnvironmentObject private var store: ParcelStore
    @Environment(\.dismiss) private var dismiss
    private var parcel: Parcel? { store.parcels.first { $0.id == parcelID && $0.deletedAt == nil } }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color(uiColor: .systemBackground).ignoresSafeArea()
                ScrollView {
                    if let parcel, let original = parcel.smsOriginal {
                        VStack(spacing: 0) {
                            VStack(spacing: 9) {
                                BrandMark(asset: CarrierBrand.asset(for: parcel.carrier) ?? "", fallback: "message.fill", label: parcel.smsSender ?? "取件通知", size: 64)
                                Text(parcel.smsSender ?? (parcel.carrier.isEmpty ? "取件通知" : parcel.carrier))
                                    .font(.system(size: 22, weight: .semibold)).padding(.horizontal, 16).padding(.vertical, 7)
                                    .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                            }.padding(.top, 18)
                            VStack(spacing: 4) {
                                Text("信息")
                                Text(messageTime(parcel.smsImportedAt ?? parcel.addedAt))
                            }.font(.system(size: 14)).foregroundStyle(.secondary).padding(.top, 30).padding(.bottom, 24)
                            HStack(alignment: .top) {
                                SMSMessageText(text: original).padding(16)
                                    .frame(maxWidth: geometry.size.width * 0.76, alignment: .leading)
                                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 23))
                                    .overlay(alignment: .bottomLeading) {
                                        SMSBubbleTail().fill(Color(uiColor: .secondarySystemBackground)).frame(width: 16, height: 14).offset(x: 12, y: 6)
                                    }
                                Spacer(minLength: 22)
                            }
                        }.padding(.horizontal, 16).padding(.bottom, 32)
                    } else { ContentUnavailableView("未保存短信原文", systemImage: "message").padding(.top, 100) }
                }
                SMSBackButton { dismiss() }.padding(.leading, 16).padding(.top, 16)
            }
        }.navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
    }
    private func messageTime(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) { return time }
        if Calendar.current.isDateInYesterday(date) { return "昨天 " + time }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct SMSBackButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left").font(.system(size: 24, weight: .semibold)).foregroundStyle(.primary)
                .frame(width: 48, height: 48).background(Color(uiColor: .secondarySystemBackground), in: Circle())
        }.buttonStyle(PressFeedbackStyle()).accessibilityLabel("返回")
    }
}

private struct SMSMessageText: UIViewRepresentable {
    let text: String
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false; view.isSelectable = true; view.isScrollEnabled = false
        view.backgroundColor = .clear; view.textContainerInset = .zero; view.textContainer.lineFragmentPadding = 0
        view.dataDetectorTypes = [.link, .address]
        view.font = .systemFont(ofSize: 20); view.textColor = .label
        view.linkTextAttributes = [.foregroundColor: UIColor.systemBlue, .underlineStyle: NSUnderlineStyle.single.rawValue]
        return view
    }
    func updateUIView(_ uiView: UITextView, context: Context) { if uiView.text != text { uiView.text = text } }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return CGSize(width: width, height: uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
    }
}

private struct SMSBubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: .zero); path.addLine(to: CGPoint(x: rect.maxX, y: 0)); path.addLine(to: CGPoint(x: 0, y: rect.maxY)); path.closeSubpath()
        return path
    }
}
