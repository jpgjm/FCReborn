//
// PasswordGenerator.swift
// FCReborn
//

import Foundation

enum PasswordGenerator {
    /// FlyingCarpet の generate_password と同じロジックで 8 文字のパスワードを生成する。
    /// 文字集合は 0/1/O/l/I を除いた英数字 (mistake-safe alphabet)。
    static func generate() -> String {
        var chars: [Character] = []
        for _ in 0..<FCProtocol.passwordLength {
            let idx = Int.random(in: 0..<FCProtocol.passwordAlphabet.count)
            chars.append(FCProtocol.passwordAlphabet[idx])
        }
        return String(chars)
    }
}
