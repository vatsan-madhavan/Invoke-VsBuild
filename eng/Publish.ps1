Install-Module Az.Accounts -Force -Scope AllUsers
Install-Module Az.Resources -Force -Scop AllUsers

Publish-Module                                                                                                  `
    -Path "$(System.ArtifactsDirectory)\$(Release.PrimaryArtifactSourceAlias)\Invoke-VsBuild\Invoke-VsBuild\"   `
    -NuGetApiKey $(PowerShellGalleryApiKey)

