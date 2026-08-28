function Get-LingoDataTypeAndLanguage($installDirPath) {
    Write-FunctionCallLog $PSBoundParameters
    # Kept as its own function (not folded into Get-LingoInfo below) since the SUPERVISOR INFO
    # section reuses this exact same value under its own label ("Report engine Lingo
    # configuration"), matching ConfigInspector's own layout.
    $dotEnvFilePath = Join-Path $installDirPath $DOT_ENV_RELATIVE_PATH
    $language = Get-DotEnvValue $dotEnvFilePath $LINGO_IMAGE_ID_KEY
    if (-not $language) {
        Write-ReturnValue "Not configured"
        return
    }
    if ($language -eq $LINGO_PII_LABEL) {
        $piiLanguage = Get-DotEnvValue $dotEnvFilePath $LINGO_PII_LANGUAGE_KEY
        Write-ReturnValue "$piiLanguage (PII)"
    } elseif ($LINGO_LANGUAGES -contains $language) {
        Write-ReturnValue "$language (regular, not PII)"
    } else {
        Write-ReturnValue "$language (unrecognized value)"
    }
}

function Get-LingoInfo($installDirPath) {
    Write-FunctionCallLog $PSBoundParameters
    $dotEnvFilePath = Join-Path $installDirPath $DOT_ENV_RELATIVE_PATH
    $lingoInfo = [pscustomobject]@{
        Enabled                  = Get-DotEnvValue $dotEnvFilePath $LINGO_ENABLED_KEY
        DataTypeAndLanguage      = Get-LingoDataTypeAndLanguage $installDirPath
        Threads                  = Get-DotEnvValue $dotEnvFilePath $LINGO_THREADS_KEY
        RecycleMemoryThresholdMb = Get-DotEnvValue $dotEnvFilePath $LINGO_RECYCLE_MEM_KEY
        RecycleRuns              = Get-DotEnvValue $dotEnvFilePath $LINGO_RECYCLE_RUNS_KEY
        RecycleTimeSeconds       = Get-DotEnvValue $dotEnvFilePath $LINGO_RECYCLE_TIME_KEY
    }
    Write-ReturnValue $lingoInfo
}
