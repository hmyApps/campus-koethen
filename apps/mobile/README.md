# Campus Köthen

Campus Köthen — an independent, unofficial campus app.

## Branding

The binding logo sources live in `assets/branding/`. Platform launcher, splash
and web icons are generated from the icon source with:

```sh
swift tool/generate_brand_assets.swift
```

Do not replace individual generated size variants. The visible product name is
always `Campus Köthen`; `campus_koethen` remains only the internal Dart package
name.

## Campus API configuration

`API_BASE_URL` must be one exact origin: credentials, paths, query strings and fragments are
rejected. Every loopback origin, including local plaintext development, also needs an explicit
opt-in:

```sh
flutter run \
  --dart-define=API_BASE_URL=http://localhost:3000 \
  --dart-define=ALLOW_LOCAL_API=true
```

Without `API_BASE_URL`, debug builds show a visible configuration warning. Android and iOS
release/profile builds fail before compilation unless the value is an HTTPS origin. Use the real
deployment origin for every distributable build; `ALLOW_LOCAL_API` never weakens this release
gate.

## Android release signing

Android release artefacts are never signed with Flutter's public debug key. Inject all four
values through the local environment or the CI secret store before building a distributable
release:

- `CAMPUS_ANDROID_KEYSTORE_PATH`: path to the private keystore
- `CAMPUS_ANDROID_KEYSTORE_PASSWORD`: keystore password
- `CAMPUS_ANDROID_KEY_ALIAS`: release-key alias
- `CAMPUS_ANDROID_KEY_PASSWORD`: release-key password

Then build with:

```sh
flutter build appbundle --release \
  --dart-define=API_BASE_URL=https://<real-campus-api-origin>
```

A partial signing configuration fails during Gradle configuration. With none of the signing
variables set, Gradle leaves the release artefact unsigned; this is suitable for local compilation
checks only and cannot be published as the official app. Never commit the keystore or its
credentials.
