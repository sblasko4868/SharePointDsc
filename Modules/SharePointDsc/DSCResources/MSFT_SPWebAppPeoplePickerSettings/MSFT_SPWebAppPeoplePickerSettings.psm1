function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $WebAppUrl,

        [parameter()]
        [System.String]
        $ActiveDirectoryCustomFilter,

        [parameter()]
        [System.String]
        $ActiveDirectoryCustomQuery,

        [parameter()]
        [System.UInt16]
        $ActiveDirectorySearchTimeout,

        [parameter()]
        [System.Boolean]
        $OnlySearchWithinSiteCollection,

        [parameter()]
        [Microsoft.Management.Infrastructure.CimInstance[]]
        $SearchActiveDirectoryDomains,

        [parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]
        $InstallAccount
    )

    Write-Verbose -Message "Getting People Picker Settings for $WebAppUrl"

    $result = Invoke-SPDSCCommand -Credential $InstallAccount `
                                  -Arguments $PSBoundParameters `
                                  -ScriptBlock {
        $params = $args[0]

        $wa = Get-SPWebApplication -Identity $params.WebAppUrl `
                                   -ErrorAction SilentlyContinue

        if ($null -eq $wa)
        {
            return @{
                WebAppUrl                      = $params.WebAppUrl
                ActiveDirectoryCustomFilter    = $null
                ActiveDirectoryCustomQuery     = $null
                ActiveDirectorySearchTimeout   = $null
                OnlySearchWithinSiteCollection = $null
                SearchActiveDirectoryDomains   = $null
            }
        }

        $searchADDomains = @()
        foreach ($searchDomain in $wa.PeoplePickerSettings.SearchActiveDirectoryDomains)
        {
            $searchADDomain = @{}
            $searchADDomain.FQDN = $searchDomain.DomainName
            $searchADDomain.IsForest = $searchDomain.IsForest
            $searchADDomain.Account  = $searchDomain.LoginName
            $searchADDomains += $searchADDomain
        }

        return @{
                WebAppUrl                      = $params.WebAppUrl
                ActiveDirectoryCustomFilter    = $wa.PeoplePickerSettings.ActiveDirectoryCustomFilter
                ActiveDirectoryCustomQuery     = $wa.PeoplePickerSettings.ActiveDirectoryCustomQuery
                ActiveDirectorySearchTimeout   = $wa.PeoplePickerSettings.ActiveDirectorySearchTimeout.TotalSeconds
                OnlySearchWithinSiteCollection = $wa.PeoplePickerSettings.OnlySearchWithinSiteCollection
                SearchActiveDirectoryDomains   = $searchADDomains
        }
    }
    return $result
}

function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $WebAppUrl,

        [parameter()]
        [System.String]
        $ActiveDirectoryCustomFilter,

        [parameter()]
        [System.String]
        $ActiveDirectoryCustomQuery,

        [parameter()]
        [System.UInt16]
        $ActiveDirectorySearchTimeout,

        [parameter()]
        [System.Boolean]
        $OnlySearchWithinSiteCollection,

        [parameter()]
        [Microsoft.Management.Infrastructure.CimInstance[]]
        $SearchActiveDirectoryDomains,

        [parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]
        $InstallAccount
    )

    Write-Verbose -Message "Setting People Picker Settings for $WebAppUrl"

    ## Perform changes
    Invoke-SPDSCCommand -Credential $InstallAccount `
                        -Arguments $PSBoundParameters `
                        -ScriptBlock {
        $params      = $args[0]

        $wa = Get-SPWebApplication -Identity $params.WebAppUrl -ErrorAction SilentlyContinue

        if ($null -eq $wa)
        {
            throw "Specified web application could not be found."
        }

        if ($params.ContainsKey("ActiveDirectoryCustomFilter"))
        {
            if ($params.ActiveDirectoryCustomFilter -ne $wa.PeoplePickerSettings.ActiveDirectoryCustomFilter)
            {
                $wa.PeoplePickerSettings.ActiveDirectoryCustomFilter = $params.ActiveDirectoryCustomFilter
            }
        }

        if ($params.ContainsKey("ActiveDirectoryCustomQuery"))
        {
            if ($params.ActiveDirectoryCustomQuery -ne $wa.PeoplePickerSettings.ActiveDirectoryCustomQuery)
            {
                $wa.PeoplePickerSettings.ActiveDirectoryCustomQuery = $params.ActiveDirectoryCustomQuery
            }
        }

        if ($params.ContainsKey("ActiveDirectorySearchTimeout"))
        {
            if ($params.ActiveDirectorySearchTimeout -ne $wa.PeoplePickerSettings.ActiveDirectorySearchTimeout.TotalSeconds)
            {
                $wa.PeoplePickerSettings.ActiveDirectorySearchTimeout = New-TimeSpan -Seconds $params.ActiveDirectorySearchTimeout
            }
        }

        if ($params.ContainsKey("OnlySearchWithinSiteCollection"))
        {
            if ($params.OnlySearchWithinSiteCollection -ne $wa.PeoplePickerSettings.OnlySearchWithinSiteCollection)
            {
                $wa.PeoplePickerSettings.OnlySearchWithinSiteCollection = $params.OnlySearchWithinSiteCollection
            }
        }

        if ($params.ContainsKey("SearchActiveDirectoryDomains"))
        {
            foreach ($searchADDomain in $params.SearchActiveDirectoryDomains)
            {
                $configuredDomain = $wa.PeoplePickerSettings.SearchActiveDirectoryDomains | `
                                    Where-Object -FilterScript {
                                        $_.DomainName -eq $searchADDomain.FQDN -and `
                                        $_.IsForest -eq $searchADDomain.IsForest
                                    }
                if ($null -eq $configuredDomain)
                {
                    # Add domain
                    $adsearchobj = New-Object Microsoft.SharePoint.Administration.SPPeoplePickerSearchActiveDirectoryDomain
                    $adsearchobj.DomainName = $searchADDomain.FQDN
                    if ($searchADDomain.ContainsKey("NetBIOSName"))
                    {
                        $adsearchobj.ShortDomainName = $searchADDomain.NetBIOSName
                    }
                    $adsearchobj.IsForest = $searchADDomain.IsForest
                    if ($searchADDomain.ContainsKey("Account"))
                    {
                        $adsearchobj.LoginName = $searchADDomain.Account.UserName
                        $adsearchobj.SetPassword($searchADDomain.Account.Password)
                    }
                    $wa.PeoplePickerSettings.SearchActiveDirectoryDomains.Add($adsearchobj)
                }
            }

            # Reverse Check: Configured domains do not exist in config
            $removeDomains = @()
            foreach ($waSearchADDomain in $wa.PeoplePickerSettings.SearchActiveDirectoryDomains)
            {
                $specifiedDomain = $params.SearchActiveDirectoryDomains | Where-Object -FilterScript {
                    $_.FQDN -eq $waSearchADDomain.DomainName -and `
                    $_.IsForest -eq $waSearchADDomain.IsForest
                }

                if ($null -eq $specifiedDomain)
                {
                    # Configured domain not found in DSC configuration, removing domain
                    $removeDomains += $waSearchADDomain
                }
            }

            foreach ($domain in $removeDomains)
            {
                $wa.PeoplePickerSettings.SearchActiveDirectoryDomains.Remove($domain) | Out-Null
            }
        }
        $wa.Update()
    }
}

function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $WebAppUrl,

        [parameter()]
        [System.String]
        $ActiveDirectoryCustomFilter,

        [parameter()]
        [System.String]
        $ActiveDirectoryCustomQuery,

        [parameter()]
        [System.UInt16]
        $ActiveDirectorySearchTimeout,

        [parameter()]
        [System.Boolean]
        $OnlySearchWithinSiteCollection,

        [parameter()]
        [Microsoft.Management.Infrastructure.CimInstance[]]
        $SearchActiveDirectoryDomains,

        [parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]
        $InstallAccount
    )

    Write-Verbose -Message "Testing People Picker Settings for $WebAppUrl"

    $CurrentValues = Get-TargetResource @PSBoundParameters

    # Testing SearchActiveDirectoryDomains
    foreach ($searchADDomain in $params.SearchActiveDirectoryDomains)
    {
        $configuredDomain = $returnval.SearchActiveDirectoryDomains | `
                            Where-Object -FilterScript {
                                $_.FQDN -eq $searchADDomain.FQDN -and `
                                $_.IsForest -eq $searchADDomain.IsForest
                            }
        if ($null -eq $configuredDomain)
        {
            return $false
        }
    }

    foreach ($searchADDomain in $returnval.SearchActiveDirectoryDomains)
    {
        $specifiedDomain = $params.SearchActiveDirectoryDomains | Where-Object -FilterScript {
            $_.FQDN -eq $searchADDomain.FQDN -and `
            $_.IsForest -eq $searchADDomain.IsForest
        }

        if ($null -eq $specifiedDomain)
        {
            return $false
        }
    }

    return Test-SPDscParameterState -CurrentValues $CurrentValues `
                                    -DesiredValues $PSBoundParameters `
                                    -ValuesToCheck @("ActiveDirectoryCustomFilter", `
                                                     "ActiveDirectoryCustomQuery", `
                                                     "ActiveDirectorySearchTimeout", `
                                                     "OnlySearchWithinSiteCollection")
}

Export-ModuleMember -Function *-TargetResource
