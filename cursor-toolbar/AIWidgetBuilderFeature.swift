//
//  AIWidgetBuilderFeature.swift
//  cursor-toolbar
//

import Combine
import Foundation
import SwiftUI

enum LLMProvider: String, CaseIterable, Identifiable {
    case gemini = "Gemini"
    case groq = "Groq (Llama 3)"
    var id: String { rawValue }
}

private enum AIWidgetBuilderConstants {
    static let providerDefaultsKey = "ai_widget_builder_provider"
    static let geminiApiKeyDefaultsKey = "gemini_api_key"
    static let groqApiKeyDefaultsKey = "groq_api_key"
    static let geminiModel = "gemini-2.0-flash-lite"
    static let groqModel = "llama-3.3-70b-versatile"
    static let generatedWidgetsKey = "toolbar_generated_widgets_v1"
}

private struct GeminiGenerateResponse: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable {
                let text: String?
            }

            let parts: [Part]?
        }

        let content: Content?
    }

    let candidates: [Candidate]?
}

@MainActor
final class AIWidgetBuilderState: ObservableObject {
    @Published var provider: LLMProvider
    @Published var userGoal: String = ""
    @Published var apiKey: String
    @Published var isGenerating: Bool = false
    @Published var statusText: String = "Describe the widget you want, then generate."
    @Published var outputFileName: String?
    @Published var progress: Double = 0

    private var progressTask: Task<Void, Never>?
    var flow: ToolbarFlowState?

    init() {
        let savedProv = UserDefaults.standard.string(forKey: AIWidgetBuilderConstants.providerDefaultsKey) ?? ""
        let p = LLMProvider(rawValue: savedProv) ?? .gemini
        self.provider = p
        
        let defaultsKey = p == .gemini ? AIWidgetBuilderConstants.geminiApiKeyDefaultsKey : AIWidgetBuilderConstants.groqApiKeyDefaultsKey
        self.apiKey = UserDefaults.standard.string(forKey: defaultsKey) ?? ""
    }

    func switchProvider(to newProvider: LLMProvider) {
        provider = newProvider
        UserDefaults.standard.set(newProvider.rawValue, forKey: AIWidgetBuilderConstants.providerDefaultsKey)
        let defaultsKey = newProvider == .gemini ? AIWidgetBuilderConstants.geminiApiKeyDefaultsKey : AIWidgetBuilderConstants.groqApiKeyDefaultsKey
        apiKey = UserDefaults.standard.string(forKey: defaultsKey) ?? ""
        statusText = "Switched to \(newProvider.rawValue). Describe the widget you want, then generate."
    }

    func clearApiKey() {
        apiKey = ""
        let defaultsKey = provider == .gemini ? AIWidgetBuilderConstants.geminiApiKeyDefaultsKey : AIWidgetBuilderConstants.groqApiKeyDefaultsKey
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        statusText = "API key cleared. Sign in with a different account to generate."
    }

    // Use #filePath at compile time to locate the project source directory.
    private static let projectSourceDir: URL = {
        let thisFile = URL(fileURLWithPath: #filePath)
        // This file is in cursor-toolbar/cursor-toolbar/AIWidgetBuilderFeature.swift
        // .deletingLastPathComponent() gives cursor-toolbar/cursor-toolbar/
        return thisFile.deletingLastPathComponent()
    }()

    private var systemPrompt: String {
        """
        You are an AI agent that creates widget definitions for a macOS toolbar app called cursor-toolbar.
        The app renders widgets from JSON blueprints at runtime.

        You MUST output ONLY valid JSON — no markdown fences, no explanation, no commentary.

        The JSON schema is:
        {
          "title": "<PascalCaseWidgetName>",
          "dataSources": [                         // optional, only for widgets needing REST data
            {
              "id": "<unique_source_id>",
              "url": "<full_endpoint_url>",
              "method": "GET",
              "headers": {},
              "refreshIntervalSeconds": 600
            }
          ],
          "elements": [
            {
              "type": "<element_type>",
              "content": "<string>",               // depends on type
              "style": {
                "fontSize": 13,
                "fontWeight": "regular",           // ultralight/thin/light/regular/medium/semibold/bold/heavy/black
                "opacity": 1.0,
                "alignment": "leading",            // leading/center/trailing
                "spacing": 6,
                "monospacedDigits": false,
                "color": "white"                   // white/secondary/accent
              },
              "children": [],                      // for vstack/hstack only

              // apiText-specific fields:
              "dataSourceId": "<source_id>",
              "keyPath": "path.to.value",
              "prefix": "",
              "suffix": "",
              "fallback": "Loading..."
            }
          ]
        }

        Supported element types:
        - "text": Static label. "content" is the text string.
        - "liveTime": Auto-updating clock. "content" is the date format (e.g. "HH:mm:ss").
        - "liveDate": Auto-updating date. "content" is the date format (e.g. "EEEE, MMM d, yyyy").
        - "spacer": Empty flexible space.
        - "divider": Thin horizontal line.
        - "vstack": Vertical container. Uses "children" array and "style.spacing".
        - "hstack": Horizontal container. Uses "children" array and "style.spacing".
        - "systemInfo": System data. "content" is the key: "hostname", "username", "os", "uptime", or "memory".
        - "progressRing": Circular ring showing % of day elapsed.
        - "image": SF Symbol icon. "content" is the SF Symbol name (e.g. "clock.fill").
        - "apiText": Text from a REST API. Requires "dataSourceId", "keyPath", and optional "prefix"/"suffix"/"fallback".

        Rules for REST APIs / dataSources:
        - Only use FREE, public, no-authentication-required APIs.
        - For weather, use Open-Meteo: https://api.open-meteo.com/v1/forecast?latitude=37.98&longitude=23.73&current_weather=true
        - For timezone data, use WorldTimeAPI: http://worldtimeapi.org/api/timezone/Europe/Athens
        - "keyPath" uses dot notation to traverse JSON (e.g. "current_weather.temperature").
        - Include a reasonable "refreshIntervalSeconds" (e.g. 600 for weather, 60 for time-based APIs).
        - Always provide a "fallback" text for loading state.

        Design guidelines:
        - Use white text on dark translucent backgrounds (the app provides the glass background).
        - Large prominent values (time, temperature) should use fontSize 36-48, fontWeight "bold".
        - Labels/subtitles should use fontSize 11-13, fontWeight "medium", opacity 0.55-0.72.
        - Group related elements in vstack/hstack containers.
        - Use SF Symbols via "image" elements for visual flair.

        Output ONLY the JSON object. No explanation. No markdown. No code fences.
        """
    }

    func generateWidgetFile() {
        let trimmedGoal = userGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedGoal.isEmpty else {
            statusText = "Enter a widget request first."
            return
        }
        guard !trimmedKey.isEmpty else {
            statusText = "Add an API key first."
            return
        }

        let defaultsKey = provider == .gemini ? AIWidgetBuilderConstants.geminiApiKeyDefaultsKey : AIWidgetBuilderConstants.groqApiKeyDefaultsKey
        UserDefaults.standard.set(trimmedKey, forKey: defaultsKey)
        isGenerating = true
        progress = 0.06
        statusText = "Generating widget blueprint…"
        outputFileName = nil

        Task {
            startProgressAnimation()
            do {
                let (title, blueprint) = try await generateBlueprint(goal: trimmedGoal, apiKey: trimmedKey)

                progressTask?.cancel()
                progress = 1.0

                let widgetId = UUID().uuidString
                let newWidget = GeneratedWidgetDefinition(
                    id: widgetId,
                    title: title,
                    requestText: trimmedGoal,
                    generatedSummary: "Created from prompt: \(trimmedGoal)",
                    blueprint: blueprint
                )

                // Persist to UserDefaults
                persistGeneratedWidget(newWidget)

                // Immediate registration
                if let flow = flow {
                    flow.registerGeneratedWidget(newWidget)
                }

                // Save a .swift template file to the project's GeneratedWidgets folder
                let savedPath = saveSwiftTemplate(title: title, blueprint: blueprint)

                outputFileName = "\(title).json"
                statusText = "✓ Widget ready! Added to dashboard list.\(savedPath != nil ? " Swift file saved to GeneratedWidgets/." : "")"

            } catch {
                progressTask?.cancel()
                progress = 0
                statusText = "Generation failed: \(error.localizedDescription)"
            }
            isGenerating = false
        }
    }

    private func startProgressAnimation() {
        progressTask?.cancel()
        progressTask = Task { @MainActor in
            while !Task.isCancelled && isGenerating {
                try? await Task.sleep(nanoseconds: 180_000_000)
                if progress < 0.9 {
                    progress += 0.03
                }
            }
        }
    }

    private func generateBlueprint(goal: String, apiKey: String) async throws -> (String, WidgetBlueprint) {
        let rawText: String
        switch provider {
        case .gemini:
            rawText = try await generateWithGemini(goal: goal, apiKey: apiKey)
        case .groq:
            rawText = try await generateWithGroq(goal: goal, apiKey: apiKey)
        }

        // Extract the JSON from the response (strip markdown fences if present)
        let jsonString = extractJSON(from: rawText)
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw NSError(
                domain: "AIWidgetBuilder",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Could not encode response as UTF-8."]
            )
        }

        // Parse the full response to get title + blueprint
        let fullResponse = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        let title = (fullResponse?["title"] as? String) ?? "GeneratedWidget"

        // Decode blueprint (elements + dataSources)
        let blueprint = try JSONDecoder().decode(WidgetBlueprint.self, from: jsonData)

        return (title, blueprint)
    }

    private func generateWithGemini(goal: String, apiKey: String) async throws -> String {
        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(AIWidgetBuilderConstants.geminiModel):generateContent?key=\(apiKey)"
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }

        let requestBody: [String: Any] = [
            "systemInstruction": [
                "parts": [["text": systemPrompt]],
            ],
            "contents": [[
                "role": "user",
                "parts": [[
                    "text": "Create a widget for this request: \(goal)",
                ]],
            ]],
            "generationConfig": [
                "temperature": 0.3,
                "maxOutputTokens": 4096,
            ],
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: requestBody)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown API error."
            throw NSError(
                domain: "AIWidgetBuilder",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: body]
            )
        }

        let decoded = try JSONDecoder().decode(GeminiGenerateResponse.self, from: data)
        let rawText = decoded.candidates?
            .first?
            .content?
            .parts?
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rawText.isEmpty else {
            throw NSError(
                domain: "AIWidgetBuilder",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Model returned empty output."]
            )
        }
        
        return rawText
    }

    private func generateWithGroq(goal: String, apiKey: String) async throws -> String {
        let endpoint = "https://api.groq.com/openai/v1/chat/completions"
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }

        let requestBody: [String: Any] = [
            "model": AIWidgetBuilderConstants.groqModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": "Create a widget for this request: \(goal)"]
            ],
            "temperature": 0.3,
            "max_tokens": 4096,
            "response_format": ["type": "json_object"]
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: requestBody)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown API error."
            throw NSError(
                domain: "AIWidgetBuilder",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: body]
            )
        }

        // Parse standard OpenAI chat completions schema
        struct GroqResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String?
                }
                let message: Message?
            }
            let choices: [Choice]?
        }
        
        let decoded = try JSONDecoder().decode(GroqResponse.self, from: data)
        let rawText = decoded.choices?.first?.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        guard !rawText.isEmpty else {
            throw NSError(
                domain: "AIWidgetBuilder",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Groq Model returned empty output."]
            )
        }
        return rawText
    }

    /// Extract JSON from AI response text, stripping markdown fences and preamble if present.
    private func extractJSON(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // If it starts with '{', assume it's already clean JSON
        if trimmed.hasPrefix("{") {
            return trimmed
        }

        // Try to extract from markdown code fences
        if trimmed.contains("```") {
            let lines = trimmed.components(separatedBy: .newlines)
            var insideFence = false
            var captured: [String] = []

            for line in lines {
                let stripped = line.trimmingCharacters(in: .whitespaces)
                if stripped.hasPrefix("```") {
                    if insideFence {
                        break
                    }
                    insideFence = true
                    continue
                }
                if insideFence {
                    captured.append(line)
                }
            }

            let fenced = captured.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !fenced.isEmpty && fenced.hasPrefix("{") {
                return fenced
            }
        }

        // Last resort: find the first '{' and last '}' and extract
        if let startIdx = trimmed.firstIndex(of: "{"),
           let endIdx = trimmed.lastIndex(of: "}") {
            return String(trimmed[startIdx...endIdx])
        }

        return trimmed
    }

    /// Save a .swift template file to the project's GeneratedWidgets folder.
    @discardableResult
    private func saveSwiftTemplate(title: String, blueprint: WidgetBlueprint) -> String? {
        let folderURL = Self.projectSourceDir.appendingPathComponent("GeneratedWidgets", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let safeName = title.replacingOccurrences(of: " ", with: "")
        let fileName = "\(safeName)Feature.swift"
        let fileURL = folderURL.appendingPathComponent(fileName)

        // Generate a Swift template based on the blueprint
        let code = generateSwiftTemplate(title: safeName, blueprint: blueprint)
        do {
            try code.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL.path
        } catch {
            return nil
        }
    }

    /// Generates a Swift source template from a WidgetBlueprint for manual Xcode integration.
    private func generateSwiftTemplate(title: String, blueprint: WidgetBlueprint) -> String {
        var lines: [String] = []
        lines.append("//")
        lines.append("//  \(title)Feature.swift")
        lines.append("//  cursor-toolbar")
        lines.append("//")
        lines.append("//  Auto-generated by AI Widget Builder.")
        lines.append("//  This is a template — add this file to your Xcode project to compile.")
        lines.append("//")
        lines.append("")
        lines.append("import SwiftUI")
        lines.append("")
        lines.append("struct \(title)SectionView: View {")
        lines.append("    var body: some View {")
        lines.append("        VStack(alignment: .leading, spacing: 8) {")

        for element in blueprint.elements {
            lines.append(contentsOf: swiftLines(for: element, indent: 12))
        }

        lines.append("        }")
        lines.append("    }")
        lines.append("}")
        lines.append("")

        return lines.joined(separator: "\n")
    }

    private func swiftLines(for element: WidgetElement, indent: Int) -> [String] {
        let pad = String(repeating: " ", count: indent)
        let size = element.style?.fontSize ?? 13
        let weight = element.style?.fontWeight ?? "regular"
        let opacity = element.style?.opacity ?? 0.9

        switch element.type {
        case "text":
            return [
                "\(pad)Text(\"\(element.content ?? "")\")",
                "\(pad)    .font(.system(size: \(size), weight: .\(weight)))",
                "\(pad)    .foregroundStyle(Color.white.opacity(\(opacity)))",
            ]
        case "liveTime":
            return [
                "\(pad)// Live time: format \"\(element.content ?? "HH:mm:ss")\"",
                "\(pad)TimelineView(.periodic(from: .now, by: 1.0)) { context in",
                "\(pad)    Text(DateFormatter.localizedString(from: context.date, dateStyle: .none, timeStyle: .medium))",
                "\(pad)        .font(.system(size: \(size), weight: .\(weight)))",
                "\(pad)        .foregroundStyle(Color.white)",
                "\(pad)}",
            ]
        case "liveDate":
            return [
                "\(pad)// Live date: format \"\(element.content ?? "EEEE, MMM d")\"",
                "\(pad)Text(Date(), style: .date)",
                "\(pad)    .font(.system(size: \(size), weight: .\(weight)))",
                "\(pad)    .foregroundStyle(Color.white.opacity(\(opacity)))",
            ]
        case "image":
            return [
                "\(pad)Image(systemName: \"\(element.content ?? "questionmark")\")",
                "\(pad)    .font(.system(size: \(size), weight: .\(weight)))",
                "\(pad)    .foregroundStyle(Color.white.opacity(\(opacity)))",
            ]
        case "spacer":
            return ["\(pad)Spacer()"]
        case "divider":
            return [
                "\(pad)Divider().overlay(Color.white.opacity(0.14))",
            ]
        case "vstack":
            var result = ["\(pad)VStack(alignment: .leading, spacing: \(element.style?.spacing ?? 6)) {"]
            for child in element.children ?? [] {
                result.append(contentsOf: swiftLines(for: child, indent: indent + 4))
            }
            result.append("\(pad)}")
            return result
        case "hstack":
            var result = ["\(pad)HStack(spacing: \(element.style?.spacing ?? 6)) {"]
            for child in element.children ?? [] {
                result.append(contentsOf: swiftLines(for: child, indent: indent + 4))
            }
            result.append("\(pad)}")
            return result
        case "apiText":
            return [
                "\(pad)// API data from \(element.dataSourceId ?? "unknown") at keyPath \(element.keyPath ?? "")",
                "\(pad)Text(\"\(element.fallback ?? "Loading...")\")",
                "\(pad)    .font(.system(size: \(size), weight: .\(weight)))",
                "\(pad)    .foregroundStyle(Color.white.opacity(\(opacity)))",
            ]
        default:
            return ["\(pad)// Unsupported element type: \(element.type)"]
        }
    }

    private func persistGeneratedWidget(_ widget: GeneratedWidgetDefinition) {
        let key = AIWidgetBuilderConstants.generatedWidgetsKey
        let existing: [GeneratedWidgetDefinition]
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([GeneratedWidgetDefinition].self, from: data) {
            existing = decoded
        } else {
            existing = []
        }

        var updated = existing.filter { $0.title.lowercased() != widget.title.lowercased() }
        updated.append(widget)
        guard let data = try? JSONEncoder().encode(updated) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - AI Widget Builder Section View (builder UI)

struct AIWidgetBuilderSectionView: View {
    @ObservedObject var state: AIWidgetBuilderState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Create a new widget with AI")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.62))

            let providerBinding = Binding(
                get: { state.provider },
                set: { state.switchProvider(to: $0) }
            )

            Picker("", selection: providerBinding) {
                ForEach(LLMProvider.allCases) { provider in
                    Text(provider.rawValue).tag(provider)
                }
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 4)

            if state.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    let urlString = state.provider == .gemini 
                        ? "https://accounts.google.com/AccountChooser?continue=https%3A%2F%2Faistudio.google.com%2Fapp%2Fapikey" 
                        : "https://console.groq.com/keys"
                    if let url = URL(string: urlString) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.crop.circle.badge.plus")
                        Text(state.provider == .gemini ? "Sign up / get Gemini key" : "Sign up / get Groq key")
                        Spacer()
                        Image(systemName: "arrow.up.forward.square")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: ToolbarGlass.innerRadius, style: .continuous)
                            .fill(Color.white.opacity(0.16))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: ToolbarGlass.innerRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                let name = state.provider == .gemini ? "Gemini" : "Groq"
                SecureField(state.apiKey.isEmpty ? "Paste \(name) API key" : "\(name) API key saved", text: $state.apiKey)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.white)

                if !state.apiKey.isEmpty {
                    Button {
                        state.clearApiKey()
                    } label: {
                        Image(systemName: "arrow.right.square")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("Sign out / clear API key")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: ToolbarGlass.innerRadius, style: .continuous)
                    .fill(Color.black.opacity(0.22))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ToolbarGlass.innerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            )

            ZStack(alignment: .topLeading) {
                TextEditor(text: $state.userGoal)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.white)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120, idealHeight: 140, maxHeight: 160)

                if state.userGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Example: Show current time, weather in Athens, or system info")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.42))
                        .padding(.top, 6)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: ToolbarGlass.innerRadius, style: .continuous)
                    .fill(Color.black.opacity(0.22))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ToolbarGlass.innerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            )

            Button {
                state.generateWidgetFile()
            } label: {
                HStack {
                    Image(systemName: state.isGenerating ? "clock.arrow.circlepath" : "wand.and.stars")
                        .font(.system(size: 13, weight: .semibold))
                    Text(state.isGenerating ? "Generating…" : "Generate widget")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: ToolbarGlass.innerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.16))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ToolbarGlass.innerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(state.isGenerating)
            .opacity(state.isGenerating ? 0.6 : 1)

            if state.isGenerating {
                ProgressView(value: state.progress, total: 1)
                    .progressViewStyle(.linear)
                    .tint(.white)
            }

            Text(state.statusText)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Generated Widget Section View (dashboard tile for generated widgets)

struct GeneratedWidgetSectionView: View {
    let widget: GeneratedWidgetDefinition

    var body: some View {
        if let blueprint = widget.blueprint {
            DynamicWidgetRenderer(blueprint: blueprint)
        } else {
            // Fallback for legacy widgets without a blueprint
            VStack(alignment: .leading, spacing: 10) {
                Text(widget.generatedSummary)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: ToolbarGlass.innerRadius, style: .continuous)
                            .fill(Color.black.opacity(0.22))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: ToolbarGlass.innerRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                    )

                Text("Request")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.55))

                Text(widget.requestText)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
