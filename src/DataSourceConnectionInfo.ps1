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

function Get-ConnectionPropertyAsLines($propertyName, $propertyValue, $indentDepth) {
    Write-FunctionCallLog $PSBoundParameters
    # Never called with a null $propertyValue - every call site filters nulls out first, rather
    # than this function returning an empty array for that case, which Write-ReturnValue's
    # array-wrapping return (needed elsewhere so a single-line result survives as a real array)
    # would turn into a stray nested-empty-array element once appended onto the caller's own
    # $lines with +=.
    $indent = $INDENTATION * $indentDepth
    if (($propertyValue -is [System.Array]) -or ($propertyValue -is [System.Management.Automation.PSCustomObject])) {
        $lines = @("$indent${propertyName}:")
        if ($propertyValue -is [System.Array]) {
            foreach ($item in @($propertyValue)) {
                if ($item -is [System.Management.Automation.PSCustomObject]) {
                    foreach ($itemProperty in $item.psobject.Properties) {
                        if ($null -eq $itemProperty.Value) { continue }
                        $lines += Get-ConnectionPropertyAsLines $itemProperty.Name $itemProperty.Value ($indentDepth + 1)
                    }
                } else {
                    $lines += "$indent$INDENTATION$item"
                }
            }
        } else {
            foreach ($property in $propertyValue.psobject.Properties) {
                if ($null -eq $property.Value) { continue }
                $lines += Get-ConnectionPropertyAsLines $property.Name $property.Value ($indentDepth + 1)
            }
        }
        Write-ReturnValue $lines
    } else {
        Write-ReturnValue @("$indent${propertyName}: $propertyValue")
    }
}

function Get-DataSourceConnectionSummary($connection, $settingsText) {
    Write-FunctionCallLog $PSBoundParameters
    $lines = @(
        "$($connection.displayName) ($($connection.connectorName))",
        "    Enabled: $($connection.isEnabled)",
        "    Document count: $($connection.documentCount)"
    )
    foreach ($property in $connection.psobject.Properties) {
        if ($DATA_SOURCE_CONNECTION_WELL_KNOWN_PROPERTIES -contains $property.Name) {
            continue
        }
        if ($null -eq $property.Value) {
            continue
        }
        $lines += Get-ConnectionPropertyAsLines $property.Name $property.Value 1
    }
    $lines += "    Settings:"
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
