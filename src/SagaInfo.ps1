function Get-SagaVersion($installDirPath) {
    Write-FunctionCallLog $PSBoundParameters
    $gitVersionFilePath = Join-Path $installDirPath $GIT_VERSION_RELATIVE_PATH
    $gitVersionJson = Get-Content -Path $gitVersionFilePath -Raw -ErrorAction Stop | ConvertFrom-Json
    Write-ReturnValue "$($gitVersionJson.Major).$($gitVersionJson.Minor).$($gitVersionJson.Patch)"
}
