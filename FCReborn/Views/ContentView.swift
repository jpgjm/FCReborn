//
// ContentView.swift
// FCReborn
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state.phase {
        case .home:
            HomeView()
        case .pickingFiles:
            SendModeView()
        case .bleWaiting:
            BLEWaitingView()
        case .awaitingWiFi:
            WiFiPromptView()
        case .connectingTCP:
            TransferProgressView()
        case .transferring:
            TransferProgressView()
        case .done:
            DoneView()
        case .failed(let msg):
            FailedView(message: msg)
        }
    }

    private var navigationTitle: String {
        switch state.phase {
        case .home: return "FCReborn"
        case .pickingFiles: return "送信ファイル選択"
        case .bleWaiting: return "Bluetooth 接続"
        case .awaitingWiFi: return "Wi-Fi 手動接続"
        case .connectingTCP, .transferring: return "転送中"
        case .done: return "完了"
        case .failed: return "エラー"
        }
    }
}
