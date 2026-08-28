BeforeAll {
    $logLevel = "off"
    $SCRIPT_PATH = Join-Path $TestDrive "Test.ps1"
    . "$PSScriptRoot/../../Winspect/src/Constants.ps1"
    . "$PSScriptRoot/../../Winspect/src/Logging.ps1"
    . "$PSScriptRoot/../../Winspect/src/Utilities.ps1"
    . "$PSScriptRoot/../src/Constants.ps1"
    . "$PSScriptRoot/../src/DirectorySizeInfo.ps1"
    . "$PSScriptRoot/../src/BackupInfo.ps1"

    function New-TestBackupDirectory($installDirPath, $backupDirName) {
        $backupDirPath = Join-Path (Join-Path $installDirPath "backup/data") $backupDirName
        New-Item -ItemType Directory -Path $backupDirPath -Force | Out-Null
        Set-Content -Path (Join-Path $backupDirPath "backup.zip") -Value ("x" * 100)
    }
}

Describe "Get-BackupDirectories" {
    It "returns the backup subdirectories under backup/data" {
        $installDirPath = Join-Path $TestDrive "saga-install-backups"
        New-TestBackupDirectory $installDirPath "202603211759_full"
        New-TestBackupDirectory $installDirPath "202603201800_full"

        # Not `@(Get-BackupDirectories ...)` - see feedback_write_returnvalue_array_wrapping.md;
        # Get-BackupDirectories already wraps its own result in @() before Write-ReturnValue, so
        # wrapping the call itself here would nest the real array one level deeper.
        $result = Get-BackupDirectories $installDirPath

        $result.Count | Should -Be 2
    }

    It "returns an empty array, not an error, when the backup directory doesn't exist" {
        $installDirPath = Join-Path $TestDrive "saga-install-no-backups"

        (Get-BackupDirectories $installDirPath).Count | Should -Be 0
    }
}

Describe "Get-LatestBackupTimestamp" {
    It "picks the most recent backup directory and formats its yyyyMMddHHmm-prefixed name" {
        $installDirPath = Join-Path $TestDrive "saga-install-latest"
        New-TestBackupDirectory $installDirPath "202603211759_full"
        New-TestBackupDirectory $installDirPath "202603201800_full"
        $backupDirectories = Get-BackupDirectories $installDirPath

        Get-LatestBackupTimestamp $backupDirectories | Should -Be "2026-03-21 17:59"
    }
}

Describe "Get-BackupsSummary" {
    It "reports zero count and no latest/size fields when there are no backups" {
        $installDirPath = Join-Path $TestDrive "saga-install-summary-empty"

        $result = Get-BackupsSummary $installDirPath

        $result.Count | Should -Be 0
        $result.LatestBackup | Should -BeNullOrEmpty
        $result.TotalSize | Should -BeNullOrEmpty
    }

    It "reports count, latest backup, and total size when backups exist" {
        $installDirPath = Join-Path $TestDrive "saga-install-summary-full"
        New-TestBackupDirectory $installDirPath "202603211759_full"

        $result = Get-BackupsSummary $installDirPath

        $result.Count | Should -Be 1
        $result.LatestBackup | Should -Be "2026-03-21 17:59"
        $result.TotalSize | Should -Not -BeNullOrEmpty
    }
}
