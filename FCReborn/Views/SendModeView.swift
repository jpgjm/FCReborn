//
// SendModeView.swift
// FCReborn
//

import SwiftUI
import UniformTypeIdentifiers

struct SendModeView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var coordinator: TransferCoordinator

    @State private var showingPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("送信するファイルを選択")
                .font(.title2)
                .fontWeight(.semibold)

            Button {
                showingPicker = true
            } label: {
                Label("ファイルを追加", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)

            if state.pickedFiles.isEmpty {
                ContentUnavailableView(
                    "ファイル未選択",
                    systemImage: "doc.badge.plus",
                    description: Text("上のボタンから送信したいファイルを追加してください")
                )
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(state.pickedFiles, id: \.self) { url in
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading) {
                                Text(url.lastPathComponent)
                                    .lineLimit(1)
                                if let size = fileSize(url: url) {
                                    Text(formatBytes(size))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete { idxs in
                        state.pickedFiles.remove(atOffsets: idxs)
                    }
                }
                .listStyle(.plain)
            }

            Spacer()

            HStack {
                Button("戻る") {
                    state.pickedFiles = []
                    state.phase = .home
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    coordinator.startSendFlow()
                } label: {
                    Label("転送開始", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.pickedFiles.isEmpty)
            }
        }
        .padding()
        .fileImporter(
            isPresented: $showingPicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                for u in urls {
                    if !state.pickedFiles.contains(u) {
                        state.pickedFiles.append(u)
                    }
                }
            case .failure(let error):
                state.log("ファイル選択エラー: \(error.localizedDescription)")
            }
        }
    }

    private func fileSize(url: URL) -> UInt64? {
        let acc = url.startAccessingSecurityScopedResource()
        defer { if acc { url.stopAccessingSecurityScopedResource() } }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let n = attrs[.size] as? NSNumber else { return nil }
        return n.uint64Value
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: Int64(bytes))
    }
}
