import XCTest
@testable import TodoDeck

final class DueTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()
    // 기준: 2026-10-18(일) 14:00
    lazy var now = date(10, 18, 14)

    func date(_ m: Int, _ d: Int, _ h: Int, _ min: Int = 0, year: Int = 2026) -> Date {
        cal.date(from: DateComponents(year: year, month: m, day: d, hour: h, minute: min))!
    }

    func check(_ text: String, _ title: String, _ due: Date?, file: StaticString = #filePath, line: UInt = #line) {
        let r = Due.parse(text, now: now, calendar: cal)
        XCTAssertEqual(r.title, title, file: file, line: line)
        XCTAssertEqual(r.due, due, file: file, line: line)
    }

    func testParse() {
        check("보고서 금요일까지", "보고서", date(10, 23, 23, 59))
        check("과제 10/25 18시", "과제", date(10, 25, 18))
        check("발표 다음주 화요일 오후 3시", "발표", date(10, 20, 15))
        check("발표 다음주 일요일", "발표", date(10, 25, 23, 59))
        check("제출 내일 9시", "제출", date(10, 19, 9))
        check("운동 6시", "운동", date(10, 18, 18))
        check("운동 6시반", "운동", date(10, 18, 18, 30))
        check("회의 오전 8시", "회의", date(10, 19, 8))          // 오늘 8시는 지났으니 내일
        check("회의 18:30", "회의", date(10, 18, 18, 30))
        check("시험 10월 25일", "시험", date(10, 25, 23, 59))
        check("책 반납 1/5", "책 반납", date(1, 5, 23, 59, year: 2027))
        check("장보기 3일 후", "장보기", date(10, 21, 23, 59))
        check("빨래 일요일", "빨래", date(10, 18, 23, 59))          // 오늘이 일요일이면 오늘
        check("빨래", "빨래", nil)
        check("내일", "내일", nil)                                    // 마감만 있으면 그냥 제목
        check("3월 계획 세우기", "3월 계획 세우기", nil)               // 끝이 아니면 건드리지 않음
    }

    func testRemaining() {
        XCTAssertEqual(Due.remaining(date(10, 18, 13), now: now, calendar: cal), "지남")
        XCTAssertEqual(Due.remaining(date(10, 18, 14, 45), now: now, calendar: cal), "45분")
        XCTAssertEqual(Due.remaining(date(10, 19, 9), now: now, calendar: cal), "19시간")
        XCTAssertEqual(Due.remaining(date(10, 23, 23, 59), now: now, calendar: cal), "D-5")
    }
}
