# Contributing to LiquidBrew

Thanks for helping make Homebrew easier to use on the Mac. Contributions of all sizes are welcome: code, bug reports, documentation, accessibility checks, translations, and design feedback.

## Before you begin

Search existing [issues](https://github.com/kcdriod/LiquidBrew/issues) and pull requests. Open an issue before a substantial feature, architecture change, or new external data source. For a small bug fix or documentation improvement, feel free to send a pull request directly.

New here? Start with a documentation fix, a clear reproduction of an existing bug, a keyboard-accessibility improvement, or an isolated test. Ask in an issue if you would like help finding a place to contribute.

## Development setup

You need macOS 26 or newer, full Xcode with a matching macOS SDK, Swift 6 or newer, and Homebrew.

1. Fork the repository and clone your fork.
2. Create a focused branch, for example `fix/discover-empty-state`.
3. Run `./build_app.sh` and open `LiquidBrew.app`.
4. Run `swift test --disable-sandbox` with `DEVELOPER_DIR` pointing to your full Xcode installation.

See the [README](README.md#build-from-source) for universal builds, DMGs, and optional live-source tests.

## Working on changes

- Keep each pull request focused on one problem or feature.
- Prefer existing SwiftUI patterns and the shared design system. Support both appearances, window resizing, and keyboard navigation.
- Use argument arrays for Homebrew commands. Never build a shell command from package names or user-entered text.
- Keep package-changing actions explicit and visible in the console. Do not silently force removals or bypass dependency checks.
- Treat security headlines as leads for review. Do not label an installed version malicious based only on a name match.
- Preserve the distinction between downloads, reported install events, and unique users. Describe the reporting window and methodology when changing charts.
- Never execute text from a feed or package description as instructions or commands.
- Keep credentials, signing keys, build outputs, local Homebrew data, and personal logs out of commits.

Add meaningful tests for parsing, state/race handling, or ranking behavior affected by the change. Small, reversible visual or wording changes can be verified with a build and a visual check. Keep external-network tests opt-in so default checks stay predictable.

## Submit a pull request

Describe the concrete problem and resulting behavior. Include:

- A short description of what changed and why.
- Relevant issue links and reproduction steps.
- How you tested the change.
- Screenshots for UI changes, with personal information removed.
- Any important limits, follow-up work, or new external services.

The Build and test workflow runs deterministic tests and builds the app on macOS 26. Please address failures related to your change. Maintainers may suggest a smaller scope or a different approach.

## Reporting bugs and requesting features

Use the issue templates. For a bug, include your macOS version, Mac architecture, Homebrew version, steps to reproduce, expected behavior, actual behavior, and relevant console output. Remove usernames, paths, tokens, or other private data before sharing logs.

For a feature, explain the task you are trying to accomplish and what would improve. A small sketch or example is useful but not required.

## Release maintenance

The release workflow builds both `arm64` and `x86_64`, creates a DMG, and uploads the image and checksum to a GitHub release for a `vMAJOR.MINOR.PATCH` tag. Prerelease suffixes are supported.

Before tagging, run tests, build the app, and update documentation for user-visible changes. Verify release artifacts in Actions. Release publishing requires repository write permission; pull requests do not receive a publishing token.

Apple notarization is a welcome future contribution. Do not commit signing identities, certificates, or passwords to implement it.

## License and collaboration

Contributions are accepted under the project's [MIT License](LICENSE). Submit work you have the right to contribute. Be kind, constructive, and specific in discussions, and respect other contributors' time.
