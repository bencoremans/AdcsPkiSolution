# Function: Add-AdcsAuthorizedServer
# Description: Adds an AuthorizedServer to the AdcsCertificateWebApi via the /api/Manage/AuthorizedServers endpoint
# Note: Ensure the SPN for the application pool gMSA account is correctly configured (e.g., HTTP/adcscertificateapi.tenant47.minjenv.nl) for Kerberos authentication.
# Note: The calling user must be a member (direct or nested) of the FRS98470\grp98470c47-sys-l-A47-ManangeAPI group in Active Directory.
# Note: Run this script under a user context with valid Kerberos credentials (e.g., frs00001\ba00001a02a0051) and verify group membership with Check-AdcsAdminsMembership.ps1.
# Note: If HTTP 401 Unauthorized errors occur, check the SPN (setspn -L FRS98470\S98470A47A8A001$) and Kerberos ticket cache (klist).
# Note: If HTTP 500.30 errors occur, check the Event Viewer (System/Application logs), stdout logs (C:\inetpub\AdcsCertificateApi\logs), and C:\Logs\AdcsCertificateApi.log for detailed errors.
# Note: The user account is in a trusted domain (frs00001.localdns.nl), ensure the domain is configured in appsettings.json and the trust relationship allows authentication.
function Add-AdcsAuthorizedServer {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "The ADCS server account name (e.g., S98470A47A5A003).")]
        [ValidateNotNullOrEmpty()]
        [ValidateLength(1, 50)]
        [string]$AdcsServerAccount,

        [Parameter(Mandatory = $true, HelpMessage = "The ADCS server name (e.g., S98470A47A5A003).")]
        [ValidateNotNullOrEmpty()]
        [ValidateLength(1, 50)]
        [string]$AdcsServerName,

        [Parameter(Mandatory = $true, HelpMessage = "The server GUID (e.g., c561cee0-d76f-404a-94fe-640cc0f7bc9d).")]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
        [string]$ServerGUID,

        [Parameter(HelpMessage = "Optional description for the server (max 4000 characters).")]
        [ValidateLength(0, 4000)]
        [string]$Description,

        [Parameter(HelpMessage = "Indicates if the server is active (default: true).")]
        [bool]$IsActive = $true,

        [Parameter(Mandatory = $true, HelpMessage = "The base URL of the ADCS Certificate API (e.g., https://adcscertificateapi.tenant47.minjenv.nl).")]
        [ValidateNotNullOrEmpty()]
        [string]$ApiBaseUrl,

        [Parameter(HelpMessage = "Timeout for the HTTP request in seconds (default: 30).")]
        [ValidateRange(1, 120)]
        [int]$TimeoutSeconds = 30
    )

    # Begin block for initialization
    begin {
        # Enable verbose logging
        $VerbosePreference = 'Continue'
        Write-Verbose "Starting Add-AdcsAuthorizedServer function..."

        # Check PowerShell version
        $psVersion = $PSVersionTable.PSVersion.Major
        if ($psVersion -ge 6) {
            Write-Verbose "Running on PowerShell Core ($psVersion). Using default Kerberos authentication."
        } else {
            Write-Verbose "Running on Windows PowerShell ($psVersion). Using default credentials for Kerberos authentication."
        }

        # Ensure TLS 1.2 is used for secure connections
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        # Initialize variables
        $uri = "$ApiBaseUrl/api/Manage/AuthorizedServers"
        $headers = @{
            'Content-Type' = 'application/json'
        }
    }

    # Process block for main logic
    process {
        try {
            # Create the JSON payload
            $payload = @{
                AdcsServerAccount = $AdcsServerAccount
                AdcsServerName = $AdcsServerName
                ServerGUID = $ServerGUID
                Description = if ($Description) { $Description } else { $null }
                IsActive = $IsActive
            }
            $jsonPayload = $payload | ConvertTo-Json -Depth 3
            Write-Verbose "Generated JSON payload: $jsonPayload"

            # Send the POST request with default credentials for Kerberos
            Write-Verbose "Sending POST request to: $uri"
            $response = Invoke-RestMethod -Uri $uri `
                                        -Method Post `
                                        -Body $jsonPayload `
                                        -Headers $headers `
                                        -UseDefaultCredentials `
                                        -TimeoutSec $TimeoutSeconds `
                                        -ErrorAction Stop

            # Log success
            Write-Verbose "Successfully added AuthorizedServer: AdcsServerAccount=$AdcsServerAccount, ServerGUID=$ServerGUID"
            Write-Output "AuthorizedServer added successfully. Response: $($response | ConvertTo-Json -Depth 3)"
            return $response
        }
        catch [System.Net.WebException] {
            if ($_.Exception.Response) {
                $responseStream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($responseStream)
                $responseBody = $reader.ReadToEnd()
                Write-Error "HTTP request failed: StatusCode=$($_.Exception.Response.StatusCode), Response=$responseBody"
                $reader.Close()
            }
            else {
                Write-Error "HTTP request failed: $($_.Exception.Message)"
            }
            Write-Verbose "Error details: $($_.Exception | Format-List -Property * -Force | Out-String)"
            throw
        }
        catch {
            Write-Error "Failed to add AuthorizedServer: $($_.Exception.Message)"
            Write-Verbose "Error details: $($_.Exception | Format-List -Property * -Force | Out-String)"
            throw
        }
    }

    # End block for cleanup
    end {
        Write-Verbose "Completed Add-AdcsAuthorizedServer function."
        $VerbosePreference = 'SilentlyContinue'
    }
}