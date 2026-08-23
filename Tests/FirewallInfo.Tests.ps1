BeforeAll {
    $logLevel = "off"
    $SCRIPT_PATH = Join-Path $TestDrive "Test.ps1"
    . "$PSScriptRoot/../../Winspect/src/Constants.ps1"
    . "$PSScriptRoot/../../Winspect/src/Logging.ps1"
    . "$PSScriptRoot/../../Winspect/src/Utilities.ps1"
    . "$PSScriptRoot/../src/Constants.ps1"
    . "$PSScriptRoot/../src/FirewallInfo.ps1"
}

Describe "Get-FqdnFromUrl" {
    It "extracts the host from a URL with a path" {
        Get-FqdnFromUrl "https://github.com/mortendj/ayfieinspector" | Should -Be "github.com"
    }

    It "extracts the host from a bare URL" {
        Get-FqdnFromUrl "https://activate.virtualworks.com" | Should -Be "activate.virtualworks.com"
    }
}

Describe "Test-UrlReachable" {
    # Mocks the real I/O boundary (Test-NetConnection, Invoke-WebRequest) directly, since this
    # function IS that boundary wrapper - nothing lower-level to mock instead.

    It "returns false when the TCP connection itself fails" {
        Mock Test-NetConnection { [pscustomobject]@{ TcpTestSucceeded = $false } }
        Mock Invoke-WebRequest { throw "should not be called" }

        Test-UrlReachable "example-non-reachable-site.com" "https://example-non-reachable-site.com" | Should -BeFalse
    }

    It "returns false when the TCP connection succeeds but the HTTP request fails" {
        Mock Test-NetConnection { [pscustomobject]@{ TcpTestSucceeded = $true } }
        Mock Invoke-WebRequest { throw "connection reset" }

        Test-UrlReachable "example.com" "https://example.com" | Should -BeFalse
    }

    It "returns true when both the TCP connection and the HTTP request succeed" {
        Mock Test-NetConnection { [pscustomobject]@{ TcpTestSucceeded = $true } }
        Mock Invoke-WebRequest { [pscustomobject]@{ StatusCode = 200 } }

        Test-UrlReachable "github.com" "https://github.com" | Should -BeTrue
    }
}

Describe "Get-FirewallReport" {
    # Mocks Test-UrlReachable (already unit-tested above), not Test-NetConnection/Invoke-WebRequest
    # directly - this describes the aggregation/formatting logic on top of the real I/O boundary.

    It "lists every URL as reachable when all of them are" {
        Mock Test-UrlReachable { $true }

        $result = Get-FirewallReport @("https://a.example.com", "https://b.example.com") @()

        $result | Should -Match "Reachable sites:"
        $result | Should -Match "a\.example\.com"
        $result | Should -Match "b\.example\.com"
        $result | Should -Not -Match "Non-reachable sites:"
    }

    It "reports 'No sites reachable' rather than an empty list when none are reachable" {
        Mock Test-UrlReachable { $false }

        $result = Get-FirewallReport @("https://a.example.com") @()

        $result | Should -Match "No sites reachable"
    }

    It "separates reachable and non-reachable sites into their own labeled groups" {
        Mock Test-UrlReachable {
            param($fqdn, $url)
            return $fqdn -eq "reachable.example.com"
        }

        $result = Get-FirewallReport @("https://reachable.example.com", "https://unreachable.example.com") @()

        $result | Should -Match "Reachable sites:[\s\S]*reachable\.example\.com"
        $result | Should -Match "Non-reachable sites:[\s\S]*unreachable\.example\.com"
    }

    It "reports alternate sites separately, each labeled Reachable or Non-reachable" {
        Mock Test-UrlReachable {
            param($fqdn, $url)
            return $fqdn -eq "alt-good.example.net"
        }

        $result = Get-FirewallReport @() @("https://alt-good.example.net", "https://alt-bad.example.org")

        $result | Should -Match "Alternate sites:"
        $result | Should -Match "Reachable: alt-good\.example\.net"
        $result | Should -Match "Non-reachable: alt-bad\.example\.org"
    }
}
