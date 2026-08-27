function Get-SagaVersion($installDirPath) {
    Write-FunctionCallLog $PSBoundParameters
    $gitVersionFilePath = Join-Path $installDirPath $GIT_VERSION_RELATIVE_PATH
    $gitVersionJson = Get-Content -Path $gitVersionFilePath -Raw -ErrorAction Stop | ConvertFrom-Json
    Write-ReturnValue "$($gitVersionJson.Major).$($gitVersionJson.Minor).$($gitVersionJson.Patch)"
}

function Get-OsSupportSummary($operatingSystemVersion) {
    Write-FunctionCallLog $PSBoundParameters
    $isSupported = $false
    foreach ($supportedOs in $SUPPORTED_OS) {
        if ($operatingSystemVersion -match $supportedOs) {
            $isSupported = $true
            break
        }
    }
    if ($isSupported) {
        Write-ReturnValue "Supported"
    } else {
        Write-ReturnValue "WARNING: '$operatingSystemVersion' is not a version supported by Ayfie Index (Saga)"
    }
}
