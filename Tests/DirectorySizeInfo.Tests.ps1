BeforeAll {
    $logLevel = "off"
    $SCRIPT_PATH = Join-Path $TestDrive "Test.ps1"
    . "$PSScriptRoot/../../Winspect/src/Constants.ps1"
    . "$PSScriptRoot/../../Winspect/src/Logging.ps1"
    . "$PSScriptRoot/../../Winspect/src/Utilities.ps1"
    . "$PSScriptRoot/../src/DirectorySizeInfo.ps1"
}

Describe "Get-FormattedDirectorySize" {
    It "sums file sizes recursively and formats with the right unit" {
        $dirPath = Join-Path $TestDrive "sized-dir"
        New-Item -ItemType Directory -Path (Join-Path $dirPath "sub") -Force | Out-Null
        Set-Content -Path (Join-Path $dirPath "a.txt") -Value ("x" * 1024)
        Set-Content -Path (Join-Path $dirPath "sub/b.txt") -Value ("x" * 1024)

        $result = Get-FormattedDirectorySize $dirPath

        $result | Should -Match "KB$"
    }

    It "returns 'N/A' when the directory doesn't exist, rather than throwing" {
        $dirPath = Join-Path $TestDrive "does-not-exist"

        Get-FormattedDirectorySize $dirPath | Should -Be "N/A"
    }

    It "returns a zero-byte size, not an error, for an empty directory" {
        $dirPath = Join-Path $TestDrive "empty-dir"
        New-Item -ItemType Directory -Path $dirPath -Force | Out-Null

        Get-FormattedDirectorySize $dirPath | Should -Be "0.000 B"
    }
}
