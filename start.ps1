<#
.SYNOPSIS
    Starts the Vagrant VM with the environment variables the Octopus Helm
    charts need. The PowerShell equivalent of start.sh.

.EXAMPLE
    .\start.ps1 <bearer-token>

.EXAMPLE
    .\start.ps1 <bearer-token> Scratchpad mattc.octopus.app

.NOTES
    This must be run as Administrator when using the Hyper-V provider.
#>

param(
    [Parameter(Mandatory = $true, Position = 0, HelpMessage = "The Octopus bearer token")]
    [string]$BearerToken,

    [Parameter(Position = 1)]
    [string]$SpaceName = "Scratchpad",

    [Parameter(Position = 2)]
    [string]$OctopusHostname = "mattc.octopus.app",

    [Parameter(Position = 3)]
    [string]$Provider = "hyperv"
)

$ErrorActionPreference = "Stop"

Set-Location -Path $PSScriptRoot

# Get space ID from Octopus API using the space name
try {
    $Spaces = Invoke-RestMethod -Method Get `
        -Uri "https://${OctopusHostname}/api/spaces?partialName=$([uri]::EscapeDataString($SpaceName))" `
        -Headers @{ Authorization = "Bearer ${BearerToken}" }
}
catch {
    Write-Error "Error: Could not query the spaces on ${OctopusHostname}: $($_.Exception.Message)"
    exit 1
}

$SpaceId = ($Spaces.Items | Where-Object { $_.Name -eq $SpaceName } | Select-Object -First 1).Id

if ([string]::IsNullOrEmpty($SpaceId)) {
    Write-Error "Error: Could not find space named ${SpaceName}"
    exit 1
}

Write-Host "Found space: ${SpaceName} (${SpaceId})"

$env:OCTOPUS_TEMPK8S_GRPC_HOSTNAME = "${OctopusHostname}:8443"
$env:OCTOPUS_TEMPK8S_HOSTNAME = $OctopusHostname
$env:OCTOPUS_TEMPK8S_POLLING_HOSTNAME = "polling.${OctopusHostname}"
$env:OCTOPUS_TEMPK8S_SPACE = $SpaceName
$env:OCTOPUS_TEMPK8S_SPACE_ID = $SpaceId
$env:OCTOPUS_TEMPK8S_BEARER_TOKEN = $BearerToken

vagrant up --provider=$Provider

exit $LASTEXITCODE
