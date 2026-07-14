# Power Snip! — iOS / TestFlight build (requires a Mac)

The game and native config are ready. Everything below needs **macOS + Xcode** —
it cannot be produced on Windows. Apple provides no way to build/sign an iOS app off macOS.

App ID: `me.yourplace.powersnip`   (change only if you own a different domain)
App Store Connect API key: `AuthKey_4G45T6S6Z3.p8`
  Key ID:    4G45T6S6Z3
  Issuer ID: f1e6baad-c3e7-43c8-9ab3-aaf7dae1ad54

## Prerequisite (do this first)
Your Apple Developer Program membership must be ACTIVE ($99/yr). If it is not,
the upload will be rejected at the last step. Check: https://developer.apple.com/account

## Steps on the Mac
```bash
cd power-snip-app
npm install
npx cap add ios
npx cap sync ios
npm run assets            # generates all icon/splash sizes from assets/
npx cap open ios          # opens Xcode
```

In Xcode:
1. Target → Signing & Capabilities → select your Team (automatic signing).
2. Target → General → Deployment Info → Device Orientation: **Landscape Left + Landscape Right only**
   (uncheck both Portrait options; iPad too).
3. Product → Archive → Distribute App → App Store Connect → Upload.

## Or upload headlessly with the .p8 key (no Xcode UI)
```bash
xcodebuild -workspace ios/App/App.xcworkspace -scheme App \
  -configuration Release -archivePath build/App.xcarchive archive
xcodebuild -exportArchive -archivePath build/App.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/

mkdir -p ~/private_keys && cp AuthKey_4G45T6S6Z3.p8 ~/private_keys/
xcrun altool --upload-app -f build/App.ipa -t ios \
  --apiKey 4G45T6S6Z3 --apiIssuer f1e6baad-c3e7-43c8-9ab3-aaf7dae1ad54
```
Then App Store Connect → TestFlight → the build appears after processing (~10-30 min)
→ add yourself as an internal tester → install via the TestFlight app.

## No Mac?
- GitHub Actions `macos-latest` runner (free minutes) can archive + upload with the same .p8 key.
- Or rent: MacStadium / MacinCloud.
Note: TestFlight still requires the paid Apple Developer membership.
