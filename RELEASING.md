# Releasing Waddly

Use this checklist for release scope, versioning, security review, and verification. `.github/workflows/release.yml` is the source of truth for packaging, release notes, GitHub publishing, and Homebrew tap updates.

## Before release

1. **Get explicit release approval.** A release plan alone is not permission to publish.
2. **Choose the scope and version.** List the PRs for this release. Include only ready changes; leave unrelated or blocked work for later. Use Semantic Versioning:

   | Version bump | Use for |
   | --- | --- |
   | PATCH (`1.9.3` → `1.9.4`) | Compatible fixes and refinements to existing behavior, including small UI or animation changes. |
   | MINOR (`1.9.4` → `1.10.0`) | New backward-compatible user-facing capabilities. |
   | MAJOR (`1.9.4` → `2.0.0`) | Incompatible behavior or changes that require users to migrate or recreate saved data. |

   Documentation-only or internal maintenance changes normally ship with the next relevant app release. Ask if compatibility impact or the version bump is unclear. `CFBundleShortVersionString` in `macos/Info.plist` is the release version and must match a stable `vX.Y.Z` tag exactly. `CFBundleVersion` is not the tag source. Do not use prerelease tags unless the release workflow is extended, and never reuse or move a published tag.
3. **Review security since the previous stable release.** Check GitGuardian and all required CI results, then review changes touching input monitoring, permissions, imported-image handling/storage, file or network access, process execution, serialization, dependencies, or GitHub Actions. Check advisories for each added or updated dependency and confirm the GitHub Actions lock check passes. CI checks Action pins and Swift safety rules but does not run a general third-party dependency CVE audit. Stop for any unresolved critical/high-severity vulnerability, exposed secret, or finding of unknown impact; exceptions require explicit maintainer approval plus a recorded risk and mitigation.

## Publish

1. **Merge release candidates first.** Each selected PR must have required approvals and current required checks, including screenshot evidence for visible UI changes. If `main` moves, update any remaining candidate branch and wait for its checks and approval again; old green checks do not count.
2. **Open the version PR.** Start from the latest `origin/main`, create a release branch, and change only `CFBundleShortVersionString` in `macos/Info.plist`. Confirm the current directory and `git status --short --branch` show the release branch. Run `mise run check`. Describe the included PRs and validation in the PR. Merge only with an up-to-date base, passing required checks, and an approved review; never bypass a gate.
3. **Tag the merged main commit.** After the version PR is merged, run:

   ```sh
   set -euo pipefail
   git fetch origin
   git switch main
   git pull --ff-only origin main
   VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' macos/Info.plist)
   test "$VERSION" = "X.Y.Z"
   git tag -a "v$VERSION" HEAD -m "Waddly $VERSION"
   git push origin "v$VERSION"
   ```

4. **Verify publication.** Watch the tag-triggered Release workflow to completion. Confirm all steps succeed, the GitHub Release contains `Waddly-X.Y.Z-macos-arm64.dmg` and its `.sha256` checksum, and the Homebrew tap reports the same version. If any step fails or versions/checksums disagree, stop and resolve it; do not update the tap by hand during a successful run.
5. **Update the local Homebrew install.** If this environment has Waddly installed, run `brew update`, inspect `brew info --cask waddly`, then run `brew upgrade --cask waddly`. Verify `brew list --cask --versions waddly` and `/Applications/Waddly.app/Contents/Info.plist`. If Waddly was running during the upgrade, its process may still use the old build; arrange a relaunch or clearly report that one is needed.

## Complete

Confirm local `main` is fast-forwarded to `origin/main` and the working tree is clean. Report the version and release link, included PRs, security review and validation results, Homebrew/app-bundle version, and any pending relaunch. Release monitoring ends after these checks; continue it only when explicitly requested.
