function Get-PersonalAssistantInfo($installDirPath) {
    Write-FunctionCallLog $PSBoundParameters
    $dotEnvFilePath = Join-Path $installDirPath $DOT_ENV_RELATIVE_PATH
    $personalAssistantInfo = [pscustomobject]@{
        Mode                            = Get-DotEnvValue $dotEnvFilePath $PA_MODE_KEY
        MainModel                       = Get-DotEnvValue $dotEnvFilePath $PA_MAIN_MODEL_KEY
        MainModelDisplayName            = Get-DotEnvValue $dotEnvFilePath $PA_MAIN_MODEL_NAME_KEY
        HighQualityModel                = Get-DotEnvValue $dotEnvFilePath $PA_HQ_MODEL_KEY
        HighQualityModelDisplayName     = Get-DotEnvValue $dotEnvFilePath $PA_HQ_MODEL_NAME_KEY
        HighQualityPlusModel            = Get-DotEnvValue $dotEnvFilePath $PA_HQ_PLUS_MODEL_KEY
        HighQualityPlusModelDisplayName = Get-DotEnvValue $dotEnvFilePath $PA_HQ_PLUS_MODEL_NAME_KEY
    }
    Write-ReturnValue $personalAssistantInfo
}
