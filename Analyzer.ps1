### Mod Analyzer - full scanner (binary .class detection + full output)
Clear-Host
Write-Host "Mod Analyzer" -ForegroundColor Yellow
Write-Host "Made by " -ForegroundColor DarkGray -NoNewline
Write-Host "drakpro6679"
Write-Host

# ----- CONFIG -----
# Default mods folder (used if user nechce zadat jinou)
$defaultMods = "$env:USERPROFILE\AppData\Roaming\.minecraft\mods"

# Temp use in-memory; použití krátké lokální složky jen pro případ - ale většina práce probíhá v paměti
$tempDir = "C:\Temp\modanalyzer"

# Spinner
$spinner = @("|","/","-","\")

# ----- Ask for mods folder (still optional) -----
Write-Host "Enter path to the mods folder: " -NoNewline
Write-Host "(press Enter to use default)" -ForegroundColor DarkGray
$mods = Read-Host "PATH"
Write-Host

if (-not $mods) {
    $mods = $defaultMods
    Write-Host "Using default mods folder: $mods" -ForegroundColor White
    Write-Host
}

if (-not (Test-Path $mods -PathType Container)) {
    Write-Host "Invalid Path!" -ForegroundColor Red
    exit 1
}

# ----- Minecraft uptime -----
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

# ----- Utility functions -----
function Get-SHA1 {
    param([string]$filePath)
    try {
        return (Get-FileHash -Path $filePath -Algorithm SHA1).Hash
    } catch {
        return ""
    }
}

function Get-ZoneIdentifier {
    param([string]$filePath)
    try {
        $ads = Get-Content -Raw -Stream Zone.Identifier $filePath -ErrorAction SilentlyContinue
        if ($ads -match "HostUrl=(.+)") { return $matches[1] }
    } catch {}
    return $null
}

function Fetch-Modrinth {
    param([string]$hash)
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

function Fetch-Megabase {
    param([string]$hash)
    try {
        $response = Invoke-RestMethod -Uri "https://megabase.vercel.app/api/query?hash=$hash" -Method Get -UseBasicParsing -ErrorAction Stop
        if (-not $response.error) { return $response.data }
    } catch {}
    return $null
}

# Byte-array contains (search for subarray)
function ByteArray-Contains {
    param (
        [byte[]]$haystack,
        [byte[]]$needle
    )
    if ($null -eq $haystack -or $null -eq $needle) { return $false }
    if ($needle.Length -eq 0) { return $true }
    if ($needle.Length -gt $haystack.Length) { return $false }

    # KMP would be faster, ale jednoduché O(n*m) je dost dobré pro naše soubory
    for ($i = 0; $i -le $haystack.Length - $needle.Length; $i++) {
        $match = $true
        for ($j = 0; $j -lt $needle.Length; $j++) {
            if ($haystack[$i + $j] -ne $needle[$j]) { $match = $false; break }
        }
        if ($match) { return $true }
    }
    return $false
}

# Convert pattern string to bytes for binary search
function PatternToBytes {
    param([string]$pattern)
    # UTF8 bytes
    return [System.Text.Encoding]::UTF8.GetBytes($pattern)
}

# ----- Define clients and their patterns (add more clients here) -----
# Přidej sem další klienty podle potřeby (Name + Strings)
$cheatClients = @(
    @{ Name = "Xenon Client"; Strings = @("dev/oceanic/xenon", "dev/oceanic/xenon/module/setting/Setting") },
    @{ Name = "Skligga"; Strings = @("net/skliggahack/module","restore pre 1.18.2 loading screen behavior") },
    @{ Name = "BleachHack"; Strings = @("org/bleachhack/","Makes you not swing your hand") },
    @{ Name = "Wingclient"; Strings = @("SelfDestruct.java","Triggerbot.java","Error retrieving HWID via PowerShell:") },
    @{ Name = "Owo Client"; Strings = @("OwoConfig","OwoMenu","Triggerbot") }
    # ... sem přidej zbytek tvých ~50 klientů
)

# Precompute byte patterns for speed
foreach ($c in $cheatClients) {
    $c.PatternBytes = @()
    foreach ($s in $c.Strings) {
        $c.PatternBytes += ,(PatternToBytes $s)
    }
}

# ----- Scan functions -----
# Scan a Stream (file bytes) for patterns; returns list of matches as PSCustomObjects
function Scan-Bytes-For-Clients {
    param(
        [byte[]]$bytes,
        [string]$sourcePath
    )
    $found = @()
    foreach ($client in $cheatClients) {
        foreach ($pb in $client.PatternBytes) {
            if (ByteArray-Contains -haystack $bytes -needle $pb) {
                $found += [PSCustomObject]@{
                    Client = $client.Name
                    Path   = $sourcePath
                    String = [System.Text.Encoding]::UTF8.GetString($pb)
                }
                # pokud chceš aby se pro tento client našly i další patterns, nevyhazuj break
                break
            }
        }
    }
    return $found
}

# Scan a ZIP stream for class files and nested jars (recursive)
function Scan-ZipStream {
    param(
        [System.IO.Stream]$stream,
        [string]$archivePath
    )
    $matches = @()

    try {
        $zip = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Read, $false)
    } catch {
        return $matches
    }

    foreach ($entry in $zip.Entries) {
        # entry.FullName obsahuje cestu v archivu
        try {
            if ($entry.Length -eq 0) { continue } # skip directories / empty

            # Pokud je to .class nebo obsahuje xenon-like cesty, čteme bytes
            $lowerName = $entry.FullName.ToLowerInvariant()

            if ($lowerName -like "*.class" -or $lowerName -match "dev/oceanic/xenon" -or $lowerName -match "xenon") {
                try {
                    $ms = New-Object System.IO.MemoryStream
                    $rs = $entry.Open()
                    $rs.CopyTo($ms)
                    $rs.Close()
                    $bytes = $ms.ToArray()
                    $ms.Dispose()

                    $source = "$archivePath`::$($entry.FullName)"
                    $m = Scan-Bytes-For-Clients -bytes $bytes -sourcePath $source
                    if ($m.Count -gt 0) { $matches += $m }

                } catch {}
            }

            # Pokud je to vnořený jar, zkusíme ho otevřít rekurzivně z paměti
            if ($lowerName -like "*.jar" -or $lowerName -like "*.zip") {
                try {
                    $mem = New-Object System.IO.MemoryStream
                    $rs2 = $entry.Open()
                    $rs2.CopyTo($mem)
                    $rs2.Close()
                    $mem.Position = 0
                    $nested = Scan-ZipStream -stream $mem -archivePath ("$archivePath`::$($entry.FullName)")
                    if ($nested.Count -gt 0) { $matches += $nested }
                    $mem.Dispose()
                } catch {}
            }
        } catch {}
    }

    $zip.Dispose()
    return $matches
}

# ----- Main scanning loop -----
$verifiedMods = @()
$unknownMods = @()
$cheatMods = @()

$jarFiles = Get-ChildItem -Path $mods -Filter *.jar -File -ErrorAction SilentlyContinue
$totalMods = $jarFiles.Count
$counter = 0

if ($totalMods -eq 0) {
    Write-Host "No .jar files found in $mods" -ForegroundColor Yellow
    exit 0
}

foreach ($file in $jarFiles) {
    $counter++
    $spin = $spinner[$counter % $spinner.Length]
    Write-Host "`r[$spin] Scanning mods: $counter / $totalMods" -ForegroundColor Yellow -NoNewline

    # compute hash and try modrinth/megabase
    $hash = Get-SHA1 -filePath $file.FullName
    $modDataModrinth = Fetch-Modrinth -hash $hash
    if ($modDataModrinth.Slug) {
        $verifiedMods += [PSCustomObject]@{ ModName = $modDataModrinth.Name; FileName = $file.Name }
        continue
    }
    $modDataMegabase = Fetch-Megabase -hash $hash
    if ($modDataMegabase -and $modDataMegabase.name) {
        $verifiedMods += [PSCustomObject]@{ ModName = $modDataMegabase.Name; FileName = $file.Name }
        continue
    }

    # zone id info
    $zoneId = Get-ZoneIdentifier -filePath $file.FullName
    $unknownMods += [PSCustomObject]@{ FileName = $file.Name; FilePath = $file.FullName; ZoneId = $zoneId }
}

# Now scan unknown mods in-memory for client strings
foreach ($mod in $unknownMods) {
    Write-Host "`rScanning unknown: $($mod.FileName) " -ForegroundColor DarkYellow -NoNewline
    try {
        $fs = [System.IO.File]::OpenRead($mod.FilePath)
        $ms = New-Object System.IO.MemoryStream
        $fs.CopyTo($ms)
        $fs.Close()
        $ms.Position = 0

        $found = Scan-ZipStream -stream $ms -archivePath $mod.FilePath
        $ms.Dispose()

        if ($found.Count -gt 0) {
            foreach ($f in $found) {
                # Výpis detailně: Client name / Path / String
                Write-Host ""
                Write-Host "Client name : $($f.Client)" -ForegroundColor Red -NoNewline
                Write-Host "  | Path: $($f.Path)" -ForegroundColor DarkGray
                Write-Host "String: $($f.String)" -ForegroundColor Magenta
                Write-Host ""
            }
            $cheatMods += [PSCustomObject]@{ FileName = $mod.FileName; FilePath = $mod.FilePath; Matches = $found }
            # remove from unknown list
            $unknownMods = $unknownMods | Where-Object { $_.FileName -ne $mod.FileName }
        }
    } catch {
        Write-Host "`nWarning: Could not read $($mod.FileName) - $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Final output formatting
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
        Write-Host "> $($mod.FileName)" -ForegroundColor Red
        foreach ($m in $mod.Matches) {
            Write-Host "  -> $($m.Client) | $($m.Path) | $($m.String)" -ForegroundColor DarkMagenta
        }
    }
    Write-Host
} else {
    Write-Host "No cheat mods detected." -ForegroundColor Green
}
