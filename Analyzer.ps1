Clear-Host
Write-Host "=== Xenon Runtime Memory Scanner ===" -ForegroundColor Cyan

# Stringy které hledáme (TVÉ XENON PATTERNY)
$patterns = @(
    "dev/oceanic/xenon",
    "oceanic/xenon",
    "xenon",
    "oceanic",
    "module/setting",
    "ModuleManager",
    "Lambda"
)

# Najdeme Minecraft proces
$mc = Get-Process javaw -ErrorAction SilentlyContinue
if (-not $mc) {
    Write-Host "Minecraft (javaw) není spuštěný!" -ForegroundColor Red
    exit
}

Write-Host "Found Minecraft PID: $($mc.Id)" -ForegroundColor Yellow

# Získáme moduly načtené do paměti
Write-Host "`n[INFO] Scanning process memory modules..." -ForegroundColor Cyan
$modules = $mc.Modules

# Připravíme kolekci pro nalezené stringy
$matches = @()

foreach ($m in $modules) {
    try {
        $path = $m.FileName

        # Otevřeme modul jako textový blok (částečně čitelné stringy)
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $text = [System.Text.Encoding]::ASCII.GetString($bytes)

        foreach ($p in $patterns) {
            if ($text.ToLower().Contains($p.ToLower())) {
                $matches += [PSCustomObject]@{
                    Pattern = $p
                    Module  = $path
                }
            }
        }
    } catch {
        # některé moduly nejdou číst → ignorujeme
    }
}

Write-Host "`n=== Scan Results ===" -ForegroundColor Green

if ($matches.Count -eq 0) {
    Write-Host "No Xenon indicators found in memory." -ForegroundColor Gray
} else {
    Write-Host "`n!!! XENON CLIENT DETECTED IN MEMORY !!!" -ForegroundColor Red
    $matches | Format-Table -AutoSize
}

Write-Host "`nScan complete."
