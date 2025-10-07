# PowerShell-script om AdcsCertificateApi te testen
# Version: 4.0 - Fixed verbose SQL parameter output, sequential tests with shared dynamic SerialNumber, compact logging

# Configuration (unchanged, included for context)
$script:Config = @{
    SqlServer           = "s98470a24b3a001.FRS98470.localdns.nl"
    ApiBaseUrl         = "https://adcscertificateapi.tenant47.minjenv.nl"
    LogFile            = "C:\Logs\AdcsCertificateApiTest.log"
    Database           = "AdcsCertificateDbV2"
    SqlScriptPath      = "Database\SQL-PKI-DB.sql"
    ClientCert         = $null  # Path to client certificate (PFX) if mTLS enabled
    CertPassword       = $null  # Password for PFX if needed
    CheckDotNetRuntime = $false # Set to $true if running on the webserver
    DebugJson          = $false # Set to $true for detailed JSON/response logging
}

# Shared test SerialNumber for sequential scenarios
$script:TestSerialNumber = $null

# Generate unique identifiers
function Get-UniqueSerialNumber {
    param([string]$Base = "test123")
    return "$Base_$((Get-Date -Format 'yyyyMMddHHmmssfff'))-$(Get-Random -Maximum 9999)"
}

function Get-UniqueRequestID {
    return [long](10000 + (Get-Random -Maximum 999999))  # Generate a smaller unique number within Int64 range
}

# Base JSON template
$script:JsonBase = [PSCustomObject]@{
    Data = [PSCustomObject]@{
        IssuerName = "CN=TestCA, O=minjenv, C=NL"
        SerialNumber = "test123"
        AdcsServerName = "S98470A47A5A002"
        Request_RequestID = 10000
        Disposition = 20
        SubmittedWhen = "2025-08-31T01:45:56Z"
        ResolvedWhen = $null
        RevokedWhen = $null
        RevokedEffectiveWhen = $null
        RevokedReason = $null
        RequesterName = "FRS98470\S98470A47A8A001$"
        CallerName = "TestCaller"
        NotBefore = "2025-08-31T01:45:56Z"
        NotAfter = "2026-08-31T01:45:56Z"
        SubjectKeyIdentifier = "3e54995d5685ff2b7d07e63c6b7fa24337a87c87"
        UPN = "testuser@FRS98470.localdns.nl"
        CommonName = "S98470A47A8A001.FRS98470.localdns.nl"
        DistinguishedName = "CN=S98470A47A8A001.FRS98470.localdns.nl, OU=jio, O=minjenv, C=NL"
        Organization = "minjenv"
        OrgUnit = "jio"
        Locality = "Amsterdam"
        State = "Noord-Holland"
        Title = "Test Title"
        GivenName = "Test"
        Initials = "T"
        SurName = "User"
        DomainComponent = "FRS98470.localdns.nl"
        EMail = "test@example.com"
        StreetAddress = "Test Street 123"
        UnstructuredName = "Test Unstructured"
        UnstructuredAddress = "Test Address"
        DeviceSerialNumber = "DEV123456"
        CertificateHash = "cfc661fb4dcee1433450b1236679228d78a0601d"
        PublicKeyLength = "2048"
        PublicKeyAlgorithm = "1.2.840.113549.1.1.1"
        TemplateOID = "1.3.6.1.4.1.311.21.7"
        TemplateName = "TestTemplate"
        Thumbprint = "cfc661fb4dcee1433450b1236679228d78a0601d"
        SignerPolicies = "DefaultPolicy"
        KeyRecoveryHashes = "NoRecovery"
        DispositionMessage = "Certificate issued"
        SignerApplicationPolicies = "AppPolicy1"
    }
    SANS = @()
    SubjectAttributes = @(
        @{
            AttributeType = "CommonName"
            AttributeValue = "S98470A47A8A001.FRS98470.localdns.nl"
        },
        @{
            AttributeType = "Organization"
            AttributeValue = "minjenv"
        }
    )
}

# Function to generate JSON payload
function Get-JsonPayload {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SerialNumber,
        [long]$Disposition = 20,
        [array]$SANS = @(),
        [array]$SubjectAttributes = @(),
        [hashtable]$Overrides = @{}
    )
    Write-Log "Generating JSON payload for SerialNumber: $SerialNumber, Disposition: $Disposition" -Level "DEBUG"
    try {
        # Create a deep copy of JsonBase
        $payload = [PSCustomObject]@{
            Data = [PSCustomObject]($script:JsonBase.Data | Select-Object *)
            SANS = $SANS
            SubjectAttributes = $SubjectAttributes
        }
        # Update required fields
        $payload.Data.SerialNumber = $SerialNumber
        $payload.Data.Disposition = $Disposition
        $payload.Data.Request_RequestID = Get-UniqueRequestID

        # Apply overrides
        foreach ($key in $Overrides.Keys) {
            if ($payload.Data.PSObject.Properties.Name -contains $key) {
                $payload.Data.$key = $Overrides[$key]
            } else {
                Write-Log "Invalid override key: $key" -Level "WARN"
            }
        }

        $json = $payload | ConvertTo-Json -Depth 10
        if ($script:Config.DebugJson) {
            Write-Log "Generated JSON: $json" -Level "DEBUG"
        }
        return $json
    } catch {
        Write-Log "Error generating JSON payload: $($_.Exception.Message)" -Level "ERROR"
        Write-Log "Failed JSON payload: $json" -Level "DEBUG"
        throw
    }
}

# Logging function
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG")]
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
    try {
        Add-Content -Path $script:Config.LogFile -Value $logMessage -ErrorAction Stop
    } catch {
        Write-Warning "Cannot write to log file: $($_.Exception.Message)"
    }
}

# Initialize log directory
function Initialize-LogDirectory {
    $logDir = Split-Path $script:Config.LogFile -Parent
    if (-not (Test-Path $logDir)) {
        try {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
            Write-Log "Log directory created: $logDir" -Level "INFO"
        } catch {
            Write-Log "Error creating log directory: $($_.Exception.Message)" -Level "ERROR"
            throw
        }
    }
}

# Get WebClient for mTLS (if needed)
function Get-WebClient {
    $client = New-Object System.Net.WebClient
    if ($script:Config.ClientCert -and (Test-Path $script:Config.ClientCert)) {
        try {
            $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
            if ($script:Config.CertPassword) {
                $cert.Import($script:Config.ClientCert, $script:Config.CertPassword, 'DefaultKeySet')
            } else {
                $cert.Import($script:Config.ClientCert)
            }
            $client.ClientCertificates.Add($cert) | Out-Null
            Write-Log "Client certificate loaded: $($script:Config.ClientCert)" -Level "INFO"
        } catch {
            Write-Log "Error loading client certificate: $($_.Exception.Message)" -Level "ERROR"
            throw
        }
    }
    return $client
}

# Test server connectivity
function Test-ServerConnection {
    param($Url)
    Write-Log "Checking server connectivity: $Url" -Level "INFO"
    try {
        $uri = New-Object System.Uri($Url)
        Test-NetConnection -ComputerName $uri.Host -Port 443 -InformationLevel Quiet -ErrorAction Stop
        Write-Log "Server is reachable on port 443" -Level "INFO"
        return $true
    } catch {
        Write-Log "Error: Cannot reach server: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# Test API endpoint
function Test-ApiEndpoint {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Uri,
        [string]$Method = "GET",
        [string]$Body = $null,
        [string]$ContentType = "application/json"
    )
    Write-Log "Testing endpoint: $Uri (Method: $Method)" -Level "INFO"
    if ($Body -and $script:Config.DebugJson) {
        Write-Log "JSON payload: $Body" -Level "DEBUG"
    }
    try {
        $headers = @{ "Content-Type" = $ContentType }
        $response = if ($Method -eq "POST") {
            Invoke-RestMethod -Uri $Uri -Method Post -Body $Body -Headers $headers -ErrorAction Stop
        } else {
            Invoke-RestMethod -Uri $Uri -Method Get -Headers $headers -ErrorAction Stop
        }
        if ($Method -eq "GET" -and $Uri -like "*expiring*") {
            Write-Log "Endpoint successful. Response count: $($response.Count)" -Level "INFO"
        } else {
            Write-Log "Endpoint successful" -Level "INFO"
        }
        if ($script:Config.DebugJson) {
            Write-Log "Response: $(ConvertTo-Json $response -Depth 3)" -Level "DEBUG"
        }
        return [PSCustomObject]@{
            Success = $true
            StatusCode = 200
            Response = $response
        }
    } catch [System.Net.WebException] {
        $responseStream = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($responseStream)
        $responseBody = $reader.ReadToEnd()
        $reader.Close()
        $statusCode = [int]$_.Exception.Response.StatusCode
        Write-Log "Error at endpoint: Status $statusCode. Body: $responseBody" -Level "ERROR"
        if ($script:Config.DebugJson) {
            Write-Log "Failed request body: $Body" -Level "DEBUG"
        }
        if ($statusCode -eq 503 -or $statusCode -eq 500) {
            Write-Log "Possible cause: ASP.NET Core 8.0 runtime not installed. Install .NET 8.0 Hosting Bundle from https://dotnet.microsoft.com/download/dotnet/8.0" -Level "ERROR"
            Write-Log "Check Event Viewer (eventvwr) for .NET Runtime or IIS errors" -Level "INFO"
        }
        Write-Log "Check IIS logs in C:\inetpub\logs\LogFiles" -Level "INFO"
        Write-Log "Check application logs in C:\Logs\AdcsCertificateApi.log" -Level "INFO"
        Write-Log "Check stdout logs in C:\inetpub\AdcsCertificateApi\logs\stdout_*.log" -Level "INFO"
        return [PSCustomObject]@{
            Success = $false
            StatusCode = $statusCode
            Response = $responseBody
        }
    } catch {
        Write-Log "Error at endpoint: $($_.Exception.Message)" -Level "ERROR"
        if ($script:Config.DebugJson) {
            Write-Log "Failed request body: $Body" -Level "DEBUG"
        }
        return [PSCustomObject]@{
            Success = $false
            StatusCode = 0
            Response = $_.Exception.Message
        }
    }
}

# Test .NET 8.0 runtime (optional)
function Test-DotNetRuntime {
    Write-Log "Checking installed .NET 8.0 runtimes" -Level "INFO"
    try {
        $runtimes = & dotnet --list-runtimes
        Write-Log "Installed runtimes: $runtimes" -Level "INFO"
        if ($runtimes -notlike "*Microsoft.AspNetCore.App 8.0*") {
            Write-Log "Microsoft.AspNetCore.App 8.0 runtime not found. Install .NET 8.0 Hosting Bundle from https://dotnet.microsoft.com/download/dotnet/8.0" -Level "ERROR"
            return $false
        }
        return $true
    } catch {
        Write-Log "Error checking runtimes: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# Initialize database with SQL script
function Initialize-Database {
    Write-Log "Checking and initializing database: $($script:Config.Database)" -Level "INFO"
    try {
        # Use the target database directly
        $connectionString = "Server=$($script:Config.SqlServer);Database=$($script:Config.Database);Trusted_Connection=True;TrustServerCertificate=True;"
        $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        $connection.Open()

        # Check if CAs table exists
        $checkTableQuery = "SELECT 1 FROM sys.tables WHERE name = 'CAs'"
        $checkTableCommand = New-Object System.Data.SqlClient.SqlCommand($checkTableQuery, $connection)
        $tableExists = $checkTableCommand.ExecuteScalar()

        if (-not $tableExists) {
            Write-Log "CAs table does not exist in database $($script:Config.Database), initializing with SQL script" -Level "INFO"
            $sqlScriptPath = Join-Path (Split-Path $PSCommandPath -Parent) $script:Config.SqlScriptPath
            if (-not (Test-Path $sqlScriptPath)) {
                Write-Log "SQL script not found at: $sqlScriptPath" -Level "ERROR"
                throw "SQL script not found"
            }
            $sqlScript = Get-Content -Path $sqlScriptPath -Raw
            $command = New-Object System.Data.SqlClient.SqlCommand($sqlScript, $connection)
            $VerbosePreference = "SilentlyContinue"
            $DebugPreference = "SilentlyContinue"
            [void]$command.ExecuteNonQuery()
            $VerbosePreference = "Continue"
            $DebugPreference = "Continue"
            Write-Log "Database schema initialized successfully" -Level "INFO"
        } else {
            Write-Log "Database schema already exists" -Level "INFO"
        }

        # Add test data if not exists
        $testDataQueries = @(
            "IF NOT EXISTS (SELECT 1 FROM CAs WHERE AdcsServerName = 'S98470A47A5A002') INSERT INTO CAs (AdcsServerName, IssuerName) VALUES ('S98470A47A5A002', 'CN=TestCA, O=minjenv, C=NL');",
            "IF NOT EXISTS (SELECT 1 FROM CertificateTemplates WHERE TemplateOID = '1.3.6.1.4.1.311.21.7') INSERT INTO CertificateTemplates (TemplateName, TemplateOID) VALUES ('TestTemplate', '1.3.6.1.4.1.311.21.7');",
            "IF NOT EXISTS (SELECT 1 FROM AuthorizedServers WHERE RequesterName = 'FRS98470\S98470A47A8A001$') INSERT INTO AuthorizedServers (RequesterName, IsActive) VALUES ('FRS98470\S98470A47A8A001$', 1);"
        )
        $VerbosePreference = "SilentlyContinue"
        $DebugPreference = "SilentlyContinue"
        foreach ($query in $testDataQueries) {
            $command = New-Object System.Data.SqlClient.SqlCommand($query, $connection)
            [void]$command.ExecuteNonQuery()
        }
        $VerbosePreference = "Continue"
        $DebugPreference = "Continue"
        Write-Log "Test data added to CAs, CertificateTemplates, and AuthorizedServers" -Level "INFO"

        return $true
    } catch {
        Write-Log "Error initializing database: $($_.Exception.Message)" -Level "ERROR"
        throw
    } finally {
        if ($connection.State -eq 'Open') { $connection.Close() }
    }
}

# Test database connectivity
function Test-DatabaseConnectivity {
    Write-Log "Checking database connectivity" -Level "INFO"
    try {
        $connectionString = "Server=$($script:Config.SqlServer);Database=$($script:Config.Database);Trusted_Connection=True;TrustServerCertificate=True;"
        $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        $connection.Open()
        Write-Log "Database connection successful" -Level "INFO"
        return $true
    } catch {
        Write-Log "Error in database connectivity: $($_.Exception.Message)" -Level "ERROR"
        return $false
    } finally {
        if ($connection.State -eq 'Open') { $connection.Close() }
    }
}

# Test database content after insert
function Test-DatabaseConnection {
    param($SerialNumber)
    Write-Log "Checking database content for SerialNumber: $SerialNumber" -Level "INFO"
    try {
        $connectionString = "Server=$($script:Config.SqlServer);Database=$($script:Config.Database);Trusted_Connection=True;TrustServerCertificate=True;"
        $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        $command = New-Object System.Data.SqlClient.SqlCommand("SELECT * FROM CertificateLogs WHERE SerialNumber = @serial", $connection)
        $command.Parameters.AddWithValue("@serial", $SerialNumber)
        $connection.Open()
        $reader = $command.ExecuteReader()
        if ($reader.Read()) {
            Write-Log "Certificate found in database: Thumbprint = $($reader['Thumbprint'])" -Level "INFO"
            return $true
        } else {
            Write-Log "No certificate found in database for SerialNumber: $SerialNumber" -Level "WARN"
            return $false
        }
    } catch {
        Write-Log "Error checking database: $($_.Exception.Message)" -Level "ERROR"
        return $false
    } finally {
        if ($connection.State -eq 'Open') { $connection.Close() }
    }
}

# Test SANS table
function Test-SansTable {
    param($SerialNumber)
    Write-Log "Checking SANS for SerialNumber: $SerialNumber" -Level "INFO"
    try {
        $connectionString = "Server=$($script:Config.SqlServer);Database=$($script:Config.Database);Trusted_Connection=True;TrustServerCertificate=True;"
        $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        $command = New-Object System.Data.SqlClient.SqlCommand("SELECT COUNT(*) FROM CertificateSANS cs JOIN CertificateLogs cl ON cs.CertificateID = cl.CertificateID WHERE cl.SerialNumber = @serial", $connection)
        $command.Parameters.AddWithValue("@serial", $SerialNumber)
        $connection.Open()
        $count = $command.ExecuteScalar()
        Write-Log "Number of SANS entries: $count" -Level "INFO"
        return $count
    } catch {
        Write-Log "Error checking SANS: $($_.Exception.Message)" -Level "ERROR"
        return 0
    } finally {
        if ($connection.State -eq 'Open') { $connection.Close() }
    }
}

# Cleanup test data
function Remove-TestData {
    param($SerialNumber)
    Write-Log "Cleaning up test data for SerialNumber: $SerialNumber" -Level "INFO"
    try {
        $connectionString = "Server=$($script:Config.SqlServer);Database=$($script:Config.Database);Trusted_Connection=True;TrustServerCertificate=True;"
        $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        $connection.Open()

        # Delete related data in correct order due to foreign keys
        $commands = @(
            "DELETE FROM CertificateSANS WHERE CertificateID IN (SELECT CertificateID FROM CertificateLogs WHERE SerialNumber = @serial)",
            "DELETE FROM SubjectAttributes WHERE CertificateID IN (SELECT CertificateID FROM CertificateLogs WHERE SerialNumber = @serial)",
            "DELETE FROM CertificateBinaries WHERE CertificateID IN (SELECT CertificateID FROM CertificateLogs WHERE SerialNumber = @serial)",
            "DELETE FROM CertificateLogs WHERE SerialNumber = @serial"
        )
        $VerbosePreference = "SilentlyContinue"
        $DebugPreference = "SilentlyContinue"
        foreach ($cmd in $commands) {
            $command = New-Object System.Data.SqlClient.SqlCommand($cmd, $connection)
            [void]$command.Parameters.AddWithValue("@serial", $SerialNumber)
            [void]$command.ExecuteNonQuery()
        }
        $VerbosePreference = "Continue"
        $DebugPreference = "Continue"
        Write-Log "Test data successfully removed" -Level "INFO"
    } catch {
        Write-Log "Error cleaning up test data: $($_.Exception.Message)" -Level "ERROR"
    } finally {
        if ($connection.State -eq 'Open') { $connection.Close() }
    }
}

# Clean invalid DispositionMessage records
function Clean-InvalidDispositionMessages {
    Write-Log "Cleaning up CertificateLogs with NULL DispositionMessage" -Level "INFO"
    try {
        $connectionString = "Server=$($script:Config.SqlServer);Database=$($script:Config.Database);Trusted_Connection=True;TrustServerCertificate=True;"
        $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        $connection.Open()

        # Update NULL DispositionMessage to a default value
        $command = New-Object System.Data.SqlClient.SqlCommand
        $command.Connection = $connection
        $command.CommandText = @"
UPDATE CertificateLogs
SET DispositionMessage = 'Unknown'
WHERE DispositionMessage IS NULL;
"@
        $VerbosePreference = "SilentlyContinue"
        $DebugPreference = "SilentlyContinue"
        $rowsAffected = [void]$command.ExecuteNonQuery()
        $VerbosePreference = "Continue"
        $DebugPreference = "Continue"
        Write-Log "Updated $rowsAffected CertificateLogs records with NULL DispositionMessage" -Level "INFO"
    } catch {
        Write-Log "Error cleaning invalid DispositionMessage records: $($_.Exception.Message)" -Level "ERROR"
    } finally {
        if ($connection.State -eq 'Open') { $connection.Close() }
    }
}


# Setup test data (create a new certificate record)
function Setup-TestData {
    Write-Log "Setting up dynamic test data" -Level "INFO"
    $script:TestSerialNumber = Get-UniqueSerialNumber -Base "test123"
    Write-Log "Generated test SerialNumber: $script:TestSerialNumber" -Level "INFO"
    $overrides = @{
        Disposition = 20
        DispositionMessage = "Certificate issued"
    }
    $certPayload = Get-JsonPayload -SerialNumber $script:TestSerialNumber -Disposition 20 -Overrides $overrides -SANS @(
        @{
            SANSType = "dnsname"
            Value = "S98470A47A8A001.FRS98470.localdns.nl"
            OID = ""
        },
        @{
            SANSType = "userprincipalname"
            Value = "S98470A47A8A001$@FRS98470.localdns.nl"
            OID = "1.3.6.1.4.1.311.20.2.3"
        }
    )
    $response = Test-ApiEndpoint -Uri "$($script:Config.ApiBaseUrl)/api/CertificateData" -Method "POST" -Body $certPayload
    if ($response.Success -and $response.Response -eq "Certificate data stored successfully") {
        Write-Log "New test record created successfully for SerialNumber: $script:TestSerialNumber" -Level "INFO"
        # Validate database insert
        $dbResult = Test-DatabaseConnection -SerialNumber $script:TestSerialNumber
        if ($dbResult) {
            $sansCount = Test-SansTable -SerialNumber $script:TestSerialNumber
            Write-Log "Database validation successful (SANS count: $sansCount)" -Level "INFO"
        }
        return $true
    } else {
        Write-Log "Setup failed: $($response.Response)" -Level "ERROR"
        return $false
    }
}

# Test Store Certificate Data (/api/CertificateData) with scenarios
function Test-StoreCertificateData {
    param(
        [ValidateSet("duplicate", "update", "revocation")]
        [string]$Scenario,
        [switch]$Verbose = $false
    )
    if (-not $script:TestSerialNumber) {
        Write-Log "No test SerialNumber available. Run Setup-TestData first." -Level "ERROR"
        return $false
    }
    Write-Log "Testing Store Certificate Data with scenario: $Scenario using SerialNumber: $script:TestSerialNumber" -Level "INFO"
    $overrides = @{}

    switch ($Scenario) {
        "duplicate" {
            $overrides = @{
                Disposition = 20  # Match existing Disposition for Conflict
                DispositionMessage = "Certificate issued"
            }
        }
        "update" {
            $overrides = @{
                Disposition = 30
                NotAfter = "2027-08-31T01:45:56Z"
                DispositionMessage = "Certificate renewed"
            }
        }
        "revocation" {
            $overrides = @{
                Disposition = 21
                RevokedWhen = (Get-Date -Format "o")
                RevokedEffectiveWhen = (Get-Date -Format "o")
                RevokedReason = 0
                DispositionMessage = "Certificate revoked"
            }
        }
    }

    $certPayload = Get-JsonPayload -SerialNumber $script:TestSerialNumber -Disposition $overrides.Disposition -Overrides $overrides -SANS @(
        @{
            SANSType = "dnsname"
            Value = "S98470A47A8A001.FRS98470.localdns.nl"
            OID = ""
        },
        @{
            SANSType = "userprincipalname"
            Value = "S98470A47A8A001$@FRS98470.localdns.nl"
            OID = "1.3.6.1.4.1.311.20.2.3"
        }
    )

    $response = Test-ApiEndpoint -Uri "$($script:Config.ApiBaseUrl)/api/CertificateData" -Method "POST" -Body $certPayload

    switch ($Scenario) {
        "duplicate" {
            if ($response.StatusCode -eq 409 -and $response.Response -match "already exists with the same Disposition") {
                Write-Log "Duplicate detection successful (409 Conflict)" -Level "INFO"
                return $true
            } else {
                Write-Log "Duplicate test failed: $($response.Response)" -Level "ERROR"
                return $false
            }
        }
        "update" {
            if ($response.Success -and $response.Response -eq "Certificate data stored successfully") {
                Write-Log "Update successful" -Level "INFO"
                # Validate database update
                $dbResult = Test-DatabaseConnection -SerialNumber $script:TestSerialNumber
                if ($dbResult) {
                    Write-Log "Update database validation successful" -Level "INFO"
                }
                return $true
            } else {
                Write-Log "Update failed: $($response.Response)" -Level "ERROR"
                return $false
            }
        }
        "revocation" {
            if ($response.Success -and $response.Response -eq "Certificate data stored successfully") {
                Write-Log "Revocation successful" -Level "INFO"
                # Validate database update
                $dbResult = Test-DatabaseConnection -SerialNumber $script:TestSerialNumber
                if ($dbResult) {
                    Write-Log "Revocation database validation successful" -Level "INFO"
                }
                return $true
            } else {
                Write-Log "Revocation failed: $($response.Response)" -Level "ERROR"
                return $false
            }
        }
    }
}

# Test Basic Endpoint (/api/Test)
function Test-BasicEndpoint {
    param([switch]$Verbose = $false)
    Write-Log "Testing basic endpoint /api/Test" -Level "INFO"
    $response = Test-ApiEndpoint -Uri "$($script:Config.ApiBaseUrl)/api/Test"
    if ($response.Success -and $response.Response -eq "Test endpoint werkt") {
        Write-Log "Basic endpoint successful" -Level "INFO"
        return $true
    } else {
        Write-Log "Basic endpoint failed: $($response.Response)" -Level "ERROR"
        return $false
    }
}

# Test Validation Endpoint (/api/Test/validate)
function Test-ValidationEndpoint {
    param([switch]$Verbose = $false)
    Write-Log "Testing validation endpoint /api/Test/validate" -Level "INFO"
    $serialNumber = Get-UniqueSerialNumber
    $testPayload = Get-JsonPayload -SerialNumber $serialNumber -Disposition 20
    $response = Test-ApiEndpoint -Uri "$($script:Config.ApiBaseUrl)/api/Test/validate" -Method "POST" -Body $testPayload
    if ($response.Success -and $response.Response -eq "JSON-body is geldig") {
        Write-Log "Validation endpoint successful" -Level "INFO"
        return $true
    } else {
        Write-Log "Validation endpoint failed: $($response.Response)" -Level "ERROR"
        return $false
    }
}

# Test Expiring Certificates Endpoint (/api/Certificates/expiring)
function Test-ExpiringCertificatesEndpoint {
    param([switch]$Verbose = $false)
    Write-Log "Testing expiring certificates endpoint /api/Certificates/expiring" -Level "INFO"
    $serialNumber = Get-UniqueSerialNumber -Base "test_expire"
    try {
        # Cleanup existing test data
        Remove-TestData -SerialNumber $serialNumber

        # Clean invalid DispositionMessage records
        Clean-InvalidDispositionMessages

        # Add test data with NotAfter within 30 days
        $connectionString = "Server=$($script:Config.SqlServer);Database=$($script:Config.Database);Trusted_Connection=True;TrustServerCertificate=True;"
        $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        $connection.Open()
        $command = New-Object System.Data.SqlClient.SqlCommand
        $command.Connection = $connection
        $command.CommandText = @"
INSERT INTO CertificateLogs (AdcsServerName, SerialNumber, Request_RequestID, Disposition, SubmittedWhen, NotBefore, NotAfter, TemplateID, Thumbprint, SignerPolicies, KeyRecoveryHashes, DispositionMessage, SignerApplicationPolicies, RequesterName, CallerName)
VALUES ('S98470A47A5A002', @serial, @requestId, 20, GETDATE(), GETDATE(), DATEADD(day, 29, GETDATE()), 1, 'cfc661fb4dcee1433450b1236679228d78a0601d', 'DefaultPolicy', 'NoRecovery', 'Certificate issued', 'AppPolicy1', 'FRS98470\S98470A47A8A001$', 'TestCaller');
"@
        [void]$command.Parameters.AddWithValue("@serial", $serialNumber)
        [void]$command.Parameters.AddWithValue("@requestId", (Get-UniqueRequestID))
        $VerbosePreference = "SilentlyContinue"
        $DebugPreference = "SilentlyContinue"
        [void]$command.ExecuteNonQuery()
        $VerbosePreference = "Continue"
        $DebugPreference = "Continue"
        Write-Log "Test data added for expiring certificates: SerialNumber = $serialNumber" -Level "INFO"
        $connection.Close()
    } catch {
        Write-Log "Error adding test data for expiring: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }

    $response = Test-ApiEndpoint -Uri "$($script:Config.ApiBaseUrl)/api/Certificates/expiring"
    if ($response.Success -and $response.Response -ne $null) {
        Write-Log "Expiring endpoint successful. Number of certificates: $($response.Response.Count)" -Level "INFO"
        return $true
    } else {
        Write-Log "Expiring endpoint failed or empty: $($response.Response)" -Level "ERROR"
        return $false
    }
}

# Main script execution
try {
    Initialize-LogDirectory

    # Check .NET 8.0 runtime (optional)
    if ($script:Config.CheckDotNetRuntime) {
        if (-not (Test-DotNetRuntime)) {
            Write-Log "Test aborted due to missing .NET 8.0 runtimes" -Level "ERROR"
            exit 1
        }
    } else {
        Write-Log "Skipping .NET runtime check (not running on webserver)" -Level "INFO"
    }

    # Initialize database
    if (-not (Initialize-Database)) {
        Write-Log "Test aborted due to database initialization problems" -Level "ERROR"
        exit 1
    }

    # Test database connectivity
    if (-not (Test-DatabaseConnectivity)) {
        Write-Log "Test aborted due to database connectivity problems" -Level "ERROR"
        exit 1
    }

    # Test server connectivity
    if (-not (Test-ServerConnection -Url $script:Config.ApiBaseUrl)) {
        Write-Log "Server not reachable, test aborted" -Level "ERROR"
        exit 1
    }

    # Run individual tests sequentially
    $allTestsPassed = $true

    # Basic endpoint test
    if (-not (Test-BasicEndpoint)) {
        $allTestsPassed = $false
    }

    # Validation endpoint test
    if (-not (Test-ValidationEndpoint)) {
        $allTestsPassed = $false
    }

    # Setup test data (create a new certificate record)
    if (-not (Setup-TestData)) {
        $allTestsPassed = $false
        Write-Log "Setup test data failed, skipping sequential tests" -Level "ERROR"
    } else {
        # Sequential Store Certificate Data tests
        Write-Log "Running sequential Store Certificate Data tests with SerialNumber: $script:TestSerialNumber" -Level "INFO"
        if (-not (Test-StoreCertificateData -Scenario "duplicate")) {
            $allTestsPassed = $false
        }
        if (-not (Test-StoreCertificateData -Scenario "update")) {
            $allTestsPassed = $false
        }
        if (-not (Test-StoreCertificateData -Scenario "revocation")) {
            $allTestsPassed = $false
        }
    }

    # Expiring certificates test
    if (-not (Test-ExpiringCertificatesEndpoint)) {
        $allTestsPassed = $false
    }

    if ($allTestsPassed) {
        Write-Log "All tests passed successfully" -Level "INFO"
    } else {
        Write-Log "Some tests failed. Check logs for details" -Level "WARN"
    }

    Write-Log "Test completed" -Level "INFO"
} catch {
    Write-Log "Unexpected error in main script: $($_.Exception.Message)" -Level "ERROR"
    exit 1
} finally {
    # Cleanup test data
    if ($script:TestSerialNumber) {
        Remove-TestData -SerialNumber $script:TestSerialNumber
        Write-Log "Cleanup completed for SerialNumber: $script:TestSerialNumber" -Level "INFO"
    }
}# PowerShell-script om AdcsCertificateApi te testen
# Version: 4.0 - Fixed verbose SQL parameter output, sequential tests with shared dynamic SerialNumber, compact logging

# Configuration (unchanged, included for context)
$script:Config = @{
    SqlServer           = "s98470a24b3a001.FRS98470.localdns.nl"
    ApiBaseUrl         = "https://adcscertificateapi.tenant47.minjenv.nl"
    LogFile            = "C:\Logs\AdcsCertificateApiTest.log"
    Database           = "AdcsCertificateDbV2"
    SqlScriptPath      = "Database\SQL-PKI-DB.sql"
    ClientCert         = $null  # Path to client certificate (PFX) if mTLS enabled
    CertPassword       = $null  # Password for PFX if needed
    CheckDotNetRuntime = $false # Set to $true if running on the webserver
    DebugJson          = $false # Set to $true for detailed JSON/response logging
}

# Shared test SerialNumber for sequential scenarios
$script:TestSerialNumber = $null

# Generate unique identifiers
function Get-UniqueSerialNumber {
    param([string]$Base = "test123")
    return "$Base_$((Get-Date -Format 'yyyyMMddHHmmssfff'))-$(Get-Random -Maximum 9999)"
}

function Get-UniqueRequestID {
    return [long](10000 + (Get-Random -Maximum 999999))  # Generate a smaller unique number within Int64 range
}

# Base JSON template
$script:JsonBase = [PSCustomObject]@{
    Data = [PSCustomObject]@{
        IssuerName = "CN=TestCA, O=minjenv, C=NL"
        SerialNumber = "test123"
        AdcsServerName = "S98470A47A5A002"
        Request_RequestID = 10000
        Disposition = 20
        SubmittedWhen = "2025-08-31T01:45:56Z"
        ResolvedWhen = $null
        RevokedWhen = $null
        RevokedEffectiveWhen = $null
        RevokedReason = $null
        RequesterName = "FRS98470\S98470A47A8A001$"
        CallerName = "TestCaller"
        NotBefore = "2025-08-31T01:45:56Z"
        NotAfter = "2026-08-31T01:45:56Z"
        SubjectKeyIdentifier = "3e54995d5685ff2b7d07e63c6b7fa24337a87c87"
        UPN = "testuser@FRS98470.localdns.nl"
        CommonName = "S98470A47A8A001.FRS98470.localdns.nl"
        DistinguishedName = "CN=S98470A47A8A001.FRS98470.localdns.nl, OU=jio, O=minjenv, C=NL"
        Organization = "minjenv"
        OrgUnit = "jio"
        Locality = "Amsterdam"
        State = "Noord-Holland"
        Title = "Test Title"
        GivenName = "Test"
        Initials = "T"
        SurName = "User"
        DomainComponent = "FRS98470.localdns.nl"
        EMail = "test@example.com"
        StreetAddress = "Test Street 123"
        UnstructuredName = "Test Unstructured"
        UnstructuredAddress = "Test Address"
        DeviceSerialNumber = "DEV123456"
        CertificateHash = "cfc661fb4dcee1433450b1236679228d78a0601d"
        PublicKeyLength = "2048"
        PublicKeyAlgorithm = "1.2.840.113549.1.1.1"
        TemplateOID = "1.3.6.1.4.1.311.21.7"
        TemplateName = "TestTemplate"
        Thumbprint = "cfc661fb4dcee1433450b1236679228d78a0601d"
        SignerPolicies = "DefaultPolicy"
        KeyRecoveryHashes = "NoRecovery"
        DispositionMessage = "Certificate issued"
        SignerApplicationPolicies = "AppPolicy1"
    }
    SANS = @()
    SubjectAttributes = @(
        @{
            AttributeType = "CommonName"
            AttributeValue = "S98470A47A8A001.FRS98470.localdns.nl"
        },
        @{
            AttributeType = "Organization"
            AttributeValue = "minjenv"
        }
    )
}

# Function to generate JSON payload
function Get-JsonPayload {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SerialNumber,
        [long]$Disposition = 20,
        [array]$SANS = @(),
        [array]$SubjectAttributes = @(),
        [hashtable]$Overrides = @{}
    )
    Write-Log "Generating JSON payload for SerialNumber: $SerialNumber, Disposition: $Disposition" -Level "DEBUG"
    try {
        # Create a deep copy of JsonBase
        $payload = [PSCustomObject]@{
            Data = [PSCustomObject]($script:JsonBase.Data | Select-Object *)
            SANS = $SANS
            SubjectAttributes = $SubjectAttributes
        }
        # Update required fields
        $payload.Data.SerialNumber = $SerialNumber
        $payload.Data.Disposition = $Disposition
        $payload.Data.Request_RequestID = Get-UniqueRequestID

        # Apply overrides
        foreach ($key in $Overrides.Keys) {
            if ($payload.Data.PSObject.Properties.Name -contains $key) {
                $payload.Data.$key = $Overrides[$key]
            } else {
                Write-Log "Invalid override key: $key" -Level "WARN"
            }
        }

        $json = $payload | ConvertTo-Json -Depth 10
        if ($script:Config.DebugJson) {
            Write-Log "Generated JSON: $json" -Level "DEBUG"
        }
        return $json
    } catch {
        Write-Log "Error generating JSON payload: $($_.Exception.Message)" -Level "ERROR"
        Write-Log "Failed JSON payload: $json" -Level "DEBUG"
        throw
    }
}

# Logging function
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG")]
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
    try {
        Add-Content -Path $script:Config.LogFile -Value $logMessage -ErrorAction Stop
    } catch {
        Write-Warning "Cannot write to log file: $($_.Exception.Message)"
    }
}

# Initialize log directory
function Initialize-LogDirectory {
    $logDir = Split-Path $script:Config.LogFile -Parent
    if (-not (Test-Path $logDir)) {
        try {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
            Write-Log "Log directory created: $logDir" -Level "INFO"
        } catch {
            Write-Log "Error creating log directory: $($_.Exception.Message)" -Level "ERROR"
            throw
        }
    }
}

# Get WebClient for mTLS (if needed)
function Get-WebClient {
    $client = New-Object System.Net.WebClient
    if ($script:Config.ClientCert -and (Test-Path $script:Config.ClientCert)) {
        try {
            $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
            if ($script:Config.CertPassword) {
                $cert.Import($script:Config.ClientCert, $script:Config.CertPassword, 'DefaultKeySet')
            } else {
                $cert.Import($script:Config.ClientCert)
            }
            $client.ClientCertificates.Add($cert) | Out-Null
            Write-Log "Client certificate loaded: $($script:Config.ClientCert)" -Level "INFO"
        } catch {
            Write-Log "Error loading client certificate: $($_.Exception.Message)" -Level "ERROR"
            throw
        }
    }
    return $client
}

# Test server connectivity
function Test-ServerConnection {
    param($Url)
    Write-Log "Checking server connectivity: $Url" -Level "INFO"
    try {
        $uri = New-Object System.Uri($Url)
        Test-NetConnection -ComputerName $uri.Host -Port 443 -InformationLevel Quiet -ErrorAction Stop
        Write-Log "Server is reachable on port 443" -Level "INFO"
        return $true
    } catch {
        Write-Log "Error: Cannot reach server: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# Test API endpoint
function Test-ApiEndpoint {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Uri,
        [string]$Method = "GET",
        [string]$Body = $null,
        [string]$ContentType = "application/json"
    )
    Write-Log "Testing endpoint: $Uri (Method: $Method)" -Level "INFO"
    if ($Body -and $script:Config.DebugJson) {
        Write-Log "JSON payload: $Body" -Level "DEBUG"
    }
    try {
        $headers = @{ "Content-Type" = $ContentType }
        $response = if ($Method -eq "POST") {
            Invoke-RestMethod -Uri $Uri -Method Post -Body $Body -Headers $headers -ErrorAction Stop
        } else {
            Invoke-RestMethod -Uri $Uri -Method Get -Headers $headers -ErrorAction Stop
        }
        if ($Method -eq "GET" -and $Uri -like "*expiring*") {
            Write-Log "Endpoint successful. Response count: $($response.Count)" -Level "INFO"
        } else {
            Write-Log "Endpoint successful" -Level "INFO"
        }
        if ($script:Config.DebugJson) {
            Write-Log "Response: $(ConvertTo-Json $response -Depth 3)" -Level "DEBUG"
        }
        return [PSCustomObject]@{
            Success = $true
            StatusCode = 200
            Response = $response
        }
    } catch [System.Net.WebException] {
        $responseStream = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($responseStream)
        $responseBody = $reader.ReadToEnd()
        $reader.Close()
        $statusCode = [int]$_.Exception.Response.StatusCode
        Write-Log "Error at endpoint: Status $statusCode. Body: $responseBody" -Level "ERROR"
        if ($script:Config.DebugJson) {
            Write-Log "Failed request body: $Body" -Level "DEBUG"
        }
        if ($statusCode -eq 503 -or $statusCode -eq 500) {
            Write-Log "Possible cause: ASP.NET Core 8.0 runtime not installed. Install .NET 8.0 Hosting Bundle from https://dotnet.microsoft.com/download/dotnet/8.0" -Level "ERROR"
            Write-Log "Check Event Viewer (eventvwr) for .NET Runtime or IIS errors" -Level "INFO"
        }
        Write-Log "Check IIS logs in C:\inetpub\logs\LogFiles" -Level "INFO"
        Write-Log "Check application logs in C:\Logs\AdcsCertificateApi.log" -Level "INFO"
        Write-Log "Check stdout logs in C:\inetpub\AdcsCertificateApi\logs\stdout_*.log" -Level "INFO"
        return [PSCustomObject]@{
            Success = $false
            StatusCode = $statusCode
            Response = $responseBody
        }
    } catch {
        Write-Log "Error at endpoint: $($_.Exception.Message)" -Level "ERROR"
        if ($script:Config.DebugJson) {
            Write-Log "Failed request body: $Body" -Level "DEBUG"
        }
        return [PSCustomObject]@{
            Success = $false
            StatusCode = 0
            Response = $_.Exception.Message
        }
    }
}

# Test .NET 8.0 runtime (optional)
function Test-DotNetRuntime {
    Write-Log "Checking installed .NET 8.0 runtimes" -Level "INFO"
    try {
        $runtimes = & dotnet --list-runtimes
        Write-Log "Installed runtimes: $runtimes" -Level "INFO"
        if ($runtimes -notlike "*Microsoft.AspNetCore.App 8.0*") {
            Write-Log "Microsoft.AspNetCore.App 8.0 runtime not found. Install .NET 8.0 Hosting Bundle from https://dotnet.microsoft.com/download/dotnet/8.0" -Level "ERROR"
            return $false
        }
        return $true
    } catch {
        Write-Log "Error checking runtimes: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# Initialize database with SQL script
function Initialize-Database {
    Write-Log "Checking and initializing database: $($script:Config.Database)" -Level "INFO"
    try {
        # Use the target database directly
        $connectionString = "Server=$($script:Config.SqlServer);Database=$($script:Config.Database);Trusted_Connection=True;TrustServerCertificate=True;"
        $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        $connection.Open()

        # Check if CAs table exists
        $checkTableQuery = "SELECT 1 FROM sys.tables WHERE name = 'CAs'"
        $checkTableCommand = New-Object System.Data.SqlClient.SqlCommand($checkTableQuery, $connection)
        $tableExists = $checkTableCommand.ExecuteScalar()

        if (-not $tableExists) {
            Write-Log "CAs table does not exist in database $($script:Config.Database), initializing with SQL script" -Level "INFO"
            $sqlScriptPath = Join-Path (Split-Path $PSCommandPath -Parent) $script:Config.SqlScriptPath
            if (-not (Test-Path $sqlScriptPath)) {
                Write-Log "SQL script not found at: $sqlScriptPath" -Level "ERROR"
                throw "SQL script not found"
            }
            $sqlScript = Get-Content -Path $sqlScriptPath -Raw
            $command = New-Object System.Data.SqlClient.SqlCommand($sqlScript, $connection)
            $VerbosePreference = "SilentlyContinue"
            $DebugPreference = "SilentlyContinue"
            [void]$command.ExecuteNonQuery()
            $VerbosePreference = "Continue"
            $DebugPreference = "Continue"
            Write-Log "Database schema initialized successfully" -Level "INFO"
        } else {
            Write-Log "Database schema already exists" -Level "INFO"
        }

        # Add test data if not exists
        $testDataQueries = @(
            "IF NOT EXISTS (SELECT 1 FROM CAs WHERE AdcsServerName = 'S98470A47A5A002') INSERT INTO CAs (AdcsServerName, IssuerName) VALUES ('S98470A47A5A002', 'CN=TestCA, O=minjenv, C=NL');",
            "IF NOT EXISTS (SELECT 1 FROM CertificateTemplates WHERE TemplateOID = '1.3.6.1.4.1.311.21.7') INSERT INTO CertificateTemplates (TemplateName, TemplateOID) VALUES ('TestTemplate', '1.3.6.1.4.1.311.21.7');",
            "IF NOT EXISTS (SELECT 1 FROM AuthorizedServers WHERE RequesterName = 'FRS98470\S98470A47A8A001$') INSERT INTO AuthorizedServers (RequesterName, IsActive) VALUES ('FRS98470\S98470A47A8A001$', 1);"
        )
        $VerbosePreference = "SilentlyContinue"
        $DebugPreference = "SilentlyContinue"
        foreach ($query in $testDataQueries) {
            $command = New-Object System.Data.SqlClient.SqlCommand($query, $connection)
            [void]$command.ExecuteNonQuery()
        }
        $VerbosePreference = "Continue"
        $DebugPreference = "Continue"
        Write-Log "Test data added to CAs, CertificateTemplates, and AuthorizedServers" -Level "INFO"

        return $true
    } catch {
        Write-Log "Error initializing database: $($_.Exception.Message)" -Level "ERROR"
        throw
    } finally {
        if ($connection.State -eq 'Open') { $connection.Close() }
    }
}

# Test database connectivity
function Test-DatabaseConnectivity {
    Write-Log "Checking database connectivity" -Level "INFO"
    try {
        $connectionString = "Server=$($script:Config.SqlServer);Database=$($script:Config.Database);Trusted_Connection=True;TrustServerCertificate=True;"
        $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        $connection.Open()
        Write-Log "Database connection successful" -Level "INFO"
        return $true
    } catch {
        Write-Log "Error in database connectivity: $($_.Exception.Message)" -Level "ERROR"
        return $false
    } finally {
        if ($connection.State -eq 'Open') { $connection.Close() }
    }
}

# Test database content after insert
function Test-DatabaseConnection {
    param($SerialNumber)
    Write-Log "Checking database content for SerialNumber: $SerialNumber" -Level "INFO"
    try {
        $connectionString = "Server=$($script:Config.SqlServer);Database=$($script:Config.Database);Trusted_Connection=True;TrustServerCertificate=True;"
        $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        $command = New-Object System.Data.SqlClient.SqlCommand("SELECT * FROM CertificateLogs WHERE SerialNumber = @serial", $connection)
        $command.Parameters.AddWithValue("@serial", $SerialNumber)
        $connection.Open()
        $reader = $command.ExecuteReader()
        if ($reader.Read()) {
            Write-Log "Certificate found in database: Thumbprint = $($reader['Thumbprint'])" -Level "INFO"
            return $true
        } else {
            Write-Log "No certificate found in database for SerialNumber: $SerialNumber" -Level "WARN"
            return $false
        }
    } catch {
        Write-Log "Error checking database: $($_.Exception.Message)" -Level "ERROR"
        return $false
    } finally {
        if ($connection.State -eq 'Open') { $connection.Close() }
    }
}

# Test SANS table
function Test-SansTable {
    param($SerialNumber)
    Write-Log "Checking SANS for SerialNumber: $SerialNumber" -Level "INFO"
    try {
        $connectionString = "Server=$($script:Config.SqlServer);Database=$($script:Config.Database);Trusted_Connection=True;TrustServerCertificate=True;"
        $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        $command = New-Object System.Data.SqlClient.SqlCommand("SELECT COUNT(*) FROM CertificateSANS cs JOIN CertificateLogs cl ON cs.CertificateID = cl.CertificateID WHERE cl.SerialNumber = @serial", $connection)
        $command.Parameters.AddWithValue("@serial", $SerialNumber)
        $connection.Open()
        $count = $command.ExecuteScalar()
        Write-Log "Number of SANS entries: $count" -Level "INFO"
        return $count
    } catch {
        Write-Log "Error checking SANS: $($_.Exception.Message)" -Level "ERROR"
        return 0
    } finally {
        if ($connection.State -eq 'Open') { $connection.Close() }
    }
}

# Cleanup test data
function Remove-TestData {
    param($SerialNumber)
    Write-Log "Cleaning up test data for SerialNumber: $SerialNumber" -Level "INFO"
    try {
        $connectionString = "Server=$($script:Config.SqlServer);Database=$($script:Config.Database);Trusted_Connection=True;TrustServerCertificate=True;"
        $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        $connection.Open()

        # Delete related data in correct order due to foreign keys
        $commands = @(
            "DELETE FROM CertificateSANS WHERE CertificateID IN (SELECT CertificateID FROM CertificateLogs WHERE SerialNumber = @serial)",
            "DELETE FROM SubjectAttributes WHERE CertificateID IN (SELECT CertificateID FROM CertificateLogs WHERE SerialNumber = @serial)",
            "DELETE FROM CertificateBinaries WHERE CertificateID IN (SELECT CertificateID FROM CertificateLogs WHERE SerialNumber = @serial)",
            "DELETE FROM CertificateLogs WHERE SerialNumber = @serial"
        )
        $VerbosePreference = "SilentlyContinue"
        $DebugPreference = "SilentlyContinue"
        foreach ($cmd in $commands) {
            $command = New-Object System.Data.SqlClient.SqlCommand($cmd, $connection)
            [void]$command.Parameters.AddWithValue("@serial", $SerialNumber)
            [void]$command.ExecuteNonQuery()
        }
        $VerbosePreference = "Continue"
        $DebugPreference = "Continue"
        Write-Log "Test data successfully removed" -Level "INFO"
    } catch {
        Write-Log "Error cleaning up test data: $($_.Exception.Message)" -Level "ERROR"
    } finally {
        if ($connection.State -eq 'Open') { $connection.Close() }
    }
}

# Clean invalid DispositionMessage records
function Clean-InvalidDispositionMessages {
    Write-Log "Cleaning up CertificateLogs with NULL DispositionMessage" -Level "INFO"
    try {
        $connectionString = "Server=$($script:Config.SqlServer);Database=$($script:Config.Database);Trusted_Connection=True;TrustServerCertificate=True;"
        $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        $connection.Open()

        # Update NULL DispositionMessage to a default value
        $command = New-Object System.Data.SqlClient.SqlCommand
        $command.Connection = $connection
        $command.CommandText = @"
UPDATE CertificateLogs
SET DispositionMessage = 'Unknown'
WHERE DispositionMessage IS NULL;
"@
        $VerbosePreference = "SilentlyContinue"
        $DebugPreference = "SilentlyContinue"
        $rowsAffected = [void]$command.ExecuteNonQuery()
        $VerbosePreference = "Continue"
        $DebugPreference = "Continue"
        Write-Log "Updated $rowsAffected CertificateLogs records with NULL DispositionMessage" -Level "INFO"
    } catch {
        Write-Log "Error cleaning invalid DispositionMessage records: $($_.Exception.Message)" -Level "ERROR"
    } finally {
        if ($connection.State -eq 'Open') { $connection.Close() }
    }
}


# Setup test data (create a new certificate record)
function Setup-TestData {
    Write-Log "Setting up dynamic test data" -Level "INFO"
    $script:TestSerialNumber = Get-UniqueSerialNumber -Base "test123"
    Write-Log "Generated test SerialNumber: $script:TestSerialNumber" -Level "INFO"
    $overrides = @{
        Disposition = 20
        DispositionMessage = "Certificate issued"
    }
    $certPayload = Get-JsonPayload -SerialNumber $script:TestSerialNumber -Disposition 20 -Overrides $overrides -SANS @(
        @{
            SANSType = "dnsname"
            Value = "S98470A47A8A001.FRS98470.localdns.nl"
            OID = ""
        },
        @{
            SANSType = "userprincipalname"
            Value = "S98470A47A8A001$@FRS98470.localdns.nl"
            OID = "1.3.6.1.4.1.311.20.2.3"
        }
    )
    $response = Test-ApiEndpoint -Uri "$($script:Config.ApiBaseUrl)/api/CertificateData" -Method "POST" -Body $certPayload
    if ($response.Success -and $response.Response -eq "Certificate data stored successfully") {
        Write-Log "New test record created successfully for SerialNumber: $script:TestSerialNumber" -Level "INFO"
        # Validate database insert
        $dbResult = Test-DatabaseConnection -SerialNumber $script:TestSerialNumber
        if ($dbResult) {
            $sansCount = Test-SansTable -SerialNumber $script:TestSerialNumber
            Write-Log "Database validation successful (SANS count: $sansCount)" -Level "INFO"
        }
        return $true
    } else {
        Write-Log "Setup failed: $($response.Response)" -Level "ERROR"
        return $false
    }
}

# Test Store Certificate Data (/api/CertificateData) with scenarios
function Test-StoreCertificateData {
    param(
        [ValidateSet("duplicate", "update", "revocation")]
        [string]$Scenario,
        [switch]$Verbose = $false
    )
    if (-not $script:TestSerialNumber) {
        Write-Log "No test SerialNumber available. Run Setup-TestData first." -Level "ERROR"
        return $false
    }
    Write-Log "Testing Store Certificate Data with scenario: $Scenario using SerialNumber: $script:TestSerialNumber" -Level "INFO"
    $overrides = @{}

    switch ($Scenario) {
        "duplicate" {
            $overrides = @{
                Disposition = 20  # Match existing Disposition for Conflict
                DispositionMessage = "Certificate issued"
            }
        }
        "update" {
            $overrides = @{
                Disposition = 30
                NotAfter = "2027-08-31T01:45:56Z"
                DispositionMessage = "Certificate renewed"
            }
        }
        "revocation" {
            $overrides = @{
                Disposition = 21
                RevokedWhen = (Get-Date -Format "o")
                RevokedEffectiveWhen = (Get-Date -Format "o")
                RevokedReason = 0
                DispositionMessage = "Certificate revoked"
            }
        }
    }

    $certPayload = Get-JsonPayload -SerialNumber $script:TestSerialNumber -Disposition $overrides.Disposition -Overrides $overrides -SANS @(
        @{
            SANSType = "dnsname"
            Value = "S98470A47A8A001.FRS98470.localdns.nl"
            OID = ""
        },
        @{
            SANSType = "userprincipalname"
            Value = "S98470A47A8A001$@FRS98470.localdns.nl"
            OID = "1.3.6.1.4.1.311.20.2.3"
        }
    )

    $response = Test-ApiEndpoint -Uri "$($script:Config.ApiBaseUrl)/api/CertificateData" -Method "POST" -Body $certPayload

    switch ($Scenario) {
        "duplicate" {
            if ($response.StatusCode -eq 409 -and $response.Response -match "already exists with the same Disposition") {
                Write-Log "Duplicate detection successful (409 Conflict)" -Level "INFO"
                return $true
            } else {
                Write-Log "Duplicate test failed: $($response.Response)" -Level "ERROR"
                return $false
            }
        }
        "update" {
            if ($response.Success -and $response.Response -eq "Certificate data stored successfully") {
                Write-Log "Update successful" -Level "INFO"
                # Validate database update
                $dbResult = Test-DatabaseConnection -SerialNumber $script:TestSerialNumber
                if ($dbResult) {
                    Write-Log "Update database validation successful" -Level "INFO"
                }
                return $true
            } else {
                Write-Log "Update failed: $($response.Response)" -Level "ERROR"
                return $false
            }
        }
        "revocation" {
            if ($response.Success -and $response.Response -eq "Certificate data stored successfully") {
                Write-Log "Revocation successful" -Level "INFO"
                # Validate database update
                $dbResult = Test-DatabaseConnection -SerialNumber $script:TestSerialNumber
                if ($dbResult) {
                    Write-Log "Revocation database validation successful" -Level "INFO"
                }
                return $true
            } else {
                Write-Log "Revocation failed: $($response.Response)" -Level "ERROR"
                return $false
            }
        }
    }
}

# Test Basic Endpoint (/api/Test)
function Test-BasicEndpoint {
    param([switch]$Verbose = $false)
    Write-Log "Testing basic endpoint /api/Test" -Level "INFO"
    $response = Test-ApiEndpoint -Uri "$($script:Config.ApiBaseUrl)/api/Test"
    if ($response.Success -and $response.Response -eq "Test endpoint werkt") {
        Write-Log "Basic endpoint successful" -Level "INFO"
        return $true
    } else {
        Write-Log "Basic endpoint failed: $($response.Response)" -Level "ERROR"
        return $false
    }
}

# Test Validation Endpoint (/api/Test/validate)
function Test-ValidationEndpoint {
    param([switch]$Verbose = $false)
    Write-Log "Testing validation endpoint /api/Test/validate" -Level "INFO"
    $serialNumber = Get-UniqueSerialNumber
    $testPayload = Get-JsonPayload -SerialNumber $serialNumber -Disposition 20
    $response = Test-ApiEndpoint -Uri "$($script:Config.ApiBaseUrl)/api/Test/validate" -Method "POST" -Body $testPayload
    if ($response.Success -and $response.Response -eq "JSON-body is geldig") {
        Write-Log "Validation endpoint successful" -Level "INFO"
        return $true
    } else {
        Write-Log "Validation endpoint failed: $($response.Response)" -Level "ERROR"
        return $false
    }
}

# Test Expiring Certificates Endpoint (/api/Certificates/expiring)
function Test-ExpiringCertificatesEndpoint {
    param([switch]$Verbose = $false)
    Write-Log "Testing expiring certificates endpoint /api/Certificates/expiring" -Level "INFO"
    $serialNumber = Get-UniqueSerialNumber -Base "test_expire"
    try {
        # Cleanup existing test data
        Remove-TestData -SerialNumber $serialNumber

        # Clean invalid DispositionMessage records
        Clean-InvalidDispositionMessages

        # Add test data with NotAfter within 30 days
        $connectionString = "Server=$($script:Config.SqlServer);Database=$($script:Config.Database);Trusted_Connection=True;TrustServerCertificate=True;"
        $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        $connection.Open()
        $command = New-Object System.Data.SqlClient.SqlCommand
        $command.Connection = $connection
        $command.CommandText = @"
INSERT INTO CertificateLogs (AdcsServerName, SerialNumber, Request_RequestID, Disposition, SubmittedWhen, NotBefore, NotAfter, TemplateID, Thumbprint, SignerPolicies, KeyRecoveryHashes, DispositionMessage, SignerApplicationPolicies, RequesterName, CallerName)
VALUES ('S98470A47A5A002', @serial, @requestId, 20, GETDATE(), GETDATE(), DATEADD(day, 29, GETDATE()), 2, 'cfc661fb4dcee1433450b1236679228d78a0601d', 'DefaultPolicy', 'NoRecovery', 'Certificate issued', 'AppPolicy1', 'FRS98470\S98470A47A8A001$', 'TestCaller');
"@
        [void]$command.Parameters.AddWithValue("@serial", $serialNumber)
        [void]$command.Parameters.AddWithValue("@requestId", (Get-UniqueRequestID))
        $VerbosePreference = "SilentlyContinue"
        $DebugPreference = "SilentlyContinue"
        [void]$command.ExecuteNonQuery()
        $VerbosePreference = "Continue"
        $DebugPreference = "Continue"
        Write-Log "Test data added for expiring certificates: SerialNumber = $serialNumber" -Level "INFO"
        $connection.Close()
    } catch {
        Write-Log "Error adding test data for expiring: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }

    $response = Test-ApiEndpoint -Uri "$($script:Config.ApiBaseUrl)/api/Certificates/expiring"
    if ($response.Success -and $response.Response -ne $null) {
        Write-Log "Expiring endpoint successful. Number of certificates: $($response.Response.Count)" -Level "INFO"
        return $true
    } else {
        Write-Log "Expiring endpoint failed or empty: $($response.Response)" -Level "ERROR"
        return $false
    }
}

# Main script execution
try {
    Initialize-LogDirectory

    # Check .NET 8.0 runtime (optional)
    if ($script:Config.CheckDotNetRuntime) {
        if (-not (Test-DotNetRuntime)) {
            Write-Log "Test aborted due to missing .NET 8.0 runtimes" -Level "ERROR"
            exit 1
        }
    } else {
        Write-Log "Skipping .NET runtime check (not running on webserver)" -Level "INFO"
    }

    # Initialize database
    if (-not (Initialize-Database)) {
        Write-Log "Test aborted due to database initialization problems" -Level "ERROR"
        exit 1
    }

    # Test database connectivity
    if (-not (Test-DatabaseConnectivity)) {
        Write-Log "Test aborted due to database connectivity problems" -Level "ERROR"
        exit 1
    }

    # Test server connectivity
    if (-not (Test-ServerConnection -Url $script:Config.ApiBaseUrl)) {
        Write-Log "Server not reachable, test aborted" -Level "ERROR"
        exit 1
    }

    # Run individual tests sequentially
    $allTestsPassed = $true

    # Basic endpoint test
    if (-not (Test-BasicEndpoint)) {
        $allTestsPassed = $false
    }

    # Validation endpoint test
    if (-not (Test-ValidationEndpoint)) {
        $allTestsPassed = $false
    }

    # Setup test data (create a new certificate record)
    if (-not (Setup-TestData)) {
        $allTestsPassed = $false
        Write-Log "Setup test data failed, skipping sequential tests" -Level "ERROR"
    } else {
        # Sequential Store Certificate Data tests
        Write-Log "Running sequential Store Certificate Data tests with SerialNumber: $script:TestSerialNumber" -Level "INFO"
        if (-not (Test-StoreCertificateData -Scenario "duplicate")) {
            $allTestsPassed = $false
        }
        if (-not (Test-StoreCertificateData -Scenario "update")) {
            $allTestsPassed = $false
        }
        if (-not (Test-StoreCertificateData -Scenario "revocation")) {
            $allTestsPassed = $false
        }
    }

    # Expiring certificates test
    if (-not (Test-ExpiringCertificatesEndpoint)) {
        $allTestsPassed = $false
    }

    if ($allTestsPassed) {
        Write-Log "All tests passed successfully" -Level "INFO"
    } else {
        Write-Log "Some tests failed. Check logs for details" -Level "WARN"
    }

    Write-Log "Test completed" -Level "INFO"
} catch {
    Write-Log "Unexpected error in main script: $($_.Exception.Message)" -Level "ERROR"
    exit 1
} finally {
    # Cleanup test data
    if ($script:TestSerialNumber) {
        Remove-TestData -SerialNumber $script:TestSerialNumber
        Write-Log "Cleanup completed for SerialNumber: $script:TestSerialNumber" -Level "INFO"
    }
}