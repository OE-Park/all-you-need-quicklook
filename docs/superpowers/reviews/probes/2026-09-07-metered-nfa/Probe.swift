import AppKit
import WebKit
import Shared

@main struct Probe {
    @MainActor static func main() throws {
        let app=NSApplication.shared
        let web=PreviewWebView(frame: CGRect(x:0,y:0,width:700,height:700))
        let nonce=PreviewWebView.makeNonce()
        let script=try String(contentsOfFile:CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/private/tmp/aynql-metered-nfa.js",encoding:.utf8)
        let body="<script nonce=\"\(nonce)\">\(script)\ntry { window.probeResult=runMeteredProbe(); } catch(e) { window.probeError=String(e); }</script>"
        web.loadHTML(HTMLTemplate.wrap(body:body,rendererType:"markdown",nonce:nonce),resourcesURL:nil,nonce:nonce)
        Task { @MainActor in
            do {
                try await Task.sleep(for:.seconds(2))
                let r=try await web.evaluateJavaScript("JSON.stringify(window.probeResult)")
                guard let json=r as? String else {print(try await web.evaluateJavaScript("window.probeError || 'Missing result'") ?? "Missing result");exit(1)}
                print(json);exit(0)
            } catch { print(error);exit(1) }
        }
        app.run()
    }
}
