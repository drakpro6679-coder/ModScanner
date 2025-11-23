Write-Host "=== FULL MOD + MEMORY STRING SCANNER ===" -ForegroundColor Cyan

# ======================================================
# 1) STRINGY PRO DETEKCI (TVÉ VLASTNÍ, ŽÁDNÉ MOJE)
# ======================================================
$detectStrings = @(
    "dev/oceanic/xenon",
    "xenon",
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


# ======================================================
# 2) AUTOMATICKÉ NALEZENÍ MODS FOLDERU
# ======================================================
$user = $env:USERNAME
$modsFolder = "C:\Users\$user\AppData\Roaming\.minecraft\mods"

if (-not (Test-Path $modsFolder)) {
    Write-Host "❌ Nenalezena složka s mody!" -ForegroundColor Red
    exit
}

Write-Host "[INFO] Mods folder: $modsFolder" -ForegroundColor Yellow


# ======================================================
# 3) FUNKCE — EXTRAKCE STRINGŮ Z BINARY (JAKO PROCESS HACKER)
# ======================================================
function Extract-Strings {
    param([byte[]]$bytes)

    $builder = New-Object System.Text.StringBuilder
    $list = New-Object System.Collections.Generic.List[string]

    foreach ($b in $bytes) {
        if ($b -ge 32 -and $b -le 126) {
            $null = $builder.Append([char]$b)
        } else {
            if ($builder.Length -ge 4) {
                $list.Add($builder.ToString())
            }
            $builder.Clear() | Out-Null
        }
    }

    if ($builder.Length -ge 4) {
        $list.Add($builder.ToString())
    }

    return $list
}


# ======================================================
# 4) SCAN JAR MODŮ
# ======================================================
Write-Host "`n=== SCAN MODS ===" -ForegroundColor Cyan

$modFiles = Get-ChildItem $modsFolder -Filter *.jar

foreach ($mod in $modFiles) {
    Write-Host "`n[SCAN] $($mod.Name)" -ForegroundColor Yellow

    try {
        $bytes = [System.IO.File]::ReadAllBytes($mod.FullName)
        $strings = Extract-Strings $bytes

        $found = @()

        foreach ($s in $detectStrings) {
            $hit = $strings | Where-Object { $_.ToLower().Contains($s.ToLower()) }
            if ($hit) {
                $found += $s
            }
        }

        if ($found.Count -gt 0) {
            Write-Host "⚠️  DETECTED in $($mod.Name):" -ForegroundColor Red
            $found | ForEach-Object { Write-Host "   → $_" -ForegroundColor Red }
        } else {
            Write-Host "✔ Clean" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "❌ Cannot read file" -ForegroundColor DarkRed
    }
}


# ======================================================
# 5) RUNTIME STRING SCAN (javaw.exe)
# ======================================================
Write-Host "`n=== RUNTIME MEMORY SCAN (javaw.exe) ===" -ForegroundColor Cyan

$proc = Get-Process javaw -ErrorAction SilentlyContinue

if (-not $proc) {
    Write-Host "❌ Minecraft není spuštěný!" -ForegroundColor Red
    exit
}

Write-Host "[INFO] Minecraft PID: $($proc.Id)" -ForegroundColor Yellow

foreach ($m in $proc.Modules) {
    try {
        $bytes = [System.IO.File]::ReadAllBytes($m.FileName)
        $strings = Extract-Strings $bytes

        foreach ($s in $detectStrings) {
            if ($strings -match $s) {
                Write-Host "🔥 DETECTED IN MEMORY → $s" -ForegroundColor Red
                Write-Host "   Module: $($m.FileName)`n" -ForegroundColor DarkRed
            }
        }
    }
    catch {}
}

Write-Host "`n=== SCAN COMPLETE ===" -ForegroundColor Cyan
