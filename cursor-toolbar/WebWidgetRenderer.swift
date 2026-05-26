//
//  WebWidgetRenderer.swift
//  cursor-toolbar
//
//  Renders an HTML string inside a WKWebView with a transparent background.
//  Used to display AI-generated widgets live in dashboard tiles.
//

import SwiftUI
import WebKit

/// SwiftUI wrapper around WKWebView that loads an HTML string with a transparent background.
struct WebWidgetView: NSViewRepresentable {
    let htmlSource: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Suppress console noise for widget tiles
        config.preferences.setValue(false, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: config)

        // Transparent background so the host glass tile shows through
        webView.setValue(false, forKey: "drawsBackground")
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor

        // Disable scrolling — widget content should fit the tile
        webView.enclosingScrollView?.hasVerticalScroller = false
        webView.enclosingScrollView?.hasHorizontalScroller = false

        // Disable magnification / zoom
        webView.allowsMagnification = false

        // Disable link navigation — widgets are view-only
        webView.navigationDelegate = context.coordinator

        loadHTML(in: webView)

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Reload if the HTML source changed
        if context.coordinator.currentHTML != htmlSource {
            context.coordinator.currentHTML = htmlSource
            loadHTML(in: webView)
        }
    }

    private func loadHTML(in webView: WKWebView) {
        webView.loadHTMLString(htmlSource, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(htmlSource: htmlSource)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var currentHTML: String

        init(htmlSource: String) {
            self.currentHTML = htmlSource
        }

        /// Block any navigation away from the loaded HTML (e.g. if the widget contains links).
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .other {
                // Allow the initial load and JS-driven updates
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }
}
