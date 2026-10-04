BeforeAll {
    $logLevel = "off"
    $SCRIPT_PATH = Join-Path $TestDrive "Test.ps1"
    . "$PSScriptRoot/../../Winspect/src/Constants.ps1"
    . "$PSScriptRoot/../../Winspect/src/Logging.ps1"
    . "$PSScriptRoot/../../Winspect/src/Utilities.ps1"
    . "$PSScriptRoot/../src/Constants.ps1"
    . "$PSScriptRoot/../src/LicenseInfo.ps1"

    function New-FakeLicense($overrides = @{}) {
        $license = [pscustomobject]@{
            licenseType = "Perpetual"
            activationDateUtc = "2022-06-01T15:12:58Z"
            expirationDateUtc = (Get-Date).AddYears(1).ToString("o")
            customerId = "1234567"
            customerName = "Test Customer"
            userCount = 100
            documentCount = 1000000
            capabilities = @(
                [pscustomobject]@{ capabilityType = "Connector"; displayName = "File Server Connector"; count = 0 }
                [pscustomobject]@{ capabilityType = "Users"; displayName = "Users"; count = 100 }
            )
        }
        foreach ($key in $overrides.Keys) {
            $license.$key = $overrides[$key]
        }
        return $license
    }
}

Describe "Get-LicensingContainerIp" {
    It "extracts the NAT IP address from docker inspect's JSON output" {
        Mock Invoke-ExternalCommand {
            @(
                '[{"NetworkSettings":{"Networks":{"nat":{"IPAddress":"172.20.10.5"}}}}]'
            )
        }

        Get-LicensingContainerIp | Should -Be "172.20.10.5"
    }
}

Describe "Get-SagaLicenses" {
    It "unwraps the .license array from the API response" {
        Mock Invoke-RestMethod {
            [pscustomobject]@{ license = @((New-FakeLicense), (New-FakeLicense)) }
        } -ParameterFilter { $Uri -eq "http://172.20.10.5/api/licensing/v1/ProductLicense" }

        $result = Get-SagaLicenses "172.20.10.5"

        $result.Count | Should -Be 2
    }
}

Describe "Test-IsLicenseValid" {
    It "is valid when the expiration date is in the future" {
        $license = New-FakeLicense @{ expirationDateUtc = (Get-Date).AddDays(30).ToString("o") }

        Test-IsLicenseValid $license | Should -BeTrue
    }

    It "is not valid when the expiration date is in the past" {
        $license = New-FakeLicense @{ expirationDateUtc = (Get-Date).AddDays(-30).ToString("o") }

        Test-IsLicenseValid $license | Should -BeFalse
    }

    It "is valid with no expiration date when the license type is Perpetual" {
        $license = New-FakeLicense @{ expirationDateUtc = $null; licenseType = "Perpetual" }

        Test-IsLicenseValid $license | Should -BeTrue
    }

    It "is not valid with no expiration date when the license type is not Perpetual" {
        $license = New-FakeLicense @{ expirationDateUtc = $null; licenseType = "Subscription" }

        Test-IsLicenseValid $license | Should -BeFalse
    }

    It "parses the real API's MM/dd/yyyy date format correctly under a day-first host locale" {
        # Regression test for a real bug hit at a customer: the licensing API returns dates like
        # "10/23/2026 07:20:04" (MM/dd/yyyy), not the ISO "o" format the other fixtures use. Under
        # a day-first culture (e.g. Norwegian), day=25 makes the naive Get-Date/[DateTime] parse
        # throw ("month 25 doesn't exist") - this must succeed instead, parsed as December 25.
        $originalCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo("nb-NO")
            $license = New-FakeLicense @{ expirationDateUtc = "12/25/2099 10:00:00" }

            Test-IsLicenseValid $license | Should -BeTrue
        } finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $originalCulture
        }
    }

    It "does not silently swap day and month for MM/dd/yyyy dates under a day-first host locale" {
        # Companion to the test above: when day-of-month <= 12, the naive parse doesn't throw, it
        # silently swaps day/month instead - a worse bug since nothing signals the wrong result. An
        # expiration date 5 days from now must not appear expired due to a swapped day/month.
        $originalCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo("nb-NO")
            $inFiveDays = (Get-Date).AddDays(5)
            $expirationString = $inFiveDays.ToString("MM/dd/yyyy HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
            $license = New-FakeLicense @{ expirationDateUtc = $expirationString }

            Test-IsLicenseValid $license | Should -BeTrue
        } finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $originalCulture
        }
    }
}

Describe "Get-SagaLicenseSummary" {
    It "returns an all-null summary when there are no licenses at all" {
        Mock Get-SagaLicenses { @() }

        $result = Get-SagaLicenseSummary "172.20.10.5"

        $result.CustomerId | Should -BeNullOrEmpty
        $result.UserCapacity | Should -BeNullOrEmpty
    }

    It "still reports customerId even when every license has expired" {
        $expiredLicense = New-FakeLicense @{ expirationDateUtc = (Get-Date).AddDays(-30).ToString("o"); licenseType = "Subscription" }
        Mock Get-SagaLicenses { @($expiredLicense) }

        $result = Get-SagaLicenseSummary "172.20.10.5"

        $result.CustomerId | Should -Be "1234567"
        $result.UserCapacity | Should -BeNullOrEmpty
    }

    It "sums user and document capacity across multiple valid licenses" {
        $licenseA = New-FakeLicense @{ userCount = 100; documentCount = 1000000 }
        $licenseB = New-FakeLicense @{ userCount = 50; documentCount = 500000 }
        Mock Get-SagaLicenses { @($licenseA, $licenseB) }

        $result = Get-SagaLicenseSummary "172.20.10.5"

        $result.UserCapacity | Should -Be 150
        $result.DocumentCapacity | Should -Be 1500000
    }

    It "joins unique activation dates and reports 'Perpetual' for a license with no expiration date" {
        $licenseA = New-FakeLicense @{ activationDateUtc = "2022-06-01T15:12:58Z"; expirationDateUtc = $null; licenseType = "Perpetual" }
        Mock Get-SagaLicenses { @($licenseA) }

        $result = Get-SagaLicenseSummary "172.20.10.5"

        $result.ActivationDates | Should -Be "2022-06-01T15:12:58Z"
        $result.ExpirationDates | Should -Be "Perpetual"
        $result.EarliestExpirationDate | Should -BeNullOrEmpty
    }

    It "reports customerName alongside customerId" {
        Mock Get-SagaLicenses { @(New-FakeLicense @{ customerName = "Acme Corp" }) }

        (Get-SagaLicenseSummary "172.20.10.5").CustomerName | Should -Be "Acme Corp"
    }

    It "picks the earliest future expiration date across multiple dated valid licenses" {
        $sooner = (Get-Date).AddDays(10)
        $later = (Get-Date).AddDays(100)
        $licenseA = New-FakeLicense @{ expirationDateUtc = $later.ToString("o"); licenseType = "Subscription" }
        $licenseB = New-FakeLicense @{ expirationDateUtc = $sooner.ToString("o"); licenseType = "Subscription" }
        Mock Get-SagaLicenses { @($licenseA, $licenseB) }

        $result = Get-SagaLicenseSummary "172.20.10.5"

        $result.EarliestExpirationDate.Date | Should -Be $sooner.Date
    }

    It "parses the real API's MM/dd/yyyy date format for EarliestExpirationDate under a day-first host locale" {
        # Same regression as Test-IsLicenseValid above, for the other parsing site
        # ([DateTime] cast, not Get-Date) - day=25 must not fail to parse as "month 25".
        $originalCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo("nb-NO")
            $license = New-FakeLicense @{ expirationDateUtc = "12/25/2099 10:00:00"; licenseType = "Subscription" }
            Mock Get-SagaLicenses { @($license) }

            $result = Get-SagaLicenseSummary "172.20.10.5"

            $result.EarliestExpirationDate.Month | Should -Be 12
            $result.EarliestExpirationDate.Day | Should -Be 25
        } finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $originalCulture
        }
    }

    It "concatenates zero-count capabilities across licenses without deduplicating" {
        $licenseA = New-FakeLicense @{ capabilities = @([pscustomobject]@{ capabilityType = "Connector"; displayName = "File Server Connector"; count = 0 }) }
        $licenseB = New-FakeLicense @{ capabilities = @([pscustomobject]@{ capabilityType = "Connector"; displayName = "File Server Connector"; count = 0 }) }
        Mock Get-SagaLicenses { @($licenseA, $licenseB) }

        $result = Get-SagaLicenseSummary "172.20.10.5"

        $featureLines = @($result.Features -split $PHYSICAL_NEWLINE)
        $featureLines.Count | Should -Be 2
        $featureLines[0] | Should -Be "Connector: File Server Connector"
        $featureLines[1] | Should -Be "Connector: File Server Connector"
    }

    It "excludes capabilities with a non-zero count (quantity-style, not feature-flag-style)" {
        $license = New-FakeLicense @{ capabilities = @([pscustomobject]@{ capabilityType = "Users"; displayName = "Users"; count = 100 }) }
        Mock Get-SagaLicenses { @($license) }

        $result = Get-SagaLicenseSummary "172.20.10.5"

        $result.Features | Should -Be ""
    }
}

Describe "Get-DaysUntilSagaLicenseExpires" {
    It "reports 'Unavailable' when the summary is null (resolution failed entirely)" {
        Get-DaysUntilSagaLicenseExpires $null | Should -Be "Unavailable"
    }

    It "reports 'No valid license' when the summary resolved fine but found no valid license" {
        $summary = [pscustomobject]@{ ExpirationDates = $null; EarliestExpirationDate = $null }

        Get-DaysUntilSagaLicenseExpires $summary | Should -Be "No valid license"
    }

    It "reports 'Perpetual' when every valid license is perpetual" {
        $summary = [pscustomobject]@{ ExpirationDates = "Perpetual"; EarliestExpirationDate = $null }

        Get-DaysUntilSagaLicenseExpires $summary | Should -Be "Perpetual"
    }

    It "reports the integer number of days until the earliest expiration date" {
        $summary = [pscustomobject]@{
            ExpirationDates = "irrelevant for this test"
            EarliestExpirationDate = (Get-Date).AddDays(30)
        }

        Get-DaysUntilSagaLicenseExpires $summary | Should -BeIn @(29, 30)
    }
}

Describe "Test-HasSagaLicenseCapability" {
    It "reports 'Has license' when the capability name appears in Features" {
        $summary = [pscustomobject]@{ Features = "Connector: File Server Connector`nReport Engine: Report Engine" }

        Test-HasSagaLicenseCapability $summary "Report Engine" | Should -Be "Has license"
    }

    It "reports 'No license' when the capability name does not appear in Features" {
        $summary = [pscustomobject]@{ Features = "Connector: File Server Connector" }

        Test-HasSagaLicenseCapability $summary "Report Engine" | Should -Be "No license"
    }

    It "reports 'Unavailable' when the license summary is null (resolution failed entirely)" {
        Test-HasSagaLicenseCapability $null "Report Engine" | Should -Be "Unavailable"
    }

    It "reports 'Unavailable' when Features itself is null (no valid license at all)" {
        $summary = [pscustomobject]@{ Features = $null }

        Test-HasSagaLicenseCapability $summary "Report Engine" | Should -Be "Unavailable"
    }
}
