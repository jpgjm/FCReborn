//
// BLEWaitingView.swift
// FCReborn
//

import SwiftUI

struct BLEWaitingView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var coordinator: TransferCoordinator

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: state.mode == .send ? "antenna.radiowaves.left.and.right" : "dot.radiowaves.left.and.right")
                .font(.system(size: 72))
                .foregroundStyle(.blue)
                .symbolEffect(.pulse, options: .repeating)

            VStack(spacing: 6) {
                Text(state.mode == .send ? "相手の接続を待っています" : "相手を探しています")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("相手 (Android) の Flying Carpet を先に起動して、\n同じモード (\(state.mode == .send ? "受信" : "送信")) を選択してください")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            LogView()
                .frame(maxHeight: 180)

            Button("キャンセル") {
                coordinator.cancelAll()
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}
