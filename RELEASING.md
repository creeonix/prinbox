# Releasing

Releases are built by `.github/workflows/release.yml` when a version tag is pushed.

## Cut a release

1. Write the `## What's new in <version>` section at the top of `.github/release-notes.md` (older
   versions stay below it; the file is also the changelog) and set `VERSION` in the `Makefile`
   and `static let number` in `Sources/PrinboxCLI/Version.swift` (the guard fails when they differ).
   `scripts/release-notes.sh` prints what the release will show and fails when the section is missing;
   CI runs it on every push.
2. Make sure `main` is green in CI.
3. Tag and push:

   ```sh
   git tag v0.3.0
   git push origin v0.3.0
   ```

4. The workflow tests, runs `make notarize notarize-cli VERSION=0.3.0` with the Developer ID identity (see
   Signing) and publishes a GitHub Release with `PRInbox-0.3.0.dmg` and `PRInbox-0.3.0.dmg.sha256`, plus
   `prinbox-0.3.0-macos.tar.gz` and its `.sha256` beside the DMG, all signed and notarized. The version
   comes from the tag.
5. Update the Homebrew tap. With a `TAP_TOKEN` repository secret (a fine-grained token with contents write
   on `creeonix/homebrew-tap`) the workflow does it; without one, run it by hand once the release page
   shows the assets:

   ```sh
   git clone git@github.com:creeonix/homebrew-tap.git ../homebrew-tap   # once
   scripts/update-tap.sh 0.6.0
   ```

   `brew install --cask creeonix/tap/prinbox` and `brew install creeonix/tap/prinbox-cli` then serve the
   new version.

`make dmg VERSION=0.3.0` builds the same DMG locally, signed ad hoc; `make notarize VERSION=0.3.0
SIGN_IDENTITY="Developer ID Application: Shiramori OY (5YB32JUPY7)"` builds the notarized one (output in
`build/`).

## Signing

Releases are signed with `Developer ID Application: Shiramori OY (5YB32JUPY7)` and notarized by Apple. With a
Developer ID identity the Makefile adds the hardened runtime and a secure timestamp, which notarization
requires; the app needs no entitlements. Without `SIGN_IDENTITY`, `make dmg`, `make install` and `make cli`
sign ad hoc, for local builds.

`make notarize` notarizes and staples the app bundle, builds the DMG from it, then signs, notarizes and
staples the DMG and rewrites its `.sha256` (stapling changes the file). `make notarize-cli` notarizes the
command before packing its tarball; a bare executable takes no staple. Both run `scripts/notarize.sh`, which
prints Apple's log when a submission is rejected, and both refuse the ad hoc identity.

### The workflow's secrets

| Secret | Contents |
|---|---|
| `MACOS_CERT_P12` | the identity (certificate and private key) as a `.p12`, base64 |
| `MACOS_CERT_PASSWORD` | the `.p12` password |
| `NOTARY_KEY` | an App Store Connect API key (`.p8`, Team Keys, role Developer), base64 |
| `NOTARY_KEY_ID` | its key ID |
| `NOTARY_ISSUER_ID` | the issuer ID from the same page |

The workflow imports the `.p12` and Apple's Developer ID G2 intermediate into a keychain of its own and
passes the API key to `notarytool` through the Makefile's `NOTARY_ARGS`. The identity's name is plain text in
`release.yml`; it is in every signature anyway.

### On a machine

The notarize targets need the identity in the login keychain and a `notarytool` keychain profile named
`prinbox`, the `NOTARY_ARGS` default:

```sh
xcrun notarytool store-credentials prinbox --key AuthKey_<KEYID>.p8 --key-id <KEYID> --issuer <ISSUERID>
make notarize notarize-cli VERSION=0.8.0 SIGN_IDENTITY="Developer ID Application: Shiramori OY (5YB32JUPY7)"
spctl -a -t open --context context:primary-signature -v build/PRInbox-0.8.0.dmg   # accepted, Notarized Developer ID
```

### Renewal

The certificate expires on 2027-12-12 and Apple does not renew it. Before then, make a new key and request
(the subject is ignored; Apple writes its own from the account):

```sh
/usr/bin/openssl req -new -newkey rsa:2048 -nodes -keyout devid.key -out devid.csr -subj "/CN=prinbox"
```

Upload `devid.csr` as a new **Developer ID Application** certificate at
developer.apple.com/account/resources/certificates (Account Holder only), download the `.cer`, and build and
import the identity:

```sh
curl -O https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer
/usr/bin/openssl x509 -inform DER -in DeveloperIDG2CA.cer -out DeveloperIDG2CA.pem
/usr/bin/openssl x509 -inform DER -in developerID_application.cer -out devid.pem
/usr/bin/openssl pkcs12 -export -inkey devid.key -in devid.pem -certfile DeveloperIDG2CA.pem -out devid.p12
security import devid.p12 -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign
```

Then store the `.p12` and its password in `MACOS_CERT_P12` and `MACOS_CERT_PASSWORD`, and delete the key
file. The API key does not expire; revoke and replace it in App Store Connect if it leaks.
