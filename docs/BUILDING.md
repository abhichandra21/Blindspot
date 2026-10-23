# Building

## Requirements

- macOS 13 or later on Apple silicon
- Xcode Command Line Tools: `xcode-select --install`

## Build and run

```
git clone https://github.com/abhichandra21/Blindspot.git
cd Blindspot
./build.sh
open Blindspot.app
```

`build.sh` compiles `main.swift` into `Blindspot.app` in the same folder.
The whole app is that one Swift file.
Then grant permissions and set up login as in [Install](INSTALL.md), steps 3 and 4.

After rebuilding, restart the running copy: right-click the shield, choose **Quit Blindspot**, and open the app again.

## Keep permissions across rebuilds (recommended)

macOS ties Screen Recording and Accessibility to the app's signature.
Without a certificate, `build.sh` signs ad-hoc, which changes on every build, so you would have to grant permissions again each time.
Create a local code signing certificate once and `build.sh` uses it automatically:

```
cat > cert.cnf <<'EOF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = TeamsShareGuard Local Signing
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 3650 -config cert.cnf
/usr/bin/openssl pkcs12 -export -inkey key.pem -in cert.pem -out id.p12 -name "TeamsShareGuard Local Signing"
security import id.p12 -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign
rm key.pem cert.pem id.p12 cert.cnf
```

The two `openssl` and `security` commands ask you to set and then enter a password for the temporary `id.p12` file.
Keychain Access shows the certificate as "not trusted"; that is expected and does not stop it from signing.
The certificate name is a leftover from the app's earlier name and is only a label.

## How detection works

Blindspot reads the window list once a second:

- While you share, Teams shows a hidden window named "Sharing Indicator" covering exactly the shared area.
- The main Teams window's title starts with the current tab, such as "Chat | ..." or "Activity | ...".
- A watched Teams window that overlaps the shared area counts as exposed.

These are observed behaviors of the new Teams for Mac, not a documented API.

## Releases

GitHub Actions builds the app on every push to `main` and every pull request.
Pushing a tag publishes a release with `Blindspot.zip` attached:

```
git tag v0.2.0
git push origin v0.2.0
```

The tag sets the app's version (`v0.2.0` becomes `0.2.0`).
Release builds are signed ad-hoc, since the local certificate never leaves your Mac.
