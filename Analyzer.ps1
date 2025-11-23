# ============================
# Java .JAR Scanner for Cheats
# ============================

$process = Get-Process javaw -ErrorAction SilentlyContinue
if (!$process) {
    Write-Host "javaw.exe nebyl nalezen."
    exit
}

# 1) Definice cheat stringů
$ClientStrings = @{
    "Xenon"        = @("dev/oceanic/xenon", "/impl/dev/oceanic/xenon")
    "Skligga"      = @("net/skliggahack/module")
    "BleachHack"   = @("org/bleachhack/")
    "Lattia"       = @("com/lattia/mod/")
    "Wurst"        = @("net/wurstclient/util")
    "Gardenia"     = @("kambing/gardenia")
    "Scrim"        = @("dev/nixoly/scrim")
    "Argon"        = @("dev/lvstrng/argon")
}

# 2) Najdeme všechny .JAR soubory, které Java načetla
Write-Host "Hledám .jar soubory načtené Java ClassLoaderem..."

$jarFiles = (Get-CimInstance Win32_Process -Filter "ProcessId = $($process.Id)").CommandLine `
    -split " " | Where-Object { $_ -like "*.jar" }

if ($jarFiles.Count -eq 0) {
    Write-Host "Nebyl nalezen žádný .jar soubor."
    exit
}

# 3) Procházíme .jar soubory a hledáme stringy
$results = @()

foreach ($jar in $jarFiles) {

    if (-not (Test-Path $jar)) {
        continue
    }

    Write-Host "Kontroluji JAR: $jar"

    $content = Get-Content $jar -Raw -ErrorAction SilentlyContinue

    foreach ($client in $ClientStrings.Keys) {
        foreach ($pattern in $ClientStrings[$client]) {

            if ($content -like "*$pattern*") {

                $results += [PSCustomObject]@{
                    Cheat  = $client
                    String = $pattern
                    Path   = $jar
                }
            }
        }
    }
}

# 4) Výpis
if ($results.Count -eq 0) {
    Write-Host "Nenalezeny žádné cheat stringy."
} else {
    $results | Format-Table -AutoSize
}
