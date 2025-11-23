# ===============================
# Memory Scanner for Cheat Strings
# ===============================

$process = Get-Process javaw -ErrorAction SilentlyContinue
if (!$process) {
    Write-Host "javaw.exe nebyl nalezen."
    exit
}

# 1) Cheat stringy
$ClientStrings = @{
    "Xenon"        = @("dev/oceanic/xenon","/impl/dev/oceanic/xenon")
    "Skligga"      = @("net/skliggahack/module")
    "Scrim"        = @("dev/nixoly/scrim")
    "Gardenia"     = @("kambing/gardenia")
    "Argon"        = @("dev/lvstrng/argon")
}

# 2) Přidáme funkce pro čtení paměti
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public class Mem {
    [DllImport("kernel32.dll")]
    public static extern IntPtr OpenProcess(int dwDesiredAccess, bool bInheritHandle, int dwProcessId);

    [DllImport("kernel32.dll")]
    public static extern bool ReadProcessMemory(IntPtr hProcess, IntPtr lpBaseAddress, byte[] lpBuffer, int dwSize, out int lpNumberOfBytesRead);

    public const int PROCESS_WM_READ = 0x0010;
}
"@

$hProc = [Mem]::OpenProcess([Mem]::PROCESS_WM_READ, $false, $process.Id)

# 3) Scan paměti modulů (jen základní memory regions)
$results = @()
foreach ($mod in $process.Modules) {
    $base = $mod.BaseAddress
    $size = $mod.ModuleMemorySize

    $buffer = New-Object byte[] $size
    $read = 0
    [Mem]::ReadProcessMemory($hProc, $base, $buffer, $size, [ref]$read) | Out-Null

    # ASCII i Unicode
    $text = [System.Text.Encoding]::ASCII.GetString($buffer) + [System.Text.Encoding]::Unicode.GetString($buffer)

    foreach ($client in $ClientStrings.Keys) {
        foreach ($pattern in $ClientStrings[$client]) {
            if ($text -like "*$pattern*") {
                $results += [PSCustomObject]@{
                    Cheat  = $client
                    String = $pattern
                    Path   = "memory"
                }
            }
        }
    }
}

# 4) Výstup
if ($results.Count -eq 0) {
    Write-Host "Nenalezeny žádné cheat stringy."
} else {
    $results | Format-Table -AutoSize
}
