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

function Get-SecurityClearedEnvFileContent($envFilePath, $sensitiveTokens) {
    Write-FunctionCallLog $PSBoundParameters
    $keyValuePairs = Get-EnvFileKeyValuePairs $envFilePath
    $lines = @()
    foreach ($key in $keyValuePairs.Keys) {
        $isSensitive = $false
        foreach ($token in $sensitiveTokens) {
            if ($key -like "*$token*") {
                $isSensitive = $true
                break
            }
        }
        if (-not $isSensitive) {
            $lines += "$key=$($keyValuePairs[$key])"
        }
    }
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
