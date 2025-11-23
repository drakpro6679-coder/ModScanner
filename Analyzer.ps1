Clear-Host
Write-Host "Mod Analyzer" -ForegroundColor Yellow
Write-Host "Made by drakpro6679" -ForegroundColor DarkGray
Write-Host

# Enter mods folder
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

# Hash a string checking
function Get-SHA1 { param([string]$filePath) return (Get-FileHash -Path $filePath -Algorithm SHA1).Hash }

$clientStrings = @(
    @{ Name = "Xenon Client"; Strings = @("dev/oceanic/xenon") }
)

function Check-Strings {
    param ([string]$filePath)
    $found = @()
    $content = Get-Content -Raw $filePath
    foreach ($client in $clientStrings) {
        foreach ($s in $client.Strings) {
            if ($content -match [regex]::Escape($s)) {
                $found += [PSCustomObject]@{
                    Client = $client.Name
                    Path = $filePath
                    String = $s
                }
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

foreach ($file in $jarFiles) {
    $counter++
    $spin = $spinner[$counter % $spinner.Length]
    Write-Host "`r[$spin] Scanning mods: $counter / $totalMods" -ForegroundColor Yellow -NoNewline

    $hash = Get-SHA1 $file.FullName

    # Here you could fetch Modrinth/Megabase if needed (skipped for simplicity)
    $unknownMods += [PSCustomObject]@{ FileName = $file.Name; FilePath = $file.FullName }
}

# Temp extraction and string check
$tempDir = Join-Path $env:TEMP "modanalyzer"

if (Test-Path $tempDir) { Remove-Item -Recurse -Force $tempDir }
New-Item -ItemType Directory -Path $tempDir | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem

foreach ($mod in $unknownMods) {
    $modStrings = Check-Strings $mod.FilePath
    if ($modStrings.Count -gt 0) {
        foreach ($fs in $modStrings) {
            Write-Host "Client name: $($fs.Client) | Path: $($fs.Path) | String: $($fs.String)" -ForegroundColor Magenta
        }
        $cheatMods += $mod
        continue
    }

    # Extract and check inside jar
    $extractPath = Join-Path $tempDir ([System.IO.Path]::GetFileNameWithoutExtension($mod.FileName))
    New-Item -ItemType Directory -Path $extractPath | Out-Null
    [System.IO.Compression.ZipFile]::ExtractToDirectory($mod.FilePath, $extractPath)

    $innerJars = Get-ChildItem -Path $extractPath -Recurse -Filter *.class
    foreach ($inner in $innerJars) {
        $innerStrings = Check-Strings $inner.FullName
        foreach ($fs in $innerStrings) {
            Write-Host "Client name: $($fs.Client) | Path: $($fs.Path) | String: $($fs.String)" -ForegroundColor Magenta
        }
    }
}

# Cleanup
Remove-Item -Recurse -Force $tempDir

Write-Host "`r$(' ' * 80)`r" -NoNewline

# Verified Mods output
if ($verifiedMods.Count -gt 0) {
    Write-Host "{ Verified Mods }" -ForegroundColor DarkCyan
    foreach ($mod in $verifiedMods) {
        Write-Host ("> {0, -30}" -f $mod.ModName) -ForegroundColor Green -NoNewline
        Write-Host "$($mod.FileName)" -ForegroundColor Gray
    }
    Write-Host
}

# Cheat Mods output
if ($cheatMods.Count -gt 0) {
    Write-Host "{ Cheat Mods }" -ForegroundColor DarkCyan
    foreach ($mod in $cheatMods) {
        Write-Host "> $($mod.FileName)" -ForegroundColor Red
    }
}
