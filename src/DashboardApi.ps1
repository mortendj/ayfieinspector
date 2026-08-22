function Get-DashboardApiResponse($dashboardApiRootUrl, $endpoint) {
    Write-FunctionCallLog $PSBoundParameters
    $uri = "$dashboardApiRootUrl/$endpoint"
    $response = Invoke-RestMethod -Uri $uri -Method Get -Headers @{ Accept = 'application/json' }
    Write-ReturnValue $response.Data
}

function Get-SourceReferenceCount($dashboardApiRootUrl) {
    Write-FunctionCallLog $PSBoundParameters
    $count = Get-DashboardApiResponse $dashboardApiRootUrl "sourcereference/count"
    $enUSCulture = [System.Globalization.CultureInfo]::GetCultureInfo("en-US")
    Write-ReturnValue $count.ToString("N0", $enUSCulture)
}
