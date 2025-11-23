Clear-Host
Write-Host "Mod Analyzer" -ForegroundColor Yellow
Write-Host "Made by drakpro6679"
Write-Host

# automatická cesta k mods
$mods = "$env:USERPROFILE\AppData\Roaming\.minecraft\mods"
Write-Host "Using default mods folder: $mods" -ForegroundColor White
Write-Host

if (-not (Test-Path $mods -PathType Container)) {
    Write-Host "Invalid Path!" -ForegroundColor Red
    exit 1
}

# Minecraft uptime
$process = Get-Process javaw -ErrorAction SilentlyContinue
if (-not $process) {
    $process = Get-Process java -ErrorAction SilentlyContinue
}

if ($process) {
    try {
        $startTime = $process.StartTime
        $elapsedTime = (Get-Date) - $startTime
    } catch {}

    Write-Host "{ Minecraft Uptime }" -ForegroundColor DarkCyan
    Write-Host "$($process.Name) PID $($process.Id) started at $startTime and running for $($elapsedTime.Hours)h $($elapsedTime.Minutes)m $($elapsedTime.Seconds)s"
    Write-Host ""
}

# Funkce pro SHA1 hash
function Get-SHA1 {
    param ([string]$filePath)
    return (Get-FileHash -Path $filePath -Algorithm SHA1).Hash
}

# Funkce pro kontrolu Zone.Identifier
function Get-ZoneIdentifier {
    param ([string]$filePath)
    $ads = Get-Content -Raw -Stream Zone.Identifier $filePath -ErrorAction SilentlyContinue
    if ($ads -match "HostUrl=(.+)") { return $matches[1] }
    return $null
}

# Funkce pro Modrinth
function Fetch-Modrinth {
    param ([string]$hash)
    try {
        $response = Invoke-RestMethod -Uri "https://api.modrinth.com/v2/version_file/$hash" -Method Get -UseBasicParsing -ErrorAction Stop
        if ($response.project_id) {
            $projectData = Invoke-RestMethod -Uri "https://api.modrinth.com/v2/project/$($response.project_id)" -Method Get -UseBasicParsing -ErrorAction Stop
            return @{ Name = $projectData.title; Slug = $projectData.slug }
        }
    } catch {}
    return @{ Name = ""; Slug = "" }
}

# Funkce pro Megabase
function Fetch-Megabase {
    param ([string]$hash)
    try {
        $response = Invoke-RestMethod -Uri "https://megabase.vercel.app/api/query?hash=$hash" -Method Get -UseBasicParsing -ErrorAction Stop
        if (-not $response.error) { return $response.data }
    } catch {}
    return $null
}

# Cheat stringy
$cheatClients = @(
    @{ Name = "Xenon Client"; Strings = @("dev/oceanic/xenon") }
    # Přidej další klienty podle potřeby
)

function Check-Strings {
    param ([string]$filePath)
    $stringsFound = [System.Collections.Generic.List[string]]::new()
    $fileContent = Get-Content -Raw $filePath
    foreach ($client in $cheatClients) {
        foreach ($str in $client.Strings) {
            if ($fileContent -match [regex]::Escape($str)) {
                $stringsFound.Add("Client name: $($client.Name) / Path: $filePath / String: $str")
            }
        }
    }
    return $stringsFound
}

$verifiedMods = @()
$unknownMods = @()
$cheatMods = @()

$jarFiles = Get-ChildItem -Path $mods -Filter *.jar
$spinner = @("|", "/", "-", "\")
$totalMods = $jarFiles.Count
$counter = 0

foreach ($file in $jarFiles) {
    $counter++
    $spin = $spinner[$counter % $spinner.Length]
    Write-Host "`r[$spin] Scanning mods: $counter / $totalMods" -ForegroundColor Yellow -NoNewline

    $hash = Get-SHA1 -filePath $file.FullName
    $modDataModrinth = Fetch-Modrinth -hash $hash
    if ($modDataModrinth.Slug) {
        $verifiedMods += [PSCustomObject]@{ ModName = $modDataModrinth.Name; FileName = $file.Name }
        continue
    }

    $modDataMegabase = Fetch-Megabase -hash $hash
    if ($modDataMegabase.name) {
        $verifiedMods += [PSCustomObject]@{ ModName = $modDataMegabase.Name; FileName = $file.Name }
        continue
    }

    $zoneId = Get-ZoneIdentifier $file.FullName
    $unknownMods += [PSCustomObject]@{ FileName = $file.Name; FilePath = $file.FullName; ZoneId = $zoneId }

    $modStrings = Check-Strings $file.FullName
    if ($modStrings.Count -gt 0) {
        $cheatMods += [PSCustomObject]@{ FileName = $file.Name; StringsFound = $modStrings }
        $unknownMods = @($unknownMods | Where-Object { $_.FileName -ne $file.Name })
    }
}

Write-Host "`r$(' ' * 80)`r" -NoNewline

if ($verifiedMods.Count -gt 0) {
    Write-Host "{ Verified Mods }" -ForegroundColor DarkCyan
    foreach ($mod in $verifiedMods) {
        Write-Host ("> {0, -30}" -f $mod.ModName) -ForegroundColor Green -NoNewline
        Write-Host "$($mod.FileName)" -ForegroundColor Gray
    }
    Write-Host
}

if ($unknownMods.Count -gt 0) {
    Write-Host "{ Unknown Mods }" -ForegroundColor DarkCyan
    foreach ($mod in $unknownMods) {
        if ($mod.ZoneId) {
            Write-Host ("> {0, -30}" -f $mod.FileName) -ForegroundColor DarkYellow -NoNewline
            Write-Host "$($mod.ZoneId)" -ForegroundColor DarkGray
            continue
        }
        Write-Host "> $($mod.FileName)" -ForegroundColor DarkYellow
    }
    Write-Host
}

if ($cheatMods.Count -gt 0) {
    Write-Host "{ Cheat Mods }" -ForegroundColor DarkCyan
    foreach ($mod in $cheatMods) {
        foreach ($str in $mod.StringsFound) {
            Write-Host "> $($mod.FileName)" -ForegroundColor Red
            Write-Host " [$str]" -ForegroundColor DarkMagenta
        }
    }
    Write-Host
}
