# Releasing FinTrack

## Build a local Apple Silicon release

```bash
bash scripts/package-app.sh 0.1.1
open releases/FinTrack-0.1.1/FinTrack.app
```

The package script does not access or modify the user database. FinTrack keeps
that database at `~/Library/Application Support/FinTrack/personal_finance.db`.

## Build a Universal release

On a Mac with the required Swift SDKs installed:

```bash
ARCHS=arm64,x86_64 bash scripts/package-app.sh 0.1.1
lipo -info releases/FinTrack-0.1.1/FinTrack.app/Contents/MacOS/PersonalFinanceApp
```

## Sign the app

Set `SIGNING_IDENTITY` to the Developer ID Application certificate name:

```bash
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  bash scripts/package-app.sh 0.1.1
codesign --verify --deep --strict --verbose=2 \
  releases/FinTrack-0.1.1/FinTrack.app
```

After signing, submit the ZIP for notarization with Apple's `notarytool`,
staple the result, and then create the GitHub Release from the notarized
artifact. The generated `.sha256` file is used in the Homebrew Cask.

## Data safety check

Before installing a release over an existing installation, back up:

```bash
cp "$HOME/Library/Application Support/FinTrack/personal_finance.db" \
   "$HOME/Library/Application Support/FinTrack/personal_finance.backup.db"
```

Do not add the FinTrack Application Support directory to a Homebrew Cask
`zap` stanza; uninstalling the app must not delete user financial data.
