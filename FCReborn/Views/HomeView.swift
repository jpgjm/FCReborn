//
// HomeView.swift
// FCReborn
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var coordinator: TransferCoordinator

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Text("FCReborn")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Flying Carpet 互換 (iOS 26 対応版)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(spacing: 16) {
                Button {
                    state.phase = .pickingFiles
                } label: {
                    Label("送信 (Send)", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    coordinator.startReceiveFlow()
                } label: {
                    Label("受信 (Receive)", systemImage: "tray.and.arrow.down.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                Text("使い方 (iOS 26 対応)")
                    .font(.headline)
                Text("• 相手 (Android) の Flying Carpet を先に起動してください")
                Text("• Bluetooth と Wi-Fi を ON にしてください")
                Text("• Wi-Fi 参加はこのアプリでは自動化できないため、案内画面で手動で参加してください")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }
}
