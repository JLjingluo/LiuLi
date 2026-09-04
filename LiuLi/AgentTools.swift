import Foundation

// MARK: - Agent 文件工具（纯逻辑，Linux 已测）
// 工具仅作用于 App 沙盒 Documents 目录，路径经过严格归一化，禁止越界。

enum PathResolver {

    /// 将模型给出的相对路径归一化为 root 下的 URL。
    /// 返回 nil：路径越界（.. 逃逸）/ 命中黑名单 / 含非法字符。
    /// 返回的 URL 一定在 root 之内（不含 root 本身的文件操作语义由调用方判断）。
    static func resolve(root: URL, relative: String, blockedTopLevel: Set<String>) -> URL? {
        var input = relative.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.contains("\0") else { return nil }
        // 容忍模型给出绝对路径或反斜杠
        input = input.replacingOccurrences(of: "\\", with: "/")
        while input.hasPrefix("/") { input.removeFirst() }
        if input.hasPrefix("~") { return nil }

        var stack: [String] = []
        for component in input.components(separatedBy: "/") {
            if component.isEmpty || component == "." { continue }
            if component == ".." {
                guard !stack.isEmpty else { return nil } // 越界
                stack.removeLast()
                continue
            }
            stack.append(component)
        }
        // 大小写不敏感匹配（iOS 文件系统不区分大小写，必须防绕过）
        if let first = stack.first {
            let lowered = first.lowercased()
            if blockedTopLevel.contains(where: { $0.lowercased() == lowered }) { return nil }
        }
        return stack.reduce(root) { $0.appendingPathComponent($1) }
    }

    /// 归一化后的相对路径（用于回显），根目录返回空串
    static func relativeDisplayPath(root: URL, target: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let targetPath = target.standardizedFileURL.path
        if targetPath == rootPath { return "" }
        if targetPath.hasPrefix(rootPath + "/") {
            return String(targetPath.dropFirst(rootPath.count + 1))
        }
        return targetPath
    }
}

/// 一个已创建的工具调用结果
enum AgentToolError: Error, Equatable {
    case pathInvalid
    case notFound(String)
    case isDirectory
    case notTextFile
    case rootProtected
}

final class AgentToolBox {

    let root: URL
    /// 工具不可触碰的顶层目录（应用会话数据）
    static let blockedTopLevel: Set<String> = ["Conversations"]
    /// 单文件读取上限（字符）
    static let readLimit = 100_000

    init(root: URL) {
        self.root = root
    }

    // MARK: 工具定义

    static func toolSchemas() -> [ToolSchema] {
        [
            ToolSchema(type: "function", function: ToolFunctionSchema(
                name: "list_files",
                description: "列出应用文档目录（工作区）中的文件和文件夹。默认列出根目录，可指定子目录。",
                parameters: ToolParameters(
                    type: "object",
                    properties: [
                        "path": ToolParamProperty(type: "string", description: "相对子目录路径，留空表示根目录")
                    ],
                    required: []
                )
            )),
            ToolSchema(type: "function", function: ToolFunctionSchema(
                name: "read_file",
                description: "读取工作区内一个文本文件的内容。",
                parameters: ToolParameters(
                    type: "object",
                    properties: [
                        "path": ToolParamProperty(type: "string", description: "文件的相对路径，如 index.html")
                    ],
                    required: ["path"]
                )
            )),
            ToolSchema(type: "function", function: ToolFunctionSchema(
                name: "write_file",
                description: "在创建或完整覆盖一个文本文件（自动创建父目录）。常用于写 HTML/CSS/JS/Markdown/脚本等小程序。",
                parameters: ToolParameters(
                    type: "object",
                    properties: [
                        "path": ToolParamProperty(type: "string", description: "目标文件相对路径，如 demo/index.html"),
                        "content": ToolParamProperty(type: "string", description: "完整文件内容")
                    ],
                    required: ["path", "content"]
                )
            )),
            ToolSchema(type: "function", function: ToolFunctionSchema(
                name: "delete_file",
                description: "删除工作区内的文件或文件夹。",
                parameters: ToolParameters(
                    type: "object",
                    properties: [
                        "path": ToolParamProperty(type: "string", description: "要删除的相对路径")
                    ],
                    required: ["path"]
                )
            ))
        ]
    }

    // MARK: 执行入口

    /// 执行一次工具调用，总是返回字符串（错误也以文本形式回给模型，便于模型自我纠正）
    func execute(name: String, argumentsJSON: String) -> String {
        guard let data = argumentsJSON.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return "错误：参数不是合法 JSON。"
        }
        let path = obj["path"] as? String ?? ""
        switch name {
        case "list_files":
            return listFiles(relativePath: path)
        case "read_file":
            return readFile(path: path)
        case "write_file":
            let content = obj["content"] as? String ?? ""
            return writeFile(path: path, content: content)
        case "delete_file":
            return deleteFile(path: path)
        default:
            return "错误：未知工具 \(name)。"
        }
    }

    // MARK: 各工具实现

    func listFiles(relativePath: String) -> String {
        let target = PathResolver.resolve(root: root, relative: relativePath, blockedTopLevel: Self.blockedTopLevel)
        guard let target else { return "错误：路径非法（可能越界或属于应用数据目录）。" }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir) else {
            return "错误：目录不存在。"
        }
        guard isDir.boolValue else { return "错误：该路径不是目录。" }

        let display = PathResolver.relativeDisplayPath(root: root, target: target)
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: target.path)) ?? []
        if entries.isEmpty {
            return "目录 \"\(display.isEmpty ? "/" : display)\" 为空。"
        }
        var lines: [String] = ["目录 \(display.isEmpty ? "/" : display)："]
        let sorted = entries
            .filter { !$0.hasPrefix(".") }
            .sorted { a, b in
                let da = isDirAt(target.appendingPathComponent(a))
                let db = isDirAt(target.appendingPathComponent(b))
                if da != db { return da && !db }
                return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
            }
        for entry in sorted {
            let full = target.appendingPathComponent(entry)
            if isDirAt(full) {
                lines.append("[目录] \(entry)/")
            } else {
                lines.append("[文件] \(entry) (\(sizeString(at: full)))")
            }
        }
        return lines.joined(separator: "\n")
    }

    func readFile(path: String) -> String {
        guard !path.isEmpty else { return "错误：缺少 path 参数。" }
        guard let target = PathResolver.resolve(root: root, relative: path, blockedTopLevel: Self.blockedTopLevel) else {
            return "错误：路径非法（可能越界或属于应用数据目录）。"
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir) else {
            return "错误：文件不存在。"
        }
        guard !isDir.boolValue else { return "错误：该路径是目录。" }
        guard let data = FileManager.default.contents(atPath: target.path),
              let text = String(data: data, encoding: .utf8) else {
            return "错误：无法按 UTF-8 文本读取（可能是二进制文件）。"
        }
        if text.count > Self.readLimit {
            let head = String(text.prefix(Self.readLimit))
            return head + "\n…（内容过长，已截断，共 \(text.count) 字符）"
        }
        return text
    }

    func writeFile(path: String, content: String) -> String {
        guard !path.isEmpty else { return "错误：缺少 path 参数。" }
        guard let target = PathResolver.resolve(root: root, relative: path, blockedTopLevel: Self.blockedTopLevel) else {
            return "错误：路径非法（可能越界或属于应用数据目录）。"
        }
        let fm = FileManager.default
        let dir = target.deletingLastPathComponent()
        do {
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            try content.data(using: .utf8)?.write(to: target, options: .atomic)
            let display = PathResolver.relativeDisplayPath(root: root, target: target)
            return "已写入 \(display)（\(content.utf8.count) 字节）。"
        } catch {
            return "错误：写入失败 - \(error.localizedDescription)"
        }
    }

    func deleteFile(path: String) -> String {
        guard !path.isEmpty else { return "错误：缺少 path 参数。" }
        guard let target = PathResolver.resolve(root: root, relative: path, blockedTopLevel: Self.blockedTopLevel) else {
            return "错误：路径非法（可能越界或属于应用数据目录）。"
        }
        guard target.path != root.path else { return "错误：不能删除根目录。" }
        let fm = FileManager.default
        guard fm.fileExists(atPath: target.path) else {
            return "错误：路径不存在。"
        }
        do {
            try fm.removeItem(at: target)
            let display = PathResolver.relativeDisplayPath(root: root, target: target)
            return "已删除 \(display)。"
        } catch {
            return "错误：删除失败 - \(error.localizedDescription)"
        }
    }

    // MARK: 私有

    private func isDirAt(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    private func sizeString(at url: URL) -> String {
        let count = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        return byteCountFormatter.string(fromByteCount: Int64(count))
    }

    private let byteCountFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()
}
