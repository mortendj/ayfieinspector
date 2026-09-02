function Get-SagaInstallDirPath() {
    Write-FunctionCallLog $PSBoundParameters
    # No --format here on purpose - Invoke-ExternalCommand passes each array element straight to
    # Start-Process's -ArgumentList, which splits on internal whitespace rather than quoting it, so
    # a template value like "{{json .}}" arrives at docker split into two broken arguments
    # (confirmed on a real host: "template parsing error: template: :1: unclosed action"). Plain
    # `docker inspect` has no such argument and returns the same data anyway, as a one-element JSON
    # array (multi-line/pretty-printed) - joined back into a single string here since
    # Invoke-ExternalCommand returns it as an array of lines, and ConvertFrom-Json needs the whole
    # document at once rather than one (individually invalid) line at a time.
    $containerConfigJsonLines = Invoke-ExternalCommand "docker" @("inspect", $LICENSING_CONTAINER_NAME)
    $containerConfig = ($containerConfigJsonLines -join "`n") | ConvertFrom-Json
    $mountSources = @($containerConfig[0].Mounts | Select-Object -ExpandProperty Source)
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

function Get-CertificateAuthority($certificate) {
    Write-FunctionCallLog $PSBoundParameters
    Write-ReturnValue $certificate.Issuer
}

function Get-CertificateSubjectAlternativeNames($certificate) {
    Write-FunctionCallLog $PSBoundParameters
    $subjectAlternativeNames = @($certificate.DnsNameList | ForEach-Object { $_.Unicode })
    Write-ReturnValue ($subjectAlternativeNames -join ", ")
}

function Get-CertificateKeyEncryptionStatus($certificateFilePath) {
    Write-FunctionCallLog $PSBoundParameters
    # The private key lives in a separate file next to the certificate itself, same name with a
    # .key extension - not part of the .crt at all, so this is a second, independent file read.
    $certificateKeyFilePath = [System.IO.Path]::ChangeExtension($certificateFilePath, ".key")
    $keyFileContent = Get-Content -Path $certificateKeyFilePath -Raw -ErrorAction Stop
    if ($keyFileContent -match $ENCRYPTED_KEY_PATTERN) {
        Write-ReturnValue "Encrypted"
    } elseif ($keyFileContent -match $UNENCRYPTED_KEY_PATTERN) {
        Write-ReturnValue "Unencrypted"
    } elseif ($keyFileContent -match $RSA_KEY_PATTERN) {
        Write-ReturnValue "RSA key (encryption status not easily determined)"
    } else {
        Write-ReturnValue "Unknown (not a recognized private key file format)"
    }
}

function Get-SagaGatewayCertificateInfo($certificateFilePathOverride) {
    Write-FunctionCallLog $PSBoundParameters
    # Also returns InstallDirPath - not just certificate info - so that Get-SagaInstallDirPath's
    # docker inspect call (the expensive part) only ever needs to run once per run, with other
    # installation facts (SAGA INFO's install directory/version/branding) reusing this same
    # resolution rather than triggering their own redundant docker inspect.
    #
    # An explicit file override is needed for the pre-installation case (checking a host before
    # Saga is actually installed there) - with no running install yet, there's no install
    # directory to auto-discover from, and no live gateway to reach either, so this stays
    # file-only rather than also trying (and failing) a live hostname check against nothing.
    if ($certificateFilePathOverride -ne "") {
        $certificateInfo = [pscustomobject]@{
            CertificateFilePath = $certificateFilePathOverride
            CertificateHostname = ""
            InstallDirPath      = ""
        }
    } else {
        $installDirPath = Get-SagaInstallDirPath
        $dotEnvFilePath = Join-Path $installDirPath $DOT_ENV_RELATIVE_PATH
        $certificateName = Get-DotEnvValue $dotEnvFilePath $GATEWAY_CERTIFICATE_NAME_KEY
        $certificateFilePath = Join-Path $installDirPath (Join-Path $SSL_CERTIFICATE_DIR "$certificateName.crt")
        $certificateHostname = Get-DotEnvValue $dotEnvFilePath $GATEWAY_HOSTNAME_KEY
        $certificateInfo = [pscustomobject]@{
            CertificateFilePath = $certificateFilePath
            CertificateHostname = $certificateHostname
            InstallDirPath      = $installDirPath
        }
    }
    Write-ReturnValue $certificateInfo
}

function Get-ResolvedGmsaAccountName($gmsaAccountName, $installDirPath) {
    Write-FunctionCallLog $PSBoundParameters
    # Auto-discovered from docker/.env the same way the gateway certificate/hostname already are -
    # ConfigInspector does this too (its own Get-GmsaAccountName reads the same
    # AYFIE_SAGA_AD_SERVICE_ACCOUNT key) rather than requiring a caller to pass it explicitly every
    # time. An explicit override always wins; so does the pre-installation case (no install dir yet
    # to auto-discover from, $installDirPath is "").
    $resolvedGmsaAccountName = $gmsaAccountName
    if (($resolvedGmsaAccountName -eq "") -and ($installDirPath -ne "")) {
        try {
            $dotEnvFilePath = Join-Path $installDirPath $DOT_ENV_RELATIVE_PATH
            $autoDiscoveredGmsaAccountName = Get-DotEnvValue $dotEnvFilePath $AD_SERVICE_ACCOUNT_KEY
            if ($null -ne $autoDiscoveredGmsaAccountName) {
                $resolvedGmsaAccountName = $autoDiscoveredGmsaAccountName
            }
        } catch {
            Write-Warning "Could not auto-discover the gMSA account name: $_"
        }
    }
    Write-ReturnValue $resolvedGmsaAccountName
}
