Write-Host "=== Full JAR String Dumper (Process Hacker style) ===" -ForegroundColor Cyan

$jar = Read-Host "Drag & Drop JAR sem"

if (-not (Test-Path $jar)) {
    Write-Host "❌ Soubor neexistuje!" -ForegroundColor Red
    exit
}

Write-Host "[INFO] Načítám celý JAR a extrahuju stringy..." -ForegroundColor Yellow

function Get-StringsFromBinary {
    param([byte[]]$bytes)

    $builder = New-Object System.Text.StringBuilder
    $strings = New-Object System.Collections.Generic.List[string]

    foreach ($b in $bytes) {
        if ($b -ge 32 -and $b -le 126) {
            $null = $builder.Append([char]$b)
        } else {
            if ($builder.Length -ge 4) {
                $strings.Add($builder.ToString())
            }
            $builder.Clear() | Out-Null
        }
    }

    if ($builder.Length -ge 4) {
        $strings.Add($builder.ToString())
    }

    return $strings
}

$bytes = [System.IO.File]::ReadAllBytes($jar)
$strings = Get-StringsFromBinary -bytes $bytes

Write-Host "`n=== FOUND STRINGS ===" -ForegroundColor Cyan

$strings | Sort-Object -Unique | Out-Host

Write-Host "`n=== DONE ==="
