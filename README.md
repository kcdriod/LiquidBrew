<p align="center">
  <img src="Assets/AppIcon.png" width="128" alt="LiquidBrew app icon" />
</p>

# LiquidBrew

**A native macOS app for managing Homebrew, discovering useful software, and understanding what is installed on your Mac.**

[![Build and test](https://github.com/kcdriod/LiquidBrew/actions/workflows/ci.yml/badge.svg)](https://github.com/kcdriod/LiquidBrew/actions/workflows/ci.yml)
[![Release DMG](https://github.com/kcdriod/LiquidBrew/actions/workflows/release.yml/badge.svg)](https://github.com/kcdriod/LiquidBrew/actions/workflows/release.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-teal.svg)](LICENSE)

LiquidBrew brings installed packages, charts, updates, background services, dependency graphs, security reports, and a live console into one SwiftUI workspace with a Liquid Glass interface.

**Help build LiquidBrew!** Bug reports, feature ideas, accessibility improvements, documentation, and pull requests are welcome. See [Contributing](CONTRIBUTING.md), [open an issue](https://github.com/kcdriod/LiquidBrew/issues/new/choose), or pick something from the [contribution ideas](#help-wanted).

## Install

Requires **macOS 26 or newer** and an existing [Homebrew](https://brew.sh) installation.

1. Download the universal `.dmg` from [Releases](https://github.com/kcdriod/LiquidBrew/releases/latest).
2. Open the disk image and drag **LiquidBrew.app** into **Applications**.
3. Launch LiquidBrew. It reads your installed packages and Homebrew configuration.

Release DMGs support **Apple Silicon and Intel Macs**. Community builds are ad-hoc signed and are **not Apple-notarized**, so macOS may show a Gatekeeper warning. The app does not bypass macOS security protections.

A `.sha256` file accompanies each DMG. To check a downloaded image, place both files in the same folder and run:

```sh
shasum -a 256 -c LiquidBrew-1.0.0-universal.dmg.sha256
```

Use the filename matching the version you downloaded. You can also [build from source](#build-from-source).

## Screenshots

### Discover: Top Charts

Browse popular software with download counts, reporting dates, descriptions, and installation status.

![Discover showing the 30-day formula download chart](docs/screenshots/discover.png)

### Installed packages and details

Inspect versions, package metadata, actions, and dependencies. This screenshot focuses on the package workspace with the navigation sidebar hidden.

![Package browser with curl selected and its details visible](docs/screenshots/packages.png)

### Interactive dependency graph

Explore a formula's dependencies and reverse dependencies in the radial layout. The navigation sidebar and node inspector are hidden here to give the graph more room.

![Radial graph showing curl dependencies and the package that uses it](docs/screenshots/dependency-graph.png)

Screenshots show the macOS app in dark appearance. Package inventories, versions, and chart data vary by Mac and date; the last two images are cropped to the workspace content.

## Features

| Workspace | What you can do |
| --- | --- |
| **Packages** | Browse installed formulae and casks; search by name or description; filter all packages, formulae, casks, top-level packages, pinned packages, or outdated packages. |
| **Package details** | View installed versions, description, homepage, tap, license, install date, caveats, dependencies, build dependencies, and packages that depend on a selection. Pin/unpin formulae, upgrade, or confirm removal. |
| **Discover** | Search as you type, use an explicit Search button, and browse Top Charts or Trending. Switch between formulae and apps, see descriptions and counts, open source details, and install packages. Installed items are marked. |
| **Updates** | Check for outdated packages, update Homebrew's index, upgrade individual packages, or upgrade everything. See installed and current versions and pinned status. |
| **Services** | Inspect Homebrew background services, their status and user; start, stop, or restart them. |
| **Dependency Graph** | Explore formula dependencies in radial or tree layouts. Focus on a selected formula or a network of top-level packages; pan, zoom, select nodes, inspect relationships, and jump to package details. |
| **Taps & Brewfile** | Browse taps, add or remove repositories, preview/regenerate a Brewfile, copy or export it, and import a Brewfile to install its declared packages. |
| **Health & Cleanup** | Run `brew doctor`, read warnings and diagnostic output, inspect cache usage, preview cleanup, clean old versions/cache, and remove unused dependencies. |
| **Security** | Review Homebrew security-related disable/deprecation warnings and recent matching news headlines. Follow source links, see affected installed package names, and confirm removal after checking dependents. Optional Mac notifications alert you to new reports. |
| **Console** | Toggle a resizable panel on the right. Read live command output with distinct command, progress, success, warning, and error styling; search output, filter issues, pause following, jump to latest, wrap lines, show timestamps, copy, or save logs. |

The console records command completion time and exit status and retains the most recent **1,000 lines in the current session**. It is a viewer for commands run by the app, not an interactive shell. Homebrew's own dependency checks remain in effect during removal.

### Top Charts and Trending

Rankings use [Homebrew's published analytics](https://formulae.brew.sh/docs/api/#analytics) and show up to 50 entries per chart:

- **Formula Top Charts:** 30-day download counts for Homebrew's measured subset of formulae, across versions and platforms. These can include repeat downloads and CI. If download data is unavailable, the UI explicitly falls back to reported direct installs.
- **App Top Charts:** reported cask installs over 30 days. These are install events, not comparable download totals or unique users.
- **Trending:** growth in daily reported installs in the latest 30 days against the **preceding 60 days**, calculated by subtracting the recent window from the 90-day totals. Formulae use direct install events, excluding dependencies.
- Trending requires at least 500 recent installs, 100 installs in the prior period, and 10% growth. New packages without a usable baseline are not ranked. Mismatched reporting windows disable the comparison.

The app shows reporting dates, refresh status, source limitations, and saved charts if a refresh fails. Successful chart data is cached in memory for an hour and saved locally for later launches.

### Security reports and notifications

Security checks run at startup, after package refreshes, and every six hours **while LiquidBrew is open**. Enable notifications in **Security**; the app asks macOS for permission when you turn them on.

Sources currently include Homebrew's public formula/cask metadata, the Homebrew news feed, and The Hacker News feed. Source status and the last successful check are visible. A failed source retains previous warnings, which may be out of date.

News matching checks available dated headlines from the last 90 days. It uses package-name boundaries and skips short or ambiguous names. A mention is labeled **review required**: it does not establish that the same product, ecosystem, or installed version is affected. Homebrew metadata warnings cover official taps; removed entries may no longer appear in the current catalogue.

This is a report-review feature, not a malware scanner or a complete vulnerability database. No matches does not guarantee safety. Removing a package does not reverse damage from a compromise; follow the original report's remediation advice.

### Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| `⌘R` | Refresh Homebrew data |
| `⇧⌘U` | Update Homebrew and taps |
| `⇧⌘G` | Upgrade all outdated packages |
| `⌥⌘T` | Show/hide the right-side console |

## Build from source

Use a **full Xcode installation** with a macOS 26-or-newer SDK and Swift 6 or newer. Command Line Tools alone may lack the SwiftUI compiler plugins required by the selected SDK.

```sh
git clone https://github.com/kcdriod/LiquidBrew.git
cd LiquidBrew
./build_app.sh
open LiquidBrew.app
```

`build_app.sh` selects `/Applications/Xcode.app` when available, builds the app, creates the full Mac icon family from `Assets/AppIcon.png`, writes the bundle metadata, and ad-hoc signs and verifies the result. The default build targets your current Mac architecture.

For a universal release build and DMG:

```sh
BUILD_CONFIGURATION=release BUILD_ARCHS='arm64 x86_64' \
  APP_VERSION=1.0.0 APP_BUILD_NUMBER=1 ./build_app.sh
./scripts/build_dmg.sh 1.0.0
```

The image and SHA-256 checksum are written to `dist/`. The DMG contains the app, an Applications shortcut, and installation notes. Build products and local credentials are excluded from Git.

## Tests

Select your full Xcode toolchain, adjusting the path if necessary:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test --disable-sandbox
```

The default suite tests headline matching, feed parsing, terminal formatting and severity, ranking calculations, search output parsing, visible search errors, and stale-search handling. Tests that depend on public endpoints or a local Homebrew executable are opt-in:

```sh
LIQUIDBREW_DISCOVER_LIVE_TESTS=1 LIQUIDBREW_SECURITY_LIVE_TESTS=1 \
  swift test --disable-sandbox
```

The live Discover test queries Homebrew and public charts; it does not install packages. Local live checks currently exercise 15 tests in total. Contributor PR checks run deterministic tests; promotions into `master` also run the live checks and validate the universal app and DMG. Release automation has a separate Python test suite: `python3 -m unittest discover -s Tests/Automation -v`.

## Branching, reviews, and releases

```text
feature/fix/docs branch → PR to develop → PR from develop to master → DMG + GitHub release
```

**`develop` is the default branch. `master` is the release branch; this project does not use a separate `main` branch.** Fork or branch from `develop` and target contributor pull requests there.

| Route | Required checks | Required approval | Result |
| --- | --- | --- | --- |
| Contributor branch → `develop` | **PR branch policy** and **Develop tests** (script validation, release-automation tests, deterministic Swift tests) | Code-owner approval from **@kcdriod** | Integrates the change; no release is built. |
| This repository's `develop` → `master` | **PR branch policy** and **Master full suite** (all Swift tests including live checks, release-automation tests, optimized universal app, and verified DMG) | Code-owner approval from **@kcdriod** | A successful merge starts the production build and release workflow. |
| Any other branch/repository → `master` | Policy check fails | — | Cannot merge; retarget to `develop`. |

Both protected branches require up-to-date checks, resolved review conversations, and fresh approval after new commits. Direct pushes, force pushes, and branch deletion are blocked, including for administrators. Approval does not grant repository write access: only existing maintainers/collaborators with merge permission can merge a passing, approved PR.

GitHub permits creating a PR with another base, so the policy blocks its **merge**, rather than preventing the PR form from being opened. GitHub does not permit approving your own PR; a maintainer-authored PR needs another eligible reviewer, and the maintainer/code-owner requirement still applies where GitHub requires it.

### Publishing a version

1. Finish contributor PRs into `develop` with the required checks and review.
2. Open a promotion PR **from this repository's `develop` to `master`**.
3. Wait for **Master full suite** and the policy check, resolve conversations, and obtain the required review.
4. Merge using a merge commit. The **Release DMG** workflow builds that exact approved merge, creates a version tag, and publishes a universal DMG and SHA-256 checksum.
5. Before the next promotion, open a `master` → `develop` synchronization PR if `develop` is behind. It follows the normal develop checks and approval process. Keep both long-lived branches; do not delete `develop` after a promotion.

`RELEASE_VERSION` defaults to **`auto`**: stable versions advance by one patch (`v1.0.0` → `v1.0.1` → `v1.0.2`). To select a minor or major release, change the file to a numeric version such as `1.1.0` or `2.0.0` in a reviewed PR to `develop`; reset it to `auto` in the next cycle. The full suite rejects an explicit version that has already been used or is older than a stable release.

Version tags are reserved atomically, so concurrent promotions cannot claim the same version. Rerunning a failed release reuses the tag already assigned to its merge commit. Already-published assets are preserved. If builds finish out of order, GitHub selects the latest stable release by its legacy semantic-version/date policy.

The numeric version is embedded in the app, and the workflow run number becomes its bundle build number. Release artifacts are retained with the run for 14 days. A repository-scoped GitHub token handles publishing; a manually pushed tag does **not** start a release. To retry a failure, rerun the original **Release DMG** run in Actions.

The **Build and test** workflow can be run manually on `develop` (quick checks) or `master` (full validation without publishing). The release workflow runs only when an eligible promotion PR has actually been merged.

Apple Developer ID signing and notarization are not configured yet. Contributions to that release process are welcome.

## Project structure

```text
Assets/                        App icon artwork and generation prompt
Sources/LiquidBrew/
  LiquidBrewApp.swift           App entry point, navigation, shortcuts, console layout
  DesignSystem/                Shared Liquid Glass styling
  Models/                      Package models and output/search helpers
  Services/                    Homebrew commands, app state, charts, security sources
  Views/                       Packages, Discover, updates, services, graph, maintenance
Tests/LiquidBrewTests/          Deterministic and opt-in live tests
.github/workflows/             Branch policy, staged PR checks, and master-merge releases
build_app.sh                   Build, package, icon generation, and ad-hoc signing
scripts/build_dmg.sh            Universal DMG creation and checksum
```

Package commands run locally through the Homebrew executable. Installed inventory is not uploaded to a project-owned server. Discover and Security fetch public registry, analytics, and news data; Homebrew's own analytics settings are separate from LiquidBrew.

## Help wanted

There is plenty of room to improve LiquidBrew. Useful contributions include:

- Accessibility, keyboard navigation, VoiceOver, and small-window layouts.
- Better search ranking, pagination, and discovery filters.
- Additional reliable security sources and version-aware advisory matching.
- Graph performance and clearer dependency explanations for large installations.
- Testing across Apple Silicon and Intel Macs and different Homebrew installations.
- Developer ID signing, notarization, and distribution improvements.
- Documentation, screenshots, translations, and reproducible bug reports.

Start with [CONTRIBUTING.md](CONTRIBUTING.md). For a larger change, open an issue first so we can agree on the behavior and avoid duplicate work. Small fixes and documentation improvements are welcome directly as pull requests.

## License and acknowledgements

[MIT License](LICENSE). LiquidBrew is an independent project and is not affiliated with Homebrew or Apple.

Built with SwiftUI and [Homebrew](https://brew.sh). Discovery data comes from [Homebrew Formulae](https://formulae.brew.sh); security headlines link back to their original publishers. The app icon was created with OpenAI's image generator; its design prompt is included in `Assets/AppIcon.prompt.txt`.
