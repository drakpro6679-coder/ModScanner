Write-Host "=== Xenon Memory Scanner ===" -ForegroundColor Cyan

# Najdi Minecraft proces
$proc = Get-Process javaw -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $proc) {
    Write-Host "Minecraft (javaw.exe) not running." -ForegroundColor Yellow
    exit
}

Write-Host "Found Minecraft PID: $($proc.Id)" -ForegroundColor Green

# Temp dump
$dumpFile = "$env:TEMP\mc_memdump.dmp"

# Získání ProcessDump.exe od Microsoftu
$pd = "$env:TEMP\procdump.exe"
if (-not (Test-Path $pd)) {
    Write-Host "Downloading procdump..." -ForegroundColor Yellow
    Invoke-WebRequest "https://download.sysinternals.com/files/Procdump.zip" -OutFile "$env:TEMP\procdump.zip"
    Expand-Archive "$env:TEMP\procdump.zip" -DestinationPath $env:TEMP -Force
}

# Vytvoření dumpu
Write-Host "Creating memory dump..." -ForegroundColor Yellow
Start-Process -FilePath $pd -ArgumentList "-ma $($proc.Id) $dumpFile" -Wait

# Čtení dumpu přes "strings"
Write-Host "Extracting text strings from memory dump..." -ForegroundColor Yellow
$strings = & "$env:windir\System32\findstr.exe" /R /N "." $dumpFile 2>$null

if (-not $strings) {
    Write-Host "Failed to read strings from dump." -ForegroundColor Red
    exit
}

# Hledané patterny pro Xenon
$patterns = @(
    "dev/oceanic/xenon"
)

Write-Host "`nSearching for Xenon..." -ForegroundColor Cyan

$found = $false

foreach ($p in $patterns) {
    if ($strings -match $p) {
        Write-Host "🔥 XENON DETECTED → $p" -ForegroundColor Red
        $found = $true
    }
}

if (-not $found) {
    Write-Host "No Xenon signatures found." -ForegroundColor Green
}

Write-Host "`nDone."
