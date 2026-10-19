import Foundation

/// "보고서 금요일까지", "과제 10/25 18시"처럼 끝에 붙은 날짜·시간을 마감으로 떼어낸다.
/// 알아듣는 말: 오늘·내일·모레·글피, 월~일요일, 다음주(담주), N일 후(뒤), 10/25·10.25, 10월·25일,
/// 오전·오후, 18시·6시반·6시 30분·18:30. 끝의 "까지"는 무시한다.
enum Due {
    static func parse(_ text: String, now: Date = Date(), calendar cal: Calendar = .current) -> (title: String, due: Date?) {
        var tokens = text.split(separator: " ").map(String.init)
        var offset: Int?, weekday: Int?, nextWeek = false, after = false
        var month: Int?, dom: Int?
        var hour: Int?, minute = 0, pm: Bool?

        // 뒤에서부터 날짜·시간처럼 보이는 토큰만 떼어낸다. 처음으로 모르는 말이 나오면 멈춘다.
        func take(_ t: String) -> Bool {
            let n = { (s: Substring) in Int(s)! }
            switch t {
            case "오늘": offset = 0
            case "내일": offset = 1
            case "모레": offset = 2
            case "글피": offset = 3
            case "다음주", "담주": nextWeek = true
            case "후", "뒤": after = true
            case "오전": pm = false
            case "오후": pm = true
            case "반": minute = 30
            default:
                if let m = t.wholeMatch(of: #/([월화수목금토일])요일/#) {
                    weekday = Array("일월화수목금토").firstIndex(of: Character(String(m.1)))! + 1
                } else if let m = t.wholeMatch(of: #/(\d+)일(후|뒤)/#) {
                    offset = n(m.1)
                } else if let m = t.wholeMatch(of: #/(\d{1,2})[\/.](\d{1,2})/#) {
                    month = n(m.1); dom = n(m.2)
                } else if let m = t.wholeMatch(of: #/(\d{1,2})월/#) {
                    month = n(m.1)
                } else if let m = t.wholeMatch(of: #/(\d{1,2})일/#) {
                    if after { offset = n(m.1) } else { dom = n(m.1) }
                } else if let m = t.wholeMatch(of: #/(오전|오후)?(\d{1,2})시(반|(\d{1,2})분)?/#) {
                    if let ap = m.1 { pm = ap == "오후" }
                    hour = n(m.2)
                    if m.3 == "반" { minute = 30 } else if let mm = m.4 { minute = n(mm) }
                } else if let m = t.wholeMatch(of: #/(\d{1,2}):(\d{2})/#) {
                    hour = n(m.1); minute = n(m.2)
                } else if let m = t.wholeMatch(of: #/(\d{1,2})분/#) {
                    minute = n(m.1)
                } else {
                    return false
                }
            }
            return true
        }

        while tokens.count > 1, var t = tokens.last {   // 제목이 한 단어는 남게
            if t.hasSuffix("까지") { t.removeLast(2) }
            guard !t.isEmpty, take(t) else { break }
            tokens.removeLast()
        }

        let today = cal.startOfDay(for: now)
        let add = { (days: Int) in cal.date(byAdding: .day, value: days, to: today)! }
        var day: Date?
        if let offset {
            day = add(offset)
        } else if let weekday {
            let todayW = cal.component(.weekday, from: today)
            if nextWeek {   // 다음주 = 다음 월요일부터 시작하는 주
                let mon = add((9 - todayW) % 7 == 0 ? 7 : (9 - todayW) % 7)
                day = cal.date(byAdding: .day, value: (weekday + 5) % 7, to: mon)
            } else {
                day = add((weekday - todayW + 7) % 7)   // 오늘이 그 요일이면 오늘
            }
        } else if nextWeek {
            let todayW = cal.component(.weekday, from: today)
            day = add((9 - todayW) % 7 == 0 ? 7 : (9 - todayW) % 7)
        } else if month != nil || dom != nil {
            var c = cal.dateComponents([.year, .month], from: today)
            if let month { c.month = month }
            c.day = dom ?? 1
            day = cal.date(from: c)
            if let d = day, d < today {   // 이미 지난 날짜면 다음 해(또는 다음 달)
                day = cal.date(byAdding: month != nil ? .year : .month, value: 1, to: d)
            }
        }

        if var h = hour {
            if pm == true, h < 12 { h += 12 }
            if pm == false, h == 12 { h = 0 }
            if pm == nil, (1...7).contains(h) { h += 12 }   // "6시"는 보통 저녁 6시
            let base = day ?? today
            var due = cal.date(bySettingHour: h, minute: minute, second: 0, of: base)!
            if day == nil, due <= now { due = cal.date(byAdding: .day, value: 1, to: due)! }   // 시간만 적었는데 지났으면 내일
            return (tokens.joined(separator: " "), due)
        }
        guard let day else { return (text, nil) }   // 날짜를 못 만들었으면 원문 그대로
        return (tokens.joined(separator: " "), cal.date(bySettingHour: 23, minute: 59, second: 0, of: day)!)
    }

    /// 남은 시간 표시: 지남 / 45분 / 5시간 / D-3
    static func remaining(_ due: Date, now: Date = Date(), calendar cal: Calendar = .current) -> String {
        let sec = due.timeIntervalSince(now)
        if sec < 0 { return "지남" }
        if sec < 3600 { return "\(max(1, Int(sec / 60)))분" }
        if sec < 86400 { return "\(Int(sec / 3600))시간" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: due)).day!
        return "D-\(days)"
    }
}
