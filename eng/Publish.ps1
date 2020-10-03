[CmdletBinding(PositionalBinding=$false)]
param (
    [Parameter(Mandatory=$true)]
    [string]
    $ArtifactsDirectory, 

    [Parameter(Mandatory=$true)]
    [string]
    $PrimaryArtifactsSourceAlias
)
Install-Module Az.Accounts -Force -Scope AllUsers
Install-Module Az.Resources -Force -Scop AllUsers

Publish-Module                                                                                  `
    -Path "$(ArtifactsDirectory)\$(PrimaryArtifactsSourceAlias)\Invoke-VsBuild\Invoke-VsBuild\" `
    -NuGetApiKey $(PowerShellGalleryApiKey)

