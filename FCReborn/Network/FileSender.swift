//
// FileSender.swift
// FCReborn
//
// Rust core/src/sending.rs 互換の送信処理。
//
// 1ファイル分の流れ:
//   [W] filename length (u64)
//   [W] filename bytes (utf-8)
//   [W] file size (u64)
//   [R] has_file (u64)
//     if has_file == 1:
//       [W] SHA-256 hash (32 bytes)
//       [R] hashes_match (u64)
//         if == 1 : skip (return)
//   loop:
//     read chunk (up to 1MB)
//     seal → wire (nonce||ct||tag)
//     [W] wire length (u64)
//     [W] wire bytes
//   [W] 0 (u64) as EOF marker
//   [R] receiver's done marker (u64)  ← 相手 receive_file の write_u64(1) を受ける
//   [W] 1 (u64) as double confirmation
//

import Foundation
import CryptoKit

enum FileSenderError: Error, LocalizedError {
    case fileNotAccessible(String)
    case ioError(String)

    var errorDescription: String? {
        switch self {
        case .fileNotAccessible(let s): return "ファイルにアクセスできません: \(s)"
        case .ioError(let s): return "IO エラー: \(s)"
        }
    }
}

struct FileSender {

    let session: TransferSession
    let key: SymmetricKey

    /// - Parameters:
    ///   - fileURL: 送信するファイル。Files アプリからピックした URL。
    ///   - relativeName: 送信ファイル名 (相手側でこの名前で保存される。パス区切りは "/"。)
    ///   - onProgress: 0.0-1.0 の進捗コールバック (メインスレッドから呼ばれる保証はない)。
    func send(fileURL: URL, relativeName: String, onProgress: @escaping (Double) -> Void) async throws {
        // Files アプリ由来の security scoped URL の場合を考慮
        let didStartAccessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing { fileURL.stopAccessingSecurityScopedResource() }
        }

        // メタデータ
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let sizeNumber = attrs[.size] as? NSNumber else {
            throw FileSenderError.fileNotAccessible("size unknown")
        }
        let size = sizeNumber.uint64Value

        // ファイル名を送信
        let nameBytes = Data(relativeName.utf8)
        try await session.writeU64(UInt64(nameBytes.count))
        try await session.writeAll(nameBytes)

        // ファイルサイズ
        try await session.writeU64(size)

        // check_for_file
        let hasFile = try await session.readU64()
        if hasFile == 1 {
            // 相手が同サイズを持ってる → ハッシュを送って比較
            let hash = try FileHasher.sha256(fileURL: fileURL)
            try await session.writeAll(hash)
            let hashesMatch = try await session.readU64()
            if hashesMatch == 1 {
                // スキップ (すでに同一ファイルあり)
                return
            }
        }

        // 転送本体
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var bytesSent: UInt64 = 0

        while true {
            let chunk: Data
            if #available(iOS 13.4, *) {
                chunk = (try? handle.read(upToCount: FCProtocol.chunkSize)) ?? Data()
            } else {
                chunk = handle.readData(ofLength: FCProtocol.chunkSize)
            }
            if chunk.isEmpty { break }

            let wire = try AESGCMFC.seal(plaintext: chunk, key: key)
            try await session.writeU64(UInt64(wire.count))
            try await session.writeAll(wire)

            bytesSent += UInt64(chunk.count)
            if size > 0 {
                onProgress(min(1.0, Double(bytesSent) / Double(size)))
            }
        }

        // 終端 (chunk size 0)
        try await session.writeU64(0)

        // 相手からの受信完了通知
        _ = try await session.readU64()

        // 二重確認
        try await session.writeU64(1)
    }
}
