import SwiftUI

private extension Color {
    init(hex: UInt32) { self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255) }
}

/// MusicDeck과 같은 색. accent는 입력 글씨·임박한 마감·체크 표시 같은 포인트 색.
struct Theme {
    var accent: Color, shell: [Color], rim: Color, ink: Color, faint: Color, screen: Color

    static let light = Theme(
        accent: Color(hex: 0xFF5A1F), shell: [Color(hex: 0xE6E5E1), Color(hex: 0xCFCDC7)], rim: .white.opacity(0.7),
        ink: Color(hex: 0x2A2A2A), faint: Color(hex: 0x8A8883), screen: Color(hex: 0x141414))

    static let matte = Theme(
        accent: Color(hex: 0xF2F0EA), shell: [Color(hex: 0x2A2A29), Color(hex: 0x222221)], rim: .white.opacity(0.06),
        ink: Color(hex: 0xD6D4CE), faint: Color(hex: 0x6C6A66), screen: Color(hex: 0x0D0D0D))
}

private func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .monospaced) }

struct BoardView: View {
    @ObservedObject var board: Board
    @State private var text = ""
    @FocusState private var typing: Bool
    private var t: Theme { board.theme == .light ? .light : .matte }

    var body: some View {
        VStack(spacing: 12) {
            header
            input
            list
        }
        .padding(16)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(colors: t.shell, startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(t.rim, lineWidth: 1))
        )
        // 빈 곳: 끌면 창이 움직이고, 클릭하면 위치에 따라 숨는다(Board.tapped 참고)
        .onTapGesture { board.tapped(at: $0) }
        .gesture(DragGesture(minimumDistance: 1)
            .onChanged { _ in board.dragWindow() }
            .onEnded { _ in board.endDrag() })
        .overlay(alignment: gripAlignment) { grip }
        .contextMenu {
            Button("완료한 일 지우기") { withAnimation { board.clearDone() } }
                .disabled(board.openCount == board.todos.count)
            Button(board.onTop ? "바탕화면에 두기" : "항상 위에 표시") { board.onTop.toggle() }
            Picker("테마", selection: $board.theme) {
                ForEach(ThemeName.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Divider()
            Button("종료") { NSApp.terminate(nil) }
        }
        .animation(.easeInOut(duration: 0.25), value: board.theme)
        .onChange(of: board.focusRequest) { typing = true }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle().fill(overdue ? t.accent : t.faint.opacity(0.5)).frame(width: 7, height: 7)
            Text("TODODECK").font(mono(10, .bold)).tracking(2.5)
            Spacer()
            Text(String(format: "%02d", board.openCount)).font(mono(10))
        }
        .foregroundStyle(t.ink)
    }

    private var overdue: Bool { board.todos.contains { $0.done == nil && ($0.due ?? .distantFuture) < Date() } }

    private var input: some View {
        HStack(spacing: 8) {
            Text("›").font(mono(14, .bold)).foregroundStyle(t.accent.opacity(0.6))
            TextField("", text: $text, prompt: Text("할 일 · 마감 (예: 보고서 금요일)").foregroundStyle(t.accent.opacity(0.35)))
                .textFieldStyle(.plain)
                .font(mono(12, .medium))
                .foregroundStyle(t.accent)
                .focused($typing)
                .onSubmit {   // 저장만 하고 그대로 둔다. 닫기는 ⌃/ 또는 ESC
                    if !text.isEmpty { Click.tick() }
                    board.add(text)
                    text = ""
                    typing = true
                }
                .onExitCommand { text = ""; board.dismiss() }
            Text("⌃/").font(mono(10)).foregroundStyle(t.accent.opacity(0.35))
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 9).fill(t.screen)
            .shadow(color: .black.opacity(0.35), radius: 1, y: -1))
    }

    private var list: some View {
        // 1분마다 다시 그려서 남은 시간을 갱신한다
        TimelineView(.everyMinute) { ctx in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(board.todos) { row($0, now: ctx.date) }
                }
            }
            .scrollIndicators(.never)
            .overlay {
                if board.todos.isEmpty {
                    Text("할 일이 없어요").font(mono(11)).foregroundStyle(t.faint)
                }
            }
        }
        .frame(height: 176)   // 약 6줄. 창 크기를 고정해 두려고 높이를 정해둔다
        .padding(.horizontal, 4)   // 양옆 손잡이와 겹치지 않게
    }

    private func row(_ todo: Todo, now: Date) -> some View {
        let done = todo.done != nil
        let left = todo.due.map { Due.remaining($0, now: now) }
        let urgent = todo.due.map { $0.timeIntervalSince(now) < 86400 } ?? false
        return HStack(spacing: 10) {
            Button {
                Click.tick()
                withAnimation(.easeOut(duration: 0.25)) { board.toggle(todo.id) }
            } label: {
                Circle()
                    .strokeBorder(done ? t.accent : t.faint, lineWidth: 1.5)
                    .background(Circle().fill(done ? t.accent : .clear).padding(3))
                    .frame(width: 15, height: 15)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

            Text(todo.title)
                .font(mono(12))
                .foregroundStyle(t.ink.opacity(done ? 0.4 : 1))
                .strikethrough(done, color: t.ink.opacity(0.4))
                .lineLimit(1)
            Spacer(minLength: 6)
            if let left, let due = todo.due, !done {
                Text(left)
                    .font(mono(10, urgent ? .bold : .regular))
                    .foregroundStyle(urgent ? t.accent : t.faint)
                    .help(due.formatted(.dateTime.month().day().weekday().hour().minute()))
            }
        }
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) { Rectangle().fill(t.faint.opacity(0.18)).frame(height: 1) }
        .transition(.opacity)
    }

    // MARK: 숨기기 손잡이 — MusicDeck과 같다

    private var gripAlignment: Alignment {
        switch board.stashed ?? board.lastSide {
        case .left: .trailing
        case .right: .leading
        case .top: .bottom
        }
    }

    private var grip: some View {
        Button(action: board.toggleStash) {
            let across = (board.stashed ?? board.lastSide) == .top    // 위쪽이면 손잡이 줄이 가로
            let lines = ForEach(0..<2, id: \.self) { _ in
                Capsule().fill(t.faint.opacity(board.stashed == nil ? 0.5 : 1)).frame(width: across ? 26 : 3, height: across ? 3 : 26)
            }
            Group { if across { VStack(spacing: 3) { lines } } else { HStack(spacing: 3) { lines } } }
                .padding(across ? .vertical : .horizontal, 5)
                .frame(maxWidth: board.stashed != nil ? .infinity : across ? 56 : nil,
                       maxHeight: board.stashed != nil ? .infinity : across ? nil : 56,
                       alignment: gripAlignment)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(board.stashed == nil ? "눌러서 숨기기" : "눌러서 꺼내기")
    }
}
