//
// AppVersion.swift
// FCReborn
//
// バージョン識別子。ログの先頭に必ず出力して、
// Sideloadly でインストールされた IPA が本当に想定のバージョンか判別できるようにする。
//
// v3 で導入。前バージョン (v1, v2) との誤インストールを検知するため。
//

import Foundation

enum AppVersion {
    static let buildTag = "v1.2.0 (build 3) [FCReborn v3]"
}
