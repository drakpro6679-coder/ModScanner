<#
  Mod Analyzer - full scanner (file scan + in-memory zip scan + runtime memory scan)
  Made by drakpro6679
  - Scans .jar files in %APPDATA%\.minecraft\mods by default (or path you input)
  - Detects many clients by binary patterns inside .class files (no long-path extraction)
  - Additionally scans java/javaw process memory for provided patterns (resistant to self-destruct)
#>

Clear-Host
Write-Host "Mod Analyzer" -ForegroundColor Yellow
Write-Host "Made by " -ForegroundColor DarkGray -NoNewline
Write-Host "drakpro6679"
Write-Host

# ---------------- CONFIG ----------------
$defaultMods = "$env:USERPROFILE\AppData\Roaming\.minecraft\mods"
$tempDir = "C:\Temp\modanalyzer"   # jen pro případ, většina práce je in-memory
$spinner = @("|","/","-","\")
# ----------------------------------------

# --------- Ask for mods folder (optional) ----------
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
# ---------------------------------------------------

# ---------------- Minecraft uptime ----------------
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
# ---------------------------------------------------

# ---------------- Utility functions ----------------
function Get-SHA1 { param([string]$filePath) try { return (Get-FileHash -Path $filePath -Algorithm SHA1).Hash } catch { return "" } }

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
        if ($response -and -not $response.error) { return $response.data }
    } catch {}
    return $null
}
# ----------------------------------------------------

# ---------------- Byte search helpers ----------------
function ByteArray-Contains {
    param (
        [byte[]]$haystack,
        [byte[]]$needle
    )
    if ($null -eq $haystack -or $null -eq $needle) { return $false }
    if ($needle.Length -eq 0) { return $true }
    if ($needle.Length -gt $haystack.Length) { return $false }

    for ($i = 0; $i -le $haystack.Length - $needle.Length; $i++) {
        $ok = $true
        for ($j = 0; $j -lt $needle.Length; $j++) {
            if ($haystack[$i + $j] -ne $needle[$j]) { $ok = $false; break }
        }
        if ($ok) { return $true }
    }
    return $false
}

function PatternToBytes {
    param([string]$pattern)
    return [System.Text.Encoding]::UTF8.GetBytes($pattern)
}
# ----------------------------------------------------

# ------------- Define clients & patterns -------------
# Přidej/změň patterny tady — používají se jak při file-skanu, tak při memory-skanu.
$cheatClients = @(
    @{ Name = "Skligga"; Strings = @('net/skliggahack/module','restore pre 1.18.2 loading screen behavior') },
    @{ Name = "BleachHack"; Strings = @('org/bleachhack/','Makes you not swing your hand','UI not available on the main menu!') },
    @{ Name = "Ghost Bleach"; Strings = @('bleachhack_outline','UI not available on the main menu!') },
    @{ Name = "Lattia"; Strings = @('.lattia','com/lattia/mod/','chickenpanckakesinwaffle') },
    @{ Name = "Wurst"; Strings = @('net/wurstclient/util') },
    @{ Name = "Wingclient"; Strings = @('SelfDestruct.java','Triggerbot.java','gradient_frame','security.txt','Error retrieving HWID via PowerShell:') },
    @{ Name = "Lumina"; Strings = @('me/stormcph/lumina') },
    @{ Name = "NoWeakAttack"; Strings = @('assets/noweakattack/') },
    @{ Name = "Coffe Client"; Strings = @('coffee/client/helper') },
    @{ Name = "Prestige"; Strings = @('dev/zprestige/prestige','MixinLightmapTextureManager.class') },
    @{ Name = "Surge Client"; Strings = @('032E02B4-0499-05D6-5A06-510700080009','gradient_frame') },
    @{ Name = "Xyla"; Strings = @('impl/xy_la','impl/xyla') },
    @{ Name = "St-Api"; Strings = @('st/mixin/KeyboardMixin') },
    @{ Name = "Meteor Client"; Strings = @('meteordevelopment/orbit/') },
    @{ Name = "ThunderHack"; Strings = @('thunder/hack') },
    @{ Name = "NewLauncher"; Strings = @('newlauncher','versions') },
    @{ Name = "Catlean"; Strings = @('Catlean') },
    @{ Name = "Cracked Grim"; Strings = @('ops/ec/kekma','abc/def/event/impl') },
    @{ Name = "Doomsday Client"; Strings = @('l.pngUT') },
    @{ Name = "Pojav Client"; Strings = @('ie/skobelevs/gui/screen/') },
    @{ Name = "Polar Client"; Strings = @('modelfix/addons/addon/render','(Ldev/lvstrng/polar/ARGONFz;Ldev/lvstrng/polar/ARGONFA','TW91c2UgU2ltdWxhdGlvbg==') },
    @{ Name = "Krypton Client"; Strings = @('a/b/c/z','^([A-Z0-9]{4}-){5}[A-Z0-9]{4}$') },
    @{ Name = "Gardenia Client"; Strings = @('kambing/gardenia') },
    @{ Name = "Shoreline"; Strings = @('shoreline/client') },
    @{ Name = "Minced"; Strings = @('free/minced') },
    @{ Name = "Scrim Client"; Strings = @('dev/nixoly/scrim','1d1o4d4HVvAIeKJPVhZ6jCZ7ixV0MS') },
    @{ Name = "Argon Client"; Strings = @('dev/lvstrng/argon') },
    @{ Name = "Owo Client"; Strings = @('OwoConfig','OwoMenu','Triggerbot') },
    # Xenon: zahrnujeme více variant, včetně těch z předchozích zpráv
    @{ Name = "Xenon Client"; Strings = @('dev/oceanic/xenon','Ldev/oceanic/xenon/module/setting/Setting;','dev/oceanic/xenon/module/ModuleManager$$Lambda+0x0000013f02588220','dev/oceanic/xenon/module/','oceanic/xenon') },
    @{ Name = "Kaira Client"; Strings = @('examplemod') }
)

# Precompute byte arrays
foreach ($c in $cheatClients) {
    $c.PatternBytes = @()
    foreach ($s in $c.Strings) {
        # use single-quoted patterns as defined; convert to bytes
        $c.PatternBytes += ,(PatternToBytes $s)
    }
}
# ---------------------------------------------------------

# ---------------- ZIP / JAR in-memory scanning ----------------
function Scan-Bytes-For-Clients {
    param([byte[]]$bytes, [string]$source)
    $found = @()
    foreach ($client in $cheatClients) {
        foreach ($pb in $client.PatternBytes) {
            if (ByteArray-Contains -haystack $bytes -needle $pb) {
                $found += [PSCustomObject]@{
                    Client = $client.Name
                    Path   = $source
                    String = [System.Text.Encoding]::UTF8.GetString($pb)
                }
                break
            }
        }
    }
    return $found
}

function Scan-ZipStream {
    param([System.IO.Stream]$stream, [string]$archivePath)
    $matches = @()
    try {
        $zip = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Read, $false)
    } catch {
        return $matches
    }
    foreach ($entry in $zip.Entries) {
        try {
            if ($entry.Length -eq 0) { continue }
            $lower = $entry.FullName.ToLowerInvariant()
            # pokud je .class nebo obsahuje podezřelé cesty, čti bytes a testuj
            if ($lower -like "*.class" -or $lower -match "dev/oceanic/xenon" -or $lower -match "xenon") {
                $ms = New-Object System.IO.MemoryStream
                $rs = $entry.Open()
                $rs.CopyTo($ms)
                $rs.Close()
                $bytes = $ms.ToArray()
                $ms.Dispose()
                $source = "$archivePath`::$($entry.FullName)"
                $m = Scan-Bytes-For-Clients -bytes $bytes -source $source
                if ($m.Count -gt 0) { $matches += $m }
            }
            # pokud je vnořený jar, rekurzivně ho zpracuj v paměti
            if ($lower -like "*.jar" -or $lower -like "*.zip") {
                $mem = New-Object System.IO.MemoryStream
                $rs2 = $entry.Open()
                $rs2.CopyTo($mem)
                $rs2.Close()
                $mem.Position = 0
                $nested = Scan-ZipStream -stream $mem -archivePath ("$archivePath`::$($entry.FullName)")
                if ($nested.Count -gt 0) { $matches += $nested }
                $mem.Dispose()
            }
        } catch {}
    }
    $zip.Dispose()
    return $matches
}
# ---------------------------------------------------------------

# ---------------- Main file scanning loop ----------------
$verifiedMods = @()
$unknownMods = @()
$cheatMods = @()

$jarFiles = Get-ChildItem -Path $mods -Filter *.jar -File -ErrorAction SilentlyContinue
$totalMods = $jarFiles.Count
$counter = 0

if ($totalMods -eq 0) {
    Write-Host "No .jar files found in $mods" -ForegroundColor Yellow
}

foreach ($file in $jarFiles) {
    $counter++
    $spin = $spinner[$counter % $spinner.Length]
    Write-Host "`r[$spin] Scanning mods: $counter / $totalMods" -ForegroundColor Yellow -NoNewline

    $hash = Get-SHA1 -filePath $file.FullName

    # Try Modrinth
    $modDataModrinth = Fetch-Modrinth -hash $hash
    if ($modDataModrinth.Slug) {
        $verifiedMods += [PSCustomObject]@{ ModName = $modDataModrinth.Name; FileName = $file.Name }
        continue
    }

    # Try Megabase
    $modDataMegabase = Fetch-Megabase -hash $hash
    if ($modDataMegabase -and $modDataMegabase.name) {
        $verifiedMods += [PSCustomObject]@{ ModName = $modDataMegabase.Name; FileName = $file.Name }
        continue
    }

    $zoneId = Get-ZoneIdentifier -filePath $file.FullName
    $unknownMods += [PSCustomObject]@{ FileName = $file.Name; FilePath = $file.FullName; ZoneId = $zoneId }
}
# -------------------------------------------------------

# -------------- Scan unknown mods in-memory --------------
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
                Write-Host ""
                Write-Host "Client name : $($f.Client)" -ForegroundColor Red -NoNewline
                Write-Host "  | Path: $($f.Path)" -ForegroundColor DarkGray
                Write-Host "String: $($f.String)" -ForegroundColor Magenta
                Write-Host ""
            }
            $cheatMods += [PSCustomObject]@{ FileName = $mod.FileName; FilePath = $mod.FilePath; Matches = $found }
            $unknownMods = $unknownMods | Where-Object { $_.FileName -ne $mod.FileName }
        }
    } catch {
        Write-Host "`nWarning: Could not read $($mod.FileName) - $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
# -----------------------------------------------------------

# ---------------- Memory scanner (runtime) ----------------
# P/Invoke declarations for ReadProcessMemory + VirtualQueryEx
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class Win32 {
    [Flags]
    public enum ProcessAccessFlags : uint {
        VMRead = 0x0010,
        QueryInformation = 0x0400,
        VMOperation = 0x0008
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MEMORY_BASIC_INFORMATION {
        public UIntPtr BaseAddress;
        public UIntPtr AllocationBase;
        public uint AllocationProtect;
        public UIntPtr RegionSize;
        public uint State;
        public uint Protect;
        public uint Type;
    }

    [DllImport("kernel32.dll")]
    public static extern IntPtr OpenProcess(ProcessAccessFlags dwDesiredAccess, bool bInheritHandle, int dwProcessId);

    [DllImport("kernel32.dll")]
    public static extern bool CloseHandle(IntPtr hObject);

    [DllImport("kernel32.dll")]
    public static extern IntPtr VirtualQueryEx(IntPtr hProcess, IntPtr lpAddress, out MEMORY_BASIC_INFORMATION lpBuffer, UIntPtr dwLength);

    [DllImport("kernel32.dll")]
    public static extern bool ReadProcessMemory(IntPtr hProcess, IntPtr lpBaseAddress, [Out] byte[] lpBuffer, UIntPtr nSize, out UIntPtr lpNumberOfBytesRead);
}
"@ -PassThru | Out-Null

function Scan-Process-Memory {
    param([int]$pid, [array]$patterns)  # patterns: array of byte[] patterns
    $h = [Win32]::OpenProcess([Win32+ProcessAccessFlags]::VMRead -bor [Win32+ProcessAccessFlags]::QueryInformation, $false, $pid)
    if ($h -eq [IntPtr]::Zero) { Write-Host "Could not open process $pid for reading." -ForegroundColor Yellow; return @() }

    $matches = @()
    $address = [IntPtr]::Zero
    $memInfo = New-Object Win32+MEMORY_BASIC_INFORMATION
    $maxAddr = [UInt64]0x7fffffffffffffff

    while ($true) {
        $res = [Win32]::VirtualQueryEx($h, $address, [ref]$memInfo, [UIntPtr]([System.Runtime.InteropServices.Marshal]::SizeOf($memInfo)))
        if ($res -eq [IntPtr]::Zero) { break }

        $regionSize = [UInt64]$memInfo.RegionSize
        $baseAddr = [UInt64]$memInfo.BaseAddress
        $state = $memInfo.State
        $protect = $memInfo.Protect

        # Only read committed pages
        if ($state -eq 0x1000 -and ($protect -band 0x01) -ne 0x01) { # MEM_COMMIT and not PAGE_NOACCESS
            try {
                $toRead = [UInt64]$regionSize
                # limit read size to reasonable chunk (e.g., 64KB) and iterate
                $offset = 0
                while ($offset -lt $toRead) {
                    $chunkSize = 65536
                    if ($offset + $chunkSize -gt $toRead) { $chunkSize = $toRead - $offset }
                    $buffer = New-Object byte[] $chunkSize
                    $bytesRead = [UIntPtr]::Zero
                    $addrPtr = [IntPtr]($baseAddr + $offset)
                    $ok = [Win32]::ReadProcessMemory($h, $addrPtr, $buffer, [UIntPtr]$chunkSize, [ref]$bytesRead)
                    if ($ok) {
                        foreach ($pat in $patterns) {
                            if (ByteArray-Contains -haystack $buffer -needle $pat) {
                                $matches += [PSCustomObject]@{ PID = $pid; Base = ("0x{0:X}" -f ($baseAddr + $offset)); Pattern = [System.Text.Encoding]::UTF8.GetString($pat) }
                            }
                        }
                    }
                    $offset += $chunkSize
                }
            } catch {}
        }

        # advance address
        $next = [UInt64]$memInfo.BaseAddress + [UInt64]$memInfo.RegionSize
        if ($next -ge $maxAddr) { break }
        $address = [IntPtr]$next
    }

    [Win32]::CloseHandle($h) > $null
    return $matches
}

# Prepare byte patterns for memory scan (all patterns from cheatClients)
$memoryPatterns = @()
foreach ($c in $cheatClients) {
    foreach ($s in $c.Strings) {
        $memoryPatterns += ,(PatternToBytes $s)
    }
}
# Deduplicate patterns (by string)
$memoryPatterns = $memoryPatterns | Select-Object -Unique

# find java/javaw process
$javaProcess = Get-Process javaw -ErrorAction SilentlyContinue
if (-not $javaProcess) { $javaProcess = Get-Process java -ErrorAction SilentlyContinue }

if ($javaProcess) {
    Write-Host "`n{ Runtime Memory Scan }" -ForegroundColor DarkCyan
    try {
        $memMatches = Scan-Process-Memory -pid $javaProcess.Id -patterns $memoryPatterns
        if ($memMatches.Count -gt 0) {
            foreach ($m in $memMatches) {
                # Map found pattern back to client name if possible
                $foundPattern = $m.Pattern
                $foundClient = ($cheatClients | Where-Object { $_.Strings -contains $foundPattern } | Select-Object -First 1).Name
                if (-not $foundClient) { $foundClient = "Unknown (memory)" }
                Write-Host "Memory match -> Client: $foundClient | PID: $($m.PID) | Addr: $($m.Base) | Pattern: $($m.Pattern)" -ForegroundColor Magenta
            }
        } else {
            Write-Host "No suspicious strings found in process memory." -ForegroundColor Green
        }
    } catch {
        Write-Host "Memory scan error: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host "No java/javaw process found for runtime memory scan." -ForegroundColor Yellow
}
# ------------------------------------------------------------

# ---------------- Final output formatting ----------------
Write-Host "`r$(' ' * 80)`r" -NoNewline

if ($verifiedMods.Count -gt 0) {
    Write-Host "{ Verified Mods }" -ForegroundColor DarkCyan
    foreach ($m in $verifiedMods) {
        Write-Host ("> {0, -30}" -f $m.ModName) -ForegroundColor Green -NoNewline
        Write-Host "$($m.FileName)" -ForegroundColor Gray
    }
    Write-Host
}

if ($unknownMods.Count -gt 0) {
    Write-Host "{ Unknown Mods }" -ForegroundColor DarkCyan
    foreach ($m in $unknownMods) {
        if ($m.ZoneId) {
            Write-Host ("> {0, -30}" -f $m.FileName) -ForegroundColor DarkYellow -NoNewline
            Write-Host "$($m.ZoneId)" -ForegroundColor DarkGray
            continue
        }
        Write-Host "> $($m.FileName)" -ForegroundColor DarkYellow
    }
    Write-Host
}

if ($cheatMods.Count -gt 0) {
    Write-Host "{ Cheat Mods }" -ForegroundColor DarkCyan
    foreach ($c in $cheatMods) {
        Write-Host "> $($c.FileName)" -ForegroundColor Red
        foreach ($m in $c.Matches) {
            Write-Host "  -> $($m.Client) | $($m.Path) | $($m.String)" -ForegroundColor DarkMagenta
        }
    }
    Write-Host
} else {
    Write-Host "No cheat mods detected." -ForegroundColor Green
}
# ---------------------------------------------------------
