import Foundation

/// What a date math row says. Enter copies the title.
struct DateAnswer: Equatable, Sendable {
    let title: String, subtitle: String
    var score: Double = 10 // math's
    var isTime = false
    var accessory = "" // the phrase it answers, when it's a suggestion
    var completion: String? = nil // a question's start, for the rest
}

private let monthNames = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october",
                          "november", "december"]
private let weekdayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"] // Calendar's order
private let holidays: [String: (month: Int, day: Int)] = ["christmas": (12, 25), "new year": (1, 1), "new years": (1, 1), "new year's": (1, 1)]

/// A month or weekday named by at least its first 3 letters ("dec", "sept", "thurs"): 1-based.
private func named(_ word: Substring, in names: [String]) -> Int? {
    word.count >= 3 ? names.firstIndex { $0.hasPrefix(word) }.map { $0 + 1 } : nil
}

private func unit(_ word: Substring) -> Calendar.Component? {
    switch word {
    case "minute", "minutes", "min", "mins": .minute
    case "hour", "hours", "hr", "hrs": .hour
    case "day", "days": .day
    case "week", "weeks", "wk", "wks": .weekOfYear
    case "month", "months": .month
    case "year", "years", "yr", "yrs": .year
    default: nil
    }
}

private func amount(_ word: Substring) -> Int { word == "a" || word == "an" ? 1 : Int(word) ?? 0 }

/// A day named in words: `dec 25`, `25 december 2027`, `dec 25th`, `2026-12-25`, `friday`, `next friday` (the one
/// after this week's, as macOS reads it), `last friday`, `today`, `tomorrow`, `yesterday`, `christmas`, `new year`.
/// Without its year, the next one, or with `past` the last one (today counts). `plainWeekday`: just a weekday's name.
func readDate(_ text: String, now: Date, calendar: Calendar, past: Bool = false) -> (date: Date, plainWeekday: Bool)? {
    let today = calendar.startOfDay(for: now)
    let day = { (offset: Int) in calendar.date(byAdding: .day, value: offset, to: today)! }
    let valid = { (year: Int, month: Int, day: Int) -> Date? in
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day))
        return date.flatMap { calendar.dateComponents([.year, .month, .day], from: $0) == DateComponents(year: year, month: month, day: day) ? $0 : nil }
    }
    switch text {
    case "today": return (today, false)
    case "tomorrow": return (day(1), false)
    case "yesterday": return (day(-1), false)
    default: break
    }
    if let iso = text.wholeMatch(of: #/(\d{4})-(\d{1,2})-(\d{1,2})/#) {
        return valid(Int(iso.1)!, Int(iso.2)!, Int(iso.3)!).map { ($0, false) }
    }
    if let match = text.wholeMatch(of: #/(?:(this|next|last) )?([a-z]+)/#), let weekday = named(match.2, in: weekdayNames) {
        let ahead = (weekday - calendar.component(.weekday, from: today) + 7) % 7 // the coming one: 0–6 days, today too
        let offset = switch match.1 {
        case "next": ahead + 7
        case "last": ahead == 0 ? -7 : ahead - 7
        case nil where past: ahead == 0 ? 0 : ahead - 7
        default: ahead
        }
        return (day(offset), match.1 == nil)
    }
    let words = { (month: Substring, day: Substring, year: Substring?) in
        named(month, in: monthNames).map { ($0, Int(day)!, year.map { Int($0)! }) }
    }
    guard let (month, date, year) = text.wholeMatch(of: #/([a-z]+)\.? (\d{1,2})(?:st|nd|rd|th)?(?:,? (\d{4}))?/#).flatMap({ words($0.1, $0.2, $0.3) })
            ?? text.wholeMatch(of: #/(\d{1,2})(?:st|nd|rd|th)? (?:of )?([a-z]+)\.?(?:,? (\d{4}))?/#).flatMap({ words($0.2, $0.1, $0.3) })
            ?? holidays[text].map({ ($0.month, $0.day, nil) })
    else { return nil }
    if let year { return valid(year, month, date).map { ($0, false) } }
    let thisYear = calendar.component(.year, from: today)
    guard let candidate = valid(thisYear, month, date) else { return nil }
    let wrong = past ? candidate > today : candidate < today
    return (wrong ? valid(thisYear + (past ? -1 : 1), month, date) ?? candidate : candidate, false)
}

/// `days until dec 25`, `weeks since jan 1`, `in 3 weeks`, `100 days from today`, `3 days ago`, `30 days after dec 25`,
/// `dec 25 + 2 weeks`, `monday in 3 weeks`, `time in 4 hours`, or a date alone (`dec 25`, `next friday`): its weekday,
/// how far it is and its week. Recognized by their shape, like math. nil for anything else.
func dateMath(_ query: String, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) -> DateAnswer? {
    var text = plainQuestion(query)
    if text.hasPrefix("time in ") { text.removeFirst(5) } // "time in 4 hours"; "time in lisbon" is a time zone's
    let today = calendar.startOfDay(for: now)
    let style = Date.FormatStyle(date: .complete, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    let daysAway = { (date: Date) in calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day! }
    let count = { (n: Int, noun: String) in "\(n.formatted(.number.locale(locale))) \(noun)\(n == 1 ? "" : "s")" }
    let read = { (text: Substring, past: Bool) in readDate(String(text), now: now, calendar: calendar, past: past)?.date }

    func dateRow(_ date: Date, score: Double = 10) -> DateAnswer {
        let days = daysAway(date)
        let when = switch days {
        case 0: "Today"
        case 1: "Tomorrow"
        case -1: "Yesterday"
        case 2...: "In \(count(days, "day"))"
        default: "\(count(-days, "day")) ago"
        }
        return DateAnswer(title: date.formatted(style), subtitle: "\(when) · week \(calendar.component(.weekOfYear, from: date))", score: score)
    }

    // How long until, or since
    if let match = text.wholeMatch(of: #/(days|weeks) (until|till|til|to|before|since|from|after) (.+)/#) {
        guard let date = read(match.3, ["since", "from", "after"].contains(match.2)) else { return nil }
        let days = daysAway(date), total = abs(days)
        let title = match.1 == "days" || total < 7 ? count(total, "day")
            : [count(total / 7, "week"), total % 7 == 0 ? nil : count(total % 7, "day")].compactMap(\.self).joined(separator: ", ")
        return DateAnswer(title: title, subtitle: "\(days < 0 ? "Since" : "Until") \(date.formatted(style))")
    }
    // That week's weekday
    if let match = text.wholeMatch(of: #/([a-z]+) in (a|an|\d{1,4}) weeks?/#), let weekday = named(match.1, in: weekdayNames),
       let later = calendar.date(byAdding: .weekOfYear, value: amount(match.2), to: today),
       let week = calendar.dateInterval(of: .weekOfYear, for: later) {
        return dateRow(calendar.date(byAdding: .day, value: (weekday - calendar.firstWeekday + 7) % 7, to: week.start)!)
    }
    // An amount of time from now, or from a date
    var offset: (amount: Int, unit: Substring, from: Date?)?
    if let match = text.wholeMatch(of: #/in (a|an|\d{1,5}) ([a-z]+)/#) {
        offset = (amount(match.1), match.2, nil)
    } else if let match = text.wholeMatch(of: #/(a|an|\d{1,5}) ([a-z]+) (from now|from today|later|ago)/#) {
        offset = (amount(match.1) * (match.3 == "ago" ? -1 : 1), match.2, nil)
    } else if let match = text.wholeMatch(of: #/(a|an|\d{1,5}) ([a-z]+) (after|from|before) (.+)/#) {
        guard let date = read(match.4, false) else { return nil }
        offset = (amount(match.1) * (match.3 == "before" ? -1 : 1), match.2, date)
    } else if let match = text.wholeMatch(of: #/(.+?) ?([+-]) ?(a|an|\d{1,5}) ([a-z]+)/#) {
        guard let date = read(match.1, false) else { return nil }
        offset = (amount(match.3) * (match.2 == "-" ? -1 : 1), match.4, date)
    }
    if let offset {
        guard let unit = unit(offset.unit) else { return nil }
        guard unit == .minute || unit == .hour else {
            return calendar.date(byAdding: unit, value: offset.amount, to: offset.from ?? today).map { dateRow($0) }
        }
        guard offset.from == nil, let time = calendar.date(byAdding: unit, value: offset.amount, to: now) else { return nil }
        let days = daysAway(time)
        return DateAnswer(title: time.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar,
                                                                 timeZone: calendar.timeZone)),
                          subtitle: days == 0 ? "Today" : days == 1 ? "Tomorrow" : days == -1 ? "Yesterday" : time.formatted(style), isTime: true)
    }
    // A date alone. Just a weekday's name ranks low: it may be an app's; an ISO date ranks over its subtraction.
    guard let (date, plainWeekday) = readDate(text, now: now, calendar: calendar) else { return nil }
    return dateRow(date, score: plainWeekday ? 0.5 : text.first?.isNumber == true && text.contains("-") ? 11 : 10)
}

/// "How many days until dec 25?" → "days until dec 25".
private func plainQuestion(_ query: String) -> String {
    var text = query.lowercased().trimmingCharacters(in: .whitespaces).replacing(#/\s+/#, with: " ")
    if text.hasPrefix("how many ") { text.removeFirst(9) }
    return text.hasSuffix("?") ? text.dropLast().trimmingCharacters(in: .whitespaces) : text
}

/// A phrase on its way, so nobody has to know them first: `in 3` answers in 3 days, weeks, months and hours, `3 weeks`
/// from now and ago; `days` and `weeks` offer until and since a date, a Tab away from typing it.
func dateSuggestions(_ query: String, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) -> [DateAnswer] {
    let text = plainQuestion(query)
    let ends: [String] = if text.wholeMatch(of: #/in (a|an|\d{1,5})/#) != nil { ["days", "weeks", "months", "hours"] }
        else if let match = text.wholeMatch(of: #/(?:a|an|\d{1,5}) ([a-z]+)/#), unit(match.1) != nil { ["from now", "ago"] }
        else { [] }
    if !ends.isEmpty {
        return ends.enumerated().compactMap { index, end in
            let phrase = "\(text) \(end)"
            return dateMath(phrase, now: now, calendar: calendar, locale: locale).map { answer in
                var answer = answer
                (answer.accessory, answer.score) = (phrase, 10 - Double(index) / 100)
                return answer
            }
        }
    }
    guard text.count >= 3 else { return [] }
    let questions = [("days until ", "Days Until a Date"), ("days since ", "Days Since a Date"),
                     ("weeks until ", "Weeks Until a Date"), ("weeks since ", "Weeks Since a Date")]
    return questions.filter { $0.0.hasPrefix(text) }.map { start, title in
        DateAnswer(title: title, subtitle: "Type a date: dec 25, friday, christmas", score: 1, completion: start)
    }
}

struct DateMathProvider: ResultProvider {
    func results(for query: String) async -> [LauncherResult] {
        let answers = dateMath(query).map { [$0] } ?? dateSuggestions(query)
        return answers.map { answer in
            LauncherResult(id: "date:\(answer.accessory)\(answer.completion ?? "")", title: answer.title, subtitle: answer.subtitle,
                           accessory: answer.accessory, icon: .symbol(answer.isTime ? "clock" : "calendar"), score: answer.score,
                           actionTitle: answer.completion == nil ? "Copy" : "Start", action: { copyToClipboard(answer.title) },
                           completion: answer.completion)
        }
    }
}
