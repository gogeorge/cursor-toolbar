# Janus

A floating, cursor-anchored macOS toolbar built in SwiftUI. Press a global hotkey anywhere on the system and a glass panel pops up under the pointer with shortcuts to your most-used utilities — folders, notes, clipboard history, AI prompt drafting, and a customizable dashboard of widgets (including LLM-generated ones).

## Activation

- **Global hotkey:** `⌘ ⇧ Space` shows the panel centered on the current cursor position.
- Clicking outside the panel dismisses it.
- The app runs as a menu bar accessory (no Dock icon). The 🎭 menu bar item shows the
  toolbar, grants Accessibility access, opens Settings, and quits.

## The icon rail



A vertical/orbital rail of six glass buttons:

1. **Previous app** — re-activates the app that was frontmost before the toolbar opened.
2. **Folders** — quick links to Documents, Downloads, Applications, Library.
3. **AI prompt** — a scratchpad to draft a prompt; copies the result to the clipboard.
4. **Notes** — persistent freeform notes.
5. **Clipboard** — history of the last 5 copied text snippets; click to re-copy.
6. **Expand / collapse** — toggles between the single-panel view and the full dashboard.

Each button reveals its own glass panel on click. Clicking a second time (or the expand toggle) opens the full dashboard.

## Dashboard

The full dashboard arranges modules as a 2-column grid of square glass tiles. Available modules:

- Folders
- Notes
- AI prompt
- Clipboard
- Commands
- AI widget builder
- Any LLM-generated widgets you've created

### Edit mode

A pencil icon enters iOS-home-screen-style edit mode: tiles wiggle, each shows a remove badge, and an "Add to dashboard" palette appears on the right with modules and generated widgets not yet on the dashboard. A checkmark commits changes; an `X` discards them.

Dashboard layout and generated widgets are persisted in `UserDefaults`.

## AI Widget Builder

Describe a widget in natural language and the app asks an LLM to return a JSON blueprint, which is rendered live by the SwiftUI runtime — no recompilation, no app restart.

- **Providers:** Gemini (`gemini-2.0-flash-lite`) or Groq (`llama-3.3-70b-versatile`). Switch providers and store API keys per-provider.
- **Blueprint elements:** `text`, `liveTime`, `liveDate`, `spacer`, `divider`, `vstack`, `hstack`, `systemInfo`, `progressRing`, `image`, `apiText`.
- **Live REST data:** Blueprints may declare `dataSources` (URL, method, headers, refresh interval). `apiText` elements pull values from the JSON response by `keyPath`, with optional `prefix`/`suffix`/`fallback`.
- **Styling:** font size/weight, color, alignment, spacing, opacity, monospaced digits.
- Generated widgets are saved and can be added to the dashboard or deleted from the add palette.

## Built-in features

- **Clipboard manager** — polls `NSPasteboard` every 0.5s and keeps the last 5 unique text entries. Copies marked concealed or transient (password managers) are ignored.
- **Notes** — single persistent note stored locally.
- **Previous app tracker** — remembers the app that was frontmost so the toolbar can hand focus back.
- **Folders** — opens the standard Finder folders.
- **Commands** — quick command launcher tile (optional).
- **AI prompt** — text editor with a copy-to-clipboard button.

## Requirements

- macOS 14.0 or later (SwiftUI + AppKit, uses Carbon `RegisterEventHotKey` for the global hotkey).
- Xcode — open `cursor-toolbar.xcodeproj` and run the `cursor-toolbar` scheme. The built
  product is `Janus.app` (bundle id `com.crasi.janus`).
- Accessibility access is optional; it is only used to un-minimize the previous app's windows.
- For the AI widget builder: a Gemini or Groq API key, entered into the AI widget builder panel.

## Persistence

API keys are stored in the **keychain** (service `com.crasi.janus`). Keys written to
`UserDefaults` by older builds are migrated on first launch and the plaintext copy is erased.

Remaining user state lives in `UserDefaults`:

- `clipboard_history` — recent clipboard entries
- `toolbar_dashboard_modules_v1` — dashboard module order
- `toolbar_generated_widgets_v1` — saved AI-generated widgets
- `toolbar_dashboard_generated_widget_ids_v1` — which generated widgets are pinned to the dashboard
- `ai_widget_builder_provider` — selected AI builder provider (keys live in the keychain)
