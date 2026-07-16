import SwiftUI

struct CompactNavigationBar: View {
    @Binding var scrollDate: Date
    let kind: TimeRangeKind
    let barCount: Int
    let visibleDuration: TimeInterval
    let minDate: Date   // earliest data point — left arrow clamps here
    var useUTCDateRange: Bool = false
    let onResetToPresent: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button { shift(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.25), value: label)

            if !isAtPresent {
                Button("Now") {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        onResetToPresent()
                    }
                }
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.blue)
                .buttonStyle(.plain)
            }

            Button { shift(by: +1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private func shift(by direction: Int) {
        let cal = Calendar.cycleAnchored
        guard let newDate = cal.date(byAdding: kind.bucketComponent, value: direction, to: scrollDate) else { return }
        // Going back: block if the window would end before any data exists
        let windowEnd = cal.date(byAdding: kind.bucketComponent, value: barCount, to: newDate)
            ?? newDate.addingTimeInterval(visibleDuration)
        if direction < 0, windowEnd < minDate { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            scrollDate = newDate
        }
    }

    private var visibleEnd: Date { scrollDate.addingTimeInterval(visibleDuration) }
    private var isAtPresent: Bool { scrollDate <= Date() && visibleEnd >= Date() }
    private var dateDisplayTimeZone: TimeZone {
        useUTCDateRange ? Calendar.cycleAnchored.timeZone : TimeZone.current
    }

    private var label: String {
        let end = visibleEnd.addingTimeInterval(-1)
        switch kind {
        case .day, .week:
            guard useUTCDateRange else {
                let s = scrollDate.formatted(.dateTime.month(.abbreviated).day())
                let e = end.formatted(.dateTime.month(.abbreviated).day())
                return "\(s) – \(e)"
            }
            let s = DateDisplayFormatting.monthDay(scrollDate, calendar: dateDisplayCalendar, timeZone: dateDisplayTimeZone)
            let e = DateDisplayFormatting.monthDay(end, calendar: dateDisplayCalendar, timeZone: dateDisplayTimeZone)
            return "\(s) – \(e) UTC"
        case .month:
            guard useUTCDateRange else {
                let s = scrollDate.formatted(.dateTime.month(.abbreviated).year())
                let e = end.formatted(.dateTime.month(.abbreviated).year())
                return "\(s) – \(e)"
            }
            let s = DateDisplayFormatting.monthYear(scrollDate, calendar: dateDisplayCalendar, timeZone: dateDisplayTimeZone)
            let e = DateDisplayFormatting.monthYear(end, calendar: dateDisplayCalendar, timeZone: dateDisplayTimeZone)
            return "\(s) – \(e) UTC"
        }
    }

    private var dateDisplayCalendar: Calendar {
        useUTCDateRange ? Calendar.cycleAnchored : Calendar.current
    }
}
