# MiningSim

A Godot 4.6 mining/factory game (Windows-only build target).

## Project layout

```
project.godot              Godot project config (config/version is the runtime version source)
VERSION                    Plain-text mirror of config/version, kept in sync for CI/tooling
icon.svg                   Window/desktop icon
scenes/                    Game scenes
autoload/updater.gd        Auto-update logic + embedded PowerShell helper
autoload/update_dialog.gd  In-game update prompt UI (blue/white themed)
design_plans/              Design docs
export_presets.cfg         Windows Desktop export preset
```

`assets/` (not in this repo) holds 3D assets used by the game scenes.

## Running locally

1. Open `project.godot` in Godot 4.6.
2. Press F5. The placeholder scene should display the version string.

The auto-updater is **disabled in the editor** — it only runs in exported builds.

## Cutting a release

This is the workflow for shipping an update to your friend.

1. **Bump the version.** Edit `config/version` in `project.godot` (e.g. `0.1.0` → `0.2.0`) — this is what the running game reads. Mirror it into `VERSION` for git/CI legibility.
2. **Commit and tag:**
   ```powershell
   git add VERSION project.godot
   git commit -m "Release v0.2.0"
   git tag v0.2.0
   git push origin main --tags
   ```
3. **Export the Windows build** from Godot: `Project → Export… → Windows Desktop → Export Project`. Output to e.g. `exports/mineco.exe` (the `.pck` will be next to it).
4. **Zip the export folder.** The zip's contents must sit at the **top level** (not nested in a folder), and must include:
   - `mineco.exe` — the executable. **The filename of the .exe must match what's already installed on your friend's machine** (the helper relaunches via the original install path).
   - `mineco.pck`
   - Any other files Godot generated.

   ```powershell
   Compress-Archive -Path exports\* -DestinationPath mineco-v0.2.0-windows.zip
   ```
5. **Create the GitHub release** with the zip attached:
   ```powershell
   gh release create v0.2.0 mineco-v0.2.0-windows.zip --title "v0.2.0" --notes "What changed in this build"
   ```

The next time your friend launches the game, the updater will see the new release, prompt them, and (if they accept) download/install/relaunch automatically.

### Asset name convention

The updater looks specifically for an asset named **`mineco-v<VERSION>-windows.zip`** on the latest release. Any other name and it will silently skip.

## How the updater works

On launch (release builds only):

1. `Updater` autoload `GET`s `api.github.com/repos/wes2000/mineco/releases/latest`.
2. Compares the release's `tag_name` (e.g. `v0.2.0`) against `ProjectSettings.application/config/version` (which Godot packs into the binary as `project.binary` — always present in the `.pck`).
3. If the release is newer and the user hasn't already skipped this version, shows the blue/white update prompt with release notes and `[Update Now] / [Skip This Version]`.
4. **Update Now**: downloads `mineco-v<VERSION>-windows.zip` to `%TEMP%\mineco_update\update.zip`, extracts to `%TEMP%\mineco_update\extracted\`, writes the embedded PowerShell helper to `%TEMP%\mineco_apply_update.ps1`, launches it (detached), then quits the game.
5. The PowerShell helper waits for the game's PID to exit, copies the new files over the install directory, and relaunches the game.

The helper script lives as a `const HELPER_SCRIPT` string inside `autoload/updater.gd` rather than as a separate `.ps1` file. This is deliberate: Godot's export filter (`all_resources`) doesn't pack non-resource files like `.ps1` or `.txt` by default, so the helper would be missing from the `.pck`. Embedding it in the GDScript bytecode sidesteps the filter entirely.

### Why a PowerShell helper?

Windows can't overwrite a running `.exe`. The game has to be fully exited before the new files can be copied in. The helper is the smallest reliable way to do that hand-off.

The helper is launched with `-ExecutionPolicy Bypass`, so it runs even on machines with restricted policy.

### "Skip this version" behavior

Stored in `user://updater_skip.cfg`. Per Godot, on Windows that's `%APPDATA%\Godot\app_userdata\MiningSim\updater_skip.cfg`. If the user clicks "Skip", that exact version won't prompt again — but the next release after it will.

### Logs

The PowerShell helper writes to `%TEMP%\mineco_update_helper.log`. Useful when an update fails on your friend's machine.

## Things to tell your friend

- **First launch will trip Windows SmartScreen.** Click "More info" → "Run anyway". This is unavoidable without code-signing the binary.
- **Don't install in `C:\Program Files\`.** The updater runs as the user, so it can't write to `Program Files`. Anywhere under the user's home (`Documents`, `Desktop`, etc.) works.
- The first time an update is attempted, Windows may prompt about PowerShell — it's the helper script doing the file swap.

## Tradeoffs / known gaps

- **No code signing.** SmartScreen warning every time someone new downloads.
- **Whole-build replacement, not delta patches.** Each update is a full download.
- **Windows only.** No Mac/Linux helper.
- **The updater can't update itself reliably** — if a future build ships a broken `updater.gd`, your friend will need a manual reinstall to recover.
- **No automatic CI build.** You build and run `gh release create` locally for each version.
