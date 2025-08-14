[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; `
$u='https://raw.githubusercontent.com/tornister76/fbverpush/main/Update-Firebird.ps1'; `
$s=irm $u; `
if($PSVersionTable.PSVersion.Major -lt 7){
  # wstaw bezpieczną domyślną tablicę argumentów
  $s = $s -replace '(\s*if\s*\(\s*\$RunFbVerPush\)\s*\{)', '$1' + "`r`n  " + '$fbArgsSafe = if ($null -ne $FbVerPushArgs) { $FbVerPushArgs } else { @() }';
  # zamień wszystkie wystąpienia ($FbVerPushArgs ?? @()) -> $fbArgsSafe
  $s = $s -replace '\(\s*\$FbVerPushArgs\s*\?\?\s*@\(\s*\)\s*\)', '$fbArgsSafe'
}
iex $s

-------------------------------
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
$u='https://raw.githubusercontent.com/tornister76/fbverpush/main/Update-Firebird.ps1'
$s=irm $u

# Patch tylko dla PS < 7: usuń '??' i dodaj bezpieczne $fbArgsSafe
if($PSVersionTable.PSVersion.Major -lt 7){
  $insert = "`r`n  " + '$fbArgsSafe = if ($null -ne $FbVerPushArgs) { $FbVerPushArgs } else { @() }'
  $s = [regex]::Replace($s, 'if\s*\(\s*\$RunFbVerPush\s*\)\s*\{', ('$&' + $insert))
  $s = [regex]::Replace($s, '\(\s*\$FbVerPushArgs\s*\?\?\s*@\(\s*\)\s*\)', '$fbArgsSafe')
}

$p=Join-Path $env:TEMP 'Update-Firebird.ps1'
Set-Content -Path $p -Value $s -Encoding UTF8
powershell -NoProfile -ExecutionPolicy Bypass -File $p
