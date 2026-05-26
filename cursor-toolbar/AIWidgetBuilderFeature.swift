//
//  AIWidgetBuilderFeature.swift
//  cursor-toolbar
//

import Combine
import Foundation
import SwiftUI
import WebKit

enum LLMProvider: String, CaseIterable, Identifiable {
    case pollinations = "Free"
    case gemini = "Gemini"
    case groq = "Groq (Llama 3)"
    var id: String { rawValue }

    /// Pollinations is keyless. The other providers require the user to bring their own key.
    var requiresAPIKey: Bool {
        switch self {
        case .pollinations: return false
        case .gemini, .groq: return true
        }
    }
}

private enum AIWidgetBuilderConstants {
    static let providerDefaultsKey = "ai_widget_builder_provider"
    static let geminiApiKeyDefaultsKey = "gemini_api_key"
    static let groqApiKeyDefaultsKey = "groq_api_key"
    static let geminiModel = "gemini-2.0-flash-lite"
    static let groqModel = "llama-3.3-70b-versatile"
    static let pollinationsModel = "openai"
    static let generatedWidgetsKey = "toolbar_generated_widgets_v2"
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
        let p = LLMProvider(rawValue: savedProv) ?? .pollinations
        self.provider = p
        self.apiKey = AIWidgetBuilderState.loadStoredKey(for: p)
    }

    private static func defaultsKey(for provider: LLMProvider) -> String? {
        switch provider {
        case .pollinations: return nil
        case .gemini: return AIWidgetBuilderConstants.geminiApiKeyDefaultsKey
        case .groq: return AIWidgetBuilderConstants.groqApiKeyDefaultsKey
        }
    }

    private static func loadStoredKey(for provider: LLMProvider) -> String {
        guard let key = defaultsKey(for: provider) else { return "" }
        return UserDefaults.standard.string(forKey: key) ?? ""
    }

    func switchProvider(to newProvider: LLMProvider) {
        provider = newProvider
        UserDefaults.standard.set(newProvider.rawValue, forKey: AIWidgetBuilderConstants.providerDefaultsKey)
        apiKey = AIWidgetBuilderState.loadStoredKey(for: newProvider)
        statusText = newProvider.requiresAPIKey
            ? "Switched to \(newProvider.rawValue). Paste your API key, describe the widget, then generate."
            : "Free mode — no API key needed. Describe the widget you want, then generate."
    }

    func clearApiKey() {
        apiKey = ""
        if let key = AIWidgetBuilderState.defaultsKey(for: provider) {
            UserDefaults.standard.removeObject(forKey: key)
        }
        statusText = "API key cleared. Sign in with a different account to generate."
    }

    // MARK: - System Prompt (loaded from bundled text file)

    /// Use #filePath at compile time to locate the project source directory.
    private static let projectSourceDir: URL = {
        let thisFile = URL(fileURLWithPath: #filePath)
        return thisFile.deletingLastPathComponent()
    }()

    /// Loads the LLM system prompt from the bundled text file.
    /// Falls back to a minimal inline prompt if the file is missing.
    private var systemPrompt: String {
        // Try loading from the project source directory (development)
        let devURL = Self.projectSourceDir.appendingPathComponent("llm_widget_system_prompt.txt")
        if let contents = try? String(contentsOf: devURL, encoding: .utf8), !contents.isEmpty {
            return contents
        }

        // Try loading from the app bundle (release builds)
        if let bundleURL = Bundle.main.url(forResource: "llm_widget_system_prompt", withExtension: "txt"),
           let contents = try? String(contentsOf: bundleURL, encoding: .utf8), !contents.isEmpty {
            return contents
        }

        // Fallback — should never hit if the file is properly included
        return """
        You are an AI agent that creates widgets as self-contained HTML documents.
        Output ONLY valid HTML with inline CSS and JS. No markdown. No explanation.
        Use transparent background. White text. Design for 244x244px.
        """
    }

    // MARK: - Widget Generation

    func generateWidgetFile() {
        let trimmedGoal = userGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedGoal.isEmpty else {
            statusText = "Enter a widget request first."
            return
        }
        if provider.requiresAPIKey && trimmedKey.isEmpty {
            statusText = "Add an API key first."
            return
        }

        if provider.requiresAPIKey, let key = AIWidgetBuilderState.defaultsKey(for: provider) {
            UserDefaults.standard.set(trimmedKey, forKey: key)
        }
        isGenerating = true
        progress = 0.06
        statusText = "Generating widget…"
        outputFileName = nil

        Task {
            startProgressAnimation()
            do {
                let rawHTML = try await callLLM(goal: trimmedGoal, apiKey: trimmedKey)
                let html = extractHTML(from: rawHTML)

                guard !html.isEmpty else {
                    throw NSError(
                        domain: "AIWidgetBuilder",
                        code: -3,
                        userInfo: [NSLocalizedDescriptionKey: "Model returned empty or invalid HTML."]
                    )
                }

                progressTask?.cancel()
                progress = 1.0

                // Derive a title from the user's prompt
                let title = deriveTitle(from: trimmedGoal)
                let widgetId = UUID().uuidString

                let newWidget = GeneratedWidgetDefinition(
                    id: widgetId,
                    title: title,
                    requestText: trimmedGoal,
                    generatedSummary: "Created from prompt: \(trimmedGoal)",
                    htmlSource: html
                )

                // Persist to UserDefaults
                persistGeneratedWidget(newWidget)

                // Immediate registration so it appears in the dashboard add list
                if let flow = flow {
                    flow.registerGeneratedWidget(newWidget)
                }

                // Save the HTML file to the project's GeneratedWidgets folder
                let savedPath = saveHTMLFile(title: title, html: html)

                outputFileName = "\(title).html"
                statusText = "✓ Widget ready! Added to dashboard list.\(savedPath != nil ? " File saved to GeneratedWidgets/." : "")"

            } catch {
                progressTask?.cancel()
                progress = 0
                statusText = "Generation failed: \(error.localizedDescription)"
            }
            isGenerating = false
        }
    }

    // MARK: - LLM API Calls

    private func callLLM(goal: String, apiKey: String) async throws -> String {
        switch provider {
        case .pollinations:
            return try await callPollinations(goal: goal)
        case .gemini:
            return try await callGemini(goal: goal, apiKey: apiKey)
        case .groq:
            return try await callGroq(goal: goal, apiKey: apiKey)
        }
    }

    private func callPollinations(goal: String) async throws -> String {
        let endpoint = "https://text.pollinations.ai/openai"
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }

        // The anonymous Pollinations tier serves a reasoning model (gpt-oss-20b)
        // with a hard ~1500 completion-token cap. We minimise wasted budget by
        // (a) shipping a compact system prompt, (b) requesting low reasoning
        // effort, and (c) telling the model to write minified output. We
        // deliberately do NOT send max_tokens — leaving it unset is what lets
        // the model actually finish the HTML document.
        let userMessage = """
        Mutate the TEMPLATE at the bottom of your instructions into a complete HTML widget that fulfills this request: \(goal)

        IMPORTANT: be COMPACT. Minify CSS and JS, no comments, no whitespace between rules, short variable names, no duplication. Your entire HTML must fit in under 1400 tokens and MUST end with </html>.
        """

        let requestBody: [String: Any] = [
            "model": AIWidgetBuilderConstants.pollinationsModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage]
            ],
            "temperature": 0.4,
            "reasoning_effort": "low",
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: requestBody)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown Pollinations error."
            throw NSError(
                domain: "AIWidgetBuilder",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: body]
            )
        }

        // Pollinations' /openai endpoint mirrors the OpenAI chat-completion shape.
        struct OpenAIResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message?
                let finish_reason: String?
            }
            let choices: [Choice]?
        }

        if let decoded = try? JSONDecoder().decode(OpenAIResponse.self, from: data),
           let choice = decoded.choices?.first,
           let text = choice.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            // If the model hit the completion-token cap before finishing the
            // HTML document, the rendered widget would be empty. Surface that
            // clearly instead of saving a broken HTML file.
            if choice.finish_reason == "length" && !text.lowercased().contains("</html>") {
                throw NSError(
                    domain: "AIWidgetBuilder",
                    code: -4,
                    userInfo: [NSLocalizedDescriptionKey: "Response was cut off before the widget finished. Try a simpler request."]
                )
            }
            return text
        }

        // Fallback: some Pollinations deployments return raw text instead of JSON.
        if let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return raw
        }

        throw NSError(
            domain: "AIWidgetBuilder",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Pollinations returned empty output."]
        )
    }

    private func callGemini(goal: String, apiKey: String) async throws -> String {
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
                "temperature": 0.4,
                "maxOutputTokens": 8192,
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

    private func callGroq(goal: String, apiKey: String) async throws -> String {
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
            "temperature": 0.4,
            "max_tokens": 8192,
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
                userInfo: [NSLocalizedDescriptionKey: "Groq model returned empty output."]
            )
        }
        return rawText
    }

    // MARK: - HTML Extraction

    /// Extract HTML from AI response, stripping markdown fences and preamble if present.
    private func extractHTML(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // If it starts with a valid HTML opening, use as-is
        if trimmed.hasPrefix("<!") || trimmed.hasPrefix("<html") {
            return trimmed
        }

        // Try to extract from markdown code fences (```html ... ``` or ``` ... ```)
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
            if !fenced.isEmpty && (fenced.hasPrefix("<!") || fenced.hasPrefix("<html") || fenced.hasPrefix("<")) {
                return fenced
            }
        }

        // Last resort: find the first '<' that starts an HTML tag and last '>'
        if let startIdx = trimmed.range(of: "<!DOCTYPE", options: .caseInsensitive)?.lowerBound
            ?? trimmed.range(of: "<html", options: .caseInsensitive)?.lowerBound {
            let endSearch = trimmed[startIdx...]
            if let endIdx = endSearch.range(of: "</html>", options: [.caseInsensitive, .backwards])?.upperBound {
                return String(trimmed[startIdx..<endIdx])
            }
            return String(trimmed[startIdx...])
        }

        // If all else fails, wrap raw content in minimal HTML
        if trimmed.contains("<") {
            return trimmed
        }

        return ""
    }

    // MARK: - Title Derivation

    /// Derives a PascalCase widget title from the user's prompt.
    private func deriveTitle(from goal: String) -> String {
        let words = goal
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .prefix(4)
            .map { word in
                let cleaned = word.filter { $0.isLetter || $0.isNumber }
                return cleaned.prefix(1).uppercased() + cleaned.dropFirst().lowercased()
            }

        let title = words.joined()
        return title.isEmpty ? "CustomWidget" : title
    }

    // MARK: - Progress Animation

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

    // MARK: - File Saving

    /// Save the generated HTML to the project's GeneratedWidgets folder.
    @discardableResult
    private func saveHTMLFile(title: String, html: String) -> String? {
        let folderURL = Self.projectSourceDir.appendingPathComponent("GeneratedWidgets", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let safeName = title.replacingOccurrences(of: " ", with: "")
        let fileName = "\(safeName).html"
        let fileURL = folderURL.appendingPathComponent(fileName)

        do {
            try html.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL.path
        } catch {
            return nil
        }
    }

    // MARK: - Persistence

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

            if state.provider.requiresAPIKey {
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
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.72))
                    Text("Free — no API key required")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.72))
                    Spacer()
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
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $state.userGoal)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.white)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120, idealHeight: 140, maxHeight: 160)

                if state.userGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Example: Show current time, weather in Athens, or crypto prices")
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
        WebWidgetView(htmlSource: widget.htmlSource)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
