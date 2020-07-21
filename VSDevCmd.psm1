class VsDevCmd {
    hidden [System.Collections.Generic.Dictionary[string, string]]$SavedEnv = @{}
    static hidden [string] $vswhere = [VsDevCmd]::Initialize_VsWhere()
    hidden [string]$vsDevCmd

    static [string] hidden Initialize_VsWhere() {
        return [VsDevCmd]::Initialize_VsWhere($env:TEMP)
    }

    static [string] hidden Initialize_VsWhere([string] $InstallDir) {
        # Look for vswhere in these locations:
        # - ${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe
        # -  $InstallDir\
        # -  $env:TEMP\
        # -  Anywhere in $env:PATH
        # If found, do not re-download.

        [string]$vswhereExe = 'vswhere.exe'
        [string]$visualStudioIntallerPath = Join-Path "${env:ProgramFiles(x86)}\\Microsoft Visual Studio\\Installer\" $vswhereExe
        [string]$downloadPath = Join-path $InstallDir $vswhereExe
        [string]$VsWhereTempPath = Join-Path $env:TEMP $vswhereExe

        # Look under VS Installer Path
        if (Test-Path $visualStudioIntallerPath -PathType Leaf) {
            return $visualStudioIntallerPath
        }

        # Look under $InstallDir
        if (Test-Path $downloadPath -PathType Leaf) {
            return $downloadPath
        }

        # Look under $env:TEMP
        if (Test-Path $VsWhereTempPath -PathType Leaf) {
            return $VsWhereTempPath
        }

        # Search $env:PATH
        $vsWhereCmd = Get-Command $vswhereExe -ErrorAction SilentlyContinue
        if ($vsWhereCmd -and $vsWhereCmd.Source -and (Test-Path $vsWhereCmd.Source)) {
            return $vsWhereCmd.Source
        }

        # Short-circuit logic didn't work - prepare to download a new copy of vswhere
        if (-not (Test-Path -Path $InstallDir)) {
            New-Item -ItemType Directory -Path $InstallDir | Out-Null
        }

        if (-not (Test-Path -Path $InstallDir -PathType Container)) {
            throw New-Object System.ArgumentException -ArgumentList 'Directory could not be created', 'InstallDir'
        }

        $vsWhereUri = 'https://github.com/microsoft/vswhere/releases/download/2.8.4/vswhere.exe'

        if (-not (Test-Path -Path $downloadPath -PathType Leaf)) {
            Invoke-WebRequest -Uri $vsWhereUri -OutFile (Join-Path $InstallDir 'vswhere.exe')
        }

        if (-not (Test-Path -Path $downloadPath -PathType Leaf)) {
            Write-Error "$downloadPath could not not be provisioned" -ErrorAction Stop
        }

        return $downloadPath
    }

    VsDevCmd() {
        $this.vsDevCmd = [VsDevCmd]::GetVsDevCmdPath($null, $null, $null, $null)
    }

    <#
        [string] $productDisplayVersion,    # 16.8.0, 15.9.24 etc.
        [string] $edition,                  # Professional, Enterprise etc.
        [string] $productLineVersion,       # 2015, 2017, 2019 etc.
        [string] $productLine) {            # Dev15, Dev16 etc.
    #>
    VsDevCmd([string]$productDisplayVersion, [string]$edition, [string]$productLineVersion, [string] $productLine) {
        $this.vsDevCmd = [VsDevCmd]::GetVsDevCmdPath($productDisplayVersion, $edition, $productLineVersion, $productLine)
    }

    [void] hidden Update_EnvironmentVariable ([string] $Name, [string] $Value) {
        if (-not ($this.SavedEnv.ContainsKey($Name))) {
            $oldValue = [System.Environment]::GetEnvironmentVariable($Name, [System.EnvironmentVariableTarget]::Process)
            $this.SavedEnv[$Name] = $oldValue
        }

        Write-Verbose "Updating env[$name] = $value"
        [System.Environment]::SetEnvironmentVariable("$name", "$value", [System.EnvironmentVariableTarget]::Process)
    }

    [void] hidden Restore_Environment() {
        $this.SavedEnv.Keys | ForEach-Object {
            $name = $_
            $value = $this.SavedEnv[$name]
            if (-not $value) {
                $value = [string]::Empty
            }
            [System.Environment]::SetEnvironmentVariable("$name", "$value", [System.EnvironmentVariableTarget]::Process)
        }
        $this.SavedEnv.Clear()
    }

    [string] hidden static GetVsDevCmdPath(
        [string] $productDisplayVersion,    # 16.8.0, 15.9.24 etc.
        [string] $edition,                  # Professional, Enterprise etc.
        [string] $productLineVersion,       # 2015, 2017, 2019 etc.
        [string] $productLine) {            # Dev15, Dev16 etc.

            <#
                productLineVersion  productLine
                2015                Dev14
                2017                Dev15
                2019                Dev16
            #>
            [hashtable]$productLineInfo = @{
                "Dev14" = "2015";
                "Dev15" = "2017";
                "Dev16" = "2019"
            }

            # Validate that productLineVersion and productLine are mutually consistent
            if ($productLineVersion -and $productLine) {
                if (-not $productLineInfo.ContainsKey($productLineVersion)) {
                    # error
                    throw New-Object System.ArgumentOutOfRangeException 'productLineVersion'
                }
                if ($productLineInfo[$productLineVersion] -ine $productLine) {
                    # error
                    throw New-Object System.ArgumentException("{productLineVersion{$productLineVersion}} and {productLine{$productLine}} are not mutually consistent; {productLine} should be {$productLineInfo[$productLineVersion]}", 'productLine')
                }
            }


            [array]$installations = . "$([VsDevCmd]::vswhere)" -prerelease -legacy -format json | ConvertFrom-Json

            # Use only installations with a catalog
            $installations = $installations | Where-Object {
                Get-Member -InputObject $_ -Name "catalog" -MemberType Properties
            }

            if ($productDisplayVersion) {
                $installations = $installations | Where-Object {
                    $_.catalog.productDisplayVersion -ilike $productDisplayVersion
                }
            }

            if ($productLineVersion) {
                $installations = $installations | Where-Object {
                    $_.catalog.productLineVersion -ieq $productLineVersion
                }
            }

            if ($productLine -and (-not $productLineVersion)) {
                $installations = $installations | Where-Object {
                    $_.catalog.productLine -ieq $productLine
                }
            }

            if ($productDisplayVersion) {
                $installations = $installations | Where-Object {
                    $_.catalog.productDisplayVersion -ilike $productDisplayVersion
                }
            }

            if ($edition) {
                $installations = $installations | Where-Object {
                    $_.productId -ilike "*$edition"
                }
            }

            [string]$installationPath = if ($installations -is [array]) { $installations[0].installationPath } else { $installations.installationPath }

            if ((-not $installationPath) -or (-not (test-path -Path $installationPath -PathType Container))) {
                throw New-Object System.IO.DirectoryNotFoundException 'Installation Path Not found'
            }

            $vsDevCmdDir = Join-Path (Join-Path $installationPath 'Common7') 'Tools'
            $vsDevCmdName = 'vsDevCmd.bat'

            $vsDevCmdPath = Join-Path $vsDevCmdDir $vsDevCmdName
            if (test-path -PathType Leaf -Path $vsDevCmdPath) {
                return $vsDevCmdPath
            }

            $vsDevCmdAltName = 'vsVars32.bat'
            $vsDevCmdPath = Join-Path $vsDevCmdDir $vsDevCmdAltName
            if (test-path -PathType Leaf -Path $vsDevCmdPath) {
                return $vsDevCmdPath
            }

            throw New-Object System.IO.FileNotFoundException "$vsDevCmdPath not found"
    }

    [void] hidden Start_VsDevCmd() {
        [string]$vsDevCmdPath = $this.vsDevCmd

        # older vcvars32.bat doesn't understand no-logo argument
        [string]$cmd = if ((Split-Path -Leaf $vsDevCmdPath) -ieq 'vsvars32.bat') {"`"$vsDevCmdPath`" && set"} else { "`"$vsDevCmdPath`" -no_logo && set" }
        [string[]]$envVars = . "${env:COMSPEC}" /s /c $cmd
        foreach ($envVar in $envVars) {
            [string]$name, [string]$value = $envVar -split '=', 2
            Write-Verbose "Setting env:$name=$value"
            if ($name -and $value) {
                $this.Update_EnvironmentVariable($name, $value)
            }
       }
    }


    [string[]] Start_BuildCommand ([string]$Command, [string[]]$Arguments) {
        return $this.Start_BuildCommand($Command, $Arguments, $false) # non-interactive
    }

    [string[]] Start_BuildCommand ([string]$Command, [string[]]$Arguments, [bool]$interactive) {
        try {
            $this.Start_VsDevCmd()

            $cmdObject = Get-Command $Command -ErrorAction SilentlyContinue -CommandType Application
            if (-not $cmdObject) {
                throw New-Object System.ArgumentException 'Application Not Found', $Command
            }

            [string] $cmd = if ($cmdObject -is [array]) { $cmdObject[0].Source } else { $cmdObject.Source }
            Write-Verbose "$cmd"

            [string]$result = [string]::Empty
            [System.Diagnostics.Process]$p = $null
            if ($Arguments -and $Arguments.Count -gt 0) {
                $p = Start-Process -FilePath "$cmd" -ArgumentList $Arguments -NoNewWindow -OutVariable result -PassThru
            } else {
                $p = Start-Process -FilePath "$cmd" -NoNewWindow -OutVariable result -PassThru
            }
            if ($interactive) {
                $p.WaitForExit() | Out-Host
            } else {
                $p.WaitForExit()
            }
            return $result
        }
        finally {
            $this.Restore_Environment()
        }
    }
}

function Invoke-VsDevCommand {
    [CmdletBinding(DefaultParameterSetName='Default')]
    param (
        [Parameter(ParameterSetName = 'Default', Position=0 ,Mandatory=$true, HelpMessage='Application or Command to Run')]
        [Parameter(ParameterSetName = 'CodeName', Position=0 ,Mandatory=$true, HelpMessage='Application or Command to Run')]
        [string]
        $Command,

        [Parameter(ParameterSetName = 'Default', Position=1, ValueFromRemainingArguments, HelpMessage='List of arguments')]
        [Parameter(ParameterSetName = 'CodeName', Position=1, ValueFromRemainingArguments, HelpMessage='List of arguments')]
        [string[]]
        $Arguments,

        [Parameter(ParameterSetName='Default', Mandatory = $false, HelpMessage='Selects Visual Studio Development Environment based on Edition (Community, Professional, Enterprise, etc.)')]
        [Parameter(ParameterSetName='CodeName', Mandatory = $false, HelpMessage='Selects Visual Studio Development Environment based on Edition (Community, Professional, Enterprise, etc.)')]
        [CmdletBinding(PositionalBinding=$false)]
        [Alias('Edition')]
        [ValidateSet('Community', 'Professional', 'Enteprise', $null)]
        [string]
        $VisualStudioEdition = $null,

        [Parameter(ParameterSetName='Default', Mandatory = $false, HelpMessage='Selects Visual Studio Development Environment based on Version (2015, 2017, 2019 etc.)')]
        [CmdletBinding(PositionalBinding=$false)]
        [Alias('Version')]
        [ValidateSet('2015', '2017', '2019', $null)]
        [string]
        $VisualStudioVersion = $null,

        [Parameter(ParameterSetName='CodeName', Mandatory = $false, HelpMessage='Selects Visual Studio Development Environment based on Version CodeName (Dev14, Dev15, Dev16 etc.)')]
        [CmdletBinding(PositionalBinding=$false)]
        [Alias('CodeName')]
        [ValidateSet('Dev14', 'Dev15', 'Dev16', $null)]
        [string]
        $VisualStudioCodeName=$null,

        [Parameter(ParameterSetName='Default', Mandatory = $false, HelpMessage='Selects Visual Studio Development Environment based on Build Version (e.g., "15.9.25", "16.8.0"). A prefix is sufficient (e.g., "15", "15.9", "16" etc.)')]
        [Parameter(ParameterSetName='CodeName', Mandatory = $false, HelpMessage='Selects Visual Studio Development Environment based on Build Version (e.g., "15.9.25", "16.8.0"). A prefix is sufficient (e.g., "15", "15.9", "16" etc.)')]
        [Alias('BuildVersion')]
        [CmdletBinding(PositionalBinding=$false)]
        [string]
        $VisualStudioBuildVersion = $null,

        [Parameter(ParameterSetName='Default', HelpMessage='Runs in interactive mode. Useful for running programs like cmd.exe, pwsh.exe, powershell.exe or csi.exe in the Visual Studio Developer Command Prompt Environment')]
        [Parameter(ParameterSetName='CodeName', HelpMessage='Runs in interactive mode. Useful for running programs like cmd.exe, pwsh.exe, powershell.exe or csi.exe in the Visual Studio Developer Command Prompt Environment')]
        [CmdletBinding(PositionalBinding=$false)]
        [switch]
        $Interactive
    )

    <#
        Parameter mapping:
            [string] $productDisplayVersion,    # 16.8.0, 15.9.24 etc.              $VisualStudioBuildVersion
            [string] $edition,                  # Professional, Enterprise etc.     $VisualStudioEdition
            [string] $productLineVersion,       # 2015, 2017, 2019 etc.             $VisualStudioVersion
            [string] $productLine) {            # Dev15, Dev16 etc.                 $VisualStudioCodeName
    #>

    [VsDevCmd]::new($VisualStudioBuildVersion, $VisualStudioEdition, $VisualStudioVersion, $VisualStudioCodeName).Start_BuildCommand($Command, $Arguments, $Interactive)

    <#
    .SYNOPSIS
        Runs an application/command in the VS Developer Command Prompt environment
    .DESCRIPTION
        Runs an application/command in the VS Developer Command Prompt environment
    .EXAMPLE
        PS C:\> Invoke-VsDevCommand msbuild /?
        Runs 'msbuild /?'
    .INPUTS
        None. You cannot pipe objects to Invoke-VsDevCommand
    .OUTPUTS
        System.String[]. Invoke-VsDevCommand returns an array of strings that rerpesents the output of executing the application/command
        with the given arguments
    .PARAMETER Command
        Application/Command to execute in the VS Developer Command Prompt Environment
    .PARAMETER Arguments
        Arguments to pass to Application/Command being executed
    .PARAMETER VisualStudioEdition
        Selects Visual Studio Development Environment based on Edition (Community, Professional, Enterprise, etc.)
    .PARAMETER VisualStudioVersion
        Selects Visual Studio Development Environment based on Version (2015, 2017, 2019 etc.)
    .PARAMETER VisualStudioCodename
        Selects Visual Studio Development Environment based on Version CodeName (Dev14, Dev15, Dev16 etc.)
    .PARAMETER VisualStudioBuildVersion
        Selects Visual Studio Development Environment based on Build Version (e.g., "15.9.25", "16.8.0").
        A prefix is sufficient (e.g., "15", "15.9", "16" etc.)
    .PARAMETER Interactive
        Runs in interactive mode. Useful for running programs like cmd.exe, pwsh.exe, powershell.exe or csi.exe in the Visual Studio Developer Command Prompt Environment
    #>
}

function Invoke-MsBuild {
    [CmdletBinding(DefaultParameterSetName='Default')]
    param (
        [Parameter(ParameterSetName = 'Default', Position=0, ValueFromRemainingArguments, HelpMessage='List of arguments')]
        [Parameter(ParameterSetName = 'CodeName', Position=0, ValueFromRemainingArguments, HelpMessage='List of arguments')]
        [string[]]
        $Arguments,

        [Parameter(ParameterSetName='Default', Mandatory = $false, HelpMessage='Selects Visual Studio Development Environment based on Edition (Community, Professional, Enterprise, etc.)')]
        [Parameter(ParameterSetName='CodeName', Mandatory = $false, HelpMessage='Selects Visual Studio Development Environment based on Edition (Community, Professional, Enterprise, etc.)')]
        [CmdletBinding(PositionalBinding=$false)]
        [Alias('Edition')]
        [ValidateSet('Community', 'Professional', 'Enteprise', $null)]
        [string]
        $VisualStudioEdition = $null,

        [Parameter(ParameterSetName='Default', Mandatory = $false, HelpMessage='Selects Visual Studio Development Environment based on Version (2015, 2017, 2019 etc.)')]
        [CmdletBinding(PositionalBinding=$false)]
        [Alias('Version')]
        [ValidateSet('2015', '2017', '2019', $null)]
        [string]
        $VisualStudioVersion = $null,

        [Parameter(ParameterSetName='CodeName', Mandatory = $false, HelpMessage='Selects Visual Studio Development Environment based on Version CodeName (Dev14, Dev15, Dev16 etc.)')]
        [CmdletBinding(PositionalBinding=$false)]
        [Alias('CodeName')]
        [ValidateSet('Dev14', 'Dev15', 'Dev16', $null)]
        [string]
        $VisualStudioCodeName=$null,

        [Parameter(ParameterSetName='Default', Mandatory = $false, HelpMessage='Selects Visual Studio Development Environment based on Build Version (e.g., "15.9.25", "16.8.0"). A prefix is sufficient (e.g., "15", "15.9", "16" etc.)')]
        [Parameter(ParameterSetName='CodeName', Mandatory = $false, HelpMessage='Selects Visual Studio Development Environment based on Build Version (e.g., "15.9.25", "16.8.0"). A prefix is sufficient (e.g., "15", "15.9", "16" etc.)')]
        [Alias('BuildVersion')]
        [CmdletBinding(PositionalBinding=$false)]
        [string]
        $VisualStudioBuildVersion = $null,

        [Parameter(ParameterSetName='Default', HelpMessage='Runs in interactive mode. Useful for running programs like cmd.exe, pwsh.exe, powershell.exe or csi.exe in the Visual Studio Developer Command Prompt Environment')]
        [Parameter(ParameterSetName='CodeName', HelpMessage='Runs in interactive mode. Useful for running programs like cmd.exe, pwsh.exe, powershell.exe or csi.exe in the Visual Studio Developer Command Prompt Environment')]
        [CmdletBinding(PositionalBinding=$false)]
        [switch]
        $Interactive
    )

    [VsDevCmd]::new($VisualStudioBuildVersion, $VisualStudioEdition, $VisualStudioVersion, $VisualStudioCodeName).Start_BuildCommand('msbuild', $Arguments, $Interactive)

    <#
    .SYNOPSIS
        Runs MSBuild in the VS Developer Command Prompt environment
    .DESCRIPTION
        Runs MSBuild in the VS Developer Command Prompt environment
    .EXAMPLE
        PS C:\> Invoke-MsBuild /?
        Runs 'msbuild /?'
    .INPUTS
        None. You cannot pipe objects to Invoke-VsDevCommand
    .OUTPUTS
        System.String[]. Invoke-MsBuild returns an array of strings that rerpesents the output of executing MSBuild
        with the given arguments
    .PARAMETER Arguments
        Arguments to pass to MSBuild
    .PARAMETER VisualStudioEdition
        Selects Visual Studio Development Environment based on Edition (Community, Professional, Enterprise, etc.)
    .PARAMETER VisualStudioVersion
        Selects Visual Studio Development Environment based on Version (2015, 2017, 2019 etc.)
    .PARAMETER VisualStudioCodename
        Selects Visual Studio Development Environment based on Version CodeName (Dev14, Dev15, Dev16 etc.)
    .PARAMETER VisualStudioBuildVersion
        Selects Visual Studio Development Environment based on Build Version (e.g., "15.9.25", "16.8.0").
        A prefix is sufficient (e.g., "15", "15.9", "16" etc.)
    .PARAMETER Interactive
        Runs in interactive mode. Useful for running programs like cmd.exe, pwsh.exe, powershell.exe or csi.exe in the Visual Studio Developer Command Prompt Environment
    #>
}

Set-Alias -Name ivdc -Value Invoke-VsDevCommand
Set-Alias -Name vsdevcmd -Value Invoke-VsDevCommand

Set-Alias -Name imb -Value Invoke-MsBuild
Set-Alias -Name msbuild -Value Invoke-MsBuild



Export-ModuleMember Invoke-VsDevCommand
Export-ModuleMember -Alias ivdc
Export-ModuleMember -Alias vsdevcmd

Export-ModuleMember Invoke-MsBuild
Export-ModuleMember -Alias imb
Export-ModuleMember -Alias msbuild