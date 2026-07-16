//
// FileHasher.swift
// FCReborn
//

import Foundation
import CryptoKit

enum FileHasher {
    /// ファイル内容の SHA-256 ハッシュを 32 バイトの Data で返す。
    /// 大きなファイルでもメモリを食わないよう 64KB ずつ読み込む。
    static func sha256(fileURL: URL) throws -> Data {
        var hasher = SHA256()
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let bufferSize = 64 * 1024
        while true {
            let chunk: Data
            if #available(iOS 13.4, *) {
                chunk = (try? handle.read(upToCount: bufferSize)) ?? Data()
            } else {
                chunk = handle.readData(ofLength: bufferSize)
            }
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return Data(hasher.finalize())
    }
}
