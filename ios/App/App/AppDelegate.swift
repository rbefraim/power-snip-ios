import UIKit
import Capacitor
import AVFoundation
import WebKit
import AppTrackingTransparency

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    // Make the game AUDIBLE even when the hardware ring/silent switch is ON.
    // WKWebView (and its WebAudio output) plays through the app's shared AVAudioSession; the default
    // category is silenced by the mute switch, which is why the game was silent on a real iPhone.
    // Forcing the `.playback` category routes game audio like a music/media app: it plays through the
    // speaker regardless of the ring switch. This is the actual native fix (the JS navigator.audioSession
    // hint is not reliably honored inside Capacitor's WKWebView).
    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[PowerSnip] AVAudioSession configuration failed: \(error)")
        }
    }

    // MARK: - App Tracking Transparency (App Review guideline 2.1)
    //
    // WHY THIS IS NATIVE NOW. Build 21 asked for tracking authorization from JavaScript
    // (AdMob.requestTrackingAuthorization()) at the moment the web view parsed its script — which
    // happens while the app is still LAUNCHING. iOS silently ignores a request made before the app
    // is in the `.active` state: no dialog is presented and no error is raised. That is exactly why
    // App Review "could not locate the App Tracking Transparency permission request" on iPadOS 26.6.
    //
    // The request now lives here, in `applicationDidBecomeActive`, so it fires only once the app is
    // genuinely active. Nothing about it is iPhone- or iPad-specific — the same code path runs on
    // every idiom, so the prompt appears on iPad exactly as it does on iPhone.
    //
    // ORDERING GUARANTEE: AdMob must not read the IDFA before the user has answered. The web layer
    // no longer starts AdMob on its own; it waits for `window.__psATTDone(status)`, which is called
    // from `notifyWebLayer` below once (and only once) the authorization decision exists.
    private var didRequestTracking = false

    private func requestTrackingAuthorizationWhenActive() {
        guard #available(iOS 14, *) else {
            notifyWebLayer(status: "unavailable")   // pre-14.5: no ATT, let ads start
            return
        }
        if didRequestTracking { return }
        didRequestTracking = true

        // Already answered on a previous launch — don't re-prompt, just release the ad gate.
        if ATTrackingManager.trackingAuthorizationStatus != .notDetermined {
            notifyWebLayer(status: describe(ATTrackingManager.trackingAuthorizationStatus))
            return
        }

        // A short delay lets the launch splash finish and makes certain the app is fully active.
        // Requesting any earlier is precisely the mistake that made the prompt never appear.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self else { return }
            guard UIApplication.shared.applicationState == .active else {
                // Became inactive again before we could ask (e.g. a phone call during launch).
                // Reset so the next activation retries instead of silently swallowing the prompt.
                self.didRequestTracking = false
                return
            }
            NSLog("[PowerSnip] ATT presenting request")
            ATTrackingManager.requestTrackingAuthorization { status in
                DispatchQueue.main.async {
                    self.notifyWebLayer(status: self.describe(status))
                }
            }
        }
    }

    @available(iOS 14, *)
    private func describe(_ status: ATTrackingManager.AuthorizationStatus) -> String {
        switch status {
        case .authorized:    return "authorized"
        case .denied:        return "denied"
        case .restricted:    return "restricted"
        case .notDetermined: return "notDetermined"
        @unknown default:    return "unknown"
        }
    }

    /// Hands the ATT outcome to the web layer, which uses it as the go-signal for AdMob.
    /// The web view may not have finished parsing when the decision lands, so this retries until the
    /// hook exists (up to ~20s) rather than firing once into a page that isn't listening yet.
    private func notifyWebLayer(status: String, attempt: Int = 0) {
        guard attempt < 40 else {
            print("[PowerSnip] ATT: web layer never exposed __psATTDone; ads fall back to their own timer.")
            return
        }
        let js = "(function(){ if (typeof window.__psATTDone === 'function') { window.__psATTDone('\(status)'); return 'ok'; } return 'wait'; })()"

        guard let webView = AppDelegate.findWebView(in: window?.rootViewController?.view) else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.notifyWebLayer(status: status, attempt: attempt + 1)
            }
            return
        }
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            if (result as? String) == "ok" {
                NSLog("[PowerSnip] ATT decision delivered: %@", status)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self?.notifyWebLayer(status: status, attempt: attempt + 1)
                }
            }
        }
    }

    private static func findWebView(in view: UIView?) -> WKWebView? {
        guard let view = view else { return nil }
        if let webView = view as? WKWebView { return webView }
        for subview in view.subviews {
            if let found = findWebView(in: subview) { return found }
        }
        return nil
    }

    #if DEBUG
    // Verification hooks for the iPad/iPhone simulator check that runs in CI before every upload.
    // Compiled ONLY into Debug builds — SWIFT_ACTIVE_COMPILATION_CONDITIONS is empty in Release, so
    // none of this exists in the archive that goes to App Review, and no launch argument can reach it.
    private var uiTestMode: Bool { ProcessInfo.processInfo.arguments.contains("-PSUITest") }

    private func runDebugVerificationHooks() {
        guard uiTestMode else { return }
        let openRestore = ProcessInfo.processInfo.arguments.contains("-PSOpenRestore")
        // Jump straight to the main menu (past the first-run intro) so the screenshot shows the
        // Restore Purchases control, and optionally open the restore sheet itself.
        var js = "(function(){ try { if (window.__ps && window.__ps.setState) window.__ps.setState({ screen: 'title' }); } catch (e) {} return 'ok'; })()"
        if openRestore {
            js = "(function(){ try { if (window.__ps && window.__ps.setState) window.__ps.setState({ screen: 'title' }); } catch (e) {} try { if (typeof window.__psRestore === 'function') window.__psRestore(); } catch (e) {} return 'ok'; })()"
        }
        evaluateWhenReady(js, attempt: 0)
    }

    private func evaluateWhenReady(_ js: String, attempt: Int) {
        guard attempt < 40 else { return }
        guard let webView = AppDelegate.findWebView(in: window?.rootViewController?.view) else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.evaluateWhenReady(js, attempt: attempt + 1)
            }
            return
        }
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            if (result as? String) != "ok" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self?.evaluateWhenReady(js, attempt: attempt + 1)
                }
            }
        }
    }
    #endif

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        configureAudioSession()
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
        // Re-assert the playback session — an interruption (call, other app) or backgrounding can
        // deactivate it, which would leave the game silent after returning to the foreground.
        configureAudioSession()

        // The app is genuinely active here — the only state in which iOS will actually present the
        // App Tracking Transparency dialog. Guarded internally so it runs once per install.
        #if DEBUG
        if uiTestMode && ProcessInfo.processInfo.arguments.contains("-PSSkipATT") {
            notifyWebLayer(status: "skipped-for-ui-test")
        } else {
            requestTrackingAuthorizationWhenActive()
        }
        runDebugVerificationHooks()
        #else
        requestTrackingAuthorizationWhenActive()
        #endif
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        // Called when the app was launched with a url. Feel free to add additional processing here,
        // but if you want the App API to support tracking app url opens, make sure to keep this call
        return ApplicationDelegateProxy.shared.application(app, open: url, options: options)
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        // Called when the app was launched with an activity, including Universal Links.
        // Feel free to add additional processing here, but if you want the App API to support
        // tracking app url opens, make sure to keep this call
        return ApplicationDelegateProxy.shared.application(application, continue: userActivity, restorationHandler: restorationHandler)
    }

}
