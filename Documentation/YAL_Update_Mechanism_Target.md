# YAL Update Mechanism Target

Last updated: 2026-07-16
Branch context: beta

This document summarizes a conservative update model for YAL. It borrows the
useful separation from the LevelUp updater discussion, but adapts it to YAL's
actual deployment model as an X-Plane/SASL plugin.

YAL is expected to implement its own update algorithm. This is a parallel path
to the LevelUp standalone installer, not a dependency on it. The two projects
can share the same conservative concepts -- manifests, hashes, staging,
dry-run, backups and install-state classification -- while remaining separate
implementations.

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
- Keep YAL's internal update engine reusable enough to handle both YAL runtime
  updates and manifest-driven content packages such as Zibo custom VNAV tables.

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

YAL owns the in-plugin update algorithm. That algorithm should keep these
update concepts separate:

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

3. **External aircraft content package**
   - package manifests downloaded from authorized GitHub Releases
   - payload files verified by hash
   - local aircraft files patched through anchors and markers
   - package-specific install state, backup, repair and uninstall metadata

The runtime updater must not pretend it can safely replace loaded native files.
If native files differ, the update should stop and direct the user to
SkunkCrafts or the full ZIP/manual install path.

This is the YAL-side equivalent of the LevelUp app/content split:

- LevelUp can have its own standalone VeloPack installer.
- YAL implements its own in-plugin update engine.
- Both implementations can use manifest-driven content packages.
- Zibo custom VNAV descent table updates can use the same manifest-driven
  content package model, with package-specific anchors, markers and payload
  hashes from `X-Plane-ZIBO-Descent-Tables`.
- VeloPack is not part of the current YAL in-plugin update algorithm. It belongs
  to the separate LevelUp standalone installer, or to a possible future YAL
  companion app that would still consume YAL-owned package/update metadata.

## YAL-Owned Update Engine

YAL should grow a reusable update engine inside the plugin instead of relying
on the LevelUp standalone installer.

The engine should expose a small set of operations:

- check available package metadata
- classify local install state
- build a dry-run plan
- stage downloads
- verify sizes and hashes
- install runtime-safe YAL files
- patch supported external aircraft content packages
- repair a known package state
- uninstall package-owned blocks and payloads
- export a diagnostic report

For YAL's own files, the engine uses the current Bunny/SkunkCrafts depot and
must keep blocking native/SASL binary replacement while X-Plane is running.

For Zibo custom VNAV tables, the same engine can consume the
`X-Plane-ZIBO-Descent-Tables` release manifest, download the payload, verify
hashes, detect a valid Zibo target, patch `B738.a_fms.lua` through the declared
markers and anchors, and record package-specific backup/install metadata.

This must remain explicit user action. YAL should not silently modify an
aircraft Lua file during a normal startup check.

## Implemented VNAV Descent Tables Flow

YAL now implements the external aircraft-content path for the currently loaded
Upstream Zibo or LevelUp aircraft. The custom C++ port remains out of scope
because it has no XLua `B738.a_fms.lua` target.

The implemented flow:

- detects only the currently loaded aircraft installation
- downloads the authorized release manifest and all four declared payloads
- verifies exact payload size and SHA-256 before creating a patch
- preserves UTF-8 BOM, line-ending style, and final-newline behavior
- stages and structurally verifies the complete patched package
- creates a per-aircraft generation backup and transaction receipt before any
  live replacement
- installs the table payload before activating its hooks
- replaces live files through adjacent temporary and rollback files
- verifies the committed bytes and restores the previous state on failure
- supports state-dependent `Install`, `Update`, `Repair`, `Uninstall`, and a
  hash-guarded `Restore Backup`
- never removes a table payload unless it still matches the published package
  hash
- never restores a backup over an aircraft file changed after the recorded
  transaction

The Settings window exposes `VNAV Descent Tables...` beside the existing view
maintenance actions. It reuses the YAL Update Status window for current status,
confirmation, operation result, `Later`, and `Ignore this version`. Every
successful modifying action requires a full X-Plane restart; YAL does not
trigger an aircraft or SASL reload for this package.

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

For the current YAL target, the update algorithm is implemented inside YAL
itself. VeloPack is therefore out of scope for the in-plugin engine.

Use VeloPack only for:

- the separate LevelUp standalone installer
- a possible future YAL companion app, if YAL ever needs a desktop shell outside
  X-Plane

Even in that later companion-app case:

- YAL's update/package manifest remains the source of truth
- the YAL plugin package keeps its own plugin version and release channel
- the companion app only provides a closed-X-Plane execution surface
- native file replacement remains blocked from the live in-plugin path

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
- Should native/SASL changes always force full ZIP/manual install, or should a
  future YAL-owned closed-X-Plane path handle them?

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
  future YAL-owned companion path.
