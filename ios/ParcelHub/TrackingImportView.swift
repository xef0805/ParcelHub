import SwiftUI
import UIKit

struct TrackingParcelCard: View {
    let parcel: Parcel
    @EnvironmentObject private var clipboard: ClipboardImportController
    @State private var addingSMS = false
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(parcel.title).font(.headline)
                    HStack(spacing: 5) {
                        Text(parcel.trackingNumber).font(.system(.subheadline, design: .monospaced)).textSelection(.enabled)
                        Button {
                            UIPasteboard.general.string = parcel.trackingNumber
                            clipboard.ignoreCurrentChange(); copied = true
                        } label: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.caption)
                                .frame(minWidth: 36, minHeight: 36).contentShape(Rectangle())
                        }.accessibilityLabel("复制运单号")
                    }
                }
                Spacer(minLength: 8)
                Text("待确认").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("补充取件短信") { addingSMS = true }
                Spacer()

            }.font(.caption)
        }.padding(18).background(Palette.card, in: RoundedRectangle(cornerRadius: 20)).buttonStyle(PressFeedbackStyle())
            .sheet(isPresented: $addingSMS) { AddParcelView(initialTrackingNumber: parcel.trackingNumber, initialCarrier: parcel.carrier) }
    }
}
