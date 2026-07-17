//
// TransferSession.swift
// FCReborn
//
// FlyingCarpet プロトコルの TCP 部分を扱うセッションクラス。
// - iOS は常に Wi-Fi client (相手のホットスポットに接続する) なので、
//   ゲートウェイ IP の port 3290 に NWConnection で TCP 接続するだけ。
// - u64 (Big Endian) の read/write、可変長バイト列の read/write を提供する。
// - AsyncStream 的な同期的 API を用意 (async/await ベース)。
//

import Foundation
import Network

enum TransferSessionError: Error, LocalizedError {
    case connectionFailed(String)
    case unexpectedEOF
    case protocolMismatch(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let s): return "TCP 接続失敗: \(s)"
        case .unexpectedEOF: return "予期しない EOF (接続が切れた)"
        case .protocolMismatch(let s): return "プロトコル不一致: \(s)"
        case .cancelled: return "ユーザーによりキャンセル"
        }
    }
}

actor TransferSession {

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "dev.local.fcreborn.tcp")
    private var readBuffer = Data()

    /// 詳細な NWConnection ログをこのハンドラ経由で通知する (nil の場合は print のみ)。
    private var logHandler: ((String) -> Void)?

    func setLogHandler(_ handler: @escaping (String) -> Void) {
        self.logHandler = handler
    }

    private func log(_ message: String) {
        print(message)
        logHandler?(message)
    }

    // MARK: - 接続

    /// gateway IP (相手のホットスポット gateway) の port 3290 に TCP 接続する。
    /// タイムアウトは指定した秒数 (デフォルト 15秒)。
    ///
    /// iOS 26 対策:
    ///   - requiredInterfaceType = .wifi にして cellular へのフォールバックを禁じる
    ///   - TCP connectionTimeout を短めに (3秒) → リトライを効かせる
    ///   - pathUpdateHandler / viabilityUpdateHandler で詳細ログ
    func connect(gatewayIP: String, timeoutSeconds: TimeInterval = 15.0) async throws {
        log("[NW] connect(gateway=\(gatewayIP):\(FCProtocol.tcpPort), timeout=\(timeoutSeconds)s) 開始")
        let host = NWEndpoint.Host(gatewayIP)
        let port = NWEndpoint.Port(rawValue: FCProtocol.tcpPort)!
        let params = NWParameters.tcp

        // ★ Wi-Fi インターフェースを必須指定 (cellular フォールバック禁止)
        params.requiredInterfaceType = .wifi

        // Wi-Fi Assist のような自動切替も禁じる
        params.prohibitExpensivePaths = false
        params.prohibitConstrainedPaths = false

        // TCP のタイムアウトを短くしてリトライを効かせる
        if let tcpOpts = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcpOpts.connectionTimeout = 5
            tcpOpts.noDelay = true
            tcpOpts.enableKeepalive = true
        }

        let conn = NWConnection(host: host, port: port, using: params)
        self.connection = conn

        // 詳細ログ用ハンドラ
        conn.pathUpdateHandler = { [weak self] path in
            let ifs = path.availableInterfaces.map { "\($0.name)(\($0.type))" }.joined(separator: ",")
            let reason: String
            if #available(iOS 14.2, *) {
                reason = "unsatisfiedReason=\(path.unsatisfiedReason)"
            } else {
                reason = ""
            }
            Task { await self?.log("[NW] path: status=\(path.status) constrained=\(path.isConstrained) expensive=\(path.isExpensive) interfaces=[\(ifs)] \(reason)") }
        }
        conn.viabilityUpdateHandler = { [weak self] viable in
            Task { await self?.log("[NW] viability: \(viable)") }
        }
        conn.betterPathUpdateHandler = { [weak self] better in
            Task { await self?.log("[NW] betterPath: \(better)") }
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var didResume = false
            let resumeOnce: (Result<Void, Error>) -> Void = { result in
                guard !didResume else { return }
                didResume = true
                switch result {
                case .success: cont.resume()
                case .failure(let e): cont.resume(throwing: e)
                }
            }

            conn.stateUpdateHandler = { [weak self] state in
                Task { await self?.log("[NW] state: \(state)") }
                switch state {
                case .ready:
                    resumeOnce(.success(()))
                case .failed(let err):
                    resumeOnce(.failure(TransferSessionError.connectionFailed(err.localizedDescription)))
                case .waiting(let err):
                    // waiting は「一時的に繋がらないが待っている」状態。iOS 26 でここでハマることが多い。
                    // タイムアウトまで待つが、ここで即fail扱いにするとリトライが早く回る。
                    Task { await self?.log("[NW] waiting: \(err.localizedDescription)") }
                case .cancelled:
                    resumeOnce(.failure(TransferSessionError.cancelled))
                default:
                    break
                }
            }
            conn.start(queue: queue)

            // タイムアウト
            queue.asyncAfter(deadline: .now() + timeoutSeconds) {
                resumeOnce(.failure(TransferSessionError.connectionFailed("timeout")))
            }
        }
    }

    func cancel() {
        connection?.cancel()
        connection = nil
    }

    // MARK: - 低レベル IO

    /// 任意サイズの Data を送信する (全部書き込むまで待つ)。
    func writeAll(_ data: Data) async throws {
        guard let conn = connection else { throw TransferSessionError.connectionFailed("connection is nil") }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed({ err in
                if let e = err {
                    cont.resume(throwing: TransferSessionError.connectionFailed(e.localizedDescription))
                } else {
                    cont.resume()
                }
            }))
        }
    }

    /// 指定バイト数を読み終わるまで待つ (read_exact 相当)。
    func readExact(_ n: Int) async throws -> Data {
        while readBuffer.count < n {
            let chunk = try await receiveOnce()
            if chunk.isEmpty { throw TransferSessionError.unexpectedEOF }
            readBuffer.append(chunk)
        }
        let head = readBuffer.prefix(n)
        readBuffer.removeFirst(n)
        return Data(head)
    }

    private func receiveOnce() async throws -> Data {
        guard let conn = connection else { throw TransferSessionError.connectionFailed("connection is nil") }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let error = error {
                    cont.resume(throwing: TransferSessionError.connectionFailed(error.localizedDescription))
                    return
                }
                if let data = data, !data.isEmpty {
                    cont.resume(returning: data)
                    return
                }
                if isComplete {
                    cont.resume(returning: Data())
                    return
                }
                cont.resume(returning: Data())
            }
        }
    }

    // MARK: - u64 helpers

    func writeU64(_ v: UInt64) async throws {
        try await writeAll(v.bigEndianBytes)
    }

    func readU64() async throws -> UInt64 {
        let data = try await readExact(8)
        guard let v = UInt64.fromBigEndian(data) else {
            throw TransferSessionError.protocolMismatch("Bad u64")
        }
        return v
    }

    // MARK: - ハンドシェイク

    /// iOS は常に Wi-Fi client なので、Rust の WifiClient 分岐 (先に自分のバージョンを書き込む) と同じ順序。
    func confirmVersion() async throws {
        try await writeU64(FCProtocol.majorVersion)
        let peerVersion = try await readU64()

        if peerVersion < FCProtocol.majorVersion {
            // 自分の方が新しい → 自分が互換性判定する
            // FlyingCarpet の是川ルール: peer >= 8 なら互換
            if peerVersion >= 8 {
                try await writeU64(1)
            } else {
                try await writeU64(0)
                throw TransferSessionError.protocolMismatch(
                    "相手 v\(peerVersion) は非対応。相手側の Flying Carpet を最新版に更新してください。"
                )
            }
        } else if peerVersion > FCProtocol.majorVersion {
            // 相手の方が新しい → 相手が判定する
            let ok = try await readU64()
            if ok == 0 {
                throw TransferSessionError.protocolMismatch(
                    "相手 v\(peerVersion) が非互換と判定 (このアプリを更新してください)"
                )
            }
        } else {
            // 完全一致 → 追加通信なし
        }
    }

    /// iOS は WifiClient なので、まず自分の mode を送り、相手の判定 (1=OK / 0=NG) を待つ。
    func confirmMode(_ mode: TransferMode) async throws {
        try await writeU64(mode.wireValue)
        let ok = try await readU64()
        if ok != 1 {
            throw TransferSessionError.protocolMismatch(
                "両端が同じモード (\(mode == .send ? "送信" : "受信")) を選択している"
            )
        }
    }
}
