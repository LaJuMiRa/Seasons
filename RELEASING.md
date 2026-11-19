# Releasing

## 1. Prepare

1. Update `VERSION` (for example `1.0.1`).
2. Add a `## [1.0.1] - YYYY-MM-DD` section to `CHANGELOG.md`. The workflow copies it into the release notes.
3. Check locally:
   ```sh
   swift test --scratch-path /tmp/seasons-spm
   ./release.sh
   ```
4. Commit: `git commit -am "chore: release 1.0.1"`.

## 2. Tag and push

```sh
git tag v1.0.1
git push origin main
git push origin v1.0.1     # tags are not pushed by a plain `git push`
```

The tag starts `.github/workflows/release.yml` on a `macos-26` (Apple Silicon) runner. The workflow checks that the tag matches `VERSION`, runs the tests, builds and ad-hoc signs the app, creates `Seasons-1.0.1-arm64.zip` with its SHA-256 and publishes a GitHub release with both files.

There is no notarization (no paid Apple Developer account). Users have to allow the first start, see the README.

## 3. Homebrew tap (one-time setup)

1. Create a public GitHub repository named **`homebrew-tap`**. The `homebrew-` prefix is required for `brew tap`.
2. Copy `packaging/homebrew/seasons.rb` to `Casks/seasons.rb` in that repository.

Then users can install with:

```sh
brew install --cask LaJuMiRa/tap/seasons
```

## 4. Homebrew tap (every release)

In `Casks/seasons.rb` of the tap:

1. Set `version` to the new version.
2. Set `sha256` to the value from `Seasons-<version>-arm64.zip.sha256` (in the release assets).
3. Commit and push. Check with `brew audit --cask LaJuMiRa/tap/seasons` and `brew install --cask LaJuMiRa/tap/seasons`.

Note: Homebrew removed the `--no-quarantine` option. The cask's caveats explain how to allow the first start (System Settings › Privacy & Security › Open Anyway, or `xattr -dr com.apple.quarantine`).
