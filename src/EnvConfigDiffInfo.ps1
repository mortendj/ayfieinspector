function Get-ReferenceEnvFileKeyValuePairs($installDirPath) {
    Write-FunctionCallLog $PSBoundParameters
    $sagaZipFilePath = Join-Path $installDirPath $SAGA_ZIP_FILE_NAME
    $tempDirPath = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $tempDirPath -Force | Out-Null
    try {
        Expand-Archive -Path $sagaZipFilePath -DestinationPath $tempDirPath -Force
        $referenceEnvFilePath = Join-Path $tempDirPath $REFERENCE_DOT_ENV_RELATIVE_PATH
        Write-ReturnValue (Get-EnvFileKeyValuePairs $referenceEnvFilePath)
    } finally {
        Remove-Item -Path $tempDirPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-DecoratedEnvKeyList($keys, $keyValuePairs, $skipValue) {
    Write-FunctionCallLog $PSBoundParameters
    # "None" / a single bare value / a bulleted multi-line block, depending on count - matches the
    # older tool this is ported from, whose single-value case deliberately stays inline rather than
    # dropping to its own bulleted line for what's usually the common case (one changed variable).
    $keys = @($keys)
    if ($keys.Count -eq 0) {
        Write-ReturnValue "None"
        return
    }
    $decoratedKeys = @($keys | ForEach-Object {
        if ($skipValue) { $_ } else { "$_ ($($keyValuePairs[$_]))" }
    })
    if ($decoratedKeys.Count -eq 1) {
        Write-ReturnValue $decoratedKeys[0]
    } else {
        $bulletedLines = @($decoratedKeys | ForEach-Object { "${INDENTATION}- $_" })
        Write-ReturnValue ($LOGICAL_NEWLINE + ($bulletedLines -join $LOGICAL_NEWLINE))
    }
}

function Get-EnvConfigDiff($installDirPath) {
    Write-FunctionCallLog $PSBoundParameters
    # Three-way diff against the as-shipped reference (from Ayfie.Saga.zip), not just a two-way
    # current-vs-reference diff - a key present in custom.env is a supported, intentional override,
    # not an unexpected hand-edit of docker/.env itself, so it's excluded from both the added and
    # modified lists even though it also differs from the reference.
    $referenceDict = Remove-SensitiveDotEnvKeys (Get-ReferenceEnvFileKeyValuePairs $installDirPath) $SENSITIVE_ENV_TOKENS
    $actualEnvFilePath = Join-Path $installDirPath $DOT_ENV_RELATIVE_PATH
    $actualDict = Remove-SensitiveDotEnvKeys (Get-EnvFileKeyValuePairs $actualEnvFilePath) $SENSITIVE_ENV_TOKENS

    $customEnvFilePath = Join-Path $installDirPath $CUSTOM_ENV_RELATIVE_PATH
    $customDict = [ordered]@{}
    if (Test-Path $customEnvFilePath) {
        $customDict = Get-EnvFileKeyValuePairs $customEnvFilePath
    }

    $addedKeys = @($actualDict.Keys | Where-Object { $_ -notin $referenceDict.Keys -and $_ -notin $customDict.Keys })
    $removedKeys = @($referenceDict.Keys | Where-Object { $_ -notin $actualDict.Keys })
    $modifiedKeys = @($referenceDict.Keys | Where-Object {
        $actualDict.Contains($_) -and $actualDict[$_] -ne $referenceDict[$_] `
            -and $_ -ne $COMPOSE_FILE_KEY -and $_ -notin $customDict.Keys
    })

    $envConfigDiff = [pscustomobject]@{
        Removed  = Get-DecoratedEnvKeyList $removedKeys $actualDict $true
        Added    = Get-DecoratedEnvKeyList $addedKeys $actualDict $false
        Modified = Get-DecoratedEnvKeyList $modifiedKeys $actualDict $false
    }
    Write-ReturnValue $envConfigDiff
}
