function Get-ConnectorApiResponse($connectorApiRootUrl, $endpoint) {
    Write-FunctionCallLog $PSBoundParameters
    # Unlike the Dashboard API (DashboardApi.ps1's Get-DashboardApiResponse, which unwraps a .Data
    # envelope), the connector-broker API returns its payload directly with no envelope - confirmed
    # against the older tool this is ported from, whose own connector-broker equivalent (Get-
    # ConnectorApiResponse) passes the raw response straight through with no .Data access at all,
    # unlike its separate Dashboard-API function which does. Applying the Dashboard convention here
    # too was a real bug found live: it silently turned every connector name into $null (PowerShell
    # auto-enumerates .Data across an array's elements, and none of them have that property),
    # eventually producing a malformed "Connections/" endpoint instead of "Connections/<name>".
    $uri = "$connectorApiRootUrl/$endpoint"
    $response = Invoke-RestMethod -Uri $uri -Method Get -Headers @{ Accept = 'application/json' }
    Write-ReturnValue $response
}

function Get-InstalledConnectorNames($connectorApiRootUrl) {
    Write-FunctionCallLog $PSBoundParameters
    # Assigned to a variable first, not wrapped directly around the call - see the note in
    # RuleEngineInfo.ps1's Get-RuleEngineRules for why @(Get-ConnectorApiResponse ...) here would
    # nest the real array one level deeper instead of flattening it.
    $installedConnectors = Get-ConnectorApiResponse $connectorApiRootUrl "connectors/installed"
    $connectorNames = @($installedConnectors | ForEach-Object { $_.connectorName })
    Write-ReturnValue $connectorNames
}

function Get-ConnectorConnections($connectorApiRootUrl, $connectorName) {
    Write-FunctionCallLog $PSBoundParameters
    $connections = Get-ConnectorApiResponse $connectorApiRootUrl "Connections/$connectorName"
    Write-ReturnValue @($connections)
}

function Get-ConnectionSettings($connectorApiRootUrl, $connectionId) {
    Write-FunctionCallLog $PSBoundParameters
    $settings = Get-ConnectorApiResponse $connectorApiRootUrl "Connections/$connectionId/settings"
    Write-ReturnValue @($settings)
}
