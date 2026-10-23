# SeamlessCoop Auto-Updater
# Usage if execution policy blocks: powershell -ExecutionPolicy Bypass -File seamlesscoop_updater.ps1

$GameRoot         = $PSScriptRoot
$ApiUrl           = "https://api.github.com/repos/LukeYui/EldenRingSeamlessCoopRelease/releases/latest"
$VersionFile      = Join-Path $GameRoot "version.txt"
$LogFile          = Join-Path $GameRoot "seamlesscoop_updater.log"
$TempDir          = Join-Path ([System.IO.Path]::GetTempPath()) "ersc_update"
$ProtectedRelPath = "SeamlessCoop\ersc_settings.ini"

function Write-Log {
    param([string]$Level, [string]$Message)
    if ((Test-Path $LogFile) -and (Get-Item $LogFile).Length -gt 500KB) {
        Clear-Content $LogFile
    }
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $line
    Write-Host $line
}

function Merge-IniFile {
    param(
        [string]$NewPath,      # downloaded/template ini
        [string]$CurrentPath   # user's existing ini
    )

    # --- Parse current INI into a nested hashtable: [section][key] = value ---
    $currentValues = @{}
    $section = ""
    foreach ($line in (Get-Content $CurrentPath)) {
        if ($line -match '^\[(.+)\]') {
            $section = $matches[1]
            if (-not $currentValues.ContainsKey($section)) { $currentValues[$section] = @{} }
        } elseif ($line -match '^\s*([^;#\s][^=]*?)\s*=\s*(.*)$' -and $section) {
            $currentValues[$section][$matches[1].Trim()] = $matches[2].Trim()
        }
    }

    # --- Walk the new INI line-by-line, substituting values where user had them ---
    $section      = ""
    $output       = [System.Collections.Generic.List[string]]::new()
    $seenSections = [System.Collections.Generic.HashSet[string]]::new()
    $seenKeys     = @{}   # [section][key] = $true

    foreach ($line in (Get-Content $NewPath)) {
        if ($line -match '^\[(.+)\]') {
            $section = $matches[1]
            $output.Add($line)
            $seenSections.Add($section) | Out-Null
            if (-not $seenKeys.ContainsKey($section)) { $seenKeys[$section] = @{} }
            if (-not $currentValues.ContainsKey($section)) {
                Write-Log INFO "    [INI] New section: [$section]"
            }
        } elseif ($line -match '^(\s*([^;#\s][^=]*?)\s*)=\s*(.*)$') {
            $key        = $matches[2].Trim()
            $prefix     = $matches[1]   # preserves leading whitespace
            $newDefault = $matches[3].Trim()
            $seenKeys[$section][$key] = $true
            if ($section -and $currentValues.ContainsKey($section) -and $currentValues[$section].ContainsKey($key)) {
                $output.Add("$prefix= $($currentValues[$section][$key])")
            } else {
                $output.Add($line)   # keep new default as-is
                Write-Log INFO "    [INI] New key: [$section] $key = $newDefault"
            }
        } else {
            $output.Add($line)       # blank lines, comments - keep verbatim
        }
    }

    # --- Report removed keys and sections ---
    foreach ($sec in $currentValues.Keys) {
        if (-not $seenSections.Contains($sec)) {
            Write-Log INFO "    [INI] Removed section: [$sec]"
            continue
        }
        foreach ($key in $currentValues[$sec].Keys) {
            if (-not $seenKeys[$sec].ContainsKey($key)) {
                Write-Log INFO "    [INI] Removed key: [$sec] $key"
            }
        }
    }

    return $output
}

try {
    Write-Log INFO "--- Session start ---"

    # FR1: GitHub API
    $release   = Invoke-RestMethod -Uri $ApiUrl -UseBasicParsing
    $latestTag = $release.tag_name
    $zipUrl    = ($release.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1).browser_download_url
    if (-not $zipUrl) { throw "No .zip asset found in release '$latestTag'" }

    # FR2: Read version.txt
    $currentTag = if (Test-Path $VersionFile) { (Get-Content $VersionFile -Raw).Trim() } else { "none" }
    Write-Log INFO "Latest: $latestTag | Current: $currentTag"

    # FR3: Skip if up to date
    if ($latestTag -eq $currentTag) {
        Write-Log INFO "Already up to date: $latestTag"
        exit 0
    }

    Write-Log INFO "Update needed: $currentTag -> $latestTag"

    # FR4: Download
    $zipName = Split-Path $zipUrl -Leaf
    $zipPath = Join-Path $TempDir $zipName
    if (Test-Path $TempDir) { Remove-Item $TempDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $TempDir | Out-Null
    Write-Log INFO "Downloading $zipName..."
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing

    # FR5: Extract
    $extractDir = Join-Path $TempDir "extracted"
    Write-Log INFO "Extracting..."
    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

    # FR6: Copy files; merge protected ini instead of skipping
    Write-Log INFO "Copying files..."
    Get-ChildItem -Path $extractDir -Recurse -File | ForEach-Object {
        $relPath = $_.FullName.Substring($extractDir.Length).TrimStart('\', '/')
        if ($relPath -eq $ProtectedRelPath) {
            $dest    = Join-Path $GameRoot $relPath
            $destDir = Split-Path $dest -Parent
            if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Force -Path $destDir | Out-Null }
            if (Test-Path $dest) {
                Write-Log INFO "  Merging: $relPath (preserving user values)"
                $merged = Merge-IniFile -NewPath $_.FullName -CurrentPath $dest
                $merged | Set-Content -Path $dest -Encoding UTF8
            } else {
                Write-Log INFO "  Installing fresh: $relPath (no existing file)"
                Copy-Item -Path $_.FullName -Destination $dest -Force
            }
            return
        }
        $dest    = Join-Path $GameRoot $relPath
        $destDir = Split-Path $dest -Parent
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Force -Path $destDir | Out-Null }
        Copy-Item -Path $_.FullName -Destination $dest -Force
    }

    # FR7: Write version.txt
    Set-Content -Path $VersionFile -Value $latestTag -NoNewline

    Write-Log INFO "Update complete. version.txt updated to $latestTag"

} catch {
    Write-Log ERROR $_.Exception.Message
    exit 1
} finally {
    if (Test-Path $TempDir) { Remove-Item $TempDir -Recurse -Force }
}
