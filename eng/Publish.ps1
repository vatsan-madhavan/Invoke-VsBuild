Install-Module Az.Accounts -Force -Scope AllUsers
Install-Module Az.Resources -Force -Scop AllUsers

[string] $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
[string] $publishLocation = Join-Path (get-item $scriptPath).Parent.FullName 'Invoke-VsBuild\'

Publish-Module              `
    -Path $publishLocation  `
    -NuGetApiKey $(PowerShellGalleryApiKey)

