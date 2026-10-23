# Elden Ring Seamless Co-op auto-updater

Keeps the [Seamless Co-op mod](https://github.com/LukeYui/EldenRingSeamlessCoopRelease) up to date.

- Checks the latest release on GitHub and compares it with `version.txt`.
- Downloads and extracts the release zip, then copies it over the game folder.
- `SeamlessCoop\ersc_settings.ini` is merged, not overwritten: your values are kept, new keys come from the release and removed keys are logged.
- Writes `seamlesscoop_updater.log` next to the script (cleared above 500 KB).

## Use

Put both files in the game folder (next to `eldenring.exe`) and run `Update SeamlessCoop.bat`.
If the execution policy blocks the script:

```
powershell -ExecutionPolicy Bypass -File seamlesscoop_updater.ps1
```
