# YAL Beta Release Checklist

This document summarizes the steps required to ship a beta build alongside the stable Skunkcrafts channel. Follow the list top to bottom for every beta drop.

## 1. Git preparation

1. Make sure your working tree is clean (`git status`).
2. Create/update the beta branch:
   ```bash
   git checkout -B beta
   ```
3. Update version strings to the new beta tag (e.g. `4.4b2`) in:
   - `data/modules/Custom Module/definitions.lua`
   - `data/modules/configuration/version.ini`
4. Commit the changes on `beta`:
   ```bash
   git commit -am "Bump beta version to 4.4b2"
   ```
5. Push the branch (replace `origin` if you use another remote):
   ```bash
   git push origin beta
   ```

## 2. Build & verify

1. Export the beta package (ZIP) from the current `beta` branch:
   - macOS/Linux: `zip -r YAL-4.4b2.zip YAL`
   - Windows: use your archiver of choice.
2. Launch X-Plane with the beta package installed and run through a regression test (start-up, cockpit init, discontinuity checks, approach handling).
3. Enable **Show beta updates** in the YAL settings window and make sure the update header shows `v4.4b2`.

## 3. Publish to Bunny.net / Skunkcrafts

1. Upload the beta ZIP to `https://wahltho.b-cdn.net/YAL Beta/` (use the Bunny web UI or your preferred S3 client).
2. Place the corresponding Skunkcrafts manifest in the same folder:
   - Copy `skunkcrafts_updater_beta.cfg` locally.
   - Edit `version|...` to match the new beta version.
   - Upload the updated `.cfg` next to the ZIP.
3. Verify download by running the Skunkcrafts Updater in X-Plane:
   - Ensure the entry **YAL Beta** appears.
   - Run an update and confirm the beta package is installed.

## 4. GitHub release

1. On GitHub create a new **Pre-release** tagged from the `beta` branch:
   - Tag name: `v4.4b2`
   - Release title: `YAL 4.4b2 (Beta)`
   - Mark as pre-release and link the Bunny download URL.
2. Attach the beta ZIP or provide the direct CDN link for testers.

## 5. Documentation

1. Update `README.md` if there are user-facing changes (new procedures, UI, etc.).
2. Add/Update change log entries. If you keep a `CHANGELOG.md`, add a beta heading.
3. Notify testers (Discord/forum) with:
   - Short feature list.
   - Link to the GitHub pre-release.
   - Reminder to enable **Show beta updates** and use `skunkcrafts_updater_beta.cfg`.

## 6. Post-release duties

1. Merge the beta branch back into the release branch when promoting the build to stable.
2. Update `skunkcrafts_updater.cfg` (stable) and Bunny stable folder.
3. Bump `definitions.lua` / `version.ini` to the next development version (e.g. `4.4b3-dev` or `4.5-dev`) on the main branch.

Keep this checklist with the project so future beta drops follow the same routine. Feel free to extend it with automation steps (scripts, CI jobs) once the workflow has stabilized.
