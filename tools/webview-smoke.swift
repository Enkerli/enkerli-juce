// webview-smoke.swift — run an embedded plugin UI bundle in a REAL WKWebView
// (the same engine as iPadOS) and verify it renders, before any device sees it.
//
//   swift tools/webview-smoke.swift <path/to/index.html> [#rootSelector]
//
// Exit 0: root element populated, no page errors. Exit 1 otherwise, with
// the page's own error report (the bundles' error overlay text included).

import WebKit

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: webview-smoke.swift <index.html> [selector]\n".data(using: .utf8)!)
    exit(2)
}
let htmlPath = args[1]
let selector = args.count >= 3 ? args[2] : "#root"

let html = htmlPath.hasPrefix("http") ? "" : ((try? String(contentsOfFile: htmlPath, encoding: .utf8)) ?? {
    FileHandle.standardError.write("cannot read \(htmlPath)\n".data(using: .utf8)!)
    exit(2)
}())

let config = WKWebViewConfiguration()
// Capture raw error objects before any page code runs — richer than the
// page's own overlay when WebKit sanitizes messages to "Script error.".
let capture = WKUserScript(source: """
  window.__errs = [];
  window.addEventListener('error', function (e) {
    try {
      window.__errs.push(String(e.message) + ' | ' +
        (e.error ? (e.error.name + ': ' + e.error.message + ' @ ' + String(e.error.stack).slice(0, 500)) : 'no-error-object') +
        ' | ' + (e.filename || '?') + ':' + (e.lineno || '?'));
    } catch (_) {}
  }, true);
  window.addEventListener('unhandledrejection', function (e) {
    try { window.__errs.push('rejection: ' + String(e.reason && e.reason.stack || e.reason)); } catch (_) {}
  });
""", injectionTime: .atDocumentStart, forMainFrameOnly: true)
config.userContentController.addUserScript(capture)
let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768), configuration: config)
// file:// base: same-origin like the juce:// scheme (null-origin sanitizes
// error messages to "Script error.", hiding the actual failure).
if htmlPath.hasPrefix("http") {
    webView.load(URLRequest(url: URL(string: htmlPath)!))
} else {
    let fileURL = URL(fileURLWithPath: htmlPath)
    webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
}
_ = html

var checks = 0
func check() {
    checks += 1
    let probe = """
    (function () {
      var root = document.querySelector('\(selector)');
      var overlay = document.querySelector('pre'); // error-overlay element
      return JSON.stringify({
        populated: !!(root && root.children.length),
        overlay: overlay ? overlay.textContent.slice(0, 400) : null,
        errs: (window.__errs || []).slice(0, 3),
        title: document.title
      });
    })()
    """
    webView.evaluateJavaScript(probe) { result, error in
        if let error = error {
            print("probe error: \(error.localizedDescription)")
            exit(1)
        }
        guard let json = result as? String,
              let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("probe returned no data")
            exit(1)
        }
        let populated = (obj["populated"] as? Bool) == true
        let errs = obj["errs"] as? [String] ?? []
        if let overlay = obj["overlay"] as? String {
            print("PAGE ERROR (root populated: \(populated)): \(overlay)")
            for e in errs { print("  raw: \(e)") }
            exit(1)
        }
        if populated {
            print("smoke OK: \(selector) rendered in WKWebView (\(obj["title"] ?? ""))")
            exit(0)
        }
        if checks < 20 { // up to ~10 s for slow first paint
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { check() }
        } else {
            print("smoke FAIL: \(selector) never populated (no error overlay either)")
            exit(1)
        }
    }
}

DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { check() }
RunLoop.main.run()
