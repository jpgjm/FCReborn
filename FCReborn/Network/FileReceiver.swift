//
// FileReceiver.swift
// FCReborn
//
// Rust core/src/receiving.rs 互換の受信処理。
//
// 1ファイル分の流れ (sender 側と対称):
//   [R] filename length (u64)
//   [R] filename bytes (utf-8)
//   [R] file size (u64)
//   check_for_file:
//     if 同名同サイズが既にある:
//       [W] 1 (u64)
//       [R] peer's SHA-256 (32 bytes)
//       hashes match ? → [W] 1 (skip) : [W] 0 (transfer)
//     else:
//       [W] 0 (u64)
//       (Rust 側は 1秒スリープ後に転送開始)
//   loop:
//     [R] wire size (u64)  ← 0 なら終端
//     [R] wire (nonce||ct||tag)
//     decrypt → append to file
//   [W] 1 (u64) 完了通知
//   [R] 1 (u64) 二重確認 (最終ファイルはタイムアウトあり)
//

import Foundation
import CryptoKit

enum FileReceiverError: Error, LocalizedError {
    case badFilename(String)
    case ioError(String)
    case decryptionFailed

    var errorDescription: String? {
        switch self {
        case .badFilename(let s): return "不正なファイル名: \(s)"
        case .ioError(let s): return "IO エラー: \(s)"
        case .decryptionFailed: return "復号に失敗 (鍵不一致か改ざん)"
        }
    }
}

struct FileReceiver {

    let session: TransferSession
    let key: SymmetricKey
    let destinationDirectory: URL

    /// - Parameters:
    ///   - isLastFile: 最後のファイルなら二重確認 read にタイムアウトを付ける (Rust 側もそうしている)。
    /// - Returns: 受信したファイルの保存先 URL。スキップされた場合は nil。
    @discardableResult
    func receive(isLastFile: Bool, onProgress: @escaping (Double) -> Void, onStart: @escaping (String) -> Void) async throws -> URL? {
        // filename
        let nameLen = try await session.readU64()
        // 非常識な長さを弾く (16MB もあり得ない)
        if nameLen == 0 || nameLen > 16 * 1024 * 1024 {
            throw FileReceiverError.badFilename("length=\(nameLen)")
        }
        let nameData = try await session.readExact(Int(nameLen))
        guard let filename = String(data: nameData, encoding: .utf8), !filename.isEmpty else {
            throw FileReceiverError.badFilename("not utf-8")
        }

        // file size
        let fileSize = try await session.readU64()

        onStart(filename)

        // 出力先パスを構築 (ディレクトリ区切りは "/")。
        // Rust 側は Windows での "\" を "/" に置換してから送っているので、こちらは常に "/" を想定。
        var fullPath = destinationDirectory
        for component in filename.split(separator: "/") {
            fullPath.appendPathComponent(String(component))
        }

        // 親ディレクトリ作成
        let parent = fullPath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        // check_for_file: 同名同サイズが既にあるか
        let existsSameSize: Bool = {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: fullPath.path),
               let n = attrs[.size] as? NSNumber,
               n.uint64Value == fileSize {
                return true
            }
            return false
        }()

        if existsSameSize {
            try await session.writeU64(1)
            // 相手が SHA-256 を送ってくる
            let peerHash = try await session.readExact(FCProtocol.hashSize)
            let localHash = try FileHasher.sha256(fileURL: fullPath)
            let match = (peerHash == localHash)
            try await session.writeU64(match ? 1 : 0)
            if match {
                // スキップ
                if !isLastFile {
                    _ = try await session.readU64()
                } else {
                    _ = try? await withTimeout(seconds: 2.0) {
                        _ = try await session.readU64()
                    }
                }
                return nil
            }
        } else {
            try await session.writeU64(0)
        }

        // 既存ファイルがある場合はリネーム (Rust 側と同じルール "(1) file.ext" 形式)
        while FileManager.default.fileExists(atPath: fullPath.path) {
            let dir = fullPath.deletingLastPathComponent()
            let base = fullPath.lastPathComponent
            let newName = FileReceiver.disambiguateName(base)
            fullPath = dir.appendingPathComponent(newName)
        }

        // 出力ファイル作成
        FileManager.default.createFile(atPath: fullPath.path, contents: nil, attributes: nil)
        let out = try FileHandle(forWritingTo: fullPath)
        defer { try? out.close() }

        var bytesReceived: UInt64 = 0
        while true {
            let wireSize = try await session.readU64()
            if wireSize == 0 { break }
            if wireSize > 16 * 1024 * 1024 {
                // 上限 (nonce+tag+1MB) を大きく超えるなら異常
                throw FileReceiverError.ioError("chunk too large: \(wireSize)")
            }
            let wire = try await session.readExact(Int(wireSize))
            let plaintext: Data
            do {
                plaintext = try AESGCMFC.open(combined: wire, key: key)
            } catch {
                throw FileReceiverError.decryptionFailed
            }
            try out.write(contentsOf: plaintext)
            bytesReceived += UInt64(plaintext.count)
            if fileSize > 0 {
                onProgress(min(1.0, Double(bytesReceived) / Double(fileSize)))
            }
        }

        // 完了通知
        try await session.writeU64(1)

        // 二重確認 (last file はタイムアウトあり)
        if isLastFile {
            _ = try? await withTimeout(seconds: 2.0) {
                _ = try await session.readU64()
            }
        } else {
            _ = try await session.readU64()
        }

        return fullPath
    }

    private static func disambiguateName(_ name: String) -> String {
        // Rust 側は "(1) name.ext", "(2) name.ext" と付けていく
        for i in 1..<10_000 {
            let candidate = "(\(i)) \(name)"
            if !candidate.isEmpty { return candidate }
        }
        return "renamed_\(UUID().uuidString)_\(name)"
    }

    // タイムアウト付き実行
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                return try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TransferSessionError.unexpectedEOF // timeout マーカー
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
