//
// FCRebornApp.swift
// FCReborn
//
// FlyingCarpet 互換のファイル送受信アプリ (iOS 26 対応版)。
// - BLE でネゴシエーション
// - Wi-Fi は手動接続 (iOS 26 の NEHotspotConfiguration バグと無署名 IPA 制約への対応)
// - TCP + AES-256-GCM でファイル転送
//

import SwiftUI

@main
struct FCRebornApp: App {

    @StateObject private var state: AppState
    @StateObject private var coordinator: TransferCoordinator

    init() {
        let s = AppState()
        _state = StateObject(wrappedValue: s)
        _coordinator = StateObject(wrappedValue: TransferCoordinator(state: s))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .environmentObject(coordinator)
        }
    }
}
