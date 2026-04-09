//
//  DynamicWidgetRenderer.swift
//  cursor-toolbar
//
//  Renders a WidgetBlueprint at runtime using SwiftUI.
//  Supports: text, liveTime, liveDate, spacer, divider, vstack, hstack,
//            systemInfo, progressRing, image, apiText (with REST data sources).
//

import Combine
import Foundation
import SwiftUI

// MARK: - API Data Manager

/// Fetches REST data sources on a refresh timer and publishes results keyed by data source ID.
@MainActor
final class APIDataManager: ObservableObject {
    @Published var results: [String: Any] = [:]
    @Published var errors: [String: String] = [:]
    private var timers: [String: Timer] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]

    func configure(dataSources: [WidgetDataSource]) {
        // Cancel existing timers/tasks
        cancelAll()

        for source in dataSources {
            // Initial fetch
            fetchData(source: source)

            // Schedule refresh
            let interval = source.refreshIntervalSeconds ?? 600
            guard interval > 0 else { continue }
            let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.fetchData(source: source)
                }
            }
            timers[source.id] = timer
        }
    }

    func cancelAll() {
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }

    private func fetchData(source: WidgetDataSource) {
        tasks[source.id]?.cancel()
        tasks[source.id] = Task { [weak self] in
            guard let url = URL(string: source.url) else {
                self?.errors[source.id] = "Invalid URL"
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = source.method ?? "GET"
            request.timeoutInterval = 15
            if let headers = source.headers {
                for (key, value) in headers {
                    request.setValue(value, forHTTPHeaderField: key)
                }
            }

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    self?.errors[source.id] = "HTTP error"
                    return
                }
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    self?.results[source.id] = json
                    self?.errors.removeValue(forKey: source.id)
                }
            } catch {
                if !Task.isCancelled {
                    self?.errors[source.id] = error.localizedDescription
                }
            }
        }
    }

    /// Extract a value from cached JSON using a dot-separated key path like "current_weather.temperature".
    func value(forSource sourceId: String, keyPath: String?) -> String? {
        guard let root = results[sourceId], let keyPath = keyPath, !keyPath.isEmpty else { return nil }
        let components = keyPath.split(separator: ".").map(String.init)
        var current: Any = root
        for component in components {
            if let dict = current as? [String: Any], let next = dict[component] {
                current = next
            } else if let array = current as? [Any], let index = Int(component), index < array.count {
                current = array[index]
            } else {
                return nil
            }
        }
        // Format numbers nicely
        if let num = current as? Double {
            if num == num.rounded() {
                return String(Int(num))
            }
            return String(format: "%.1f", num)
        }
        if let num = current as? Int {
            return String(num)
        }
        return "\(current)"
    }

    deinit {
        timers.values.forEach { $0.invalidate() }
    }
}

// MARK: - Dynamic Widget Renderer

struct DynamicWidgetRenderer: View {
    let blueprint: WidgetBlueprint
    @StateObject private var apiManager = APIDataManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blueprint.elements.enumerated()), id: \.offset) { _, element in
                WidgetElementView(element: element, apiManager: apiManager)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            if let sources = blueprint.dataSources, !sources.isEmpty {
                apiManager.configure(dataSources: sources)
            }
        }
        .onDisappear {
            apiManager.cancelAll()
        }
    }
}

// MARK: - Widget Element View (non-recursive, uses AnyView for children)

/// Renders a single WidgetElement. Uses AnyView to break SwiftUI's recursive type inference.
struct WidgetElementView: View {
    let element: WidgetElement
    @ObservedObject var apiManager: APIDataManager

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        switch element.type {
        case "text":
            Text(element.content ?? "")
                .font(.system(
                    size: element.style?.fontSize ?? 13,
                    weight: resolveWeight(element.style?.fontWeight)
                ))
                .foregroundStyle(Color.white.opacity(element.style?.opacity ?? 0.9))

        case "liveTime":
            LiveTimeView(format: element.content ?? "HH:mm:ss", style: element.style)

        case "liveDate":
            LiveDateView(format: element.content ?? "EEEE, MMM d, yyyy", style: element.style)

        case "spacer":
            Spacer(minLength: element.style?.spacing ?? 4)

        case "divider":
            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(height: 1)
                .padding(.vertical, 2)

        case "vstack":
            VStack(alignment: resolveAlignment(element.style?.alignment), spacing: element.style?.spacing ?? 6) {
                childrenViews
            }

        case "hstack":
            HStack(alignment: .center, spacing: element.style?.spacing ?? 6) {
                childrenViews
            }

        case "systemInfo":
            SystemInfoView(key: element.content ?? "hostname", style: element.style)

        case "progressRing":
            DayProgressRing(style: element.style)

        case "image":
            Image(systemName: element.content ?? "questionmark")
                .font(.system(size: element.style?.fontSize ?? 20, weight: resolveWeight(element.style?.fontWeight)))
                .foregroundStyle(Color.white.opacity(element.style?.opacity ?? 0.85))

        case "apiText":
            APITextView(element: element, apiManager: apiManager)

        default:
            Text("Unknown: \(element.type)")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.4))
        }
    }

    /// Renders children using AnyView to break recursive type inference.
    @ViewBuilder
    private var childrenViews: some View {
        if let children = element.children {
            ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                AnyView(WidgetElementView(element: child, apiManager: apiManager))
            }
        }
    }
}

// MARK: - Live Time View

private struct LiveTimeView: View {
    let format: String
    let style: WidgetStyle?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let formatted = Self.formatDate(context.date, format: format)
            Text(formatted)
                .font(.system(
                    size: style?.fontSize ?? 42,
                    weight: resolveWeight(style?.fontWeight ?? "bold"),
                    design: (style?.monospacedDigits ?? true) ? .monospaced : .default
                ))
                .foregroundStyle(Color.white.opacity(style?.opacity ?? 1.0))
        }
    }

    private static func formatDate(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}

// MARK: - Live Date View

private struct LiveDateView: View {
    let format: String
    let style: WidgetStyle?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60.0)) { context in
            let formatted = Self.formatDate(context.date, format: format)
            Text(formatted)
                .font(.system(
                    size: style?.fontSize ?? 14,
                    weight: resolveWeight(style?.fontWeight ?? "medium")
                ))
                .foregroundStyle(Color.white.opacity(style?.opacity ?? 0.72))
        }
    }

    private static func formatDate(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}

// MARK: - System Info View

private struct SystemInfoView: View {
    let key: String
    let style: WidgetStyle?

    var body: some View {
        Text(resolveSystemInfo(key))
            .font(.system(
                size: style?.fontSize ?? 13,
                weight: resolveWeight(style?.fontWeight)
            ))
            .foregroundStyle(Color.white.opacity(style?.opacity ?? 0.72))
    }

    private func resolveSystemInfo(_ key: String) -> String {
        switch key.lowercased() {
        case "hostname":
            return Host.current().localizedName ?? "Unknown"
        case "username":
            return NSFullUserName()
        case "os", "osversion":
            let v = ProcessInfo.processInfo.operatingSystemVersion
            return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        case "uptime":
            let seconds = ProcessInfo.processInfo.systemUptime
            let hours = Int(seconds) / 3600
            let minutes = (Int(seconds) % 3600) / 60
            return "\(hours)h \(minutes)m"
        case "memory":
            return "\(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)) GB RAM"
        default:
            return key
        }
    }
}

// MARK: - Day Progress Ring

private struct DayProgressRing: View {
    let style: WidgetStyle?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60.0)) { context in
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: context.date)
            let elapsed = context.date.timeIntervalSince(startOfDay)
            let fraction = min(elapsed / 86400.0, 1.0)
            let percentage = Int(fraction * 100)

            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(percentage)%")
                        .font(.system(
                            size: style?.fontSize ?? 13,
                            weight: resolveWeight(style?.fontWeight ?? "semibold"),
                            design: .monospaced
                        ))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                .frame(width: 64, height: 64)

                Text("Day progress")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
    }
}

// MARK: - API Text View

private struct APITextView: View {
    let element: WidgetElement
    @ObservedObject var apiManager: APIDataManager

    var body: some View {
        let sourceId = element.dataSourceId ?? ""
        let value = apiManager.value(forSource: sourceId, keyPath: element.keyPath)
        let displayText: String = {
            if let value = value {
                return (element.prefix ?? "") + value + (element.suffix ?? "")
            } else if let error = apiManager.errors[sourceId] {
                return "⚠ \(error)"
            } else {
                return element.fallback ?? "Loading…"
            }
        }()

        Text(displayText)
            .font(.system(
                size: element.style?.fontSize ?? 13,
                weight: resolveWeight(element.style?.fontWeight)
            ))
            .foregroundStyle(Color.white.opacity(element.style?.opacity ?? 0.9))
    }
}

// MARK: - Helpers

private func resolveWeight(_ name: String?) -> Font.Weight {
    switch name?.lowercased() {
    case "ultralight": return .ultraLight
    case "thin": return .thin
    case "light": return .light
    case "regular": return .regular
    case "medium": return .medium
    case "semibold": return .semibold
    case "bold": return .bold
    case "heavy": return .heavy
    case "black": return .black
    default: return .regular
    }
}

private func resolveAlignment(_ name: String?) -> HorizontalAlignment {
    switch name?.lowercased() {
    case "center": return .center
    case "trailing": return .trailing
    default: return .leading
    }
}
