# Update-Firebird PowerShell Script

Skrypt do automatycznego pobierania i uruchamiania narzędzia Update-Firebird z obsługą różnych wersji PowerShell.

## Wymagania

- PowerShell 5.1 lub nowszy
- Połączenie z internetem
- Uprawnienia do wykonywania skryptów PowerShell

## Instalacja i uruchomienie

### Metoda 1: Bezpośrednie uruchomienie (zalecana)

```powershell
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
```

### Metoda 2: Zapisz jako plik .ps1

1. Skopiuj powyższy kod do pliku `install-firebird.ps1`
2. Uruchom w PowerShell:
   ```powershell
   .\install-firebird.ps1
   ```

### Metoda 3: Jedna linia (dla zaawansowanych)

```powershell
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $u='https://raw.githubusercontent.com/tornister76/fbverpush/main/Update-Firebird.ps1'; $s=irm $u; if($PSVersionTable.PSVersion.Major -lt 7){ $insert = "`r`n  " + '$fbArgsSafe = if ($null -ne $FbVerPushArgs) { $FbVerPushArgs } else { @() }'; $s = [regex]::Replace($s, 'if\s*\(\s*\$RunFbVerPush\s*\)\s*\{', ('$&' + $insert)); $s = [regex]::Replace($s, '\(\s*\$FbVerPushArgs\s*\?\?\s*@\(\s*\)\s*\)', '$fbArgsSafe') }; $p=Join-Path $env:TEMP 'Update-Firebird.ps1'; Set-Content -Path $p -Value $s -Encoding UTF8; powershell -NoProfile -ExecutionPolicy Bypass -File $p
```

## Opis działania

1. **Konfiguracja TLS**: Ustawia TLS 1.2 dla bezpiecznego połączenia HTTPS
2. **Pobieranie skryptu**: Ściąga najnowszą wersję z GitHub
3. **Kompatybilność**: Automatycznie naprawia składnię dla PowerShell < 7.0
4. **Uruchomienie**: Wykonuje skrypt z odpowiednimi parametrami bezpieczeństwa

## Rozwiązywanie problemów

### PowerShell nie jest rozpoznawany

Jeśli otrzymujesz błąd "powershell is not recognized":

```powershell
# Użyj pełnej ścieżki
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File $p

# Lub dodaj PowerShell do PATH
$env:PATH += ";C:\Windows\System32\WindowsPowerShell\v1.0"
```

### Błędy ExecutionPolicy

```powershell
# Tymczasowo zmień policy
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# Lub uruchom jako administrator i ustaw globalnie
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine
```

### Problemy z TLS/SSL

```powershell
# Jeśli masz problemy z połączeniem HTTPS
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls
```

## Funkcje

- ✅ Automatyczna kompatybilność z PowerShell 5.1+
- ✅ Bezpieczne pobieranie przez HTTPS
- ✅ Tymczasowe przechowywanie w folderze TEMP
- ✅ Automatyczne czyszczenie składni dla starszych wersji PS
- ✅ Bypass ExecutionPolicy dla jednorazowego uruchomienia

## Wsparcie

W przypadku problemów sprawdź:
- Wersję PowerShell: `$PSVersionTable.PSVersion`
- Połączenie internetowe
- Ustawienia ExecutionPolicy: `Get-ExecutionPolicy`
- Dostęp do GitHub: `Test-NetConnection raw.githubusercontent.com -Port 443`

## Licencja

Skrypt korzysta z narzędzia dostępnego na: https://github.com/tornister76/fbverpush
