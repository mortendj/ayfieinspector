function Get-EnvFileKeyValuePairs($envFilePath) {
    Write-FunctionCallLog $PSBoundParameters
    $keyValuePairs = [ordered]@{}
    Get-Content -Path $envFilePath -ErrorAction Stop | ForEach-Object {
        $line = $_.Trim()
        if ($line -ne "" -and -not $line.StartsWith("#")) {
            $parts = $line -split '=', 2
            if ($parts.Count -eq 2) {
                $keyValuePairs[$parts[0].Trim()] = $parts[1].Trim()
            }
        }
    }
    Write-ReturnValue $keyValuePairs
}

function Remove-SensitiveDotEnvKeys($keyValuePairs, $sensitiveTokens) {
    Write-FunctionCallLog $PSBoundParameters
    # Same "drop the whole key, don't mask the value" redaction principle used throughout this
    # project (custom.env content, data source connection settings) - operates on the parsed
    # dictionary rather than raw text so callers that need the filtered key/value data itself (the
    # .env config diff), not just a rendered text block, can reuse it too.
    $clearedKeyValuePairs = [ordered]@{}
    foreach ($key in $keyValuePairs.Keys) {
        $isSensitive = $false
        foreach ($token in $sensitiveTokens) {
            if ($key -like "*$token*") {
                $isSensitive = $true
                break
            }
        }
        if (-not $isSensitive) {
            $clearedKeyValuePairs[$key] = $keyValuePairs[$key]
        }
    }
    Write-ReturnValue $clearedKeyValuePairs
}

function Get-SecurityClearedEnvFileContent($envFilePath, $sensitiveTokens) {
    Write-FunctionCallLog $PSBoundParameters
    $keyValuePairs = Remove-SensitiveDotEnvKeys (Get-EnvFileKeyValuePairs $envFilePath) $sensitiveTokens
    $lines = @($keyValuePairs.Keys | ForEach-Object { "$_=$($keyValuePairs[$_])" })
    Write-ReturnValue ($lines -join $PHYSICAL_NEWLINE)
}

function Get-CustomEnvFileContent($installDirPath) {
    Write-FunctionCallLog $PSBoundParameters
    $customEnvFilePath = Join-Path $installDirPath $CUSTOM_ENV_RELATIVE_PATH
    if (Test-Path $customEnvFilePath) {
        $content = Get-SecurityClearedEnvFileContent $customEnvFilePath $SENSITIVE_ENV_TOKENS
        if ($content -eq "") {
            $content = "(empty)"
        }
    } else {
        $content = "Not present (no customizations)"
    }
    Write-ReturnValue $content
}
