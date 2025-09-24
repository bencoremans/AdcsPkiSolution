[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateScript({$_.Exists -and $_.Extension -eq '.dll'})]
    [System.IO.FileInfo]$Path,
    [Parameter(Mandatory=$false)]
    [string]$ApiUrl = "http://pki20api.tenant47.minjenv.nl/api/certificate/issue",
    [Parameter(Mandatory=$false)]
    [string]$BufferDir = "C:\PKIExitBuffer",
    [Parameter(Mandatory=$false)]
    [string]$LogBaseDir = "C:\Logs",
    [Parameter(Mandatory=$false)]
    [int]$LogLevel = 3, # 3 = Debug (dword)
    [Parameter(Mandatory=$false)]
    [string]$ApiKey = "X7K9P2M4Q8J5R3L1N6V0T2Y4W8Z9A3B5C",
    [switch]$RegisterOnly,
    [switch]$AddToCA,
    [switch]$Restart
)
$ErrorActionPreference = 'Stop'
$VerbosePreference = 'Continue'

# Define constants
$RegPolTemplateBase = 'HKLM:\System\CurrentControlSet\Services\CertSvc\Configuration'
$ExpectedRuntimeVersion = 'v4.0.30319'

# Definieer GUID's en naamstrings als variabelen
$exitGuid = '{34EBA06C-24E0-4068-A049-262E871A6D7B}' # GUID voor Exit
$exitManageGuid = '{434350AA-7CDF-4C78-9973-8F51BF320365}' # GUID voor ExitManage
$assemblyName = 'ADCS.CertMod' # AssemblyName
$exitClassName = 'ADCS.CertMod.Exit' # Class-naam voor Exit
$exitManageClassName = 'ADCS.CertMod.ExitManage' # Class-naam voor ExitManage
$exitProgId = 'AdcsCertMod.Exit' # ProgId voor Exit
$exitManageProgId = 'AdcsCertMod.ExitManage' # ProgId voor ExitManage
$ExpectedFileName = "$assemblyName.dll" # Dynamisch gebaseerd op assemblyName

# Functie om registry-configuratie uit te voeren
function Configure-Registry {
    param (
        [string]$ApiUrl,
        [string]$BufferDir,
        [string]$LogBaseDir,
        [int]$LogLevel,
        [string]$ApiKey,
        [string]$CaName
    )
    $registryPath = "$RegPolTemplateBase\$CaName\ExitModules\$exitProgId"
    if (-not (Test-Path $registryPath)) {
        try {
            New-Item -Path $registryPath -Force | Out-Null
            Write-Verbose "Registry-sleutel $registryPath aangemaakt."
        }
        catch {
            Write-Error "Kon registry-sleutel $registryPath niet aanmaken: $_"
            throw
        }
    }
    if (-not (Test-Path $BufferDir)) {
        try {
            New-Item -Path $BufferDir -ItemType Directory -Force | Out-Null
            Write-Verbose "Map $BufferDir aangemaakt."
        }
        catch {
            Write-Error "Kon map $BufferDir niet aanmaken: $_"
            throw
        }
    }
    if (-not (Test-Path $LogBaseDir)) {
        try {
            New-Item -Path $LogBaseDir -ItemType Directory -Force | Out-Null
            Write-Verbose "Map $LogBaseDir aangemaakt."
        }
        catch {
            Write-Error "Kon map $LogBaseDir niet aanmaken: $_"
            throw
        }
    }
    try {
        Add-Type -AssemblyName System.Security
        Write-Verbose "Assembly System.Security.Cryptography geladen."
    }
    catch {
        Write-Error "Kon System.Security.Cryptography niet laden: $_"
        throw
    }
    try {
        $apiKeyBytes = [System.Text.Encoding]::UTF8.GetBytes($ApiKey)
        $encryptedBytes = [System.Security.Cryptography.ProtectedData]::Protect($apiKeyBytes, $null, [System.Security.Cryptography.DataProtectionScope]::LocalMachine)
        $encryptedApiKey = [Convert]::ToBase64String($encryptedBytes)
        Write-Verbose "API-sleutel succesvol versleuteld."
    }
    catch {
        Write-Error "Fout bij versleutelen van de API-sleutel: $_"
        throw
    }
    try {
        Set-ItemProperty -Path $registryPath -Name "ApiUrl" -Value $ApiUrl
        Set-ItemProperty -Path $registryPath -Name "ApiKeyEncrypted" -Value $encryptedApiKey
        Set-ItemProperty -Path $registryPath -Name "BufferDir" -Value $BufferDir
        Set-ItemProperty -Path $registryPath -Name "LogBaseDir" -Value $LogBaseDir
        Set-ItemProperty -Path $registryPath -Name "LogLevel" -Value $LogLevel -Type DWord
        Write-Verbose "Registry-waarden succesvol ingesteld."
    }
    catch {
        Write-Error "Fout bij instellen van registry-waarden: $_"
        throw
    }
    $registryValues = Get-ItemProperty -Path $registryPath -ErrorAction Stop
    Write-Verbose "Configuratie succesvol ingesteld:"
    Write-Verbose "ApiUrl: $($registryValues.ApiUrl)"
    Write-Verbose "ApiKeyEncrypted: $($registryValues.ApiKeyEncrypted)"
    Write-Verbose "BufferDir: $($registryValues.BufferDir)"
    Write-Verbose "LogBaseDir: $($registryValues.LogBaseDir)"
    Write-Verbose "LogLevel: $($registryValues.LogLevel)"
}

function Test-AdminPrivileges {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        Write-Error "Kon administrator-rechten niet verifiëren: $_"
        return $false
    }
}

function Test-RegistryProvider {
    try {
        if (-not (Get-PSDrive -PSProvider Registry -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'HKCR' })) {
            Write-Verbose "HKCR drive niet gevonden. Poging tot aanmaken."
            New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT -Scope Script -ErrorAction Stop | Out-Null
            Write-Verbose "HKCR drive succesvol aangemaakt."
        }
        return $true
    }
    catch {
        Write-Error "Kon Registry provider of HKCR drive niet initialiseren: $_"
        return $false
    }
}

function Get-DotNetAssemblyInfo {
    param (
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )
    try {
        Write-Verbose "Valideren .NET assembly: $FilePath"
        $assembly = [System.Reflection.Assembly]::ReflectionOnlyLoadFrom($FilePath)
        $assemblyName = $assembly.GetName()
        $version = $assemblyName.Version.ToString()
        $publicKeyTokenBytes = $assemblyName.GetPublicKeyToken()
        $publicKeyToken = if ($publicKeyTokenBytes -and $publicKeyTokenBytes.Length -gt 0) {
            ($publicKeyTokenBytes | ForEach-Object { '{0:x2}' -f $_ }) -join ''
        } else {
            'null'
        }
        if (-not $version) {
            Write-Error "Assembly-versie kon niet worden bepaald."
            return $null
        }
        Write-Verbose "Assembly Name: $($assemblyName.Name), Version: $version, PublicKeyToken: $publicKeyToken"
        return @{
            Version = $version
            PublicKeyToken = $publicKeyToken
        }
    }
    catch {
        Write-Error "Kon assembly niet laden voor validatie: $_"
        return $null
    }
}

function Test-DotNetFramework {
    try {
        Write-Verbose "Controleren op .NET Framework $ExpectedRuntimeVersion"
        $frameworkPath = "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full"
        if (-not (Test-Path $frameworkPath)) {
            Write-Error ".NET Framework $ExpectedRuntimeVersion is niet geïnstalleerd."
            return $false
        }
        $release = (Get-ItemProperty -Path $frameworkPath -Name Release -ErrorAction Stop).Release
        if ($release -lt 378389) {
            Write-Error "Geïnstalleerde .NET Framework versie is te laag. Vereist: $ExpectedRuntimeVersion"
            return $false
        }
        Write-Verbose ".NET Framework $ExpectedRuntimeVersion is geïnstalleerd."
        return $true
    }
    catch {
        Write-Error "Kon .NET Framework versie niet controleren: $_"
        return $false
    }
}

function Register-COM {
    param (
        [Parameter(Mandatory=$true)]
        [string]$FilePath,
        [Parameter(Mandatory=$true)]
        [string]$Version,
        [Parameter(Mandatory=$true)]
        [string]$PublicKeyToken
    )
    try {
        Write-Verbose "COM-component registreren voor $FilePath"
        if (-not (Test-RegistryProvider)) {
            throw "Initialisatie van Registry provider mislukt."
        }
        $formattedPath = $FilePath -replace '\\', '/'
        $assemblyString = if ($PublicKeyToken -eq 'null') {
            "$assemblyName, Version=$Version, Culture=neutral"
        } else {
            "$assemblyName, Version=$Version, Culture=neutral, PublicKeyToken=$PublicKeyToken"
        }
        $regEntries = @(
            @{
                Path = 'Registry::HKEY_CLASSES_ROOT\' + $exitProgId
                Properties = @{
                    '(default)' = $exitClassName
                }
            },
            @{
                Path = 'Registry::HKEY_CLASSES_ROOT\' + $exitProgId + '\CLSID'
                Properties = @{
                    '(default)' = $exitGuid
                }
            },
            @{
                Path = "Registry::HKEY_CLASSES_ROOT\CLSID\$exitGuid"
                Properties = @{
                    '(default)' = $exitClassName
                }
            },
            @{
                Path = "Registry::HKEY_CLASSES_ROOT\CLSID\$exitGuid\InprocServer32"
                Properties = @{
                    '(default)' = 'mscoree.dll'
                    'ThreadingModel' = 'Both'
                    'Class' = $exitClassName
                    'Assembly' = $assemblyString
                    'RuntimeVersion' = $ExpectedRuntimeVersion
                    'CodeBase' = "file:///$formattedPath"
                }
            },
            @{
                Path = "Registry::HKEY_CLASSES_ROOT\CLSID\$exitGuid\InprocServer32\$Version"
                Properties = @{
                    'Class' = $exitClassName
                    'Assembly' = $assemblyString
                    'RuntimeVersion' = $ExpectedRuntimeVersion
                    'CodeBase' = "file:///$formattedPath"
                }
            },
            @{
                Path = "Registry::HKEY_CLASSES_ROOT\CLSID\$exitGuid\ProgId"
                Properties = @{
                    '(default)' = $exitProgId
                }
            },
            @{
                Path = "Registry::HKEY_CLASSES_ROOT\CLSID\$exitGuid\Implemented Categories\{62C8FE65-4EBB-45E7-B440-6E39B2CDBF29}"
                Properties = @{}
            },
            @{
                Path = 'Registry::HKEY_CLASSES_ROOT\' + $exitManageProgId
                Properties = @{
                    '(default)' = $exitManageClassName
                }
            },
            @{
                Path = 'Registry::HKEY_CLASSES_ROOT\' + $exitManageProgId + '\CLSID'
                Properties = @{
                    '(default)' = $exitManageGuid
                }
            },
            @{
                Path = "Registry::HKEY_CLASSES_ROOT\CLSID\$exitManageGuid"
                Properties = @{
                    '(default)' = $exitManageClassName
                }
            },
            @{
                Path = "Registry::HKEY_CLASSES_ROOT\CLSID\$exitManageGuid\InprocServer32"
                Properties = @{
                    '(default)' = 'mscoree.dll'
                    'ThreadingModel' = 'Both'
                    'Class' = $exitManageClassName
                    'Assembly' = $assemblyString
                    'RuntimeVersion' = $ExpectedRuntimeVersion
                    'CodeBase' = "file:///$formattedPath"
                }
            },
            @{
                Path = "Registry::HKEY_CLASSES_ROOT\CLSID\$exitManageGuid\InprocServer32\$Version"
                Properties = @{
                    'Class' = $exitManageClassName
                    'Assembly' = $assemblyString
                    'RuntimeVersion' = $ExpectedRuntimeVersion
                    'CodeBase' = "file:///$formattedPath"
                }
            },
            @{
                Path = "Registry::HKEY_CLASSES_ROOT\CLSID\$exitManageGuid\ProgId"
                Properties = @{
                    '(default)' = $exitManageProgId
                }
            },
            @{
                Path = "Registry::HKEY_CLASSES_ROOT\CLSID\$exitManageGuid\Implemented Categories\{62C8FE65-4EBB-45E7-B440-6E39B2CDBF29}"
                Properties = @{}
            }
        )
        foreach ($entry in $regEntries) {
            $regPath = $entry.Path
            $properties = $entry.Properties
            Write-Verbose "Verwerken registry pad: $regPath"
            if (-not (Test-Path $regPath)) {
                Write-Verbose "Aanmaken registry-sleutel: $regPath"
                New-Item -Path $regPath -Force -ErrorAction Stop | Out-Null
            }
            foreach ($prop in $properties.GetEnumerator()) {
                $propName = $prop.Name
                $propValue = $prop.Value
                Write-Verbose "Instellen eigenschap '$propName' naar '$propValue' op $regPath"
                Set-ItemProperty -Path $regPath -Name $propName -Value $propValue -ErrorAction Stop
            }
        }
        $keyPath = "Registry::HKEY_CLASSES_ROOT\CLSID\$exitGuid\InprocServer32"
        if (-not (Test-Path $keyPath)) {
            Write-Error "Registry-sleutel $keyPath werd niet aangemaakt."
            throw "Registry verificatie mislukt"
        }
        $codeBase = (Get-ItemProperty -Path $keyPath -Name CodeBase -ErrorAction Stop).CodeBase
        if ($codeBase -ne "file:///$formattedPath") {
            Write-Error "CodeBase komt niet overeen. Verwacht: file:///$formattedPath, Gevonden: $codeBase"
            throw "Registry verificatie mislukt"
        }
        $assembly = (Get-ItemProperty -Path $keyPath -Name Assembly -ErrorAction Stop).Assembly
        if ($assembly -ne $assemblyString) {
            Write-Error "Assembly komt niet overeen. Verwacht: $assemblyString, Gevonden: $assembly"
            throw "Registry verificatie mislukt"
        }
        Write-Verbose "COM-registratie succesvol"
    }
    catch {
        Write-Error "Kon COM-component niet registreren: $_"
        throw
    }
}

function Add-ToCA {
    try {
        Write-Verbose "Module toevoegen aan Certification Authority"
        $regPolTemplate = $RegPolTemplateBase
        if (-not (Test-Path $regPolTemplate)) {
            Write-Error "Certification Authority registry pad niet gevonden: $regPolTemplate"
            throw "Ongeldig registry pad"
        }
        $activeCA = (Get-ItemProperty -Path $regPolTemplate -Name Active -ErrorAction Stop).Active
        if (-not $activeCA) {
            Write-Error "Geen actieve Certification Authority configuratie gevonden"
            throw "Geen actieve CA"
        }
        $regPolTemplate += "\$activeCA\ExitModules"
        $currentModules = (Get-ItemProperty -Path $regPolTemplate -Name Active -ErrorAction SilentlyContinue).Active
        if (-not $currentModules) {
            $currentModules = @()
        }
        if ($currentModules -notcontains $exitProgId) {
            $currentModules += $exitProgId
            Set-ItemProperty -Path $regPolTemplate -Name Active -Value $currentModules -ErrorAction Stop
            Write-Verbose "Module $exitProgId toegevoegd aan CA exit modules"
        }
        else {
            Write-Verbose "Module $exitProgId bestaat al in CA exit modules"
        }
        $caConfigPath = "$RegPolTemplateBase\$activeCA\ExitModules\$exitProgId"
        if (-not (Test-Path $caConfigPath)) {
            New-Item -Path $caConfigPath -Force | Out-Null
            Write-Verbose "CA-specifieke registry-sleutel $caConfigPath aangemaakt."
        }
        Set-ItemProperty -Path $caConfigPath -Name "ApiUrl" -Value $ApiUrl
        Set-ItemProperty -Path $caConfigPath -Name "ApiKeyEncrypted" -Value ([Convert]::ToBase64String([System.Security.Cryptography.ProtectedData]::Protect([System.Text.Encoding]::UTF8.GetBytes($ApiKey), $null, [System.Security.Cryptography.DataProtectionScope]::LocalMachine)))
        Set-ItemProperty -Path $caConfigPath -Name "BufferDir" -Value $BufferDir
        Set-ItemProperty -Path $caConfigPath -Name "LogBaseDir" -Value $LogBaseDir
        Set-ItemProperty -Path $caConfigPath -Name "LogLevel" -Value $LogLevel -Type DWord
        Write-Verbose "Configuratie succesvol toegevoegd aan CA-specifieke locatie."
    }
    catch {
        Write-Error "Kon module niet toevoegen aan CA: $_"
        throw
    }
}

try {
    if (-not (Get-Service -Name CertSvc -ErrorAction SilentlyContinue)) {
        Write-Error "Certification Authority service (CertSvc) is niet geïnstalleerd."
        exit 1
    }
    if (-not (Test-AdminPrivileges)) {
        Write-Error "Dit script vereist lokale administrator-rechten. Voer het uit in een verhoogde PowerShell-sessie."
        exit 1
    }
    if (-not $Path.Exists) {
        Write-Error "Het opgegeven bestand '$($Path.FullName)' bestaat niet."
        exit 1
    }
    if ($Path.Name -ne $ExpectedFileName) {
        Write-Error "Het opgegeven bestand is niet het verwachte Exit module bestand '$ExpectedFileName'."
        exit 1
    }
    $activeCA = (Get-ItemProperty -Path $RegPolTemplateBase -Name Active -ErrorAction Stop).Active
    Configure-Registry -ApiUrl $ApiUrl -BufferDir $BufferDir -LogBaseDir $LogBaseDir -LogLevel $LogLevel -ApiKey $ApiKey -CaName $activeCA
    $assemblyInfo = Get-DotNetAssemblyInfo -FilePath $Path.FullName
    if (-not $assemblyInfo) {
        Write-Error "Assembly validatie mislukt voor '$($Path.FullName)'."
        exit 1
    }
    $version = $assemblyInfo.Version
    $publicKeyToken = $assemblyInfo.PublicKeyToken
    if (-not (Test-DotNetFramework)) {
        Write-Error ".NET Framework validatie mislukt."
        exit 1
    }
    Register-COM -FilePath $Path.FullName -Version $version -PublicKeyToken $publicKeyToken
    if (-not $RegisterOnly) {
        if ($AddToCA) {
            Add-ToCA
            if ($Restart) {
                try {
                    Write-Verbose "Herstarten Certification Authority service"
                    Restart-Service -Name CertSvc -Force -ErrorAction Stop
                    Write-Verbose "Certification Authority service succesvol herstart"
                }
                catch {
                    Write-Error "Kon Certification Authority service niet herstarten: $_"
                    exit 1
                }
            }
        }
    }
    Write-Verbose "Scriptuitvoering succesvol voltooid"
}
catch {
    Write-Error "Er is een onverwachte fout opgetreden: $_"
    exit 1
}