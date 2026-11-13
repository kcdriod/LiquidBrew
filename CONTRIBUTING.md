# Contributing to LiquidBrew

Thanks for helping make Homebrew easier to use on the Mac. Contributions of all sizes are welcome: code, bug reports, documentation, accessibility checks, translations, and design feedback.

## Before you begin

Search existing [issues](https://github.com/kcdriod/LiquidBrew/issues) and pull requests. Open an issue before a substantial feature, architecture change, or new external data source. For a small bug fix or documentation improvement, feel free to send a pull request directly.

New here? Start with a documentation fix, a clear reproduction of an existing bug, a keyboard-accessibility improvement, or an isolated test. Ask in an issue if you would like help finding a place to contribute.

## Development setup

You need macOS 26 or newer, full Xcode with a matching macOS SDK, Swift 6 or newer, and Homebrew.

1. Fork the repository, clone your fork, and start from the default `develop` branch.
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

Target **`develop`** for every contributor PR, including documentation and workflow changes. PRs from feature branches or forks into `master` cannot pass the required branch policy. `master` accepts only a promotion from this repository's `develop` branch.

Describe the concrete problem and resulting behavior. Include:

- A short description of what changed and why.
- Relevant issue links and reproduction steps.
- How you tested the change.
- Screenshots for UI changes, with personal information removed.
- Any important limits, follow-up work, or new external services.

Contributor PRs need **PR branch policy** and **Develop tests** to pass. Develop tests validate scripts, exercise release-version automation, and run deterministic Swift tests on macOS 26. Request review from **@kcdriod**, the code owner. New commits dismiss stale approvals. Resolve review conversations and update your branch against `develop` before merging.

Only people with repository merge permission can merge. Other collaborators need code-owner approval from **@kcdriod**; new commits dismiss stale approval. **@kcdriod** has a review-only exception and may merge a passing PR, including an owner-authored PR, without a separate approving review. Use GitHub's owner bypass option for that review rule after the checks pass. This exception cannot bypass tests, PR routing, the up-to-date requirement, or resolved conversations. Direct pushes remain blocked for everyone. Do not use automation to impersonate a reviewer or manufacture a self-approval.

## Reporting bugs and requesting features

Use the issue templates. For a bug, include your macOS version, Mac architecture, Homebrew version, steps to reproduce, expected behavior, actual behavior, and relevant console output. Remove usernames, paths, tokens, or other private data before sharing logs.

For a feature, explain the task you are trying to accomplish and what would improve. A small sketch or example is useful but not required.

## Release maintenance

`develop` is the integration branch and `master` is the production/release branch. There is no separate `main` branch.

1. Open a PR from this repository's **`develop` to `master`**.
2. The required **Master full suite** runs release-automation tests and all Swift tests, including Homebrew/news/analytics live checks. It builds an optimized universal app and verifies a validation DMG. **PR branch policy** also checks the source branch and repository.
3. Obtain code-owner review from **@kcdriod**, or use the review-only exception if merging as that owner account. Keep the branch up to date and resolve all review conversations.
4. Merge only after every required check and review passes. Use the merge-commit option; the repository disables squash/rebase merges to preserve promotion history.
5. The merged PR triggers **Release DMG**, which builds the exact merge commit, reserves its version tag, and publishes the DMG and checksum.
6. Synchronize `master` back into `develop` through a normal PR before the next promotion when GitHub reports that `develop` is behind. Both long-lived branches are protected against deletion.

Leave `RELEASE_VERSION` as `auto` for the next patch release. To choose a major/minor version, change it in a reviewed contributor PR before promotion, then reset it to `auto` during the next development cycle. Explicit versions must be newer than the stable tags. Do not create a release by manually pushing a tag; use the promotion route. Rerun a failed release workflow to retry its original version.

You can manually dispatch **Build and test** on `develop` or `master` to validate their respective suites without publishing. The full suite depends on live public sources; fix or retry a failed source check instead of bypassing it.

Apple notarization remains welcome future work. Never commit signing identities, certificates, or passwords.

## License and collaboration

Contributions are accepted under the project's [MIT License](LICENSE). Submit work you have the right to contribute. Be kind, constructive, and specific in discussions, and respect other contributors' time.
