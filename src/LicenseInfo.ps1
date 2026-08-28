function Get-LicensingContainerIp() {
    Write-FunctionCallLog $PSBoundParameters
    # Same docker inspect + JSON-join pattern as Get-SagaInstallDirPath (SagaCertificateInfo.ps1) -
    # see the note there for why --format is avoided (Invoke-ExternalCommand's argument-splitting
    # bug) and why the multi-line Get-Content-style output needs joining before ConvertFrom-Json.
    # A separate docker inspect call from the certificate/install-dir one - cheap, and keeps this
    # concern independently testable rather than coupling it to certificate resolution.
    $containerConfigJsonLines = Invoke-ExternalCommand "docker" @("inspect", $LICENSING_CONTAINER_NAME)
    $containerConfig = ($containerConfigJsonLines -join "`n") | ConvertFrom-Json
    Write-ReturnValue $containerConfig[0].NetworkSettings.Networks.nat.IPAddress
}

function Get-SagaLicenses($licensingContainerIp) {
    Write-FunctionCallLog $PSBoundParameters
    $uri = "http://$licensingContainerIp/$LICENSING_API_PATH"
    $response = Invoke-RestMethod -Uri $uri -Method Get
    Write-ReturnValue @($response.license)
}

function Test-IsLicenseValid($license) {
    Write-FunctionCallLog $PSBoundParameters
    if (-not $license.expirationDateUtc) {
        # No expiration date at all only means "valid forever" for a genuinely perpetual license -
        # anything else with a missing expiration date is malformed, not implicitly valid.
        Write-ReturnValue ($license.licenseType -eq $PERPETUAL_LICENSE_LABEL)
        return
    }
    Write-ReturnValue ((Get-Date $license.expirationDateUtc) -gt (Get-Date))
}

function Get-SagaLicenseSummary($licensingContainerIp) {
    Write-FunctionCallLog $PSBoundParameters
    $licenses = Get-SagaLicenses $licensingContainerIp
    $summary = [pscustomobject]@{
        CustomerId = $null; CustomerName = $null; ActivationDates = $null; ExpirationDates = $null
        UserCapacity = $null; DocumentCapacity = $null; Features = $null; EarliestExpirationDate = $null
    }
    if ($licenses.Count -eq 0) {
        Write-ReturnValue $summary
        return
    }
    # customerId/customerName are reported even with no currently-valid license (matches the older
    # tool this is ported from) - they're identifying information about who the license belongs to,
    # not a capacity or feature claim that would be misleading to show for an expired license.
    $summary.CustomerId = $licenses[0].customerId
    $summary.CustomerName = $licenses[0].customerName

    $validLicenses = @($licenses | Where-Object { Test-IsLicenseValid $_ })
    if ($validLicenses.Count -eq 0) {
        Write-ReturnValue $summary
        return
    }

    $summary.ActivationDates = (@($validLicenses.activationDateUtc) | Select-Object -Unique) -join ", "
    $summary.ExpirationDates = (@($validLicenses | ForEach-Object {
        if ($_.expirationDateUtc) { $_.expirationDateUtc } else { $PERPETUAL_LICENSE_LABEL }
    }) | Select-Object -Unique) -join ", "
    $summary.UserCapacity = (@($validLicenses) | Measure-Object -Property userCount -Sum).Sum
    $summary.DocumentCapacity = (@($validLicenses) | Measure-Object -Property documentCount -Sum).Sum

    # The single soonest future expiration date across every dated (non-perpetual) valid license -
    # kept as a real [DateTime], not re-parsed out of the joined display string above, so
    # Get-DaysUntilSagaLicenseExpires can do simple date math instead of string parsing. Stays $null
    # when every valid license is perpetual, which Get-DaysUntilSagaLicenseExpires treats as its own
    # distinct case rather than an error.
    $futureExpirationDates = @($validLicenses | Where-Object { $_.expirationDateUtc } | ForEach-Object { [DateTime]$_.expirationDateUtc } | Sort-Object)
    if ($futureExpirationDates.Count -gt 0) {
        $summary.EarliestExpirationDate = $futureExpirationDates[0]
    }

    # A Saga installation can hold more than one active license (e.g. a base license plus an
    # add-on) - features are concatenated across all of them, not deduplicated, matching real
    # production output where the same capability can legitimately appear more than once.
    $featureLines = @()
    foreach ($license in $validLicenses) {
        foreach ($capability in @($license.capabilities)) {
            if ($capability.count -eq 0) {
                $featureLines += "$($capability.capabilityType): $($capability.displayName)"
            }
        }
    }
    $summary.Features = $featureLines -join $PHYSICAL_NEWLINE

    Write-ReturnValue $summary
}

function Get-DaysUntilSagaLicenseExpires($licenseSummary) {
    Write-FunctionCallLog $PSBoundParameters
    # $licenseSummary is $null only when resolving it failed entirely (see Start-AyfieInspector) -
    # distinct from a successfully-resolved summary that just has nothing to report (no valid
    # license at all: ExpirationDates itself stays $null; every valid license perpetual:
    # ExpirationDates is set but EarliestExpirationDate stays $null).
    if ($null -eq $licenseSummary) {
        Write-ReturnValue "Unavailable"
        return
    }
    if ($null -eq $licenseSummary.ExpirationDates) {
        Write-ReturnValue "No valid license"
        return
    }
    if ($null -eq $licenseSummary.EarliestExpirationDate) {
        Write-ReturnValue $PERPETUAL_LICENSE_LABEL
        return
    }
    Write-ReturnValue (New-TimeSpan -Start (Get-Date) -End $licenseSummary.EarliestExpirationDate).Days
}
