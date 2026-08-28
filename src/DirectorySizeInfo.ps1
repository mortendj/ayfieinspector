function Get-FormattedDirectorySize($directoryPath) {
    Write-FunctionCallLog $PSBoundParameters
    if (-not (Test-Path $directoryPath)) {
        Write-ReturnValue "N/A"
        return
    }
    $totalBytes = Get-ChildItem -Path $directoryPath -Recurse -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum | Select-Object -ExpandProperty Sum
    if (-not $totalBytes) {
        $totalBytes = 0
    }
    $units = "B", "KB", "MB", "GB", "TB"
    $unitIndex = 0
    $size = [double]$totalBytes
    while ($size -ge 1024 -and $unitIndex -lt ($units.Length - 1)) {
        $size = $size / 1024
        $unitIndex++
    }
    # Explicit invariant culture, not the host's own - the -f operator's "{0:N3}" otherwise uses the
    # current culture's decimal separator (confirmed on this very machine: a comma instead of a
    # period), which would make the report's format depend on the locale of whoever runs it.
    $invariantCulture = [System.Globalization.CultureInfo]::InvariantCulture
    $formattedSize = $size.ToString("N3", $invariantCulture)
    Write-ReturnValue "$formattedSize $($units[$unitIndex])"
}
