//
// AppState.swift
// FCReborn
//
// SwiftUI View 全体で共有するアプリ状態。
// - 転送モード / 現在のフェーズ
// - BLE で交換した SSID/パスワード
// - 進捗と対話的なログ
// をまとめて保持する。
//

import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {

    /// 転送全体のフェーズ。UI 遷移のトリガーになる。
    enum Phase: Equatable {
        /// 初期画面 (Send/Receive を選ぶ)。
        case home
        /// Send モードで転送するファイルを選ぶ画面。
        case pickingFiles
        /// BLE で相手を待っている / 相手を探している。
        case bleWaiting
        /// BLE ハンドシェイクが完了し、Wi-Fi 情報が確定。
        /// ユーザーに手動で Wi-Fi 参加してもらうフェーズ。
        case awaitingWiFi
        /// Wi-Fi 参加後、TCP 接続を試みている。
        case connectingTCP
        /// 実際にファイルを転送中。
        case transferring
        /// 転送完了。
        case done
        /// エラー発生。
        case failed(String)
    }

    @Published var phase: Phase = .home
    @Published var mode: TransferMode = .send

    /// BLE でハンドシェイクした相手の OS。
    @Published var peer: Peer = .unknown

    /// BLE でハンドシェイクした Wi-Fi の SSID とパスワード。
    /// - .send モードでは iOS が生成する。
    /// - .receive モードでは相手が生成したものを受け取る。
    @Published var ssid: String = ""
    @Published var password: String = ""

    /// 選択されたファイル URL (Send モード用)。複数対応。
    @Published var pickedFiles: [URL] = []

    /// 進捗ログ (画面下部に表示)。
    @Published var logs: [String] = []

    /// 転送進捗率 (0.0 - 1.0)。
    @Published var progress: Double = 0.0

    /// 現在転送中のファイル名。
    @Published var currentFileName: String = ""

    /// ファイル数と現在のインデックス。
    @Published var currentFileIndex: Int = 0
    @Published var totalFileCount: Int = 0

    init() {
        // v3 で追加: 起動直後に必ずビルド識別子をログに刻む。
        // これで Sideloadly 経由で古い IPA が入っている等の混乱を防げる。
        log("========================================")
        log("FCReborn \(AppVersion.buildTag) 起動")
        log("========================================")
    }

    /// 受信ファイルの保存先ディレクトリ (Documents/inbox)。
    var receiveDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let inbox = docs.appendingPathComponent("inbox", isDirectory: true)
        if !FileManager.default.fileExists(atPath: inbox.path) {
            try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        }
        return inbox
    }

    func log(_ message: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts.suffix(8).prefix(8))] \(message)"
        logs.append(line)
        // 溜まりすぎたら古いのを捨てる
        if logs.count > 200 {
            logs.removeFirst(logs.count - 200)
        }
        print(line)
    }

    func reset() {
        phase = .home
        peer = .unknown
        ssid = ""
        password = ""
        pickedFiles = []
        progress = 0
        currentFileName = ""
        currentFileIndex = 0
        totalFileCount = 0
        // ログは残す (デバッグ用)。必要なら logs = [] を呼ぶ側で。
    }
}
