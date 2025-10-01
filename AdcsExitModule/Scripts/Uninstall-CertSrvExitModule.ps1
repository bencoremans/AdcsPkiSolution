[CmdletBinding()]
param(
    [switch]$Restart
)
$ErrorActionPreference = 'Stop'
$VerbosePreference = 'Continue'

# Definieer GUID's en naamstrings als variabelen
$exitGuid = '{34EBA06C-24E0-4068-A049-262E871A6D7B}'          # GUID voor Exit (Exit.cs, [Guid] attribuut)
$exitManageGuid = '{434350AA-7CDF-4C78-9973-8F51BF320365}'    # GUID voor ExitManage (ExitManage.cs, [Guid] attribuut)
$assemblyName = 'AdcsExitModule'                                 # AssemblyName (ADCSExitModule.csproj, <AssemblyName>)
$exitClassName = 'ADCS.CertMod.Exit'                           # Class-naam voor Exit (Exit.cs, namespace en class naam)
$exitManageClassName = 'ADCS.CertMod.ExitManage'               # Class-naam voor ExitManage (ExitManage.cs, namespace en class naam)
$exitProgId = 'AdcsCertMod.Exit'                               # ProgId voor Exit (Exit.cs, [ProgId] attribuut)
$exitManageProgId = 'AdcsCertMod.ExitManage'                   # ProgId voor ExitManage (ExitManage.cs, [ProgId] attribuut)

# Definieer de registry-pad voor CA-configuratie
$RegPolTemplateBase = 'HKLM:\System\CurrentControlSet\Services\CertSvc\Configuration'

function Test-AdminPrivileges {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        Write-Error "Failed to verify administrator privileges: $_"
        return $false
    }
}

function Test-RegistryProvider {
    try {
        if (-not (Get-PSDrive -PSProvider Registry -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'HKCR' })) {
            Write-Verbose "HKCR drive not found. Attempting to create it."
            New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT -Scope Script -ErrorAction Stop | Out-Null
            Write-Verbose "HKCR drive created successfully."
        }
        return $true
    }
    catch {
        Write-Error "Failed to initialize Registry provider or HKCR drive: $_"
        return $false
    }
}

function Unregister-COM {
    try {
        Write-Verbose "Unregistering COM components"

        # Valideer registry provider
        if (-not (Test-RegistryProvider)) {
            throw "Registry provider initialization failed."
        }

        # Definieer de registry-sleutels om te verwijderen
        $regPaths = @(
            "Registry::HKEY_CLASSES_ROOT\$exitProgId",
            "Registry::HKEY_CLASSES_ROOT\$exitProgId\CLSID",
            "Registry::HKEY_CLASSES_ROOT\CLSID\$exitGuid",
            "Registry::HKEY_CLASSES_ROOT\CLSID\$exitGuid\InprocServer32",
            "Registry::HKEY_CLASSES_ROOT\CLSID\$exitGuid\ProgId",
            "Registry::HKEY_CLASSES_ROOT\CLSID\$exitGuid\Implemented Categories\{62C8FE65-4EBB-45E7-B440-6E39B2CDBF29}",
            "Registry::HKEY_CLASSES_ROOT\$exitManageProgId",
            "Registry::HKEY_CLASSES_ROOT\$exitManageProgId\CLSID",
            "Registry::HKEY_CLASSES_ROOT\CLSID\$exitManageGuid",
            "Registry::HKEY_CLASSES_ROOT\CLSID\$exitManageGuid\InprocServer32",
            "Registry::HKEY_CLASSES_ROOT\CLSID\$exitManageGuid\ProgId",
            "Registry::HKEY_CLASSES_ROOT\CLSID\$exitManageGuid\Implemented Categories\{62C8FE65-4EBB-45E7-B440-6E39B2CDBF29}"
        )

        foreach ($regPath in $regPaths) {
            if (Test-Path $regPath) {
                Write-Verbose "Removing registry key: $regPath"
                Remove-Item -Path $regPath -Recurse -Force -ErrorAction Stop
                Write-Verbose "Registry key $regPath verwijderd."
            }
            else {
                Write-Verbose "Registry key $regPath niet gevonden, overslaan."
            }
        }

        # Verifieer dat de sleutels zijn verwijderd
        $keyPath = "Registry::HKEY_CLASSES_ROOT\CLSID\$exitGuid\InprocServer32"
        if (Test-Path $keyPath) {
            Write-Error "Registry key $keyPath is niet verwijderd."
            throw "Unregistration verification failed"
        }
        Write-Verbose "COM unregistration successful"
    }
    catch {
        Write-Error "Failed to unregister COM components: $_"
        throw
    }
}

function Remove-FromCA {
    try {
        Write-Verbose "Removing module from Certification Authority"
        $regPolTemplate = $RegPolTemplateBase
        if (-not (Test-Path $regPolTemplate)) {
            Write-Error "Certification Authority registry path not found: $regPolTemplate"
            throw "Invalid registry path"
        }
        $activeCA = (Get-ItemProperty -Path $regPolTemplate -Name Active -ErrorAction Stop).Active
        if (-not $activeCA) {
            Write-Error "No active Certification Authority configuration found"
            throw "No active CA"
        }
        $regPolTemplate += "\$activeCA\ExitModules"
        $currentModules = (Get-ItemProperty -Path $regPolTemplate -Name Active -ErrorAction SilentlyContinue).Active
        if ($currentModules -and $currentModules -contains $exitProgId) {
            [string[]]$updatedModules = $currentModules | Where-Object { $_ -ne $exitProgId }
            if ($updatedModules.Count -eq 0) {
                Remove-Item -Path $regPolTemplate -Force -ErrorAction Stop
                Write-Verbose "ExitModules-sleutel verwijderd omdat deze leeg is."
            }
            else {
                Set-ItemProperty -Path $regPolTemplate -Name "Active" -Value $updatedModules -ErrorAction Stop
                Write-Verbose "Module $exitProgId verwijderd uit CA exit modules."
            }
        }
        else {
            Write-Verbose "Module $exitProgId niet gevonden in CA exit modules, geen actie ondernomen."
        }
    }
    catch {
        Write-Error "Failed to remove module from CA: $_"
        throw
    }
}

try {
    # Validate Certification Authority service
    if (-not (Get-Service -Name CertSvc -ErrorAction SilentlyContinue)) {
        Write-Error "Certification Authority service (CertSvc) is not installed."
        exit 1
    }
    # Check for admin privileges
    if (-not (Test-AdminPrivileges)) {
        Write-Error "This script requires local administrator privileges. Run it in an elevated PowerShell session."
        exit 1
    }

    # Unregister COM components
    Unregister-COM

    # Remove module from CA if not RegisterOnly
    if (-not $RegisterOnly) {
        Remove-FromCA
        if ($Restart) {
            try {
                Write-Verbose "Restarting Certification Authority service"
                Restart-Service -Name CertSvc -Force -ErrorAction Stop
                Write-Verbose "Certification Authority service restarted successfully"
            }
            catch {
                Write-Error "Failed to restart Certification Authority service: $_"
                exit 1
            }
        }
    }

    Write-Verbose "Script execution completed successfully"
}
catch {
    Write-Error "An unexpected error occurred: $_"
    exit 1
}