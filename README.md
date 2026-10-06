# Okazzo client (Flutter)

Consumer app for event tickets. Two store listings: **EU** and **AU** (separate package / bundle IDs).

## Flavors (EU vs AU)

Always pass **both** `--flavor` and `--dart-define=ENV_FILE=...`. The flavor selects the native app identity; the env file selects API keys and backend URL.

| Flavor | Env file | Android `applicationId` (release) | iOS `PRODUCT_BUNDLE_IDENTIFIER` (release) | Display name |
|--------|----------|-----------------------------------|-------------------------------------------|--------------|
| `eu` | `.env.eu` | `com.okazzo.client.eu` | `com.finnep.okazzo.eu` | Okazzo EU |
| `au` | `.env.au` | `com.okazzo.client.au` | `com.finnep.okazzo.au` | Okazzo AUS |

**Debug builds** append `.debug` to the Android application id (e.g. `com.okazzo.client.eu.debug`). iOS debug uses the iOS bundle id with a `.debug` suffix in the Xcode flavor configs.

iOS bundle IDs are configured in `ios/Flutter/FlavorValues.xcconfig` (generated from `ios/scripts/generate_flavor_configs.sh`). Android application IDs are in `android/app/build.gradle.kts` — they are intentionally separate.

You do **not** pass the package name on the command line — `--flavor eu` or `--flavor au` is what switches it.

### Where package IDs are defined (if you need to change them)

| Platform | EU | AU |
|----------|----|----|
| Android | `android/app/build.gradle.kts` → `productFlavors { create("eu") { applicationId = "..." } }` | same, `create("au")` |
| iOS | `ios/Flutter/Debug-eu.xcconfig`, `Release-eu.xcconfig`, `Profile-eu.xcconfig` → `PRODUCT_BUNDLE_IDENTIFIER` | `*-au.xcconfig` |

After changing iOS bundle IDs, run `cd ios && pod install && cd ..`.

## Environment

Copy `.env.example` to `.env`, `.env.eu`, and `.env.au` locally (`.env*` files are gitignored — never commit secrets).

Required keys (see `.env.example`):

- `API_BASE_URL`
- `STRIPE_PUBLISHABLE_KEY`

Optional: `MARKET_COUNTRY_CODE` in `.env.eu` / `.env.au` if the app reads it at runtime.

## Test on a real device (before Play / App Store)

Use **production env** (`.env.eu` or `.env.au`), not the default `.env` (that one points at test).

### Android

1. On the phone: **Settings → Developer options → USB debugging** on; plug in USB (or pair wireless debugging).
2. On the Mac: `flutter devices` — you should see the phone listed.
3. **Closest to the store build** (release, signed, same package id as Play):

```bash
flutter run --release --flavor eu --dart-define=ENV_FILE=.env.eu
```

4. **Faster iteration** (debug package `com.okazzo.client.eu.debug`, still uses `.env.eu` if you pass it):

```bash
flutter run --flavor eu --dart-define=ENV_FILE=.env.eu
```

5. **Install a release APK without USB run** (pick the ABI that matches the phone, often `arm64-v8a`):

```bash
flutter build apk --release --flavor eu --dart-define=ENV_FILE=.env.eu --target-platform android-arm64
adb install -r build/app/outputs/flutter-apk/app-eu-release.apk
```

On the device, confirm the app talks to **`https://okazzo.eu/front`** (EU), not `test.okazzo.eu`. Exercise login, browse events, checkout, Stripe, and Paytrail return.

### iOS

Use Xcode schemes **`eu`** or **`au`** (match `--flavor`). First time or after Podfile changes:

```bash
cd ios && pod install && cd ..
```

Upload the IPA built with the matching flavor so App Store Connect receives the correct bundle id (`com.finnep.okazzo.eu` vs `com.finnep.okazzo.au`).

#### Deploy from Xcode (Archive / Run)

Xcode does not pass `flutter run`/`flutter build` `--dart-define` flags. Regional config must stay out of tracked env files:

1. Copy env templates locally (not committed):
   - `.env.example` → `.env.eu` and `.env.au`
   - `ios/.xcode.env.example` → `ios/.xcode.env` (optional Stripe override for Xcode)
2. Fill each regional file with production `API_BASE_URL` and Stripe keys for that market.
3. Optional in `ios/.xcode.env` (per-flavor preferred):
   - `STRIPE_PUBLISHABLE_KEY_EU` / `STRIPE_PUBLISHABLE_KEY_AU`
4. Regenerate iOS build config (also runs automatically as an Xcode pre-build step):
   `ios/scripts/generate_flavor_configs.sh`
5. Open `ios/Runner.xcworkspace`, select scheme **`eu`** or **`au`**, then Run or Archive.

Re-run step 4 after changing `ios/.xcode.env`.

Unlock the iPhone, trust the Mac, enable **Developer Mode** on the device. First-time device run may require opening `ios/Runner.xcworkspace` in Xcode once to set your **Team** signing.

For CLI builds on device:

```bash
flutter run --release --flavor eu --dart-define=ENV_FILE=.env.eu
```

**EU**

```bash
flutter run --flavor eu --dart-define=ENV_FILE=.env.eu

flutter build appbundle --release --flavor eu --dart-define=ENV_FILE=.env.eu
flutter build ipa --release --flavor eu --dart-define=ENV_FILE=.env.eu
```

**AU**

```bash
flutter run --flavor au --dart-define=ENV_FILE=.env.au

flutter build appbundle --release --flavor au --dart-define=ENV_FILE=.env.au
flutter build ipa --release --flavor au --dart-define=ENV_FILE=.env.au
```

**Android release APKs** (split per ABI; same flavor + env as above):

```bash
flutter build apk --release --flavor eu --split-per-abi --dart-define=ENV_FILE=.env.eu
flutter build apk --release --flavor au --split-per-abi --dart-define=ENV_FILE=.env.au
```

### Android release signing

Release builds need `android/key.properties` (copy from `android/key.properties.example`). Without it, `flutter build appbundle --release` fails by design.

### iOS

Use Xcode schemes **`eu`** or **`au`** (match `--flavor`). First time or after Podfile changes:

```bash
cd ios && pod install && cd ..
```

Upload the IPA built with the matching flavor so App Store Connect receives the correct bundle id (`com.finnep.okazzo.eu` vs `com.finnep.okazzo.au`).

#### Deploy from Xcode (Archive / Run)

See **Test on a real device → iOS → Deploy from Xcode** above for the full local setup (`ios/.xcode.env`, flavor config generation, and scheme selection).

---

## Run / build

- [ ] Built with correct `--flavor` and `ENV_FILE` for the region
- [ ] Play Console / App Store Connect app record matches that flavor’s package / bundle id
- [ ] `.env.eu` or `.env.au` uses production `API_BASE_URL` and live/test Stripe key as intended
- [ ] Android `key.properties` present for release signing


# Android (still com.okazzo.client.eu)
flutter build appbundle --release --flavor eu --dart-define=ENV_FILE=.env.eu
# iOS TestFlight (com.finnep.okazzo.eu)
flutter build ipa --release --flavor eu --dart-define=ENV_FILE=.env.eu


The “default placeholder icon” warning should be gone.

Note: If you change the app icon later, regenerate launch images:

SRC=ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png
DST=ios/Runner/Assets.xcassets/LaunchImage.imageset
sips -z 168 168 "$SRC" --out "$DST/LaunchImage.png"
sips -z 336 336 "$SRC" --out "$DST/LaunchImage@2x.png"
sips -z 504 504 "$SRC" --out "$DST/LaunchImage@3x.png"