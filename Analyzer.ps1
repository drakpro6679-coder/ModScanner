Write-Host "=== Automatic Mod + javaw.exe String Scanner ===" -ForegroundColor Cyan

# ====== CONFIG ======
$modFolder = "$env:APPDATA\.minecraft\mods"
$searchStrings = @(
    "xenon",
    "dev/oceanic/xenon",
    "oceanic",
    "kauri",
    "novoline",
    "sigma",
    "clickgui",
    "aimassist",
    "reach",
    "uuidspoof",
    "velocity_bypass"
)

# ====== FUNCTION: Extract strings from JAR bytes ======
function Get-StringsFromBytes {
    param([byte[]]$bytes)

    $sb = New-Object System.Text.StringBuilder
    $strings = @()

    foreach ($b in $bytes) {
        if ($b -ge 32 -and $b -le 126) {
            $null = $sb.Append([char]$b)
        } else {
            if ($sb.Length -ge 4) {
                $strings += $sb.ToString()
            }
            $sb.Clear() | Out-Null
        }
    }

    if ($sb.Length -ge 4) {
        $strings += $sb.ToString()
    }

    return $strings
}

# ====== SCAN MODS ======
Write-Host "`n[INFO] Scanning mods folder: $modFolder`n"

$modFiles = Get-ChildItem -Path $modFolder -Filter "*.jar" -ErrorAction SilentlyContinue

if ($modFiles.Count -eq 0) {
    Write-Host "[WARN] No JAR files found." -ForegroundColor Yellow
} else {
    foreach ($mod in $modFiles) {
        Write-Host "`n--- Scanning: $($mod.Name) ---" -ForegroundColor Cyan

        try {
            $bytes = [System.IO.File]::ReadAllBytes($mod.FullName)
            $allStrings = Get-StringsFromBytes $bytes

            foreach ($pattern in $searchStrings) {
                $found = $allStrings | Where-Object { $_ -match $pattern }
                if ($found) {
                    Write-Host "[FOUND] '$pattern' in $($mod.Name)" -ForegroundColor Green
                }
            }
        }
        catch {
            Write-Host "[ERROR] Could not read file: $($mod.Name)" -ForegroundColor Red
        }
    }
}

# ====== SCAN javaw.exe (Process Hacker style) ======
Write-Host "`n[INFO] Searching for javaw.exe process..." -ForegroundColor Cyan

$java = Get-Process javaw -ErrorAction SilentlyContinue

if ($java) {
    Write-Host "[INFO] javaw.exe PID: $($java.Id)`n"

    try {
        $handle = $java.Handle
        $memDump = ""
        $reader = New-Object System.IO.StreamReader($java.MainModule.FileName)
        $bytes = [System.IO.File]::ReadAllBytes($java.MainModule.FileName)
        $allStrings = Get-StringsFromBytes $bytes

        Write-Host "=== Checking javaw.exe strings ==="

        foreach ($pattern in $searchStrings) {
            $found = $allStrings | Where-Object { $_ -match $pattern }
            if ($found) {
                Write-Host "[FOUND] '$pattern' in javaw.exe" -ForegroundColor Green
            }
        }
    }
    catch {
        Write-Host "[ERROR] Cannot scan javaw.exe memory." -ForegroundColor Red
    }
}
else {
    Write-Host "[INFO] javaw.exe not running."
}

Write-Host "`n=== DONE ==="
