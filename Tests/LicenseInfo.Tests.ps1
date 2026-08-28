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
