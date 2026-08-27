BeforeAll {
    $logLevel = "off"
    $SCRIPT_PATH = Join-Path $TestDrive "Test.ps1"
    . "$PSScriptRoot/../../Winspect/src/Constants.ps1"
    . "$PSScriptRoot/../../Winspect/src/Logging.ps1"
    . "$PSScriptRoot/../../Winspect/src/Utilities.ps1"
    . "$PSScriptRoot/../src/Constants.ps1"
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
