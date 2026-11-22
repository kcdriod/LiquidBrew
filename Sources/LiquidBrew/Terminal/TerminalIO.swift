import Foundation
import Darwin

enum TerminalKey: Equatable {
    case text(String), paste(String), escape, enter, backspace, tab, up, down, left, right, pageUp, pageDown, interrupt
}

struct TerminalInput {
    private var bytes: [UInt8] = []
    private var escapeTime: Date?
    private var pasted: [UInt8]?

    mutating func decode(_ incoming: [UInt8], now: Date = Date()) -> [TerminalKey] {
        bytes += incoming
        var keys: [TerminalKey] = []
        while !bytes.isEmpty {
            if var paste = pasted {
                let end: [UInt8] = [27, 91, 50, 48, 49, 126]
                if bytes.starts(with: end) {
                    keys.append(.paste(TerminalText.clean(String(decoding: paste, as: UTF8.self))))
                    pasted = nil
                    bytes.removeFirst(end.count)
                } else if bytes.count < end.count && end.starts(with: bytes) {
                    break
                } else {
                    if paste.count < 4096 { paste.append(bytes[0]) }
                    pasted = paste
                    bytes.removeFirst()
                }
                continue
            }
            let first = bytes[0]
            if first == 27 {
                if bytes.count == 1 {
                    if let escapeTime, now.timeIntervalSince(escapeTime) > 0.04 {
                        keys.append(.escape); bytes.removeFirst(); self.escapeTime = nil
                    } else if escapeTime == nil { escapeTime = now }
                    break
                }
                escapeTime = nil
                if bytes[1] == 91 || bytes[1] == 79 {
                    guard let end = bytes.indices.dropFirst(2).first(where: { (64...126).contains(bytes[$0]) }) else {
                        if bytes.count > 64 { bytes.removeAll() }
                        break
                    }
                    let sequence = String(decoding: bytes[0...end], as: UTF8.self)
                    switch sequence {
                    case "\u{1b}[A", "\u{1b}OA": keys.append(.up)
                    case "\u{1b}[B", "\u{1b}OB": keys.append(.down)
                    case "\u{1b}[C", "\u{1b}OC": keys.append(.right)
                    case "\u{1b}[D", "\u{1b}OD": keys.append(.left)
                    case "\u{1b}[5~": keys.append(.pageUp)
                    case "\u{1b}[6~": keys.append(.pageDown)
                    case "\u{1b}[200~": pasted = []
                    default: break
                    }
                    bytes.removeFirst(end + 1)
                    continue
                }
                keys.append(.escape); bytes.removeFirst()
                continue
            }
            switch first {
            case 3: keys.append(.interrupt)
            case 9: keys.append(.tab)
            case 10, 13: keys.append(.enter)
            case 8, 127: keys.append(.backspace)
            case 0...31: break
            default:
                let length = first < 128 ? 1 : (first < 224 ? 2 : (first < 240 ? 3 : 4))
                guard bytes.count >= length else { return keys }
                if let text = String(bytes: bytes.prefix(length), encoding: .utf8) { keys.append(.text(text)) }
                bytes.removeFirst(length)
                continue
            }
            bytes.removeFirst()
        }
        return keys
    }
}

final class TerminalSession {
    private var original = termios()
    private var active = false
    private var previous: [TerminalCell] = []
    private var lastSize = (0, 0)
    private var input = TerminalInput()

    init() throws {
        guard isatty(STDIN_FILENO) == 1, isatty(STDOUT_FILENO) == 1,
              ProcessInfo.processInfo.environment["TERM"] != "dumb" else {
            throw TerminalOptions.invalid("Open an interactive terminal, or use --snapshot / list / --help")
        }
        guard tcgetattr(STDIN_FILENO, &original) == 0 else { throw TerminalOptions.invalid("Could not read terminal settings") }
        var raw = original
        cfmakeraw(&raw)
        guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == 0 else { throw TerminalOptions.invalid("Could not enter terminal mode") }
        active = true
        write("\u{1b}[?1049h\u{1b}[?25l\u{1b}[?2004h\u{1b}[0m\u{1b}[2J")
    }

    deinit { restore() }

    func restore() {
        guard active else { return }
        write("\u{1b}[0m\u{1b}[?2004l\u{1b}[?25h\u{1b}[?1049l")
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
        active = false
    }

    var size: (width: Int, height: Int) {
        var size = winsize()
        _ = ioctl(STDOUT_FILENO, TIOCGWINSZ, &size)
        return (max(1, min(500, Int(size.ws_col))), max(1, min(200, Int(size.ws_row))))
    }

    func keys() -> [TerminalKey] {
        var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        var incoming: [UInt8] = []
        if poll(&descriptor, 1, 0) > 0, descriptor.revents & Int16(POLLIN) != 0 {
            var buffer = [UInt8](repeating: 0, count: 4096)
            let count = Darwin.read(STDIN_FILENO, &buffer, buffer.count)
            if count > 0 { incoming = Array(buffer.prefix(count)) }
        }
        return input.decode(incoming)
    }

    func draw(_ frame: TerminalFrame) {
        let resized = lastSize != (frame.width, frame.height)
        if resized { previous = []; lastSize = (frame.width, frame.height) }
        var result = resized ? "\u{1b}[2J" : ""
        var foreground: TerminalRGB?
        var background: TerminalRGB?
        var bold = false
        for y in 0..<frame.height {
            var positioned = false
            for x in 0..<frame.width {
                let index = y * frame.width + x
                let cell = frame.cells[index]
                if cell.continuation { continue }
                if previous.count == frame.cells.count && previous[index] == cell {
                    positioned = false
                    continue
                }
                if !positioned { result += "\u{1b}[\(y + 1);\(x + 1)H"; positioned = true }
                if foreground != cell.foreground {
                    let c = cell.foreground
                    result += "\u{1b}[38;2;\(c.r);\(c.g);\(c.b)m"; foreground = c
                }
                if background != cell.background {
                    let c = cell.background
                    result += "\u{1b}[48;2;\(c.r);\(c.g);\(c.b)m"; background = c
                }
                if bold != cell.bold { result += cell.bold ? "\u{1b}[1m" : "\u{1b}[22m"; bold = cell.bold }
                result += cell.text
            }
        }
        if !result.isEmpty { write(result + "\u{1b}[0m") }
        previous = frame.cells
    }

    private func write(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
    }
}

enum TerminalText {
    static func clean(_ value: String) -> String {
        let withoutEscape = value
            .replacingOccurrences(of: #"\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\x1B\[[0-?]*[ -/]*[@-~]"#, with: "", options: .regularExpression)
        return String(String.UnicodeScalarView(withoutEscape.unicodeScalars.filter {
            ($0.value >= 32 && $0.value != 127 && !($0.value >= 128 && $0.value < 160)) &&
            !(0x202A...0x202E).contains($0.value) && !(0x2066...0x2069).contains($0.value)
        }))
    }

    static func width(_ character: Character) -> Int {
        if character.unicodeScalars.contains(where: { $0.value == 0xFE0F || $0.properties.isEmojiPresentation }) { return 2 }
        return max(0, character.unicodeScalars.map { max(0, Int(wcwidth(wchar_t($0.value)))) }.max() ?? 0)
    }

    static func clipped(_ text: String, to limit: Int) -> String {
        var result = ""
        var used = 0
        for character in clean(text) {
            let size = width(character)
            guard used + size <= max(0, limit) else { break }
            result.append(character)
            used += size
        }
        return result
    }

    static func wrapped(_ text: String, width: Int) -> [String] {
        guard width > 0 else { return [] }
        return text.components(separatedBy: .newlines).flatMap { raw -> [String] in
            var lines: [String] = []
            var line = ""
            var used = 0
            for character in clean(raw.replacingOccurrences(of: "\t", with: "    ")) {
                let size = Self.width(character)
                if used + size > width { lines.append(line); line = ""; used = 0 }
                if size <= width { line.append(character); used += size }
            }
            lines.append(line)
            return lines
        }
    }
}

struct TerminalCell: Equatable {
    var text = " "
    var foreground = TerminalRGB.text
    var background = TerminalRGB.background
    var bold = false
    var continuation = false
}

struct TerminalFrame {
    let width: Int
    let height: Int
    var cells: [TerminalCell]

    init(width: Int, height: Int) {
        self.width = width; self.height = height
        cells = Array(repeating: TerminalCell(), count: width * height)
    }

    mutating func fill(x: Int, y: Int, width: Int, height: Int, background: TerminalRGB) {
        guard width > 0, height > 0 else { return }
        for row in min(self.height, max(0, y))..<max(0, min(self.height, y + height)) {
            for column in min(self.width, max(0, x))..<max(0, min(self.width, x + width)) {
                cells[row * self.width + column] = TerminalCell(background: background)
            }
        }
    }

    mutating func text(_ value: String, x: Int, y: Int, limit: Int? = nil, color: TerminalRGB = .text, bold: Bool = false) {
        guard y >= 0, y < height, x >= 0, x < width else { return }
        var column = x
        let end = min(width, x + max(0, limit ?? width - x))
        for character in TerminalText.clean(value) {
            let size = TerminalText.width(character)
            guard size > 0 else { continue }
            guard column + size <= end else { break }
            let index = y * width + column
            cells[index].text = String(character)
            cells[index].foreground = color
            cells[index].bold = bold
            cells[index].continuation = false
            if size == 2 {
                cells[index + 1].text = ""
                cells[index + 1].continuation = true
            }
            column += size
        }
    }

    mutating func box(x: Int, y: Int, width: Int, height: Int, title: String) {
        guard width >= 4, height >= 3 else { return }
        fill(x: x, y: y, width: width, height: height, background: .panel)
        text("╭" + String(repeating: "─", count: width - 2) + "╮", x: x, y: y, color: .muted)
        text("╰" + String(repeating: "─", count: width - 2) + "╯", x: x, y: y + height - 1, color: .muted)
        for row in (y + 1)..<(y + height - 1) {
            text("│", x: x, y: row, color: .muted)
            text("│", x: x + width - 1, y: row, color: .muted)
        }
        text(" \(title) ", x: x + 2, y: y, limit: width - 4, color: .cyan, bold: true)
    }

    var plainText: String {
        (0..<height).map { row in cells[(row * width)..<((row + 1) * width)].map(\.text).joined() }.joined(separator: "\n")
    }
}
