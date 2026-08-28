function Get-SecurityClearedConnectionSettings($settings, $sensitiveTokens) {
    Write-FunctionCallLog $PSBoundParameters
    $lines = @()
    foreach ($setting in @($settings)) {
        $isSensitive = $false
        foreach ($token in $sensitiveTokens) {
            if ($setting.settingName -like "*$token*") {
                $isSensitive = $true
                break
            }
        }
        if (-not $isSensitive) {
            $lines += "$($setting.settingName)=$($setting.settingValue)"
        }
    }
    Write-ReturnValue ($lines -join $PHYSICAL_NEWLINE)
}

function Get-DataSourceConnectionSummary($connection, $settingsText) {
    Write-FunctionCallLog $PSBoundParameters
    $lines = @(
        "$($connection.displayName) ($($connection.connectorName))",
        "    Enabled: $($connection.isEnabled)",
        "    Document count: $($connection.documentCount)",
        "    Settings:"
    )
    foreach ($settingLine in @($settingsText -split $PHYSICAL_NEWLINE)) {
        if ($settingLine -ne "") {
            $lines += "        $settingLine"
        }
    }
    Write-ReturnValue ($lines -join $PHYSICAL_NEWLINE)
}

function Get-DataSourceConnectionsSummary($connectorApiRootUrl) {
    Write-FunctionCallLog $PSBoundParameters
    # Assigned to variables first, not wrapped directly around the calls - see the note in
    # RuleEngineInfo.ps1's Get-RuleEngineRules for why @(Get-InstalledConnectorNames ...) here
    # would nest the real array one level deeper instead of flattening it.
    $connectorNames = Get-InstalledConnectorNames $connectorApiRootUrl
    $connectionSummaries = @()
    foreach ($connectorName in $connectorNames) {
        $connections = Get-ConnectorConnections $connectorApiRootUrl $connectorName
        foreach ($connection in $connections) {
            $settings = Get-ConnectionSettings $connectorApiRootUrl $connection.id
            $settingsText = Get-SecurityClearedConnectionSettings $settings $SENSITIVE_CONN_TOKENS
            $connectionSummaries += Get-DataSourceConnectionSummary $connection $settingsText
        }
    }
    if ($connectionSummaries.Count -eq 0) {
        Write-ReturnValue "No data source connections found"
    } else {
        Write-ReturnValue ($connectionSummaries -join "$PHYSICAL_NEWLINE$PHYSICAL_NEWLINE")
    }
}
