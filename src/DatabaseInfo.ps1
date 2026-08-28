function Get-DatabaseInfo($installDirPath) {
    Write-FunctionCallLog $PSBoundParameters
    $dotEnvFilePath = Join-Path $installDirPath $DOT_ENV_RELATIVE_PATH
    $databaseInfo = [pscustomobject]@{
        Type   = Get-DotEnvValue $dotEnvFilePath $DATABASE_TYPE_KEY
        Name   = Get-DotEnvValue $dotEnvFilePath $DATABASE_NAME_KEY
        User   = Get-DotEnvValue $dotEnvFilePath $DATABASE_USER_KEY
        Server = Get-DotEnvValue $dotEnvFilePath $DATABASE_SERVER_KEY
        Port   = Get-DotEnvValue $dotEnvFilePath $DATABASE_PORT_KEY
    }
    Write-ReturnValue $databaseInfo
}

function Get-AdAndAzureAdSync($installDirPath) {
    Write-FunctionCallLog $PSBoundParameters
    $dotEnvFilePath = Join-Path $installDirPath $DOT_ENV_RELATIVE_PATH
    Write-ReturnValue (Get-DotEnvValue $dotEnvFilePath $AD_AAD_SYNC_KEY)
}
