# Release Checklist

AgentTally releases are published from `suiyun08/agenttally` by pushing a version tag.

## Steps

1. Write the release notes in `docs/releases/v<version>.md`. The Release workflow puts them
   above the installation notes; without the file, GitHub generates notes from merged PRs.
2. Bump every version field with the script, never by hand:

   ```bash
   ./scripts/bump-version.sh <version>
   ```

3. Land the bump on `master` through a PR merged at the reviewed HEAD, and wait for CI.
4. Tag the merged commit and push the tag:

   ```bash
   git tag v<version> && git push origin v<version>
   ```

   `.github/workflows/release.yml` checks the tag against the committed versions, builds
   Apple Silicon and Intel apps (a zip and a DMG each), and publishes the GitHub Release.

## Verify

```bash
gh release view v<version> -R suiyun08/agenttally
```

- The release lists `AgentTally-macOS-{arm64,x86_64}.{zip,dmg}`.
- A downloaded zip passes `codesign --verify --deep --strict`, shows the new version in
  `Contents/Info.plist`, and its executable has the right architecture (`lipo -archs`).

## Not set up yet

- Developer ID signing and notarization: builds are ad-hoc signed, so macOS asks users to
  allow the first launch, and Sparkle updates stay off.
- Sparkle appcast and a Homebrew tap: users update by downloading the new release.
