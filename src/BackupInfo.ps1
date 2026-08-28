function Get-BackupDirectories($installDirPath) {
    Write-FunctionCallLog $PSBoundParameters
    $backupRootPath = Join-Path $installDirPath $BACKUP_RELATIVE_PATH
    if (-not (Test-Path $backupRootPath)) {
        Write-ReturnValue @()
        return
    }
    $backupDirectories = @(Get-ChildItem -Path $backupRootPath -Directory -ErrorAction SilentlyContinue)
    Write-ReturnValue $backupDirectories
}

function Get-LatestBackupTimestamp($backupDirectories) {
    Write-FunctionCallLog $PSBoundParameters
    # Backup directories are named with a yyyyMMddHHmm prefix - matches the naming convention the
    # older tool this is ported from already relies on (Get-LatestBackup).
    $latestBackupDirectory = @($backupDirectories) | Sort-Object Name -Descending | Select-Object -First 1
    $dateTimeString = $latestBackupDirectory.Name.Substring(0, 12)
    $dateTime = [DateTime]::ParseExact($dateTimeString, 'yyyyMMddHHmm', $null)
    Write-ReturnValue $dateTime.ToString('yyyy-MM-dd HH:mm')
}

function Get-BackupsSummary($installDirPath) {
    Write-FunctionCallLog $PSBoundParameters
    $backupDirectories = Get-BackupDirectories $installDirPath
    $backupsSummary = [pscustomobject]@{
        Count        = @($backupDirectories).Count
        LatestBackup = $null
        TotalSize    = $null
    }
    if ($backupsSummary.Count -gt 0) {
        $backupsSummary.LatestBackup = Get-LatestBackupTimestamp $backupDirectories
        $backupRootPath = Join-Path $installDirPath $BACKUP_RELATIVE_PATH
        $backupsSummary.TotalSize = Get-FormattedDirectorySize $backupRootPath
    }
    Write-ReturnValue $backupsSummary
}
