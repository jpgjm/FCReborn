//
// DataExtensions.swift
// FCReborn
//
// Rust の tokio AsyncReadExt/AsyncWriteExt の write_u64/read_u64 は
// デフォルトで Big Endian で読み書きする。プロトコル互換のため統一する。
//

import Foundation

extension UInt64 {
    /// 8バイトの Big Endian 表現を返す。
    var bigEndianBytes: Data {
        var be = self.bigEndian
        return Data(bytes: &be, count: 8)
    }

    /// 8バイトの Big Endian バイト列から UInt64 を復元する。
    static func fromBigEndian(_ data: Data) -> UInt64? {
        guard data.count >= 8 else { return nil }
        return data.prefix(8).withUnsafeBytes { rawBuf in
            let ptr = rawBuf.bindMemory(to: UInt64.self)
            guard let first = ptr.baseAddress else { return UInt64(0) }
            return UInt64(bigEndian: first.pointee)
        }
    }
}

extension Data {
    /// 16進文字列表現 (デバッグ用)。
    var hexEncodedString: String {
        return self.map { String(format: "%02x", $0) }.joined()
    }
}
