# Releasing

Releases are built by `.github/workflows/release.yml` when a version tag is pushed.

## Cut a release

1. Write the `## What's new in <version>` section at the top of `.github/release-notes.md` (older
   versions stay below it; the file is also the changelog) and set `VERSION` in the `Makefile`.
   `scripts/release-notes.sh` prints what the release will show and fails when the section is missing;
   CI runs it on every push.
2. Make sure `main` is green in CI.
3. Tag and push:

   ```sh
   git tag v0.3.0
   git push origin v0.3.0
   ```

4. The workflow tests, runs `make dmg VERSION=0.3.0` and publishes a GitHub Release with
   `PRInbox-0.3.0.dmg` and `PRInbox-0.3.0.dmg.sha256`. The version comes from the tag; no file needs to
   change.

To build the same DMG locally: `make dmg VERSION=0.3.0` (output in `build/`).

## Signing

Builds are signed ad hoc (`SIGN_IDENTITY=-`), so Gatekeeper blocks the first launch until the user
chooses Open (the release notes explain how). Switching to Developer ID needs a paid Apple Developer
Program membership and no restructuring:

1. Create a **Developer ID Application** certificate and export it with its key as a `.p12`.
2. Create an App Store Connect API key for notarization (`.p8`, key ID, issuer ID).
3. Add repository secrets: `MACOS_CERT_P12` (base64 of the `.p12`), `MACOS_CERT_PASSWORD`,
   `NOTARY_KEY` (base64 of the `.p8`), `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`.
4. In `release.yml`, before "Build DMG", import the certificate into a temporary keychain:

   ```sh
   echo "$MACOS_CERT_P12" | base64 --decode > cert.p12
   security create-keychain -p ci build.keychain
   security default-keychain -s build.keychain
   security unlock-keychain -p ci build.keychain
   security import cert.p12 -k build.keychain -P "$MACOS_CERT_PASSWORD" -T /usr/bin/codesign
   security set-key-partition-list -S apple-tool:,apple: -s -k ci build.keychain
   ```

5. Build with the identity. With a real identity, the Makefile adds the hardened runtime and a secure
   timestamp, which notarization requires:

   ```sh
   make dmg VERSION="${GITHUB_REF_NAME#v}" SIGN_IDENTITY="Developer ID Application: <Name> (<TEAMID>)"
   ```

6. Sign, notarize and staple the DMG:

   ```sh
   codesign --sign "Developer ID Application: <Name> (<TEAMID>)" --timestamp build/PRInbox-*.dmg
   echo "$NOTARY_KEY" | base64 --decode > notary.p8
   xcrun notarytool submit build/PRInbox-*.dmg --key notary.p8 --key-id "$NOTARY_KEY_ID" \
     --issuer "$NOTARY_ISSUER_ID" --wait
   xcrun stapler staple build/PRInbox-*.dmg
   ```

7. Regenerate the `.sha256` after stapling (stapling changes the file), and drop the Gatekeeper
   paragraph from `.github/release-notes.md`.
