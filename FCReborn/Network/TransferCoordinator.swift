//
// TransferCoordinator.swift
// FCReborn
//
// 転送全体のフローを統括する。SwiftUI View から呼ばれる公開 API は:
//   - startSendFlow() : Send モード開始 (BLE peripheral)
//   - startReceiveFlow() : Receive モード開始 (BLE central)
//   - proceedAfterWiFiJoin() : ユーザーが手動で Wi-Fi 参加したあと呼ぶ
//   - cancelAll() : キャンセル
//
// AppState.phase を更新し、SwiftUI 側の画面遷移を駆動する。
//

import Foundation
import CryptoKit
import Combine

@MainActor
final class TransferCoordinator: ObservableObject {

    private let state: AppState

    private var peripheralHandler: BLEPeripheral?
    private var centralHandler: BLECentral?

    private var currentSession: TransferSession?
    private var currentTask: Task<Void, Never>?

    init(state: AppState) {
        self.state = state
    }

    deinit {
        currentTask?.cancel()
    }

    // MARK: - Public API

    /// Send モード開始。ファイル選択 → 呼ばれる。
    func startSendFlow() {
        guard !state.pickedFiles.isEmpty else {
            state.log("送信するファイルが選択されていません")
            state.phase = .failed("送信するファイルが選択されていません")
            return
        }
        state.mode = .send
        state.phase = .bleWaiting
        state.log("Send モード開始 (BLE peripheral)")

        let handler = BLEPeripheral()
        handler.delegate = self
        peripheralHandler = handler
        handler.start()
    }

    /// Receive モード開始。
    func startReceiveFlow() {
        state.mode = .receive
        state.phase = .bleWaiting
        state.log("Receive モード開始 (BLE central)")

        let handler = BLECentral()
        handler.delegate = self
        centralHandler = handler
        handler.start()
    }

    /// ユーザーが Wi-Fi 参加を完了した後、View から呼ばれる。
    /// gateway IP を推定して TCP 接続 → 転送を開始する。
    func proceedAfterWiFiJoin() {
        state.phase = .connectingTCP
        state.log("TCP 接続開始")

        currentTask = Task { [weak self] in
            guard let self = self else { return }
            await self.runTransfer()
        }
    }

    /// キャンセル。
    func cancelAll() {
        currentTask?.cancel()
        currentTask = nil
        peripheralHandler?.stop()
        centralHandler?.stop()
        peripheralHandler = nil
        centralHandler = nil
        Task { [session = currentSession] in
            await session?.cancel()
        }
        currentSession = nil
        state.log("キャンセルしました")
        state.reset()
    }

    // MARK: - private

    private func runTransfer() async {
        // ★ 最初に Local Network Permission ダイアログを明示発火
        state.log("Local Network 権限プロンプトを表示 (初回のみ)")
        await LocalNetworkPrimer.prime { [weak self] msg in
            Task { @MainActor in self?.state.log(msg) }
        }

        // ★ v4: 全インターフェースをログ出力
        let allInterfaces = WiFiHelper.allInterfaceAddresses()
        state.log("全 IPv4 インターフェース:")
        for (name, ip) in allInterfaces {
            state.log("  \(name) = \(ip)")
        }

        // ★ v4: gateway 候補を PF_ROUTE + 定番リストで構築
        var candidates: [String] = []
        // Wi-Fi 参加直後は route table が反映されるまで少し待ってから取得
        for i in 0..<10 {
            candidates = WiFiHelper.gatewayCandidates()
            if !candidates.isEmpty { break }
            state.log("gateway 候補 未確定 (\(i+1)/10) 500ms 待機")
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        guard !candidates.isEmpty else {
            state.phase = .failed("gateway 候補が取得できません。Wi-Fi 参加ができているか確認してください。")
            return
        }
        state.log("gateway 候補一覧: \(candidates.joined(separator: ", "))")

        // 自機の IP もログ
        if let myIP = WiFiHelper.interfaceIPv4Address(name: "en0") {
            state.log("iPad Wi-Fi IP = \(myIP)")
        }

        let session = TransferSession()
        currentSession = session

        // Session の内部ログを画面に出す
        await session.setLogHandler { [weak self] msg in
            Task { @MainActor in self?.state.log(msg) }
        }

        // ★ v4: 複数 gateway 候補 × 15 回リトライで TCP 接続を試みる
        var connectedGateway: String? = nil
        outer: for attempt in 1...15 {
            for gw in candidates {
                do {
                    state.log("[試行\(attempt)] TCP → \(gw):\(FCProtocol.tcpPort)")
                    try await session.connect(gatewayIP: gw, timeoutSeconds: 4.0)
                    connectedGateway = gw
                    break outer
                } catch {
                    state.log("  → 失敗: \(error.localizedDescription)")
                }
            }
            if connectedGateway == nil {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        guard let gw = connectedGateway else {
            state.phase = .failed("すべての gateway 候補で TCP 接続に失敗。設定 > Wi-Fi の (i) から実際の「ルーター」の IP を確認してください。")
            return
        }
        state.log("TCP 接続成功 (gateway = \(gw))")

        // KDF
        let derived = KeyAndSSID.derive(from: state.password)
        let key = derived.key

        // ハンドシェイク
        do {
            try await session.confirmVersion()
            state.log("バージョン一致")
            try await session.confirmMode(state.mode)
            state.log("モード交渉 OK")
        } catch {
            state.phase = .failed(error.localizedDescription)
            return
        }

        state.phase = .transferring

        // 送信 or 受信
        if state.mode == .send {
            await runSend(session: session, key: key)
        } else {
            await runReceive(session: session, key: key)
        }
    }

    private func runSend(session: TransferSession, key: SymmetricKey) async {
        let files = state.pickedFiles
        state.totalFileCount = files.count
        do {
            try await session.writeU64(UInt64(files.count))
            for (i, url) in files.enumerated() {
                state.currentFileIndex = i + 1
                state.currentFileName = url.lastPathComponent
                state.progress = 0
                state.log("[\(i+1)/\(files.count)] 送信: \(url.lastPathComponent)")

                let sender = FileSender(session: session, key: key)
                try await sender.send(
                    fileURL: url,
                    relativeName: url.lastPathComponent
                ) { p in
                    Task { @MainActor in self.state.progress = p }
                }
                state.log("[\(i+1)/\(files.count)] 完了")
            }
            state.phase = .done
            state.log("すべての送信が完了")
        } catch {
            state.phase = .failed(error.localizedDescription)
        }
    }

    private func runReceive(session: TransferSession, key: SymmetricKey) async {
        do {
            let numFiles = try await session.readU64()
            state.totalFileCount = Int(numFiles)
            state.log("受信予定ファイル数: \(numFiles)")

            let dest = state.receiveDirectory
            for i in 0..<Int(numFiles) {
                state.currentFileIndex = i + 1
                state.progress = 0
                let isLast = (i == Int(numFiles) - 1)
                let receiver = FileReceiver(session: session, key: key, destinationDirectory: dest)
                _ = try await receiver.receive(
                    isLastFile: isLast,
                    onProgress: { p in
                        Task { @MainActor in self.state.progress = p }
                    },
                    onStart: { name in
                        Task { @MainActor in
                            self.state.currentFileName = name
                            self.state.log("[\(i+1)/\(numFiles)] 受信開始: \(name)")
                        }
                    }
                )
                state.log("[\(i+1)/\(numFiles)] 完了")
            }
            state.phase = .done
            state.log("すべての受信が完了。保存先: \(dest.path)")
        } catch {
            state.phase = .failed(error.localizedDescription)
        }
    }
}

// MARK: - BLEPeripheralDelegate (Send フロー)

extension TransferCoordinator: BLEPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: BLEPeripheral, log message: String) {
        Task { @MainActor in self.state.log("[BLE-P] \(message)") }
    }

    nonisolated func peripheral(_ peripheral: BLEPeripheral, didExchangeInfoPeerOS os: String, ssid: String, password: String) {
        Task { @MainActor in
            self.state.peer = Peer(osString: os)
            self.state.ssid = ssid
            self.state.password = password
            self.state.log("BLE ハンドシェイク完了。peer=\(self.state.peer.displayName), SSID=\(ssid)")
            self.state.phase = .awaitingWiFi
        }
    }

    nonisolated func peripheral(_ peripheral: BLEPeripheral, didFailWith error: Error) {
        Task { @MainActor in
            self.state.log("[BLE-P] エラー: \(error.localizedDescription)")
            self.state.phase = .failed(error.localizedDescription)
        }
    }
}

// MARK: - BLECentralDelegate (Receive フロー)

extension TransferCoordinator: BLECentralDelegate {
    nonisolated func central(_ central: BLECentral, log message: String) {
        Task { @MainActor in self.state.log("[BLE-C] \(message)") }
    }

    nonisolated func central(_ central: BLECentral, didExchangeInfoPeerOS os: String, ssid: String, password: String) {
        Task { @MainActor in
            self.state.peer = Peer(osString: os)
            self.state.ssid = ssid
            self.state.password = password
            self.state.log("BLE ハンドシェイク完了。peer=\(self.state.peer.displayName), SSID=\(ssid)")
            self.state.phase = .awaitingWiFi
        }
    }

    nonisolated func central(_ central: BLECentral, didFailWith error: Error) {
        Task { @MainActor in
            self.state.log("[BLE-C] エラー: \(error.localizedDescription)")
            self.state.phase = .failed(error.localizedDescription)
        }
    }
}
