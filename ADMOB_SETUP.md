# AdMob — rewarded video (native build only)

## What is already wired
`www/index.html` auto-detects Capacitor + the AdMob plugin at runtime and defines
`window.PowerSnipAds = { rewarded(), interstitial() }`.

- **Native app** → rewarded video works; the "Watch a video" door appears on the choice gate.
- **Web (power-snip.pages.dev)** → Capacitor is absent, so `PowerSnipAds` is never defined.
  The game's `adsOn()` returns false and the choice gate simply OMITS the video option.
  No blank/broken ad slot is ever rendered. This is verified live.
- If an ad fails to load, `rewarded()` resolves `false` — the player is never blocked.

## What YOU must do (I cannot invent your ad unit IDs)
1. AdMob console → create the app + a **Rewarded** ad unit (and optionally Interstitial).
2. Paste the IDs into `www/admob-config.js` and set `testMode: false`.
3. Add your AdMob **App ID** to the native shells:
   - `android/app/src/main/AndroidManifest.xml`:
     `<meta-data android:name="com.google.android.gms.ads.APPLICATION_ID" android:value="ca-app-pub-XXX~XXX"/>`
   - `ios/App/App/Info.plist`:
     `<key>GADApplicationIdentifier</key><string>ca-app-pub-XXX~XXX</string>`
4. EEA/UK: add Google UMP consent before requesting ads.

Until step 2 is done the build serves Google's official TEST ads (safe — never click your own live ads).

## Build
```bash
npm install
npx cap sync
```
