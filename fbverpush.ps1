# 1. Sprawdzenie wersji Firebird za pomocą gstat -z
function Get-FirebirdVersion {
    # Pobierz ścieżkę instalacji Firebird z rejestru
    $firebirdPath = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Firebird Project\Firebird Server\Instances").DefaultInstance
    if (-not $firebirdPath) {
        Write-Error "Nie znaleziono ścieżki instalacji Firebird w rejestrze."
        return
    }
    # Sprawdź, czy gstat.exe istnieje bezpośrednio w ścieżce instalacji
    $gstatPath = Join-Path -Path $firebirdPath -ChildPath "gstat.exe"
    
    if (-not (Test-Path $gstatPath)) {
        # Jeśli gstat.exe nie istnieje, dodaj katalog bin
        $gstatPath = Join-Path -Path $firebirdPath -ChildPath "bin\gstat.exe"
        
        if (-not (Test-Path $gstatPath)) {
            Write-Error "Nie znaleziono pliku gstat.exe ani w ścieżce głównej, ani w katalogu bin: $firebirdPath"
            return
        }
    }
    # Wykonanie gstat -z i wyciągnięcie samej wersji
    $gstatResult = & $gstatPath -z
    # Wyciągnięcie odpowiedniej linii, która zawiera wersję
    if ($gstatResult) {
        # Wyciągnij wersję bez tekstu "gstat version "
        $firebirdVersion = $gstatResult | Select-String -Pattern "gstat version" | ForEach-Object { $_.Line -replace "gstat version ", "" }
        return $firebirdVersion
    } else {
        Write-Error "Nie udało się uzyskać wersji Firebird za pomocą gstat -z."
        return $null
    }
}
# 2. Odczytanie ID klienta z pliku licencji XML
function Get-LicenseId {
    # Sprawdź klucz rejestru
    $registryPath = "HKLM:\SOFTWARE\WOW6432Node\KAMSOFT\KS-APW"
    $registryKey = "sciezka"
    $programPath = (Get-ItemProperty -Path $registryPath -Name $registryKey -ErrorAction SilentlyContinue).$registryKey
    # Znalezienie lokalizacji pliku XML
    if ($programPath) {
        $xmlFilePath = Join-Path -Path $programPath -ChildPath "APW\AP\licencja_aow.xml"
        if (-not (Test-Path $xmlFilePath)) {
            Write-Error "Nie znaleziono pliku licencja_aow.xml w ścieżce: $xmlFilePath"
            return
        }
    } else {
        # Znajdź dysk zawierający plik "licencja_aow.xml"
        Write-Output "Szukam pliku licencja_aow.xml na dostępnych dyskach..."
        $diskPaths = Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Root }
        $xmlFilePath = $null
        foreach ($diskPath in $diskPaths) {
            $xmlFilePath = Get-ChildItem -Path "$diskPath\KS\APW\AP\licencja_aow.xml" -Recurse -ErrorAction SilentlyContinue -Force | Select-Object -ExpandProperty FullName -First 1
            if ($xmlFilePath) { break }
        }
        if (-not $xmlFilePath) {
            Write-Error "Nie znaleziono pliku licencja_aow.xml na żadnym dysku"
            return
        }
    }
    # Odczyt XML i wyciągnięcie ID klienta
    try {
        [xml]$xmlDoc = Get-Content $xmlFilePath
        # Tworzymy menedżera przestrzeni nazw
        $namespaceManager = New-Object System.Xml.XmlNamespaceManager($xmlDoc.NameTable)
        $namespaceManager.AddNamespace("ks", "http://www.kamsoft.pl/ks")
        # Pobieramy ID klienta z użyciem przestrzeni nazw
        $idKntKs = $xmlDoc.SelectSingleNode("//ks:licencja/ks:klient/ks:id-knt-ks", $namespaceManager).InnerText
        if ($idKntKs) {
            return $idKntKs
        } else {
            Write-Error "Nie znaleziono ID klienta KS w pliku XML."
            return $null
        }
    } catch {
        Write-Error "Wystąpił błąd podczas odczytu pliku XML: $_"
        return $null
    }
}
# 3. Wysyłanie danych za pomocą cURL
function Send-DataToWebhook {
    param (
        [string]$firebirdVersion,
        [string]$idKntKs
    )
    $url = "http://ap.xsystem.io:7080/api/v1/webhooks/cKcVyhDHqoHy26ef04Bda"
    # Dane w formacie JSON
    $jsonPayload = @{
        FB_VER = $firebirdVersion
        IDKS = $idKntKs
    } | ConvertTo-Json
    # Wysłanie danych
    try {
        $response = Invoke-RestMethod -Uri $url -Method Post -ContentType "application/json" -Body $jsonPayload
        Write-Output "Wysłano dane do webhooka. Odpowiedź: $response"
    } catch {
        Write-Error "Wystąpił błąd podczas wysyłania danych: $_"
    }
}
# Uruchomienie funkcji
$firebirdVersion = Get-FirebirdVersion
$idKntKs = Get-LicenseId
# Wyświetlenie wyników i wysłanie ich do webhooka
if ($firebirdVersion -and $idKntKs) {
    Write-Output "Wersja Firebird: $firebirdVersion"
    Write-Output "ID klienta KS: $idKntKs"
    # Wysłanie danych do webhooka
    Send-DataToWebhook -firebirdVersion $firebirdVersion -idKntKs $idKntKs
}