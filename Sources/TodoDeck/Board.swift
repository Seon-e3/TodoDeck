import AppKit

struct Todo: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var due: Date?
    var created = Date()
    var done: Date?         // 완료한 시각. 완료한 일은 다음 날 자동으로 정리된다
}

enum ThemeName: String, CaseIterable {
    case light, matte
    var title: String { self == .light ? "라이트" : "무광 블랙" }
}

final class Board: ObservableObject {
    /// 마감이 가까운 순, 마감 없는 일은 아래(적은 순서대로), 완료한 일은 맨 아래
    @Published private(set) var todos: [Todo] = []
    @Published var focusRequest = 0   // 값이 바뀌면 입력칸에 커서를 놓는다

    @Published var theme = ThemeName(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .light {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "theme") }
    }
    @Published var onTop = false { didSet { window?.level = onTop ? .floating : Board.desktopLevel } }

    static let desktopLevel = NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    weak var window: NSWindow?

    // MARK: 할 일 저장 — ~/Library/Application Support/TodoDeck/todos.json

    private let file: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "TodoDeck")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "todos.json")
    }()

    init() {
        guard let data = try? Data(contentsOf: file) else { return }
        do {
            todos = try JSONDecoder().decode([Todo].self, from: data)
        } catch {
            // 읽지 못한 파일을 다음 저장 때 덮어쓰지 않도록 옆에 따로 보관한다
            try? FileManager.default.moveItem(at: file, to: file.deletingLastPathComponent().appending(path: "todos.broken-\(Int(Date().timeIntervalSince1970)).json"))
        }
        clearOldDone()
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.clearOldDone() }
    }

    var openCount: Int { todos.filter { $0.done == nil }.count }

    private func save() {
        sort()
        if let data = try? JSONEncoder().encode(todos) { try? data.write(to: file, options: .atomic) }
    }

    private func sort() {
        todos.sort { a, b in
            if let x = a.done, let y = b.done { return x < y }
            if (a.done == nil) != (b.done == nil) { return a.done == nil }
            return switch (a.due, b.due) {
            case let (x?, y?): x < y
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): a.created < b.created
            }
        }
    }

    func add(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let (title, due) = Due.parse(text)
        todos.append(Todo(title: title, due: due))
        save()
    }

    /// 체크 / 체크 해제
    func toggle(_ id: UUID) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[i].done = todos[i].done == nil ? Date() : nil
        save()
    }

    func clearDone() {
        todos.removeAll { $0.done != nil }
        save()
    }

    /// 오늘 이전에 완료한 일은 지운다
    private func clearOldDone() {
        let today = Calendar.current.startOfDay(for: Date())
        let before = todos.count
        todos.removeAll { ($0.done ?? .distantFuture) < today }
        if todos.count != before { save() } else { sort() }
    }

    // MARK: 단축키(⌃/)로 불러내기

    private var beforeSummon: (stashed: Side?, onTop: Bool)?
    private var previousApp: NSRunningApplication?   // 불러내기 전에 쓰던 앱. 끝나면 키보드를 돌려준다

    /// ⌃/: 나와 있으면 들어가고, 아니면 튀어나온다
    func hotKey() {
        if beforeSummon != nil { dismiss() } else { summon() }
    }

    /// 어디서든 튀어나와 입력칸에 커서를 놓는다
    func summon() {
        guard let win = window else { return }
        if beforeSummon == nil {
            beforeSummon = (stashed, onTop)
            previousApp = NSWorkspace.shared.frontmostApplication
        }
        if stashed != nil { toggleStash() }
        win.level = .floating
        win.makeKeyAndOrderFront(nil)
        focusRequest += 1
    }

    /// 엔터·ESC 뒤: 불러내기 전 상태로 돌아가고, 키보드를 원래 쓰던 앱에 돌려준다
    func dismiss() {
        guard let win = window, let before = beforeSummon else { return }
        beforeSummon = nil
        if let side = before.stashed, let screen = win.screen ?? NSScreen.main {
            stash(side, on: screen)
        } else {
            win.level = before.onTop ? .floating : Board.desktopLevel
        }
        // 원래 쓰던 앱을 다시 앞으로 불러 키보드를 돌려준다(창을 내렸다 올리면 깜빡여서 이렇게 한다)
        previousApp?.activate()
        previousApp = nil
    }

    // MARK: 스태시 — MusicDeck과 같은 동작. 화면 끝으로 밀면 숨고, 손잡이를 누르면 나온다

    enum Side { case left, right, top }
    @Published var stashed: Side?
    @Published var lastSide = Side.left           // MusicDeck은 오른쪽, TodoDeck은 왼쪽이 기본
    private static let peek: CGFloat = 22        // 숨었을 때 화면에 남는 폭
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?
    private var peeking = false                  // 손잡이로 꺼낸 뒤 아직 옮기지 않은 상태

    func restoreStash() {
        if let screen = window?.screen { stashIfPastEdge(of: screen) }   // 숨긴 채로 종료했으면 그대로 복원
    }

    /// 창 끌기. 시스템 창 끌기는 창을 화면 안에 가두기 때문에 화면 밖으로 밀 수 있게 직접 옮긴다.
    func dragWindow() {
        guard let win = window, stashed == nil else { return }
        peeking = false
        let m = NSEvent.mouseLocation
        if dragStart == nil { dragStart = (m, win.frame.origin) }
        let d = dragStart!
        win.setFrameOrigin(NSPoint(x: d.origin.x + m.x - d.mouse.x, y: d.origin.y + m.y - d.mouse.y))
    }

    func endDrag() {
        dragStart = nil
        let m = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(m, $0.frame, false) }) { stashIfPastEdge(of: screen) }
    }

    /// 창이 화면 밖으로 30pt 넘게 나갔고, 그 바깥에 다른 모니터가 없으면 숨긴다
    private func stashIfPastEdge(of screen: NSScreen) {
        guard let f = window?.frame else { return }
        let s = screen.frame, top = screen.visibleFrame.maxY      // 위쪽은 메뉴 막대 아래가 기준
        let noScreen = { (p: NSPoint) in !NSScreen.screens.contains { NSMouseInRect(p, $0.frame, false) } }
        if f.maxX - s.maxX > 30, noScreen(NSPoint(x: s.maxX + 1, y: f.midY)) { stash(.right, on: screen) }
        else if s.minX - f.minX > 30, noScreen(NSPoint(x: s.minX - 1, y: f.midY)) { stash(.left, on: screen) }
        else if f.maxY - top > 30, noScreen(NSPoint(x: f.midX, y: s.maxY + 1)) { stash(.top, on: screen) }
    }

    /// 숨었을 때(hidden)와 꺼냈을 때의 창 위치
    private func frame(for side: Side, hidden: Bool, on screen: NSScreen) -> NSRect? {
        guard var f = window?.frame else { return nil }
        let s = screen.frame, top = screen.visibleFrame.maxY
        switch side {
        case .right: f.origin.x = hidden ? s.maxX - Board.peek : s.maxX - f.width - 12
        case .left: f.origin.x = hidden ? s.minX - f.width + Board.peek : s.minX + 12
        case .top: f.origin.y = hidden ? top - Board.peek : top - f.height - 12
        }
        return f
    }

    /// 빈 곳 클릭(p는 창 안 좌표, 왼쪽 위 원점).
    /// 테두리 여백을 누르면 미는 방향으로 들어간다: 왼쪽 끝→오른쪽, 오른쪽 끝→왼쪽, 아래 끝→위.
    /// 그 밖의 빈 곳은 손잡이로 잠깐 꺼낸 상태일 때만 원래 자리로 돌아간다.
    func tapped(at p: CGPoint) {
        guard let size = window?.frame.size, let screen = window?.screen ?? NSScreen.main else { return }
        let band: CGFloat = 18
        let side: Side? = p.x < band ? .right
            : p.x > size.width - band ? .left
            : p.y > size.height - band ? .top
            : peeking ? lastSide : nil
        guard let side else { return }
        Click.press()
        stash(side, on: screen)
    }

    private func stash(_ side: Side, on screen: NSScreen) {
        guard let f = frame(for: side, hidden: true, on: screen) else { return }
        onTop = true            // 숨긴 손잡이가 다른 창에 가려지면 꺼낼 수 없으므로
        stashed = side
        lastSide = side
        peeking = false
        slide(to: f)
    }

    /// 손잡이: 숨어 있으면 꺼내고, 나와 있으면 마지막으로 숨었던 쪽으로 다시 넣는다
    func toggleStash() {
        Click.press()
        guard let screen = window?.screen ?? NSScreen.main else { return }
        guard let side = stashed else { return stash(lastSide, on: screen) }
        stashed = nil
        peeking = true
        if let f = frame(for: side, hidden: false, on: screen) { slide(to: f) }
    }

    private func slide(to f: NSRect) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window?.animator().setFrame(f, display: true)
        })
    }
}
