//
// StatusViews.swift
// FCReborn
//

import SwiftUI

struct DoneView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var coordinator: TransferCoordinator

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 88))
                .foregroundStyle(.green)
            Text("転送完了")
                .font(.title.bold())
            if state.mode == .receive {
                VStack(spacing: 4) {
                    Text("保存先")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Files アプリ → このアプリ → inbox")
                        .font(.callout)
                }
            }
            Spacer()

            LogView()
                .frame(maxHeight: 180)

            Button("ホームに戻る") {
                coordinator.cancelAll()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }
}

struct FailedView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var coordinator: TransferCoordinator

    let message: String

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 72))
                .foregroundStyle(.red)
            Text("エラー")
                .font(.title.bold())
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            LogView()
                .frame(maxHeight: 200)

            Button("ホームに戻る") {
                coordinator.cancelAll()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

struct LogView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(state.logs.enumerated()), id: \.offset) { idx, line in
                        Text(line)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .id(idx)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(uiColor: .secondarySystemBackground)))
            .onChange(of: state.logs.count) { _, newValue in
                if newValue > 0 {
                    withAnimation { proxy.scrollTo(newValue - 1, anchor: .bottom) }
                }
            }
        }
    }
}
