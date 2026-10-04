// Campus Koethen App - AGPL-3.0-only
// Copyright (c) 2026 Leviora Studio and Jona Loreen Sommer

import SwiftUI
import WidgetKit

private let appGroup = "group.dev.erikengler.campuskoethen"
private let payloadKey = "calendar_widget_payload"
private let widgetKind = "CampusCalendarWidget"
private let launchURL = URL(string: "campuskoethen://calendar?homeWidget=1")

private struct CalendarPayload: Decodable {
    let version: Int
    let enabled: Bool
    let generatedAt: Int64
    let locale: String
    let showDetails: Bool
    let events: [CalendarEvent]

    static let disabled = CalendarPayload(
        version: 1,
        enabled: false,
        generatedAt: 0,
        locale: "de",
        showDetails: false,
        events: []
    )
}

private struct CalendarEvent: Decodable, Identifiable {
    let id: String
    let start: Int64
    let end: Int64
    let allDay: Bool
    let title: String?
    let location: String?

    var startDate: Date { Date(timeIntervalSince1970: Double(start) / 1000) }
    var endDate: Date { Date(timeIntervalSince1970: Double(end) / 1000) }
}

private struct CalendarEntry: TimelineEntry {
    let date: Date
    let payload: CalendarPayload
}

private struct CalendarProvider: TimelineProvider {
    func placeholder(in context: Context) -> CalendarEntry {
        CalendarEntry(date: Date(), payload: .disabled)
    }

    func getSnapshot(in context: Context, completion: @escaping (CalendarEntry) -> Void) {
        completion(CalendarEntry(date: Date(), payload: loadPayload()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CalendarEntry>) -> Void) {
        let now = Date()
        let payload = loadPayload()
        let nextBoundary = payload.events
            .flatMap { [$0.startDate, $0.endDate] }
            .filter { $0 > now }
            .min()
        let regularRefresh = now.addingTimeInterval(30 * 60)
        let nextRefresh = min(nextBoundary ?? regularRefresh, regularRefresh)
        completion(Timeline(
            entries: [CalendarEntry(date: now, payload: payload)],
            policy: .after(nextRefresh)
        ))
    }

    private func loadPayload() -> CalendarPayload {
        guard
            let defaults = UserDefaults(suiteName: appGroup),
            let raw = defaults.string(forKey: payloadKey),
            raw.utf8.count <= 64 * 1024,
            let data = raw.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(CalendarPayload.self, from: data),
            decoded.version == 1
        else {
            return .disabled
        }
        return decoded
    }
}

private struct WidgetCopy {
    let language: String

    private var bundle: Bundle {
        let selected = language == "en" ? "en" : "de"
        guard
            let path = Bundle.main.path(forResource: selected, ofType: "lproj"),
            let localized = Bundle(path: path)
        else {
            return .main
        }
        return localized
    }

    func text(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    func updated(_ date: Date) -> String {
        String(format: text("widget.updated"), formatDate(date, dateStyle: .short, timeStyle: .short))
    }

    func when(_ event: CalendarEvent, now: Date) -> String {
        let calendar = Calendar.current
        let day: String
        if calendar.isDate(event.startDate, inSameDayAs: now) {
            day = text("widget.today")
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
                  calendar.isDate(event.startDate, inSameDayAs: tomorrow) {
            day = text("widget.tomorrow")
        } else {
            day = formatDate(event.startDate, dateStyle: .short, timeStyle: .none)
        }
        if event.allDay {
            return "\(day) \u{00B7} \(text("widget.allDay"))"
        }
        return "\(day) \u{00B7} \(formatDate(event.startDate, dateStyle: .none, timeStyle: .short))"
    }

    private func formatDate(
        _ date: Date,
        dateStyle: DateFormatter.Style,
        timeStyle: DateFormatter.Style
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == "en" ? "en" : "de")
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        return formatter.string(from: date)
    }
}

private struct CalendarWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CalendarEntry

    private var copy: WidgetCopy { WidgetCopy(language: entry.payload.locale) }

    private var events: [CalendarEvent] {
        let now = entry.date
        let maximum = family == .systemSmall ? 1 : 3
        return Array(entry.payload.events
            .filter { $0.endDate > now || ($0.end <= $0.start && $0.startDate > now) }
            .sorted { lhs, rhs in
                lhs.start == rhs.start ? lhs.id < rhs.id : lhs.start < rhs.start
            }
            .prefix(maximum))
    }

    var body: some View {
        widgetBackground {
            VStack(alignment: .leading, spacing: 7) {
                Label(copy.text("widget.title"), systemImage: "calendar")
                    .font(.headline)
                    .lineLimit(1)

                if !entry.payload.enabled {
                    message(copy.text("widget.disabled"))
                } else if events.isEmpty {
                    message(copy.text("widget.empty"))
                } else {
                    ForEach(events) { event in
                        eventRow(event)
                    }
                }

                Spacer(minLength: 0)
                if entry.payload.enabled, entry.payload.generatedAt > 0 {
                    Text(copy.updated(Date(
                        timeIntervalSince1970: Double(entry.payload.generatedAt) / 1000
                    )))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
            .padding()
        }
        .widgetURL(launchURL)
    }

    @ViewBuilder
    private func widgetBackground<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            content().containerBackground(.fill.tertiary, for: .widget)
        } else {
            content().background(Color(.systemBackground))
        }
    }

    private func message(_ value: String) -> some View {
        Text(value)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func eventRow(_ event: CalendarEvent) -> some View {
        let showDetails = entry.payload.showDetails
        let title = showDetails
            ? event.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        let visibleTitle = title?.isEmpty == false ? title! : copy.text("widget.privateEvent")
        let location = showDetails
            ? event.location?.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        return VStack(alignment: .leading, spacing: 1) {
            Text(copy.when(event, now: entry.date))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(location?.isEmpty == false ? "\(visibleTitle) \u{00B7} \(location!)" : visibleTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CampusCalendarWidget: Widget {
    let kind = widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CalendarProvider()) { entry in
            CalendarWidgetView(entry: entry)
        }
        .configurationDisplayName("Campus Koethen")
        .description("widget.description")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct CampusCalendarWidgetBundle: WidgetBundle {
    var body: some Widget {
        CampusCalendarWidget()
    }
}
