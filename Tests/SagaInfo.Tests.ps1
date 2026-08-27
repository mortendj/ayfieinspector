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
