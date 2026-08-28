BeforeAll {
    $logLevel = "off"
    $SCRIPT_PATH = Join-Path $TestDrive "Test.ps1"
    . "$PSScriptRoot/../../Winspect/src/Constants.ps1"
    . "$PSScriptRoot/../../Winspect/src/Logging.ps1"
    . "$PSScriptRoot/../../Winspect/src/Utilities.ps1"
    . "$PSScriptRoot/../src/Constants.ps1"
    . "$PSScriptRoot/../src/ConnectorApi.ps1"
    . "$PSScriptRoot/../src/SagaInfo.ps1"
}

Describe "Get-SagaVersion" {
    It "joins Major.Minor.Patch from git.version's JSON content" {
        $installDirPath = Join-Path $TestDrive "saga-install"
        New-Item -ItemType Directory -Path $installDirPath -Force | Out-Null
        Set-Content -Path (Join-Path $installDirPath "git.version") -Value '{"Major":7,"Minor":19,"Patch":0}'

        Get-SagaVersion $installDirPath | Should -Be "7.19.0"
    }

    It "throws when git.version doesn't exist, rather than silently returning something misleading" {
        $installDirPath = Join-Path $TestDrive "no-such-install"

        { Get-SagaVersion $installDirPath } | Should -Throw
    }
}

Describe "Get-OsSupportSummary" {
    It "reports 'Supported' for each OS version on Saga's supported list" {
        Get-OsSupportSummary "Microsoft Windows Server 2019 Standard (10.0.17763, build 17763)" | Should -Be "Supported"
        Get-OsSupportSummary "Microsoft Windows Server 2022 Standard (10.0.20348, build 20348)" | Should -Be "Supported"
        Get-OsSupportSummary "Microsoft Windows Server 2025 Standard (10.0.26100, build 26100)" | Should -Be "Supported"
    }

    It "reports a warning, not a blocking error, for an OS not on the supported list" {
        # Ported from the older tool this check originated from, which threw and aborted an
        # unrelated RSAT feature-installation step for any unsupported OS - deliberately downgraded
        # here to an informational warning that doesn't prevent the rest of the report from running.
        $result = Get-OsSupportSummary "Microsoft Windows Server 2016 Standard (10.0.14393, build 14393)"

        $result | Should -Match "^WARNING"
        $result | Should -Match "not a version supported by Ayfie Index \(Saga\)"
    }
}

Describe "Get-InstalledConnectorNamesFromPluginsDirectory" {
    It "strips the connector- prefix from each matching plugin directory name" {
        $installDirPath = Join-Path $TestDrive "saga-install-plugins"
        $pluginsDirPath = Join-Path $installDirPath "plugins"
        New-Item -ItemType Directory -Path (Join-Path $pluginsDirPath "connector-fileserver") -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $pluginsDirPath "connector-exchange") -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $pluginsDirPath "not-a-connector") -Force | Out-Null

        # Not `@(Get-InstalledConnectorNamesFromPluginsDirectory ...)` - see
        # feedback_write_returnvalue_array_wrapping.md; the function already wraps its own result
        # in @() before Write-ReturnValue, so wrapping the call here would nest it one level deeper.
        $result = Get-InstalledConnectorNamesFromPluginsDirectory $installDirPath

        $result | Should -Contain "fileserver"
        $result | Should -Contain "exchange"
        $result | Should -Not -Contain "not-a-connector"
    }

    It "returns an empty array, not an error, when the plugins directory doesn't exist" {
        $installDirPath = Join-Path $TestDrive "saga-install-no-plugins"

        (Get-InstalledConnectorNamesFromPluginsDirectory $installDirPath).Count | Should -Be 0
    }
}

Describe "Get-ConnectorNamesInUse" {
    It "keeps only connector names that have at least one connection" {
        Mock Get-ConnectorConnections {
            param($connectorApiRootUrl, $connectorName)
            if ($connectorName -eq "fileserver") { @([pscustomobject]@{ id = 1 }) } else { @() }
        }

        # Not `@(Get-ConnectorNamesInUse ...)` - see feedback_write_returnvalue_array_wrapping.md.
        $result = Get-ConnectorNamesInUse "http://localhost/api/connector-broker/v1" @("fileserver", "exchange")

        $result.Count | Should -Be 1
        $result[0] | Should -Be "fileserver"
    }
}
