//
// WiFiPromptView.swift
// FCReborn
//
// iOS 26 で NEHotspotConfiguration が壊れているため、また無署名 IPA では
// entitlement を付与できないため、Wi-Fi 参加はプログラム経由ではなく
// ユーザーが手動で「設定 > Wi-Fi」から接続してもらう。
//
// このアプリの最重要画面 (iOS 26 対応の要)。
//

import SwiftUI

struct WiFiPromptView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var coordinator: TransferCoordinator

    @State private var copiedField: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // ヘッダ
            VStack(alignment: .leading, spacing: 8) {
                Text("Wi-Fi に手動で参加してください")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("iOS 26 では自動接続が使えないため、下の情報で手動接続してください")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            // 情報カード
            VStack(spacing: 12) {
                infoRow(label: "SSID", value: state.ssid)
                Divider()
                infoRow(label: "パスワード", value: state.password)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))

            // 手順
            VStack(alignment: .leading, spacing: 8) {
                Text("手順").font(.headline)
                stepRow(number: 1, text: "下のボタンで「設定」アプリを開く")
                stepRow(number: 2, text: "Wi-Fi 画面で「\(state.ssid)」を選ぶ")
                stepRow(number: 3, text: "パスワードを貼り付けて接続")
                stepRow(number: 4, text: "このアプリに戻ってきて下の「接続完了、次へ」を押す")
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    WiFiHelper.openSettings()
                } label: {
                    Label("設定アプリを開く", systemImage: "gearshape.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)

                Button {
                    coordinator.proceedAfterWiFiJoin()
                } label: {
                    Label("接続完了、次へ", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)

                Button("キャンセル") {
                    coordinator.cancelAll()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .padding(.top, 4)
            }
        }
        .padding()
    }

    @ViewBuilder
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.semibold)
                    .textSelection(.enabled)
            }
            Spacer()
            Button {
                UIPasteboard.general.string = value
                copiedField = label
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    if copiedField == label { copiedField = nil }
                }
            } label: {
                if copiedField == label {
                    Label("コピー済", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.green)
                } else {
                    Label("コピー", systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                }
            }
            .font(.title3)
        }
    }

    @ViewBuilder
    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.blue)
                .frame(width: 24, alignment: .leading)
            Text(text)
                .font(.callout)
        }
    }
}
