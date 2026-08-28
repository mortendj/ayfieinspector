function Get-RunningContainerNames() {
    Write-FunctionCallLog $PSBoundParameters
    # No embedded whitespace in this template (unlike "{{json .}}" elsewhere in this project), so
    # this is safe to pass straight through Invoke-ExternalCommand's argument array - see the note
    # in SagaCertificateInfo.ps1's Get-SagaInstallDirPath for why a whitespace-containing --format
    # template would need special handling here.
    $containerNames = Invoke-ExternalCommand "docker" @("ps", "--format", "{{.Names}}")
    Write-ReturnValue $containerNames
}

function Get-DockerImagesOfRunningContainers() {
    Write-FunctionCallLog $PSBoundParameters
    $images = Invoke-ExternalCommand "docker" @("ps", "--format", "{{.Image}}")
    Write-ReturnValue ($images -join $PHYSICAL_NEWLINE)
}

function Get-RunningConnectorNames() {
    Write-FunctionCallLog $PSBoundParameters
    $containerNames = Get-RunningContainerNames
    $connectorNames = @()
    foreach ($containerName in $containerNames) {
        if ($containerName -match $CONNECTOR_CONTAINER_NAME_PATTERN) {
            $connectorNames += $Matches[1]
        }
    }
    if ($connectorNames.Count -eq 0) {
        Write-ReturnValue "No containers"
    } else {
        Write-ReturnValue (($connectorNames | ForEach-Object { " - $_" }) -join $PHYSICAL_NEWLINE)
    }
}
