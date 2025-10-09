# PowerShell 5.1 script om alle endpoints van de ManageController te testen
# Vereist Kerberos-authenticatie en lidmaatschap van FRS98470\grp98470c47-sys-l-A47-ManangeAPI

# Configuratie
$baseUrl = "https://adcscertificateapi.tenant47.minjenv.nl/api/Manage/AuthorizedServers"
$logPath = "C:\Logs\AdcsCertificateApi.log"

# Functie om HTTP-fouten te behandelen
function Handle-HttpError {
    param (
        [Parameter(Mandatory=$true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )
    $exception = $ErrorRecord.Exception
    if ($exception -is [System.Net.WebException]) {
        $webException = $exception
        $response = $webException.Response
        if ($response -is [System.Net.HttpWebResponse]) {
            $statusCode = [int]$response.StatusCode
            $statusDescription = $response.StatusDescription
            $requestUrl = $webException.Response.ResponseUri
            $requestMethod = $webException.Request.Method
            Write-Host "HTTP error occurred: $statusCode $statusDescription for $requestMethod $requestUrl" -ForegroundColor Red
            if ($statusCode -eq 401) {
                Write-Error "Authentication failed: Unauthorized access for $requestMethod $requestUrl. Ensure the current user ($env:USERNAME) is a member of FRS98470\grp98470c47-sys-l-A47-ManangeAPI."
            }
            elseif ($statusCode -eq 403) {
                Write-Error "Authorization failed: User lacks required permissions for $requestMethod $requestUrl."
            }
            elseif ($statusCode -eq 404) {
                Write-Error "Resource not found for $requestMethod $requestUrl."
            }
            elseif ($statusCode -eq 400) {
                Write-Error "Bad request: Invalid input data for $requestMethod $requestUrl."
            }
            elseif ($statusCode -eq 409) {
                Write-Error "Conflict: Resource already exists for $requestMethod $requestUrl."
            }
            else {
                Write-Error "HTTP error: $statusCode $statusDescription for $requestMethod $requestUrl"
                Write-Host "Check the API log at $logPath for more details."
            }
        }
        else {
            Write-Error "Network error: $($exception.Message) for $requestMethod $requestUrl"
        }
    }
    else {
        Write-Error "Unexpected error: $($exception.Message)"
    }
}

# GET /api/Manage/AuthorizedServers
function Get-AllAuthorizedServers {
    try {
        $response = Invoke-RestMethod -Uri $baseUrl -Method Get -UseDefaultCredentials -ContentType "application/json"
        return $response
    }
    catch {
        Handle-HttpError -ErrorRecord $_
        return $null
    }
}

# GET /api/Manage/AuthorizedServers/{id}
function Get-AuthorizedServer {
    param (
        [Parameter(Mandatory=$true)]
        [long]$ServerId
    )
    $url = "$baseUrl/$ServerId"
    try {
        $response = Invoke-RestMethod -Uri $url -Method Get -UseDefaultCredentials -ContentType "application/json"
        return $response
    }
    catch {
        Handle-HttpError -ErrorRecord $_
        return $null
    }
}

# POST /api/Manage/AuthorizedServers
function New-AuthorizedServer {
    param (
        [Parameter(Mandatory=$true)]
        [string]$AdcsServerAccount,
        [Parameter(Mandatory=$true)]
        [string]$AdcsServerName,
        [Parameter(Mandatory=$true)]
        [string]$ServerGUID,
        [string]$Description = "",
        [bool]$IsActive = $true
    )
    $body = @{
        AdcsServerAccount = $AdcsServerAccount
        AdcsServerName = $AdcsServerName
        ServerGUID = $ServerGUID
        Description = $Description
        IsActive = $IsActive
    } | ConvertTo-Json

    try {
        $response = Invoke-RestMethod -Uri $baseUrl -Method Post -UseDefaultCredentials -ContentType "application/json" -Body $body
        return $response
    }
    catch {
        Handle-HttpError -ErrorRecord $_
        return $null
    }
}

# PUT /api/Manage/AuthorizedServers/{id}
function Update-AuthorizedServer {
    param (
        [Parameter(Mandatory=$true)]
        [long]$ServerId,
        [Parameter(Mandatory=$true)]
        [string]$AdcsServerAccount,
        [Parameter(Mandatory=$true)]
        [string]$AdcsServerName,
        [Parameter(Mandatory=$true)]
        [string]$ServerGUID,
        [string]$Description = "",
        [bool]$IsActive = $true
    )
    $url = "$baseUrl/$ServerId"
    $body = @{
        AdcsServerAccount = $AdcsServerAccount
        AdcsServerName = $AdcsServerName
        ServerGUID = $ServerGUID
        Description = $Description
        IsActive = $IsActive
    } | ConvertTo-Json

    try {
        $response = Invoke-RestMethod -Uri $url -Method Put -UseDefaultCredentials -ContentType "application/json" -Body $body
        return [PSCustomObject]@{ Status = "Success"; Message = "Successfully updated Authorized Server with ID: $ServerId" }
    }
    catch {
        Handle-HttpError -ErrorRecord $_
        return $null
    }
}

# PUT /api/Manage/AuthorizedServers/{id} (voor enable/disable)
function Set-AuthorizedServerActive {
    param (
        [Parameter(Mandatory=$true)]
        [long]$ServerId,
        [Parameter(Mandatory=$true)]
        [bool]$IsActive
    )
    $url = "$baseUrl/$ServerId"
    $server = Get-AuthorizedServer -ServerId $ServerId
    if ($null -eq $server) {
        Write-Error "Cannot set active status: Server with ID $ServerId not found."
        return $null
    }
    $body = @{
        AdcsServerAccount = $server.AdcsServerAccount
        AdcsServerName = $server.AdcsServerName
        ServerGUID = $server.ServerGUID
        Description = $server.Description
        IsActive = $IsActive
    } | ConvertTo-Json

    try {
        $response = Invoke-RestMethod -Uri $url -Method Put -UseDefaultCredentials -ContentType "application/json" -Body $body
        return [PSCustomObject]@{ Status = "Success"; Message = "Successfully set Authorized Server with ID: $ServerId to IsActive: $IsActive" }
    }
    catch {
        Handle-HttpError -ErrorRecord $_
        return $null
    }
}

# Voorbeeldgebruik van alle functies
try {
    Write-Host "Testing all ManageController endpoints..."
    Write-Host "========================================="

    # Reactiveer server ID 9
    Write-Host "Reactivating server ID 9..."
    Invoke-Sqlcmd -ServerInstance "s98470a24b3a001.frs98470.localdns.nl" -Database "AdcsCertificateDbV2" -Query "UPDATE AuthorizedServers SET IsActive = 1 WHERE ServerID = 9"
    Write-Host ""

    # Test GET /api/Manage/AuthorizedServers
    Write-Host "Testing GET /api/Manage/AuthorizedServers..."
    $allServers = Get-AllAuthorizedServers
    if ($null -eq $allServers -or $allServers.Count -eq 0) {
        Write-Host "No Authorized Servers found."
    }
    else {
        Write-Host "Retrieved $($allServers.Count) Authorized Servers:"
        $allServers | ForEach-Object {
            Write-Host "-----------------------------------------"
            Write-Host "ServerID: $($_.ServerID)"
            Write-Host "AdcsServerAccount: $($_.AdcsServerAccount)"
            Write-Host "AdcsServerName: $($_.AdcsServerName)"
            Write-Host "ServerGUID: $($_.ServerGUID)"
            Write-Host "Description: $($_.Description)"
            Write-Host "IsActive: $($_.IsActive)"
            Write-Host "CreatedAt: $($_.CreatedAt)"
        }
    }
    Write-Host ""

    # Test GET /api/Manage/AuthorizedServers/9
    Write-Host "Testing GET /api/Manage/AuthorizedServers/9..."
    $server = Get-AuthorizedServer -ServerId 9
    if ($null -eq $server) {
        Write-Host "Server with ID 9 not found."
    }
    else {
        Write-Host "Retrieved Authorized Server:"
        Write-Host "-----------------------------------------"
        Write-Host "ServerID: $($server.ServerID)"
        Write-Host "AdcsServerAccount: $($server.AdcsServerAccount)"
        Write-Host "AdcsServerName: $($server.AdcsServerName)"
        Write-Host "ServerGUID: $($server.ServerGUID)"
        Write-Host "Description: $($server.Description)"
        Write-Host "IsActive: $($server.IsActive)"
        Write-Host "CreatedAt: $($server.CreatedAt)"
    }
    Write-Host ""

    # Test POST /api/Manage/AuthorizedServers
    Write-Host "Testing POST /api/Manage/AuthorizedServers..."
    $newGuid = (New-Guid).ToString()
    $uniqueAccount = "svc-adcs-test-$(Get-Date -Format 'yyyyMMddHHmmss')"
    $uniqueName = "adcs-test-$(Get-Date -Format 'yyyyMMddHHmmss')"
    $newServer = New-AuthorizedServer -AdcsServerAccount $uniqueAccount -AdcsServerName $uniqueName -ServerGUID $newGuid -Description "Test Server $(Get-Date -Format 'yyyyMMddHHmmss')" -IsActive $true
    if ($null -eq $newServer) {
        Write-Host "Failed to create new Authorized Server."
    }
    else {
        Write-Host "Created Authorized Server:"
        Write-Host "-----------------------------------------"
        Write-Host "ServerID: $($newServer.ServerID)"
        Write-Host "AdcsServerAccount: $($newServer.AdcsServerAccount)"
        Write-Host "AdcsServerName: $($newServer.AdcsServerName)"
        Write-Host "ServerGUID: $($newServer.ServerGUID)"
        Write-Host "Description: $($newServer.Description)"
        Write-Host "IsActive: $($newServer.IsActive)"
        Write-Host "CreatedAt: $($newServer.CreatedAt)"
    }
    Write-Host ""

    # Test PUT /api/Manage/AuthorizedServers
    if ($newServer) {
        Write-Host "Testing PUT /api/Manage/AuthorizedServers/$($newServer.ServerID)..."
        $updatedServer = Update-AuthorizedServer -ServerId $newServer.ServerID -AdcsServerAccount $uniqueAccount -AdcsServerName $uniqueName -ServerGUID $newGuid -Description "Updated Test Server $(Get-Date -Format 'yyyyMMddHHmmss')" -IsActive $true
        if ($null -eq $updatedServer) {
            Write-Host "Failed to update Authorized Server with ID: $($newServer.ServerID)"
        }
        else {
            Write-Host $updatedServer.Message
        }
        Write-Host ""
    }

    # Test Enable /api/Manage/AuthorizedServers
    if ($newServer) {
        Write-Host "Testing Enable /api/Manage/AuthorizedServers/$($newServer.ServerID)..."
        $enableResult = Set-AuthorizedServerActive -ServerId $newServer.ServerID -IsActive $true
        if ($null -eq $enableResult) {
            Write-Host "Failed to enable Authorized Server with ID: $($newServer.ServerID)"
        }
        else {
            Write-Host $enableResult.Message
        }
        Write-Host ""
    }

    # Test Disable /api/Manage/AuthorizedServers
    if ($newServer) {
        Write-Host "Testing Disable /api/Manage/AuthorizedServers/$($newServer.ServerID)..."
        $disableResult = Set-AuthorizedServerActive -ServerId $newServer.ServerID -IsActive $false
        if ($null -eq $disableResult) {
            Write-Host "Failed to disable Authorized Server with ID: $($newServer.ServerID)"
        }
        else {
            Write-Host $disableResult.Message
        }
        Write-Host ""
    }
}