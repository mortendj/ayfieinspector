function Get-FqdnFromUrl($url) {
    Write-FunctionCallLog $PSBoundParameters
    $uri = [System.Uri]::new($url)
    Write-ReturnValue $uri.Host
}

function Test-UrlReachable($fqdn, $url) {
    Write-FunctionCallLog $PSBoundParameters
    $isReachable = $false
    try {
        $connectionTest = Test-NetConnection -ComputerName $fqdn -Port $HTTPS_PORT -WarningAction SilentlyContinue -ErrorAction Stop
        if ($connectionTest.TcpTestSucceeded) {
            $null = Invoke-WebRequest -Uri $url -UseBasicParsing -MaximumRedirection 5 -TimeoutSec 10
            $isReachable = $true
        }
    } catch {
        $isReachable = $false
    }
    Write-ReturnValue $isReachable
}

function Get-FirewallReport($urls, $alternateUrls) {
    Write-FunctionCallLog $PSBoundParameters
    $reachableFqdns = @()
    $nonReachableFqdns = @()
    foreach ($url in $urls) {
        $fqdn = Get-FqdnFromUrl $url
        if (Test-UrlReachable $fqdn $url) {
            $reachableFqdns += $fqdn
        } else {
            $nonReachableFqdns += $fqdn
        }
    }

    $alternateResults = @()
    foreach ($url in $alternateUrls) {
        $fqdn = Get-FqdnFromUrl $url
        $status = if (Test-UrlReachable $fqdn $url) { "Reachable" } else { "Non-reachable" }
        $alternateResults += "$status`: $fqdn"
    }

    $lines = @()
    $lines += "Reachable sites:"
    if ($reachableFqdns.Count -gt 0) {
        $lines += $reachableFqdns | ForEach-Object { "$INDENTATION$_" }
    } else {
        $lines += "${INDENTATION}No sites reachable"
    }
    if ($nonReachableFqdns.Count -gt 0) {
        $lines += "Non-reachable sites:"
        $lines += $nonReachableFqdns | ForEach-Object { "$INDENTATION$_" }
    }
    if ($alternateResults.Count -gt 0) {
        $lines += "Alternate sites:"
        $lines += $alternateResults | ForEach-Object { "$INDENTATION$_" }
    }
    Write-ReturnValue ($lines -join $LOGICAL_NEWLINE)
}
