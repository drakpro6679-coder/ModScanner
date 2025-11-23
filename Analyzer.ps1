Clear-Host
Write-Host "Mod Analyzer" -ForegroundColor Yellow
Write-Host "Made by drakpro6679" -ForegroundColor DarkGray
Write-Host

# Prompt for mods folder
Write-Host "Enter path to the mods folder: " -NoNewline
Write-Host "(press Enter to use default)" -ForegroundColor DarkGray
$mods = Read-Host "PATH"
Write-Host

if (-not $mods) {
    $mods = "$env:USERPROFILE\AppData\Roaming\.minecraft\mods"
    Write-Host "Using default mods folder: $mods" -ForegroundColor White
    Write-Host
}

if (-not (Test-Path $mods -PathType Container)) {
    Write-Host "Invalid Path!" -ForegroundColor Red
    exit 1
}

# Minecraft uptime
$process = Get-Process javaw -ErrorAction SilentlyContinue
if (-not $process) { $process = Get-Process java -ErrorAction SilentlyContinue }

if ($process) {
    try {
        $startTime = $process.StartTime
        $elapsedTime = (Get-Date) - $startTime
    } catch {}

    Write-Host "{ Minecraft Uptime }" -ForegroundColor DarkCyan
    Write-Host "$($process.Name) PID $($process.Id) started at $startTime and running for $($elapsedTime.Hours)h $($elapsedTime.Minutes)m $($elapsedTime.Seconds)s"
    Write-Host ""
}

# Hash function
function Get-SHA1 {
    param ([string]$filePath)
    return (Get-FileHash -Path $filePath -Algorithm SHA1).Hash
}

# Zone identifier (for downloaded files)
function Get-ZoneIdentifier {
    param ([string]$filePath)
    $ads = Get-Content -Raw -Stream Zone.Identifier $filePath -ErrorAction SilentlyContinue
    if ($ads -match "HostUrl=(.+)") { return $matches[1] }
    return $null
}

# Fetch info from Modrinth
function Fetch-Modrinth {
    param ([string]$hash)
    try {
        $response = Invoke-RestMethod -Uri "https://api.modrinth.com/v2/version_file/$hash" -Method Get -UseBasicParsing -ErrorAction Stop
        if ($response.project_id) {
            $projectResponse = "https://api.modrinth.com/v2/project/$($response.project_id)"
            $projectData = Invoke-RestMethod -Uri $projectResponse -Method Get -UseBasicParsing -ErrorAction Stop
            return @{ Name = $projectData.title; Slug = $projectData.slug }
        }
    } catch {}
    return @{ Name = ""; Slug = "" }
}

# Fetch info from Megabase
function Fetch-Megabase {
    param ([string]$hash)
    try {
        $response = Invoke-RestMethod -Uri "https://megabase.vercel.app/api/query?hash=$hash" -Method Get -UseBasicParsing -ErrorAction Stop
        if (-not $response.error) { return $response.data }
    } catch {}
    return $null
}

# Cheat strings
$cheatStrings = @(
    @{ Name = "Skligga"; Strings = @("net/skliggahack/module", "restore pre 1.18.2 loading screen behavior") },
    @{ Name = "BleachHack"; Strings = @("org/bleachhack/", "Makes you not swing your hand") },
    @{ Name = "Ghost Bleach"; Strings = @("bleachhack_outline") },
    @{ Name = "Lattia"; Strings = @(".lattia","com/lattia/mod/") },
    @{ Name = "Wurst"; Strings = @("net/wurstclient/util") },
    @{ Name = "Wingclient"; Strings = @("SelfDestruct.java","Triggerbot.java","gradient_frame") },
    @{ Name = "Lumina"; Strings = @("me/stormcph/lumina") },
    @{ Name = "NoWeakAttack"; Strings = @("assets/noweakattack/") },
    @{ Name = "Coffe Client"; Strings = @("coffee/client/helper") },
    @{ Name = "Prestige"; Strings = @("dev/zprestige/prestige","MixinLightmapTextureManager.class") },
    @{ Name = "Surge Client"; Strings = @("032E02B4-0499-05D6-5A06-510700080009","gradient_frame") },
    @{ Name = "Xyla"; Strings = @("impl/xy_la","impl/xyla") },
    @{ Name = "St-Api"; Strings = @("st/mixin/KeyboardMixin") },
    @{ Name = "Meteor Client"; Strings = @("meteordevelopment/orbit/") },
    @{ Name = "ThunderHack"; Strings = @("thunder/hack") },
    @{ Name = "NewLauncher"; Strings = @("newlauncher") },
    @{ Name = "Catlean"; Strings = @("Catlean") },
    @{ Name = "Cracked Grim"; Strings = @("ops/ec/kekma","abc/def/event/impl") },
    @{ Name = "Doomsday Client"; Strings = @("l.pngUT") },
    @{ Name = "Pojav Client"; Strings = @("ie/skobelevs/gui/screen/") },
    @{ Name = "Polar Client"; Strings = @("modelfix/addons/addon/render") },
    @{ Name = "Krypton Client"; Strings = @("a/b/c/z") },
    @{ Name = "Gardenia Client"; Strings = @("kambing/gardenia") },
    @{ Name = "Shoreline"; Strings = @("shoreline/client") },
    @{ Name = "Minced"; Strings = @("free/minced") },
    @{ Name = "Scrim Client"; Strings = @("dev/nixoly/scrim") },
    @{ Name = "Argon Client"; Strings = @("dev/lvstrng/argon") },
    @{ Name = "Owo Client"; Strings = @("OwoConfig","OwoMenu","Triggerbot") },
    @{ Name = "Xenon Client"; Strings = @("dev/oceanic/xenon") },
    @{ Name = "Kaira Client"; Strings = @("examplemod") }
)

# Check cheat strings in file
function Check-Strings {
    param ([string]$filePath)
    $found = @()
    $content = Get-Content -Raw $filePath
    foreach ($client in $cheatStrings) {
        foreach ($str in $client.Strings) {
            if ($content -match [regex]::Escape($str)) {
                $found += @{ Client = $client.Name; Path = $filePath; String = $str }
            }
        }
    }
    return $found
}

$verifiedMods = @()
$unknownMods = @()
$cheatMods = @()

$jarFiles = Get-ChildItem -Path $mods -Filter *.jar
$spinner = @("|","/","-","\")
$totalMods = $jarFiles.Count
$counter = 0

$tempDir = Join-Path $env:TEMP "modanalyzer"

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
}

# Scan unknown mods for cheat strings
foreach ($mod in $unknownMods) {
    $modStrings = Check-Strings $mod.FilePath
    if ($modStrings.Count -gt 0) {
        foreach ($f in $modStrings) {
            Write-Host "Client name: $($f.Client)  | Path: $($f.Path)  | String: $($f.String)" -ForegroundColor Red
        }
        $cheatMods += $mod
        $unknownMods = $unknownMods | Where-Object { $_ -ne $mod }
    }
}

# Display results
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
    foreach ($mod in $cheatMods) { Write-Host "> $($mod.FileName)" -ForegroundColor Red }
    Write-Host
}
