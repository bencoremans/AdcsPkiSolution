# Function: Test-AdcsAdminsMembership
# Description: Checks if a user is a member of a specified group in the primary Active Directory domain, with the user in primary or trusted domains
function Test-AdcsAdminsMembership {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "The SAM account name of the user to check (e.g., ba00001a02a0051).")]
        [ValidateNotNullOrEmpty()]
        [string]$UserSamAccountName,
        [Parameter(HelpMessage = "The AD group name (default: grp98470c47-sys-l-A47-ManangeAPI).")]
        [ValidateNotNullOrEmpty()]
        [string]$GroupName = "grp98470c47-sys-l-A47-ManangeAPI",
        [Parameter(HelpMessage = "The primary domain name where the group resides (default: FRS98470.localdns.nl).")]
        [ValidateNotNullOrEmpty()]
        [string]$PrimaryDomain = "FRS98470.localdns.nl",
        [Parameter(HelpMessage = "List of trusted domain names where the user may reside (e.g., frs00001.localdns.nl).")]
        [string[]]$TrustedDomains = @("frs00001.localdns.nl")
    )

    # Begin block for initialization
    begin {
        # Enable verbose logging
        $VerbosePreference = 'Continue'
        Write-Verbose "Starting Test-AdcsAdminsMembership function..."

        # Check if ActiveDirectory module is available
        if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
            Write-Error "ActiveDirectory module is not available. Install the RSAT-AD-PowerShell feature."
            throw
        }
        Import-Module ActiveDirectory -ErrorAction Stop
    }

    # Process block for main logic
    process {
        try {
            # Get the group from the primary domain
            Write-Verbose "Testing connectivity to primary domain: $PrimaryDomain"
            $domainController = [string]((Get-ADDomainController -DomainName $PrimaryDomain -Discover -ErrorAction Stop).HostName | Select-Object -First 1)
            Write-Verbose "Found domain controller: $domainController"
            Write-Verbose "Checking group: $GroupName in domain: $PrimaryDomain"
            $group = Get-ADGroup -Identity $GroupName -Server $domainController -ErrorAction Stop
            if (-not $group) {
                Write-Error "Group $GroupName not found in domain $PrimaryDomain."
                throw
            }

            # Check user membership in primary domain
            $isMember = Check-ADGroupMembership -Domain $PrimaryDomain -UserSamAccountName $UserSamAccountName -Group $group
            if ($isMember) {
                Write-Output "User $UserSamAccountName is a member of $GroupName in domain $PrimaryDomain."
                return $true
            }

            # Check user membership in trusted domains
            foreach ($domain in $TrustedDomains) {
                $isMember = Check-ADGroupMembership -Domain $domain -UserSamAccountName $UserSamAccountName -Group $group
                if ($isMember) {
                    Write-Output "User $UserSamAccountName is a member of $GroupName in trusted domain $domain."
                    return $true
                }
            }

            Write-Output "User $UserSamAccountName is not a member of $GroupName in any configured domain."
            return $false
        }
        catch {
            Write-Error "Failed to check group membership: $($_.Exception.Message)"
            Write-Verbose "Error details: $($_.Exception | Format-List -Property * -Force | Out-String)"
            throw
        }
    }

    # End block for cleanup
    end {
        Write-Verbose "Completed Test-AdcsAdminsMembership function."
        $VerbosePreference = 'SilentlyContinue'
    }
}

# Helper function to check group membership for a user in a specific domain
function Check-ADGroupMembership {
    param (
        [string]$Domain,
        [string]$UserSamAccountName,
        [Microsoft.ActiveDirectory.Management.ADGroup]$Group
    )

    try {
        Write-Verbose "Testing connectivity to domain: $Domain"
        $domainController = [string]((Get-ADDomainController -DomainName $Domain -Discover -ErrorAction Stop).HostName | Select-Object -First 1)
        Write-Verbose "Found domain controller: $domainController"
        Write-Verbose "Checking user: $UserSamAccountName in domain: $Domain"

        $user = Get-ADUser -Identity $UserSamAccountName -Server $domainController -Properties distinguishedName, objectSid, tokenGroupsGlobalAndUniversal -ErrorAction Stop
        if (-not $user) {
            Write-Verbose "User $UserSamAccountName not found in domain $Domain."
            return $false
        }

        Write-Verbose "Checking membership for user: $UserSamAccountName in group: $($Group.Name)"
        $groupDn = $Group.DistinguishedName
        $recursiveFilter = ":1.2.840.113556.1.4.1941:"
        $userDn = $user.distinguishedName
        $filter = "(&(objectClass=group)(distinguishedName=$groupDn)(member$recursiveFilter=$userDn))"

        # Convert primary domain to DC components for FSP path
        $groupDomainDn = ($PrimaryDomain -split '\.' | ForEach-Object { "DC=$_" }) -join ','
        $userDomainDn = ($Domain -split '\.' | ForEach-Object { "DC=$_" }) -join ','

        # Check if the group is domain local and user is from a different domain
        if (($Group.groupType -band 4) -and ($groupDomainDn -ne $userDomainDn)) {
            $fspFilters = New-Object System.Text.StringBuilder
            $userSid = $user.objectSid.Value
            $fspFilters.Append("(&(objectClass=group)(distinguishedName=$groupDn)(member$recursiveFilter=CN=$userSid,CN=ForeignSecurityPrincipals,$groupDomainDn))") | Out-Null

            # Add token groups for recursive checks
            foreach ($token in $user.tokenGroupsGlobalAndUniversal) {
                $groupSid = $token.Value
                $fspFilters.Append("(member$recursiveFilter=CN=$groupSid,CN=ForeignSecurityPrincipals,$groupDomainDn)") | Out-Null
            }

            $filter = "(|$filter$($fspFilters.ToString()))"
        }

        $searcher = New-Object System.DirectoryServices.DirectorySearcher
        $searcher.SearchRoot = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$domainController/$groupDn")
        $searcher.Filter = $filter
        $searcher.PageSize = 1
        $searcher.SearchScope = "Base" # Set to Base to match C# code and fix error
        $searcher.PropertiesToLoad.Add("cn") | Out-Null

        Write-Verbose "Executing LDAP query with filter: $filter"
        $result = $searcher.FindOne()

        if ($result) {
            Write-Verbose "User $UserSamAccountName is a member of $($Group.Name) (including nested groups) in domain $Domain."
            return $true
        }
        else {
            Write-Verbose "User $UserSamAccountName is NOT a member of $($Group.Name) in domain $Domain."
            return $false
        }
    }
    catch {
        Write-Verbose "Error checking group membership in domain $Domain: $($_.Exception.Message)"
        return $false
    }
}