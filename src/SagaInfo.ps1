function Get-SagaVersion($installDirPath) {
    Write-FunctionCallLog $PSBoundParameters
    $gitVersionFilePath = Join-Path $installDirPath $GIT_VERSION_RELATIVE_PATH
    $gitVersionJson = Get-Content -Path $gitVersionFilePath -Raw -ErrorAction Stop | ConvertFrom-Json
    Write-ReturnValue "$($gitVersionJson.Major).$($gitVersionJson.Minor).$($gitVersionJson.Patch)"
}

function Get-OsSupportSummary($operatingSystemVersion) {
    Write-FunctionCallLog $PSBoundParameters
    $isSupported = $false
    foreach ($supportedOs in $SUPPORTED_OS) {
        if ($operatingSystemVersion -match $supportedOs) {
            $isSupported = $true
            break
        }
    }
    if ($isSupported) {
        Write-ReturnValue "Supported"
    } else {
        Write-ReturnValue "WARNING: '$operatingSystemVersion' is not a version supported by Ayfie Index (Saga)"
    }
}

function Get-InstalledConnectorNamesFromPluginsDirectory($installDirPath) {
    Write-FunctionCallLog $PSBoundParameters
    $pluginsDirPath = Join-Path $installDirPath $CONNECTOR_PLUGINS_RELATIVE_PATH
    if (-not (Test-Path $pluginsDirPath)) {
        Write-ReturnValue @()
        return
    }
    $pluginDirectories = @(Get-ChildItem -Path $pluginsDirPath -Directory -Filter "$CONNECTOR_PLUGIN_PREFIX*" -ErrorAction SilentlyContinue)
    $connectorNames = @($pluginDirectories | ForEach-Object { $_.Name -replace [regex]::Escape($CONNECTOR_PLUGIN_PREFIX), '' })
    Write-ReturnValue $connectorNames
}

function Get-ConnectorNamesInUse($connectorApiRootUrl, $connectorNames) {
    Write-FunctionCallLog $PSBoundParameters
    $connectorNamesInUse = @()
    foreach ($connectorName in $connectorNames) {
        $connections = Get-ConnectorConnections $connectorApiRootUrl $connectorName
        if (@($connections).Count -gt 0) {
            $connectorNamesInUse += $connectorName
        }
    }
    Write-ReturnValue $connectorNamesInUse
}
