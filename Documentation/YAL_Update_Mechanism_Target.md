# YAL Update Mechanism Target

Last updated: 2026-07-16
Branch context: beta

This document summarizes a conservative update model for YAL. It borrows the
useful separation from the LevelUp updater discussion, but adapts it to YAL's
actual deployment model as an X-Plane/SASL plugin.

## Goals

- Keep the runtime update path deterministic, auditable and easy to explain.
- Use the published update depot as the source of truth, not a Git branch.
- Keep stable and beta channels explicit.
- Avoid replacing loaded native SASL/plugin binaries while X-Plane is running.
- Stage and verify downloaded files before copying them into the live plugin.
- Write the installed version marker last.
- Preserve a clean full-install path for updates that cannot be applied at
  runtime.
- Keep GitHub Releases useful for traceability, but keep Bunny/SkunkCrafts
  depot publishing as a separate distribution step unless intentionally changed.

## Current YAL Update Surfaces

YAL currently has three related, but separate, update surfaces.

### SkunkCrafts/Bunny depot

Stable feed:

- `skunkcrafts_updater.cfg`
- depot: `https://wahltho.b-cdn.net/YAL`

Beta feed:

- `skunkcrafts_updater_beta.cfg`
- depot: `https://wahltho.b-cdn.net/YAL%20Beta`

These feeds are the published runtime update source. The runtime updater should
compare against these published depot files, not against repository branch files.

### In-plugin startup check and installer

The in-plugin startup check:

- runs after startup initialization is far enough along
- skips when the auto-update setting is off
- skips Zibo update checks when LevelUp is detected
- skips during a SASL reload within the same session
- chooses stable or beta based on `Show beta updates`
- compares against the published Bunny depot version
- supports beta-to-stable replacement when a prerelease is installed and beta
  updates are disabled

The in-plugin installer currently reads depot metadata and stages changed
non-native files:

- `skunkcrafts_updater.cfg`
- `skunkcrafts_updater_whitelist.txt`
- `skunkcrafts_updater_sizeslist.txt`

It verifies size and CRC32 before copying staged files into the plugin.
Runtime replacement is blocked when native SASL/plugin files change.

### GitHub release workflow

`.github/workflows/github-release.yml` builds a full-install ZIP and manifest
for GitHub Releases. This is useful for review, manual download, and release
traceability.

It does not publish Bunny/SkunkCrafts depots. That is intentional unless the
release process is explicitly extended later.

## Ownership Model

YAL should keep two update concepts separate:

1. **Runtime plugin content update**
   - Lua files
   - assets
   - configuration files that are safe to replace while X-Plane is running
   - depot metadata
   - installed YAL version marker

2. **Full install / native update**
   - `64/*`
   - `liblinux/*`
   - `.xpl`, `.dll`, `.so`, `.dylib`
   - SASL runtime files
   - any package that requires X-Plane to be closed

The runtime updater must not pretend it can safely replace loaded native files.
If native files differ, the update should stop and direct the user to
SkunkCrafts or the full ZIP/manual install path.

This is the YAL equivalent of the LevelUp app/content split:

- LevelUp external app updates can use VeloPack.
- LevelUp VNAV content updates are manifest-driven.
- YAL has no standalone external app today, so the in-plugin runtime updater is
  closer to a manifest-driven content updater.
- If a standalone YAL updater is ever created, that app can use VeloPack, while
  YAL plugin packages remain separately versioned and manifest-driven.

## Recommended Runtime Update Flow

1. User allows update checks in settings.
2. Startup check waits until YAL is initialized and not in a reload-only startup.
3. Select channel:
   - stable by default
   - beta when `Show beta updates` is enabled
   - stable replacement allowed when a prerelease is installed and beta is off
4. Fetch published depot version over HTTPS.
5. Compare published version with `def.VERSION`.
6. If an update/replacement is available, show a non-blocking popup.
7. User chooses `Later`, `Ignore`, or `Install YAL Stable/Beta`.
8. On install confirmation:
   - fetch depot config
   - reject disabled/locked depot
   - fetch whitelist and sizes list
   - normalize and validate every relative path
   - reject path traversal and paths outside `def.PLUGINPATH`
   - classify changed files as runtime-safe or native
9. If native files changed:
   - stop runtime install
   - show "requires X-Plane restart/full install"
   - do not partially update
10. Stage runtime-safe changes under `Output/caches/YAL.cache/update_staging`.
11. Verify staged size and CRC32.
12. Copy staged files to final locations.
13. Write `data/modules/configuration/version.ini` last.
14. Show completion state:
   - update installed
   - reload YAL or restart X-Plane
15. Reload must be deferred:
   - do not trigger reload directly from an active popup/callback lifetime
   - close/detach update window callback state first
   - schedule reload for a later flightloop tick if automatic reload is used

## Transaction Rules

The runtime updater should follow these rules:

- Published depot metadata is the source of truth.
- Never use repository branch files or auto-generated GitHub ZIPs as the runtime
  update API.
- Only update files listed in the manifest/depot metadata.
- Never trust manifest paths directly.
- Reject absolute paths, `..`, empty path segments, drive letters and root-like
  paths.
- Never delete local files unless a future manifest format explicitly supports
  deletes and the operation is reviewed.
- Stage before copy.
- Verify after download and before copy.
- Prefer writing version metadata last.
- If any staged download fails, do not copy anything.
- If copying fails midway, show a clear error and require manual repair/full
  install.
- Runtime updater may remain backup-free for now, but it should avoid claiming
  rollback support unless a backup model is actually implemented.

## Suggested Manifest Direction

The current SkunkCrafts metadata can remain supported. A future YAL-owned
manifest can be added beside it when useful.

Suggested JSON shape:

```json
{
  "schemaVersion": 1,
  "packageId": "yal-plugin",
  "packageVersion": "4.8b2",
  "releaseTag": "v4.8b2",
  "releaseChannel": "beta",
  "repository": "https://github.com/wahltho/YAL",
  "depotBaseUrl": "https://wahltho.b-cdn.net/YAL%20Beta",
  "runtimeInstallAllowed": true,
  "restartRequired": true,
  "files": [
    {
      "path": "data/modules/Custom Module/yal.lua",
      "size": 123456,
      "sha256": "..."
    }
  ],
  "nativeFiles": [
    {
      "path": "64/mac.xpl",
      "size": 123456,
      "sha256": "..."
    }
  ]
}
```

Migration path:

- Keep reading SkunkCrafts whitelist/sizes metadata.
- Add JSON manifest support as optional stronger metadata.
- Prefer SHA-256 in the new manifest.
- Keep CRC32 only for SkunkCrafts compatibility.
- If both are present, require both checks to pass.

## UI/UX States

The current update popup can map to these states:

- `checking`
- `available`
- `confirm`
- `installing`
- `installed`
- `blocked-native`
- `failed`
- `up-to-date`
- `ignored`

Recommended user-facing text should stay simple, but technical logs should be
precise:

- "Installing YAL Beta from published update depot"
- "Staging changed files"
- "Verifying downloaded files"
- "Native plugin files changed; full install required"
- "Update installed; reload YAL or restart X-Plane"

Avoid text that implies a guarantee that does not exist:

- Do not claim rollback unless backups are implemented.
- Do not claim atomic replacement for multiple files.
- Do not claim native plugin files were updated while X-Plane is running.

## Release Process Target

For each beta or stable release:

1. Ensure working tree is clean.
2. Set version consistently:
   - `definitions.lua`
   - `data/modules/configuration/version.ini`
   - `README.md`
   - active SkunkCrafts config for the target channel
3. Run Lua syntax checks.
4. Run package validation.
5. Build full-install ZIP and manifest through GitHub Actions.
6. Create GitHub Release or Pre-release.
7. Publish Bunny/SkunkCrafts depot separately:
   - ZIP/files
   - `skunkcrafts_updater.cfg`
   - whitelist
   - sizes list
   - optional future JSON manifest
8. Verify that YAL startup check sees the published version.
9. Verify install path with the selected channel.
10. Announce with channel-specific instructions.

## Boundary With VeloPack

VeloPack is useful for standalone desktop applications. It should not be forced
inside the SASL plugin runtime.

Use VeloPack only if YAL later gets a separate external updater/control app.
In that case:

- the external updater app has its own app version and VeloPack releases
- the YAL plugin package has its own plugin version and manifest
- the app can download/install YAL plugin packages while X-Plane is closed
- the app can handle native files safely
- the in-plugin updater can remain lightweight or become a check-only notifier

## Open Decisions

- Keep runtime updater backup-free, or add per-file backups for runtime-safe
  files?
- Keep Bunny/SkunkCrafts as the only runtime source, or add a signed JSON
  manifest beside it?
- Should runtime install be restricted to startup/on-ground/preflight states?
- Should YAL auto-schedule reload after runtime-safe updates, or only ask the
  user to reload/restart?
- Should GitHub Releases remain traceability-only, or become an official manual
  download surface?
- Should native/SASL changes always force full ZIP/manual install, or can an
  external updater later handle them?

## Current Practical Recommendation

Short term:

- Keep SkunkCrafts/Bunny as the runtime update source.
- Keep GitHub Releases for full ZIP traceability.
- Keep native file changes blocked in runtime updater.
- Keep `version.ini` as the last file copied.
- Add clearer install progress and failure states to the update popup.
- Consider adding an optional JSON manifest with SHA-256 hashes, while keeping
  SkunkCrafts metadata for compatibility.

Medium term:

- Add a stricter manifest schema.
- Add a dry-run/install plan summary.
- Add optional per-file backups only if rollback behavior is implemented and
  tested.
- Move native-file updates to a closed-X-Plane path, either manual install or a
  future external updater.
