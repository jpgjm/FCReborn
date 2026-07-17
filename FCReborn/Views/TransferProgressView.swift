//
// TransferProgressView.swift
// FCReborn
//

import SwiftUI

struct TransferProgressView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var coordinator: TransferCoordinator

    var body: some View {
        VStack(spacing: 24) {

            VStack(spacing: 6) {
                Text(state.mode == .send ? "送信中" : "受信中")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("相手: \(state.peer.displayName)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("[\(state.currentFileIndex)/\(state.totalFileCount)]")
                        .font(.system(.body, design: .monospaced))
                    Text(state.currentFileName.isEmpty ? "準備中…" : state.currentFileName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                ProgressView(value: state.progress)
                    .progressViewStyle(.linear)
                Text("\(Int(state.progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            LogView()

            Button("キャンセル") {
                coordinator.cancelAll()
            }
            .buttonStyle(.bordered)
            .foregroundStyle(.red)
        }
        .padding()
    }
}
