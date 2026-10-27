# Contributing

## Setup

Open `Secure-Vault.xcodeproj` using Xcode 26.5 or newer with the iOS platform and an iOS 26+ simulator installed. Select the shared `Secure-Vault` scheme. No external packages or provider keys are needed.

## Branch workflow

```text
feature/* → development → staging → main
```

Create focused feature/fix branches from `development`. Promote reviewed changes through `staging` and then `main` using pull requests. Synchronize any direct hotfix back into both branches. Deployment, signing, branch protection, and approval settings are separate from these source branches.

## Validation

Run **Product → Test** in Xcode, or use the simulator command in the [README](README.md#tests). CI runs the same project and test target on macOS with an available iPhone simulator.

For crypto, Keychain, or storage changes, include relevant round-trip, tampering, error-path, and cleanup verification. Keep Keychain tests isolated with unique service namespaces and filesystem tests in temporary directories. Do not use personal vault data as fixtures.

## Scope and documentation

The implemented product is a file-encryption core with a SwiftUI starter shell. Document the actual behavior of UI, authentication, previews, and persistence when expanding it. Avoid adding claims of biometric protection, secure deletion, recovery, or production qualification unless the corresponding behavior and evidence are present.

Keep generated Xcode output, signing material, developer-local settings, and test artifacts outside commits. Preserve the current module boundaries and describe any format or migration implications in the pull request.
