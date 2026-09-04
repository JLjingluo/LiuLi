import SwiftUI
import UniformTypeIdentifiers

// MARK: - 文件浏览器（工作区 = App 沙盒 Documents）

#Preview {
    FilesView()
}

struct FilesView: View {
    var body: some View {
        NavigationStack {
            DirectoryListView(directoryURL: nil)
        }
    }
}

// MARK: - 目录列表（递归）

struct DirectoryListView: View {
    /// nil = 根（工作区）
    let directoryURL: URL?

    @EnvironmentObject private var router: AppRouter
    @State private var entries: [FileEntry] = []
    @State private var showNewFileAlert = false
    @State private var showNewFolderAlert = false
    @State private var newName = ""
    @State private var renamingEntry: FileEntry?
    @State private var renameText = ""
    @State private var importPickerShown = false
    @State private var refreshToken = UUID()

    var body: some View {
        List {
            if entries.isEmpty {
                Text("此目录为空。\n\n深度模式下让 AI 帮你写文件，或点右上 + 新建。")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.liuliTextSecondary)
            } else {
                ForEach(entries) { entry in
                    NavigationLink(value: entry) {
                        rowContent(entry)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteEntry(entry)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        Button {
                            renamingEntry = entry
                            renameText = entry.name
                        } label: {
                            Label("重命名", systemImage: "pencil")
                        }
                        .tint(Color.liuliIndigo)
                        Button {
                            router.askAI(aboutFile: relativePath(of: entry))
                        } label: {
                            Label("问 AI", systemImage: "wand.and.stars")
                        }
                        .tint(Color.liuliViolet)
                    }
                }
            }
        }
        .id(refreshToken)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(red: 0.043, green: 0.055, blue: 0.11))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showNewFileAlert = true } label: {
                        Label("新建文件", systemImage: "doc.badge.plus")
                    }
                    Button { showNewFolderAlert = true } label: {
                        Label("新建文件夹", systemImage: "folder.badge.plus")
                    }
                    Button { importPickerShown = true } label: {
                        Label("导入文件", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Color.liuliAccent)
                }
            }
        }
        .navigationDestination(for: FileEntry.self) { entry in
            if entry.isDirectory {
                DirectoryListView(directoryURL: entry.url)
            } else {
                EditorView(fileURL: entry.url)
            }
        }
        .fileImporter(isPresented: $importPickerShown, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            handleImport(result)
        }
        .onAppear(perform: reload)
        .refreshable { reload() }
        .alert("新建文件", isPresented: $showNewFileAlert) {
            TextField("文件名（如 index.html）", text: $newName)
                .autocapitalization(.none)
            Button("创建") { createEntry(directory: false) }
            Button("取消", role: .cancel) {}
        }
        .alert("新建文件夹", isPresented: $showNewFolderAlert) {
            TextField("文件夹名", text: $newName)
            Button("创建") { createEntry(directory: true) }
            Button("取消", role: .cancel) {}
        }
        .alert("重命名", isPresented: Binding(
            get: { renamingEntry != nil },
            set: { if !$0 { renamingEntry = nil } }
        )) {
            TextField("新名称", text: $renameText)
                .autocapitalization(.none)
            Button("确定") { performRename() }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: 数据模型

    struct FileEntry: Identifiable, Hashable, Equatable {
        let id = UUID()
        let name: String
        let url: URL
        let isDirectory: Bool
        let size: Int
    }

    // MARK: 路径

    private var rootURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    private var currentURL: URL {
        directoryURL ?? rootURL
    }

    private var title: String {
        directoryURL == nil ? "工作区" : directoryURL!.lastPathComponent
    }

    private func reload() {
        let fm = FileManager.default
        var items: [FileEntry] = []
        if let names = try? fm.contentsOfDirectory(at: currentURL, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey]) {
            for url in names {
                if directoryURL == nil && url.lastPathComponent == "Conversations" { continue } // 应用会话数据
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                items.append(FileEntry(name: url.lastPathComponent, url: url, isDirectory: isDir, size: size))
            }
        }
        entries = items.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    // MARK: 行

    private func rowContent(_ entry: FileEntry) -> some View {
        HStack(spacing: 11) {
            Image(systemName: entry.isDirectory ? "folder.fill" : iconName(for: entry.name))
                .font(.system(size: 16))
                .foregroundStyle(entry.isDirectory ? Color.liuliIndigo : Color.liuliTeal)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !entry.isDirectory {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(entry.size), countStyle: .file))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.liuliTextTertiary)
                }
            }
            Spacer()

            if isHTMLFile(entry.name) && !entry.isDirectory {
                NavigationLink(value: entry) {
                    GlassBadge(text: "编辑", tint: .liuliAccent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func iconName(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "html", "htm": return "globe"
        case "css": return "paintbrush"
        case "js": return "curlybraces.square"
        case "json": return "curlybraces"
        case "md", "markdown", "txt": return "doc.text"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "swift": return "swift"
        case "png", "jpg", "jpeg", "gif", "webp": return "photo"
        case "csv": return "tablecells"
        default: return "doc"
        }
    }

    private func isHTMLFile(_ name: String) -> Bool {
        ["html", "htm"].contains((name as NSString).pathExtension.lowercased())
    }

    private func relativePath(of entry: FileEntry) -> String {
        let rootPath = rootURL.path
        let p = entry.url.path
        if p.hasPrefix(rootPath + "/") {
            return String(p.dropFirst(rootPath.count + 1))
        }
        return entry.name
    }

    // MARK: 操作

    private func createEntry(directory: Bool) {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !name.contains("/") else { return }
        let target = currentURL.appendingPathComponent(name)
        let fm = FileManager.default
        guard !fm.fileExists(atPath: target.path) else { return }
        if directory {
            try? fm.createDirectory(at: target, withIntermediateDirectories: true)
        } else {
            fm.createFile(atPath: target.path, contents: Data())
        }
        newName = ""
        reload()
    }

    private func deleteEntry(_ entry: FileEntry) {
        try? FileManager.default.removeItem(at: entry.url)
        reload()
    }

    private func performRename() {
        guard let entry = renamingEntry else { return }
        let name = renameText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !name.contains("/") else { return }
        let target = entry.url.deletingLastPathComponent().appendingPathComponent(name)
        try? FileManager.default.moveItem(at: entry.url, to: target)
        renamingEntry = nil
        reload()
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        let fm = FileManager.default
        for src in urls {
            let accessed = src.startAccessingSecurityScopedResource()
            defer { if accessed { src.stopAccessingSecurityScopedResource() } }
            let dst = currentURL.appendingPathComponent(src.lastPathComponent)
            try? fm.copyItem(at: src, to: dst)
        }
        reload()
    }
}

// MARK: - 文件编辑器（文本编辑 + HTML 预览）

struct EditorView: View {
    let fileURL: URL

    @EnvironmentObject private var router: AppRouter
    @State private var content: String = ""
    @State private var loaded = false
    @State private var showPreview = false
    @State private var savedFlash = false

    private var isHTML: Bool {
        ["html", "htm"].contains((fileURL.lastPathComponent as NSString).pathExtension.lowercased())
    }

    private var lineCount: Int {
        max(1, content.split(whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == "\r\n" }).count)
    }

    var body: some View {
        TextEditor(text: $content)
            .font(.system(size: 13, design: .monospaced))
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.03, green: 0.04, blue: 0.08))
            .padding(.horizontal, 8)
            .navigationTitle(fileURL.lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        save()
                    } label: {
                        Image(systemName: savedFlash ? "checkmark.circle.fill" : "square.and.arrow.down")
                            .foregroundStyle(savedFlash ? Color.liuliTeal : Color.liuliAccent)
                    }
                }
                if isHTML {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            save()
                            showPreview = true
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .foregroundStyle(Color.liuliTeal)
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Text("\(lineCount) 行 · \(content.utf8.count) 字节")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.liuliTextTertiary)
                        Spacer()
                        Button {
                            router.askAI(aboutFile: relativePath())
                        } label: {
                            Label("让 AI 编辑", systemImage: "wand.and.stars")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.liuliViolet)
                        }
                    }
                }
            }
            .onAppear(perform: load)
            .sheet(isPresented: $showPreview) {
                HTMLPreviewSheet(title: fileURL.lastPathComponent, fileURL: fileURL, html: nil)
            }
    }

    private func relativePath() -> String {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: "/")
        let p = fileURL.path
        if p.hasPrefix(root.path + "/") {
            return String(p.dropFirst(root.path.count + 1))
        }
        return fileURL.lastPathComponent
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let data = FileManager.default.contents(atPath: fileURL.path),
           let text = String(data: data, encoding: .utf8) {
            content = text
        }
    }

    private func save() {
        try? content.data(using: .utf8)?.write(to: fileURL, options: .atomic)
        withAnimation { savedFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation { savedFlash = false }
        }
    }
}
