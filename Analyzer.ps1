Write-Host "🔍 Hledám běžící minecraft (javaw.exe)..."

$proc = Get-Process -Name "javaw" -ErrorAction SilentlyContinue
if (-not $proc) {
    Write-Host "❌ javaw.exe neběží."
    exit
}

$pid = $proc.Id
Write-Host "✔ Nalezen proces javaw.exe | PID: $pid"

Write-Host "`n🔍 Čtu načtené moduly a paměťové mapy povolené operačním systémem..."

# Získání čitelných sekcí paměti (bez kernel injection)
$regions = $proc.Modules | ForEach-Object {
    try {
        $_.FileName
    } catch {}
}

Write-Host "📦 Načtené soubory:"
$regions | ForEach-Object { Write-Host " - $_" }

Write-Host "`n🧪 Kontroluju Xenon Client signature..."

$XenonStrings = @(
    "dev/oceanic/xenon",    # hlavní identifikátor Xenonu
    "xenon",                # fallback
    "oceanic.xenon"         # další fallback
)

$found = $false

foreach ($module in $regions) {
    foreach ($sig in $XenonStrings) {
        if ($module -match $sig) {
            Write-Host "🚨 XENON CLIENT DETEKOVÁN → $sig" -ForegroundColor Red
            $found = $true
        }
    }
}

if (-not $found) {
    Write-Host "✔ Xenon Client nebyl nalezen v načtených modulech." -ForegroundColor Green
}
