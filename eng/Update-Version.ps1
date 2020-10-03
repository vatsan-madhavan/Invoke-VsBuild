function Get-NextBuild {
    param (
        [System.Version]
        $Version
    )

    if ($Version.Build -eq [int]::MaxValue) {
        Write-Error "Build too large - cannot find next Build" -ErrorAction Stop
    }

    if ($Version.Revision -gt 0) {
        New-Object System.Version $Version.Major, $Version.Minor, ($Version.Build + 1), $Version.Revision
    } else {
        New-Object System.Version $Version.Major, $Version.Minor, ($Version.Build + 1)
    }
}

[string] $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
[string]$manifestPath = Join-Path (get-item $scriptPath).Parent.FullName 'Invoke-VsBuild\Invoke-VsBuild.psd1'
[psmoduleinfo]$module = Test-ModuleManifest -Path $manifestPath

Write-Verbose "Module Version: ($module.Version)"
[Version]$updatedVersion = Get-NextBuild -Version $module.Version
Write-Verbose "New Version: $updatedVersion"
Update-ModuleManifest -Path $manifestPath -ModuleVersion $updatedVersion

Write-Host "##vso[task.setvariable variable=UpdatedModuleVersion;]$updatedVersion"
Write-Host "Updated Module Version to $updatedVersion"