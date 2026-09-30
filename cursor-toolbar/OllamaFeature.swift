//
//  OllamaFeature.swift
//  cursor-toolbar
//
//  Offline LLM chat against a local Ollama server (http://localhost:11434).
//  Dev/terminal mode only. Streams tokens as they arrive.
//

import Combine
import Foundation
import SwiftUI

// MARK: - State

@MainActor
final class OllamaState: ObservableObject {
    struct Message: Identifiable, Equatable {
        let id = UUID()
        var role: String   // "user" | "assistant"
        var content: String
    }

    @Published var models: [String] = []
    @Published var selectedModel: String = ""
    @Published var messages: [Message] = []
    @Published var input: String = ""
    @Published var isStreaming = false
    @Published var errorText: String?

    private let host = "http://localhost:11434"
    private var streamTask: Task<Void, Never>?

    // MARK: Models

    func refreshModels() async {
        errorText = nil
        guard let url = URL(string: "\(host)/api/tags") else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                errorText = "Ollama not reachable on :11434"
                return
            }
            let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
            models = decoded.models.map(\.name)
            if selectedModel.isEmpty || !models.contains(selectedModel) {
                selectedModel = models.first ?? ""
            }
        } catch {
            errorText = "Couldn't reach Ollama. Is it running? (ollama serve)"
        }
    }

    // MARK: Chat

    func send() {
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !selectedModel.isEmpty, !isStreaming else { return }
        errorText = nil
        input = ""
        messages.append(Message(role: "user", content: prompt))
        messages.append(Message(role: "assistant", content: ""))
        isStreaming = true

        let payloadMessages = messages.dropLast().map { ["role": $0.role, "content": $0.content] }
        let body: [String: Any] = [
            "model": selectedModel,
            "messages": Array(payloadMessages),
            "stream": true,
        ]

        streamTask = Task { [weak self] in
            await self?.stream(body: body)
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    func clearConversation() {
        stop()
        messages.removeAll()
    }

    private func stream(body: [String: Any]) async {
        defer { isStreaming = false }
        guard let url = URL(string: "\(host)/api/chat"),
              let data = try? JSONSerialization.data(withJSONObject: body) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                appendToLastAssistant("\n[error: HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)]")
                return
            }
            for try await line in bytes.lines {
                if Task.isCancelled { break }
                guard let lineData = line.data(using: .utf8),
                      let chunk = try? JSONDecoder().decode(ChatChunk.self, from: lineData) else { continue }
                if let content = chunk.message?.content, !content.isEmpty {
                    appendToLastAssistant(content)
                }
                if chunk.done { break }
            }
        } catch {
            if !Task.isCancelled {
                errorText = "Chat failed: \(error.localizedDescription)"
            }
        }
    }

    private func appendToLastAssistant(_ text: String) {
        guard let idx = messages.indices.last, messages[idx].role == "assistant" else { return }
        messages[idx].content += text
    }

    // MARK: Decoding

    private struct TagsResponse: Decodable {
        struct Model: Decodable { let name: String }
        let models: [Model]
    }

    private struct ChatChunk: Decodable {
        struct ChatMessage: Decodable { let role: String?; let content: String? }
        let message: ChatMessage?
        let done: Bool
    }
}

// MARK: - View

struct OllamaSectionView: View {
    @ObservedObject var state: OllamaState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            modelPicker
            transcript
            inputRow
            if let err = state.errorText {
                Text(err)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(red: 1.0, green: 0.6, blue: 0.55))
            }
        }
        .task { await state.refreshModels() }
    }

    private var modelPicker: some View {
        HStack(spacing: 8) {
            Image(systemName: "cpu")
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.6))
            if state.models.isEmpty {
                Text("No models — is Ollama running?")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.5))
            } else {
                Picker("", selection: $state.selectedModel) {
                    ForEach(state.models, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .labelsHidden()
                .tint(.white)
            }
            Spacer()
            Button {
                Task { await state.refreshModels() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Refresh models")

            Button(action: state.clearConversation) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Clear conversation")
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if state.messages.isEmpty {
                        Text("Chat with your local model. Nothing leaves this Mac.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                    ForEach(state.messages) { message in
                        bubble(for: message)
                            .id(message.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(10)
            }
            .frame(minHeight: 150, maxHeight: 220)
            .background(
                RoundedRectangle(cornerRadius: ToolbarGlass.innerRadius, style: .continuous)
                    .fill(Color.black.opacity(0.28))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ToolbarGlass.innerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )
            .onChange(of: lastContentLength) { _, _ in
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private var lastContentLength: Int {
        (state.messages.last?.content.count ?? 0) + state.messages.count
    }

    private func bubble(for message: OllamaState.Message) -> some View {
        let isUser = message.role == "user"
        return VStack(alignment: .leading, spacing: 3) {
            Text(isUser ? "You" : "Model")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.45))
            Text(message.content.isEmpty ? "…" : message.content)
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.9))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isUser ? Color.white.opacity(0.12) : Color.black.opacity(0.25))
        )
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField("Message the model…", text: $state.input, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color.white)
                .lineLimit(1...4)
                .onSubmit { state.send() }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.22)))

            if state.isStreaming {
                Button(action: state.stop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 34, height: 30)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.red.opacity(0.55)))
                }
                .buttonStyle(.plain)
            } else {
                Button(action: state.send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.white, Color.white.opacity(0.25))
                }
                .buttonStyle(.plain)
                .disabled(state.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.selectedModel.isEmpty)
            }
        }
    }
}
