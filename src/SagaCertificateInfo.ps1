function Get-SagaInstallDirPath() {
    Write-FunctionCallLog $PSBoundParameters
    $containerConfigJson = Invoke-ExternalCommand "docker" @("inspect", $LICENSING_CONTAINER_NAME, "--format", "{{json .}}")
    $containerConfig = $containerConfigJson | ConvertFrom-Json
    $mountSources = @($containerConfig.Mounts | Select-Object -ExpandProperty Source)
    $sagaInstallDirPath = $null
    if ($mountSources.Count -ge 2) {
        # The install directory itself isn't reported anywhere directly - derived here as the
        # longest common path prefix of two of the container's own bind mounts, which always sit
        # somewhere under it.
        $mountPoint1 = $mountSources[0]
        $mountPoint2 = $mountSources[1]
        $commonPrefix = ""
        $shorterLength = [Math]::Min($mountPoint1.Length, $mountPoint2.Length)
        for ($i = 0; $i -lt $shorterLength -and $mountPoint1[$i] -eq $mountPoint2[$i]; $i++) {
            $commonPrefix += $mountPoint1[$i]
        }
        $sagaInstallDirPath = $commonPrefix
    }
    Write-ReturnValue $sagaInstallDirPath
}

function Get-DotEnvValue($dotEnvFilePath, $key) {
    Write-FunctionCallLog $PSBoundParameters
    $value = $null
    $matchingLine = Get-Content -Path $dotEnvFilePath -ErrorAction Stop |
        Where-Object { $_ -match "^\s*$([regex]::Escape($key))\s*=" } |
        Select-Object -First 1
    if ($matchingLine) {
        $value = ($matchingLine -split '=', 2)[1].Trim()
    }
    Write-ReturnValue $value
}

function Get-SagaGatewayCertificateFilePath($certificateFilePathOverride) {
    Write-FunctionCallLog $PSBoundParameters
    # An explicit override is needed for the pre-installation case (checking a host before Saga is
    # actually installed there) - with no install directory yet, auto-discovery has nothing to find.
    if ($certificateFilePathOverride -ne "") {
        $certificateFilePath = $certificateFilePathOverride
    } else {
        $installDirPath = Get-SagaInstallDirPath
        $dotEnvFilePath = Join-Path $installDirPath $DOT_ENV_RELATIVE_PATH
        $certificateName = Get-DotEnvValue $dotEnvFilePath $GATEWAY_CERTIFICATE_NAME_KEY
        $certificateFilePath = Join-Path $installDirPath (Join-Path $SSL_CERTIFICATE_DIR "$certificateName.crt")
    }
    Write-ReturnValue $certificateFilePath
}
