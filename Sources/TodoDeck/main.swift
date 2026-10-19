import AppKit
import Carbon.HIToolbox
import SwiftUI

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // Dock 아이콘 없이 실행

final class BoardPanel: NSPanel {
    override var canBecomeKey: Bool { true }   // 테두리 없는 창도 글자를 입력받을 수 있게
    // macOS는 창이 메뉴 막대 위로 올라가지 못하게 위치를 보정한다. 위쪽 숨기기를 위해 보정을 끈다.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

let board = Board()
let panel = BoardPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = true
panel.level = Board.desktopLevel       // 바탕화면 아이콘 바로 위, 다른 창들 아래
panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
let host = NSHostingView(rootView: BoardView(board: board))
panel.contentView = host
panel.setContentSize(host.fittingSize)
if !panel.setFrameUsingName("TodoDeck") { panel.center() }
panel.setFrameAutosaveName("TodoDeck")
panel.orderFrontRegardless()
board.window = panel
board.restoreStash()

// ⌘A·⌘C·⌘V·⌘X·⌘Z는 편집 메뉴를 통해 동작한다. 메뉴 막대가 없는 앱이라 보이지 않는 편집 메뉴를 달아준다.
let editMenu = NSMenu(title: "편집")
editMenu.addItem(withTitle: "실행 취소", action: Selector(("undo:")), keyEquivalent: "z")
editMenu.addItem(withTitle: "실행 복귀", action: Selector(("redo:")), keyEquivalent: "Z")
editMenu.addItem(withTitle: "잘라내기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
editMenu.addItem(withTitle: "복사하기", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
editMenu.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
editMenu.addItem(withTitle: "전체 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
let editItem = NSMenuItem()
editItem.submenu = editMenu
app.mainMenu = NSMenu()
app.mainMenu!.addItem(editItem)

// 전역 단축키 ⌃/ — 손쉬운 사용 권한 없이 쓸 수 있는 Carbon 단축키 등록
var hotKeyRef: EventHotKeyRef?
var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in board.hotKey(); return noErr }, 1, &pressed, nil, nil)
let status = RegisterEventHotKey(UInt32(kVK_ANSI_Slash), UInt32(controlKey), EventHotKeyID(signature: 0x54444B31, id: 1),
                                 GetApplicationEventTarget(), 0, &hotKeyRef)
if status != noErr { NSLog("TodoDeck: ⌃/ 단축키 등록 실패 (\(status)). 다른 앱이 쓰고 있을 수 있습니다.") }

app.run()
