<#
    Copyright Vatsan Madhavan (c) 2020
    https://github.com/vatsan-madhavan/Invoke-VsBuild
#>

<#
.SYNOPSIS
    Different matching rules used by 'VersionMatchingRule' parameter
#>
enum VersionMatchingRule {
    ExactMatch;
    Like;
    NewestGreaterThan;
}

<#
.SYNOPSIS
    Thrown when VsWhere could not be found
#>
class VsWhereNotFoundException : System.IO.FileNotFoundException {
    VsWhereNotFoundException() : base('VsWhere not found') {}
    VsWhereNotFoundException([string]$filename) : base('VsWhere not found', $filename) {}
    VsWhereNotFoundException([string]$filename, [System.Exception]$inner): base('VsWhere not found', $filename, $inner) {}
    VsWhereNotFoundException([System.Exception]$inner): base('VsWhere not found', 'VsWhere.exe', $inner) {}
}

<#
.SYNOPSIS
    Thrown when no instance of Visual Studio can be found
#>
class VisualStudioNotFoundException : System.Exception {
    VisualStudioNotFoundException() {}
    VisualStudioNotFoundException([string]$message) : base($message) {}
    VisualStudioNotFoundException([string]$message, [System.Exception]$inner): base($message, $inner) {}
}

<#
.SYNOPSIS
    Thrown when no instance of Visual Studio can be found that matches the specified criteria
#>
class VisualStudioInstanceNotMatchedException : System.Exception {
    VisualStudioInstanceNotMatchedException() {}
    VisualStudioInstanceNotMatchedException([string]$message) : base($message) {}
    VisualStudioInstanceNotMatchedException([string]$message, [System.Exception]$inner): base($message, $inner) {}
}

<#
.SYNOPSIS
    Thrown when the application intended to be launched within the Visual Studio Developer
    Command Prompt environment can not be found.
#>
class UserApplicationNotFoundException : System.ArgumentException {
    UserApplicationNotFoundException() : base('Application not found') {}
    UserApplicationNotFoundException([string]$paramName) : base('Application not found', $paramName) {}
    UserApplicationNotFoundException([string] $paramName, [System.Exception]$inner): base('Application not found', $paramName, $inner) {}
}

<#
.SYNOPSIS
    Core information about a Visual Studio Installation
 #>
class InstallationInfo  {
    [string] $InstanceId
    [System.Management.Automation.SemanticVersion] $SemanticVersion
    [string] $ProductId # e.g., Microsoft.VisualStudio.Product.Enterprise
    [string] $ProductLineVersion # e.g., 2019 (as in, Visual Studio 2019)
    [string] $ProductLine # e.g., Dev15
    [string] $InstallationPath
}


class ProcessInfo {
    [string] $ExeFile
    [string[]] $Arguments
}

<#
.SYNOPSIS
    Structure representing the result of [ProcessHelper]::Run(...)
#>
class ProcessResult : ProcessInfo {
    [int] $ExitCode
    [string] $Output
}

class BackgroundProcessResult : ProcessInfo {
    [System.Diagnostics.Process] $Handle
}

<#
.SYNOPSIS
    Helper class to orchestrate the execution of an application and capture its
    standard output and standard error streams.
#>
class ProcessHelper {
    [BackgroundProcessResult] static RunDetached([String]$sExeFile, [String[]]$cArgs) {
        # sExeFile is a mandatory parameter
        if ((-not $sExeFile) -or (-not (Test-Path -PathType Leaf -Path $sExeFile))){
            throw New-Object System.ArgumentException 'sExeFile'
        }    

        $sExeFile = (Resolve-Path $sExeFile).Path # clean-up the path

        [System.Diagnostics.Process] $process = $null
        if ($cArgs -And $cArgs -gt 0) {
            $process = Start-Process -FilePath $sExeFile -ArgumentList $cArgs -NoNewWindow -PassThru
        } else {
            $process = Start-Process -FilePath $sExeFile -NoNewWindow -PassThru
        }

        [BackgroundProcessResult] $result = [BackgroundProcessResult]::new()
        $result.ExeFile = $sExeFile
        $result.Arguments = $cArgs
        $result.Handle = $process

        return $result
    }

    [ProcessResult] static Run([String]$sExeFile,[String[]]$cArgs) {
        # sExeFile is a mandatory parameter
        if ((-not $sExeFile) -or (-not (Test-Path -PathType Leaf -Path $sExeFile))){
            throw New-Object System.ArgumentException 'sExeFile'
        }        

        $sExeFile = (Resolve-Path $sExeFile).Path # clean-up the path

        [ProcessResult]$result = [ProcessResult]::new()
        $result.ExeFile = $sExeFile
        $result.Arguments = $cArgs

        if ($cArgs -and $cArgs.Count -gt 0) {
            [string[]]$output = & "$sExeFile" $cArgs 2>&1
        } else {
            [string[]]$output = & "$sExeFile" 2>&1
        }

        $result.Output = $output -join [System.Environment]::NewLine
        $result.ExitCode = $LASTEXITCODE
        return $result
    }

    [ProcessResult] static Run([String]$sExeFile) {
        return [ProcessHelper]::Run($sExeFile, $null, $null, $false)
    }
}

<#
.SYNOPSIS
    Contains main logic for executing applications in the VS Developer Command Prompt
    Environment
#>
class VsDevCmd {
    static hidden [string]$VsWhereUri = 'https://github.com/microsoft/vswhere/releases/download/2.8.4/vswhere.exe'
    static hidden [string]$VsWhereExe = 'vswhere.exe'
    static hidden [string] $vswhere = [VsDevCmd]::Initialize_VsWhere()
    
    hidden [System.Collections.Generic.Dictionary[string, string]]$SavedEnv = @{}
    hidden [string]$vsDevCmd  # full path to VS Developer Command Prompt Batch File

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

        [string]$visualStudioInstallerPath = Join-Path "${env:ProgramFiles(x86)}\\Microsoft Visual Studio\\Installer\" $([VsDevCmd]::VsWhereExe)
        [string]$downloadPath = Join-path $InstallDir $([VsDevCmd]::VsWhereExe)
        [string]$VsWhereTempPath = Join-Path $env:TEMP $([VsDevCmd]::VsWhereExe)

        # Look under VS Installer Path
        if (Test-Path $visualStudioInstallerPath -PathType Leaf) {
            return $visualStudioInstallerPath
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
        $vsWhereCmd = Get-Command $([VsDevCmd]::VsWhereExe) -ErrorAction SilentlyContinue
        if ($vsWhereCmd -and $vsWhereCmd.Source -and (Test-Path $vsWhereCmd.Source)) {
            return $vsWhereCmd.Source
        }

        # Short-circuit logic didn't work - prepare to download a new copy of vswhere
        if (-not (Test-Path -Path $InstallDir)) {
            New-Item -ItemType Directory -Path $InstallDir | Out-Null
        }

        if (-not (Test-Path -Path $InstallDir -PathType Container)) {
            $inner =  New-Object System.ArgumentException -ArgumentList 'Directory could not be created', 'InstallDir'
            throw New-Object VsWhereNotFoundException -ArgumentList $inner
        }

        if (-not (Test-Path -Path $downloadPath -PathType Leaf)) {
            Invoke-WebRequest -Uri $([VsDevCmd]::VsWhereUri) -OutFile (Join-Path $InstallDir $([VsDevCmd]::VsWhereExe))
        }

        if (-not (Test-Path -Path $downloadPath -PathType Leaf)) {
            Write-Error "$downloadPath could not not be provisioned" -ErrorAction Stop
        }

        return $downloadPath
    }

    <#
        [string] $productDisplayVersion,            # 16.8.0, 15.9.24 etc.
        [VersionMatchingRule] $versionMatchingRule, # Rule to use to match $productDisplayVersion
        [string] $edition,                          # Professional, Enterprise etc.
        [string] $productLineVersion,               # 2015, 2017, 2019 etc.
        [string] $productLine) {                    # Dev15, Dev16 etc.
    #>
    VsDevCmd([string]$productDisplayVersion, [VersionMatchingRule] $versionMatchingRule, [string]$edition, [string]$productLineVersion, [string] $productLine, [string[]]$requiredComponents) {
        $this.vsDevCmd = [VsDevCmd]::GetVsDevCmdPath($productDisplayVersion, $versionMatchingRule, $edition, $productLineVersion, $productLine, $requiredComponents)
    }

    [void] hidden Update_EnvironmentVariable ([string] $Name, [string] $Value) {
        if (-not ($this.SavedEnv.ContainsKey($Name))) {
            $oldValue = [System.Environment]::GetEnvironmentVariable($Name, [System.EnvironmentVariableTarget]::Process)
            $this.SavedEnv[$Name] = $oldValue
        }

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

    <#
     # Creates a SemanticVersion object from a version-string
     #  Uses a standard SemVer2 regex to parse the string into parts before instantiating a SemanticVersion object. 
     #  If the version-string doesn't match the regex, then attempts instantiating via [string]$ver -> [version] -> [SemanticVersion] path.
     #>
    [System.Management.Automation.SemanticVersion] static hidden MakeSemanticVersion([string]$ver) {
        [string]$semVerRegex = '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$'
        [System.Management.Automation.SemanticVersion]$semanticVersion = $null

        $m = [regex]::Match($ver, $semVerRegex)
        if ($m -and $m.Groups -and $m.Groups.Count -eq 6) {
            $semanticVersion = 
                New-Object System.Management.Automation.SemanticVersion($m.Groups[1].Value, $m.Groups[2].Value, $m.Groups[3].Value, $m.Groups[4].Value, $m.Groups[5].Value)
        } else {
            # Try if the SemanticVersion object can be created via a [version] object
            try {
                $semanticVersion = [System.Management.Automation.SemanticVersion][version]$ver
            }
            catch{
               # Swallow the exception 
            }
        }

        return $semanticVersion
    }

    [InstallationInfo[]] hidden static GetProductInfo($installations) {
        [InstallationInfo[]]$info = @()
        $installations | Where-Object {
            $_.catalog
        } | ForEach-Object {
            [InstallationInfo]$record = [InstallationInfo]::new()
            $record.InstanceId = $_.instanceId
            $record.SemanticVersion = [VsDevCmd]::MakeSemanticVersion($_.catalog.productSemanticVersion)
            $record.ProductId = $_.productId
            $record.ProductLineVersion = $_.catalog.productLineVersion
            $record.ProductLine = $_.catalog.ProductLine
            $record.InstallationPath = $_.installationPath
            $info += $record
        }

        return $info
    }

    <#
     # Gets VS Instances that have the requested components
     #  This only works for VS 2017 and later.
     #>
    [InstallationInfo[]] static hidden GetInstancesWithRequiredComponents([string[]] $requiredComponents) {
        if ((-not $requiredComponents) -or ($requiredComponents.Length -eq 0)) {
            throw New-Object System.ArgumentException -ArgumentList "'requiredComponents' is null or empty", 'requiredComponents'
        }

        [array]$arguments = @('-prerelease', '-format', 'json') + ($requiredComponents | ForEach-Object { ('-requires', $_) })

        [ProcessResult]$result = [ProcessHelper]::Run($([VsDevCmd]::vswhere), $arguments)

        <#
        [System.Diagnostics.ProcessStartInfo]$psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.FileName = "$([VSDevCmd]::vswhere)"
        $psi.Arguments = $arguments -join ' '
        $psi.UseShellExecute = $false
            
        [System.Diagnostics.Process]$p = New-Object System.Diagnostics.Process
        $p.StartInfo = $psi
        $p.Start() | Out-Null 
        $installationsWithRequiredComponents = $p.StandardOutput.ReadToEnd()
        $p.WaitForExit()
        
        $installationsWithRequiredComponents = $installationsWithRequiredComponents | ConvertFrom-Json
        #>
        $installationsWithRequiredComponents = $result.Output | ConvertFrom-Json
        
        if ($installationsWithRequiredComponents) {
            return [VsDevCmd]::GetProductInfo($installationsWithRequiredComponents)
        }

        throw New-Object VisualStudioInstanceNotMatchedException 'No instances of Visual Studio containing all required components could be found'
    }

    # Default matching rule for $productDisplayVersion is [VersionMatchingRule]::Like
    # [string] hidden static GetVsDevCmdPath(
    #     [string] $productDisplayVersion,    # 16.8.0, 15.9.24 etc.
    #     [string] $edition,                  # Professional, Enterprise etc.
    #     [string] $productLineVersion,       # 2015, 2017, 2019 etc.
    #     [string] $productLine) {            # Dev15, Dev16 etc.
    #         return [VsDevCmd].GetVsDevCmdPath(
    #             $productDisplayVersion,
    #             [VersionMatchingRule]::Like,
    #             $edition, 
    #             $productLineVersion, 
    #             $productLine)
    # }

    [string] hidden static GetVsDevCmdPath(
        [string] $productDisplayVersion, # 16.8.0, 15.9.24 etc.
        [VersionMatchingRule] $versionMatchingRule, # Rule to use to match $productDisplayVersion
        [string] $edition, # Professional, Enterprise etc.
        [string] $productLineVersion, # 2015, 2017, 2019 etc.
        [string] $productLine, # Dev15, Dev16 etc. 
        [string[]] $requiredComponents) {                    
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
                $inner = New-Object System.ArgumentOutOfRangeException 'productLineVersion'
                throw New-Object VisualStudioInstanceNotMatchedException -ArgumentList "productLineVersion {$productLineVersion} is invalid", $inner 
            }
            if ($productLineInfo[$productLineVersion] -ine $productLine) {
                # error
                $inner = System.ArgumentException("{productLineVersion{$productLineVersion}} and {productLine{$productLine}} are not mutually consistent; {productLine} should be {$productLineInfo[$productLineVersion]}", 'productLine')
                throw New-Object VisualStudioInstanceNotMatchedException $inner.Message, $inner
            }
        }

        # Validate that $requiredComponents is only specified when $productLineVersion >= 2017
        # if (($requiredComponents -and $requiredComponents.Length -gt 0) -and ($productLineVersion -or $productLine)) {
        #     if (($productLineVersion -and ($productLineVersion -eq '2015')) -or ($productLine -and ($productLine -ieq 'Dev15'))) {
        #         throw New-Object System.ArgumentException("'requiredComponents' cannot be used when VS Version 2015/Dev15 is queried", 'requiredComponents')
        #     }
        # }


        [ProcessResult]$processResult = [ProcessHelper]::Run("$([VsDevCmd]::vswhere)", @('-prerelease', '-legacy', '-format', 'json'))
        if (-not ($processResult.ExitCode -eq 0)) {
            throw New-Object VisualStudioNotFoundException -ArgumentList "Failed to run $([VsDevCmd]::vswhere)"
        }
        [array]$json = $processResult.Output | ConvertFrom-Json

        [InstallationInfo[]]$installs = [VsDevCmd]::GetProductInfo($json)


        if ($productLineVersion) {
            $installs = $installs | Where-Object {
                $_.ProductLineVersion -ieq $productLineVersion
            }
        }

        if ($productLine) {
            $installs = $installs | Where-Object {
                $_.ProductLine -ieq $productLine
            }
        }


        # Evaluate $productDisplayVersion last
        if ($productDisplayVersion) {
            switch ($versionMatchingRule) {
                'Like' {
                    $installs = $installs | Where-Object {
                        [string]$_.SemanticVersion -ilike $productDisplayVersion
                    }
                    Break;
                }
                'ExactMatch' {
                    [System.Management.Automation.SemanticVersion]$productDisplayVersionSemVer = [VsDevCmd]::MakeSemanticVersion($productDisplayVersion)
                    $installs = $installs | Where-Object {
                        $_.SemanticVersion -eq $productDisplayVersionSemVer
                    }
                    Break;
                }

                'NewestGreaterThan' {
                    [System.Management.Automation.SemanticVersion]$productDisplayVersionSemVer = [VsDevCmd]::MakeSemanticVersion($productDisplayVersion)


                    $largest = $null 
                    foreach ($install in $installs) {
                        if ($install.SemanticVersion -gt $productDisplayVersionSemVer) {
                            # This is a candidate; update $largest if $install > $largest
                            if ((-not $largest) -or ($install.SemanticVersion -gt $largest.SemanticVersion)) {
                                $largest = $install
                            }
                        }
                    }                  

                    $installs = if ($largest) { @($largest) } else { $null }
                    Break;
                }

                Default {
                    # Invalid rule
                    # Default to [VersionMatchingRule]::Like
                    $installs = $installs | Where-Object {
                        [string]$_.SemanticVersion -ilike $productDisplayVersion
                    }
                }
            }
        }

        if ($requiredComponents -and ($requiredComponents.Length -gt 0)) {
            [InstallationInfo[]]$installsWithrequiredComponents = [VsDevCmd]::GetInstancesWithRequiredComponents($requiredComponents)

            $installs = $installs | Where-Object {
                $installsWithrequiredComponents.InstanceId-icontains $_.InstanceId
            }
        }

        if ($edition -and ($edition -ne '*')) {
            [string]$productId = "Microsoft.VisualStudio.Product." + $edition.Trim()
            $installs = $installs | Where-Object {
                $_.ProductId -ieq $productId
            }
        }

        if (-not $installs) {
            throw New-Object VisualStudioInstanceNotMatchedException 'No instance of Visual Studio matches all specified criteria'
        }

        [string]$installationPath = if ($installs -is [array]) { $installs[0].InstallationPath } else { $installs.InstallationPath }

        if ((-not $installationPath) -or (-not (test-path -Path $installationPath -PathType Container))) {
            throw New-Object VisualStudioInstanceNotMatchedException "Installation Path {$installationPath} Not Found"
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

        throw New-Object VisualStudioInstanceNotMatchedException "Visual Studio Developer Command Prompt Batch File {$vsDevCmdPath} path not found"
    }

    [void] hidden Start_VsDevCmd() {
        [string]$vsDevCmdPath = $this.vsDevCmd

        # older vcvars32.bat doesn't understand no-logo argument
        [string]$cmd = if ((Split-Path -Leaf $vsDevCmdPath) -ieq 'vsvars32.bat') { "`"$vsDevCmdPath`" && set" } else { "`"$vsDevCmdPath`" -no_logo && set" }
        [ProcessResult]$processResult = [ProcessHelper]::Run("${env:COMSPEC}", @('/s', '/c', $cmd))
        if ($processResult.ExitCode -ne 0) {
            throw New-Object VisualStudioNotFoundException "Failed to run ${env:COMSPEC} /s /c $cmd"
        }
        [string[]]$envVars = $processResult.Output -split [System.Environment]::NewLine

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
                throw New-Object UserApplicationNotFoundException $Command
            }

            [string] $cmd = if ($cmdObject -is [array]) { $cmdObject[0].Source } else { $cmdObject.Source }
            [ProcessResult]$result = [ProcessHelper]::Run($cmd, $Arguments)

            return $result.Output
        }
        finally {
            $this.Restore_Environment()
        }
    }
}

function Invoke-VsDevCommand {
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    param (
        [Parameter(ParameterSetName = 'Default', Position = 0 , Mandatory = $true, HelpMessage = 'Application or Command to Run')]
        [Parameter(ParameterSetName = 'CodeName', Position = 0 , Mandatory = $true, HelpMessage = 'Application or Command to Run')]
        [string]
        $Command,

        [Parameter(ParameterSetName = 'Default', Position = 1, ValueFromRemainingArguments, HelpMessage = 'List of arguments')]
        [Parameter(ParameterSetName = 'CodeName', Position = 1, ValueFromRemainingArguments, HelpMessage = 'List of arguments')]
        [string[]]
        $Arguments,

        [Parameter(ParameterSetName = 'Default', Mandatory = $false, HelpMessage = 'Selects Visual Studio Development Environment based on Edition (Community, Professional, Enterprise, etc.)')]
        [Parameter(ParameterSetName = 'CodeName', Mandatory = $false, HelpMessage = 'Selects Visual Studio Development Environment based on Edition (Community, Professional, Enterprise, etc.)')]
        [CmdletBinding(PositionalBinding = $false)]
        [Alias('Edition')]
        [ValidateSet('Community', 'Professional', 'Enterprise', 'TeamExplorer', 'WDExpress', 'BuildTools', 'TestAgent', 'TestController', 'TestProfessional', 'FeedbackClient', '*')]        [string]
        $VisualStudioEdition = '*',

        [Parameter(ParameterSetName = 'Default', Mandatory = $false, HelpMessage = 'Selects Visual Studio Development Environment based on Version (2015, 2017, 2019 etc.)')]
        [CmdletBinding(PositionalBinding = $false)]
        [Alias('Version')]
        [ValidateSet('2015', '2017', '2019', $null)]
        [string]
        $VisualStudioVersion = $null,

        [Parameter(ParameterSetName = 'CodeName', Mandatory = $false, HelpMessage = 'Selects Visual Studio Development Environment based on Version CodeName (Dev14, Dev15, Dev16 etc.)')]
        [CmdletBinding(PositionalBinding = $false)]
        [Alias('CodeName')]
        [ValidateSet('Dev14', 'Dev15', 'Dev16', $null)]
        [string]
        $VisualStudioCodeName = $null,

        [Parameter(ParameterSetName = 'Default', Mandatory = $false, HelpMessage = 'Selects Visual Studio Development Environment based on Build Version (e.g., "15.9.25", "16.8.0"). A prefix is sufficient (e.g., "15", "15.9", "16" etc.)')]
        [Parameter(ParameterSetName = 'CodeName', Mandatory = $false, HelpMessage = 'Selects Visual Studio Development Environment based on Build Version (e.g., "15.9.25", "16.8.0"). A prefix is sufficient (e.g., "15", "15.9", "16" etc.)')]
        [Alias('BuildVersion')]
        [CmdletBinding(PositionalBinding = $false)]
        [string]
        $VisualStudioBuildVersion = $null,

        [Parameter(ParameterSetName = 'Default', Mandatory = $false, HelpMessage = "Identifies the rule for matching 'VisualStudioBuildVersion' parameter. Valid values are {'Like', 'ExactMatch', 'NewestGreaterThan'} 'Like' is similar to powershell's '-like' operator; 'ExactMatch' looks for an exact version match; 'NewestGreaterThan' interprets the supplied version as a number and identifies a Visual Studio installation whose version is greater-than-or-equal to the requested version (the highest available version is selected)")]
        [Parameter(ParameterSetName = 'CodeName', Mandatory = $false, HelpMessage = "Identifies the rule for matching 'VisualStudioBuildVersion' parameter. Valid values are {'Like', 'ExactMatch', 'NewestGreaterThan'} 'Like' is similar to powershell's '-like' operator; 'ExactMatch' looks for an exact version match; 'NewestGreaterThan' interprets the supplied version as a number and identifies a Visual Studio installation whose version is greater-than-or-equal to the requested version (the highest available version is selected)")]
        [ValidateSet('Like', 'ExactMatch', 'NewestGreaterThan')]
        [CmdletBinding(PositionalBinding = $false)]
        [string]
        $VersionMatchingRule = 'Like',

        [Parameter(ParameterSetName = 'Default', Mandatory = $false, HelpMessage = "List of required components. See https://aka.ms/vs/workloads for list of edition-specific workload ID's")]
        [Parameter(ParameterSetName = 'CodeName', Mandatory = $false, HelpMessage = "List of required components. See https://aka.ms/vs/workloads for list of edition-specific workload ID's")]
        [CmdletBinding(PositionalBinding = $false)]
        [string[]]
        $RequiredComponents,

        [Parameter(ParameterSetName = 'Default', HelpMessage = 'Runs in interactive mode. Useful for running programs like cmd.exe, pwsh.exe, powershell.exe or csi.exe in the Visual Studio Developer Command Prompt Environment')]
        [Parameter(ParameterSetName = 'CodeName', HelpMessage = 'Runs in interactive mode. Useful for running programs like cmd.exe, pwsh.exe, powershell.exe or csi.exe in the Visual Studio Developer Command Prompt Environment')]
        [CmdletBinding(PositionalBinding = $false)]
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

    [VsDevCmd]::new($VisualStudioBuildVersion, $VersionMatchingRule -as [VersionMatchingRule], $VisualStudioEdition, $VisualStudioVersion, $VisualStudioCodeName, $RequiredComponents).Start_BuildCommand($Command, $Arguments, $Interactive)

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
        System.String[]. Invoke-VsDevCommand returns an array of strings that represents the output of executing the application/command
        with the given arguments
    .PARAMETER Command
        Application/Command to execute in the VS Developer Command Prompt Environment
    .PARAMETER Arguments
        Arguments to pass to Application/Command being executed
    .PARAMETER VisualStudioEdition
        Selects Visual Studio Development Environment based on Edition
        Valid values are 'Community', 'Professional', 'Enterprise', 'TeamExplorer', 'WDExpress', 'BuildTools', 'TestAgent', 'TestController', 'TestProfessional', 'FeedbackClient', '*'
        Defaults to '*' (any edition)
    .PARAMETER VisualStudioVersion
        Selects Visual Studio Development Environment based on Version (2015, 2017, 2019 etc.)
    .PARAMETER VisualStudioCodename
        Selects Visual Studio Development Environment based on Version CodeName (Dev14, Dev15, Dev16 etc.)
    .PARAMETER VisualStudioBuildVersion
        Selects Visual Studio Development Environment based on Build Version (e.g., "15.9.25", "16.8.0").
        A prefix is sufficient (e.g., "15", "15.9", "16" etc.)
    .PARAMETER VersionMatchingRule
        Identifies the rule for matching 'VisualStudioBuildVersion' parameter. Valid values are {'Like', 'ExactMatch', 'NewestGreaterThan'} 
        
        - 'Like' (Default) is similar to powershell's '-like' operator
        - 'ExactMatch' looks for an exact version match
        - 'NewestGreaterThan' interprets the supplied version as a number and identifies a Visual Studio installation whose version is greater-than-or-equal to the requested version (the highest available version is selected)
    .PARAMETER RequiredComponents
        List of required components. See https://aka.ms/vs/workloads for list of edition-specific workload ID's
    .PARAMETER Interactive
        Runs in interactive mode. Useful for running programs like cmd.exe, pwsh.exe, powershell.exe or csi.exe in the Visual Studio Developer Command Prompt Environment
    .LINK
        #Get-Alias
    .EXAMPLE
    #>
}

function Invoke-MsBuild {
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    param (
        [Parameter(ParameterSetName = 'Default', Position = 0, ValueFromRemainingArguments, HelpMessage = 'List of arguments')]
        [Parameter(ParameterSetName = 'CodeName', Position = 0, ValueFromRemainingArguments, HelpMessage = 'List of arguments')]
        [string[]]
        $Arguments,

        [Parameter(ParameterSetName = 'Default', Mandatory = $false, HelpMessage = 'Selects Visual Studio Development Environment based on Edition (Community, Professional, Enterprise, etc.)')]
        [Parameter(ParameterSetName = 'CodeName', Mandatory = $false, HelpMessage = 'Selects Visual Studio Development Environment based on Edition (Community, Professional, Enterprise, etc.)')]
        [CmdletBinding(PositionalBinding = $false)]
        [Alias('Edition')]
        [ValidateSet('Community', 'Professional', 'Enterprise', 'TeamExplorer', 'WDExpress', 'BuildTools', 'TestAgent', 'TestController', 'TestProfessional', 'FeedbackClient', '*')]
        [string]
        $VisualStudioEdition = '*',

        [Parameter(ParameterSetName = 'Default', Mandatory = $false, HelpMessage = 'Selects Visual Studio Development Environment based on Version (2015, 2017, 2019 etc.)')]
        [CmdletBinding(PositionalBinding = $false)]
        [Alias('Version')]
        [ValidateSet('2015', '2017', '2019', $null)]
        [string]
        $VisualStudioVersion = $null,

        [Parameter(ParameterSetName = 'CodeName', Mandatory = $false, HelpMessage = 'Selects Visual Studio Development Environment based on Version CodeName (Dev14, Dev15, Dev16 etc.)')]
        [CmdletBinding(PositionalBinding = $false)]
        [Alias('CodeName')]
        [ValidateSet('Dev14', 'Dev15', 'Dev16', $null)]
        [string]
        $VisualStudioCodeName = $null,

        [Parameter(ParameterSetName = 'Default', Mandatory = $false, HelpMessage = 'Selects Visual Studio Development Environment based on Build Version (e.g., "15.9.25", "16.8.0"). A prefix is sufficient (e.g., "15", "15.9", "16" etc.)')]
        [Parameter(ParameterSetName = 'CodeName', Mandatory = $false, HelpMessage = 'Selects Visual Studio Development Environment based on Build Version (e.g., "15.9.25", "16.8.0"). A prefix is sufficient (e.g., "15", "15.9", "16" etc.)')]
        [Alias('BuildVersion')]
        [CmdletBinding(PositionalBinding = $false)]
        [string]
        $VisualStudioBuildVersion = $null,

        [Parameter(ParameterSetName = 'Default', Mandatory = $false, HelpMessage = "Identifies the rule for matching 'VisualStudioBuildVersion' parameter. Valid values are {'Like', 'ExactMatch', 'NewestGreaterThan'} 'Like' is similar to powershell's '-like' operator; 'ExactMatch' looks for an exact version match; 'NewestGreaterThan' interprets the supplied version as a number and identifies a Visual Studio installation whose version is greater-than-or-equal to the requested version (the highest available version is selected)")]
        [Parameter(ParameterSetName = 'CodeName', Mandatory = $false, HelpMessage = "Identifies the rule for matching 'VisualStudioBuildVersion' parameter. Valid values are {'Like', 'ExactMatch', 'NewestGreaterThan'} 'Like' is similar to powershell's '-like' operator; 'ExactMatch' looks for an exact version match; 'NewestGreaterThan' interprets the supplied version as a number and identifies a Visual Studio installation whose version is greater-than-or-equal to the requested version (the highest available version is selected)")]
        [ValidateSet('Like', 'ExactMatch', 'NewestGreaterThan')]
        [CmdletBinding(PositionalBinding = $false)]
        [string]
        $VersionMatchingRule = 'Like',

        [Parameter(ParameterSetName = 'Default', Mandatory = $false, HelpMessage = "List of required components. See https://aka.ms/vs/workloads for list of edition-specific workload ID's")]
        [Parameter(ParameterSetName = 'CodeName', Mandatory = $false, HelpMessage = "List of required components. See https://aka.ms/vs/workloads for list of edition-specific workload ID's")]
        [CmdletBinding(PositionalBinding = $false)]
        [string[]]
        $RequiredComponents,

        [Parameter(ParameterSetName = 'Default', HelpMessage = 'Runs in interactive mode. Useful for running programs like cmd.exe, pwsh.exe, powershell.exe or csi.exe in the Visual Studio Developer Command Prompt Environment')]
        [Parameter(ParameterSetName = 'CodeName', HelpMessage = 'Runs in interactive mode. Useful for running programs like cmd.exe, pwsh.exe, powershell.exe or csi.exe in the Visual Studio Developer Command Prompt Environment')]
        [CmdletBinding(PositionalBinding = $false)]
        [switch]
        $Interactive
    )

    [VsDevCmd]::new($VisualStudioBuildVersion, $VersionMatchingRule, $VisualStudioEdition, $VisualStudioVersion, $VisualStudioCodeName, $RequiredComponents).Start_BuildCommand('msbuild', $Arguments, $Interactive)

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
        System.String[]. Invoke-MsBuild returns an array of strings that represents the output of executing MSBuild
        with the given arguments
    .PARAMETER Arguments
        Arguments to pass to MSBuild
    .PARAMETER VisualStudioEdition
        Selects Visual Studio Development Environment based on Edition
        Valid values are 'Community', 'Professional', 'Enterprise', 'TeamExplorer', 'WDExpress', 'BuildTools', 'TestAgent', 'TestController', 'TestProfessional', 'FeedbackClient', '*'
        Defaults to '*' (any edition)
    .PARAMETER VisualStudioVersion
        Selects Visual Studio Development Environment based on Version (2015, 2017, 2019 etc.)
    .PARAMETER VisualStudioCodename
        Selects Visual Studio Development Environment based on Version CodeName (Dev14, Dev15, Dev16 etc.)
    .PARAMETER VisualStudioBuildVersion
        Selects Visual Studio Development Environment based on Build Version (e.g., "15.9.25", "16.8.0").
        A prefix is sufficient (e.g., "15", "15.9", "16" etc.)
    .PARAMETER VersionMatchingRule
        Identifies the rule for matching 'VisualStudioBuildVersion' parameter. Valid values are {'Like', 'ExactMatch', 'NewestGreaterThan'} 
        
        - 'Like' (Default) is similar to powershell's '-like' operator
        - 'ExactMatch' looks for an exact version match
        - 'NewestGreaterThan' interprets the supplied version as a number and identifies a Visual Studio installation whose version is greater-than-or-equal to the requested version (the highest available version is selected)
    .PARAMETER RequiredComponents
        List of required components. See https://aka.ms/vs/workloads for list of edition-specific workload ID's
    .PARAMETER Interactive
        Runs in interactive mode. Useful for running programs like cmd.exe, pwsh.exe, powershell.exe or csi.exe in the Visual Studio Developer Command Prompt Environment
    #>
}

function Invoke-VsBuild {
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    param (
        [Parameter(ParameterSetName = 'Default', Mandatory = $true, Position = 0, HelpMessage = 'List of arguments')]
        [Parameter(ParameterSetName = 'CodeName', Mandatory = $true, Position = 0, HelpMessage = 'List of arguments')]
        [Parameter(ParameterSetName = 'IDEMode', Mandatory = $false, Position = 0, HelpMessage = 'List of arguments')]
        [string]
        $SolutionFile,

        [Parameter(ParameterSetName = 'Default', Position = 1, ValueFromRemainingArguments, HelpMessage = 'List of arguments')]
        [Parameter(ParameterSetName = 'CodeName', Position = 1, ValueFromRemainingArguments, HelpMessage = 'List of arguments')]
        [string[]]
        $Arguments,

        [Parameter(ParameterSetName = 'Default', Mandatory = $false, HelpMessage = 'Selects Visual Studio Development Environment based on Edition (Community, Professional, Enterprise, etc.)')]
        [Parameter(ParameterSetName = 'CodeName', Mandatory = $false, HelpMessage = 'Selects Visual Studio Development Environment based on Edition (Community, Professional, Enterprise, etc.)')]
        [Parameter(ParameterSetName = 'IDEMode', Mandatory = $false, HelpMessage = 'Selects Visual Studio Development Environment based on Edition (Community, Professional, Enterprise, etc.)')]
        [CmdletBinding(PositionalBinding = $false)]
        [Alias('Edition')]
        [ValidateSet('Community', 'Professional', 'Enterprise', 'TeamExplorer', 'WDExpress', 'BuildTools', 'TestAgent', 'TestController', 'TestProfessional', 'FeedbackClient', '*')]        [string]
        $VisualStudioEdition = '*',

        [Parameter(ParameterSetName = 'Default', Mandatory = $false, HelpMessage = 'Selects Visual Studio Development Environment based on Version (2015, 2017, 2019 etc.)')]
        [Parameter(ParameterSetName = 'IDEMode', Mandatory = $false, HelpMessage = 'Selects Visual Studio Development Environment based on Version (2015, 2017, 2019 etc.)')]
        [CmdletBinding(PositionalBinding = $false)]
        [Alias('Version')]
        [ValidateSet('2015', '2017', '2019', $null)]
        [string]
        $VisualStudioVersion = $null,

        [Parameter(ParameterSetName = 'CodeName', Mandatory = $false, HelpMessage = 'Selects Visual Studio Development Environment based on Version CodeName (Dev14, Dev15, Dev16 etc.)')]
        [Parameter(ParameterSetName = 'IDEMode', Mandatory = $false, HelpMessage = 'Selects Visual Studio Development Environment based on Version CodeName (Dev14, Dev15, Dev16 etc.)')]
        [CmdletBinding(PositionalBinding = $false)]
        [Alias('CodeName')]
        [ValidateSet('Dev14', 'Dev15', 'Dev16', $null)]
        [string]
        $VisualStudioCodeName = $null,

        [Parameter(ParameterSetName = 'Default', Mandatory = $false, HelpMessage = 'Selects Visual Studio Development Environment based on Build Version (e.g., "15.9.25", "16.8.0"). A prefix is sufficient (e.g., "15", "15.9", "16" etc.)')]
        [Parameter(ParameterSetName = 'CodeName', Mandatory = $false, HelpMessage = 'Selects Visual Studio Development Environment based on Build Version (e.g., "15.9.25", "16.8.0"). A prefix is sufficient (e.g., "15", "15.9", "16" etc.)')]
        [Parameter(ParameterSetName = 'IDEMode', Mandatory = $false, HelpMessage = 'Selects Visual Studio Development Environment based on Build Version (e.g., "15.9.25", "16.8.0"). A prefix is sufficient (e.g., "15", "15.9", "16" etc.)')]
        [Alias('BuildVersion')]
        [CmdletBinding(PositionalBinding = $false)]
        [string]
        $VisualStudioBuildVersion = $null,

        [Parameter(ParameterSetName = 'Default', Mandatory = $false, HelpMessage = "Identifies the rule for matching 'VisualStudioBuildVersion' parameter. Valid values are {'Like', 'ExactMatch', 'NewestGreaterThan'} 'Like' is similar to powershell's '-like' operator; 'ExactMatch' looks for an exact version match; 'NewestGreaterThan' interprets the supplied version as a number and identifies a Visual Studio installation whose version is greater-than-or-equal to the requested version (the highest available version is selected)")]
        [Parameter(ParameterSetName = 'CodeName', Mandatory = $false, HelpMessage = "Identifies the rule for matching 'VisualStudioBuildVersion' parameter. Valid values are {'Like', 'ExactMatch', 'NewestGreaterThan'} 'Like' is similar to powershell's '-like' operator; 'ExactMatch' looks for an exact version match; 'NewestGreaterThan' interprets the supplied version as a number and identifies a Visual Studio installation whose version is greater-than-or-equal to the requested version (the highest available version is selected)")]
        [Parameter(ParameterSetName = 'IDEMode', Mandatory = $false, HelpMessage = "Identifies the rule for matching 'VisualStudioBuildVersion' parameter. Valid values are {'Like', 'ExactMatch', 'NewestGreaterThan'} 'Like' is similar to powershell's '-like' operator; 'ExactMatch' looks for an exact version match; 'NewestGreaterThan' interprets the supplied version as a number and identifies a Visual Studio installation whose version is greater-than-or-equal to the requested version (the highest available version is selected)")]
        [ValidateSet('Like', 'ExactMatch', 'NewestGreaterThan')]
        [CmdletBinding(PositionalBinding = $false)]
        [string]
        $VersionMatchingRule = 'Like',

        [Parameter(ParameterSetName = 'Default', Mandatory = $false, HelpMessage = "List of required components. See https://aka.ms/vs/workloads for list of edition-specific workload ID's")]
        [Parameter(ParameterSetName = 'CodeName', Mandatory = $false, HelpMessage = "List of required components. See https://aka.ms/vs/workloads for list of edition-specific workload ID's")]
        [Parameter(ParameterSetName = 'IDEMode', Mandatory = $false, HelpMessage = "List of required components. See https://aka.ms/vs/workloads for list of edition-specific workload ID's")]
        [CmdletBinding(PositionalBinding = $false)]
        [string[]]
        $RequiredComponents,

        [Parameter(ParameterSetName = 'Default', HelpMessage = 'Runs in interactive mode. Useful for running programs like cmd.exe, pwsh.exe, powershell.exe or csi.exe in the Visual Studio Developer Command Prompt Environment')]
        [Parameter(ParameterSetName = 'CodeName', HelpMessage = 'Runs in interactive mode. Useful for running programs like cmd.exe, pwsh.exe, powershell.exe or csi.exe in the Visual Studio Developer Command Prompt Environment')]
        [Parameter(ParameterSetName = 'IDEMode', HelpMessage = 'Runs in interactive mode. Useful for running programs like cmd.exe, pwsh.exe, powershell.exe or csi.exe in the Visual Studio Developer Command Prompt Environment')]
        [CmdletBinding(PositionalBinding = $false)]
        [switch]
        $Interactive,

        
        [Parameter(ParameterSetName = 'Default', HelpMessage = "Build Target to Run. Options are 'Build' (Default), 'Rebuild', 'Clean', 'Deploy'")]
        [Parameter(ParameterSetName = 'CodeName', HelpMessage = "Build Target to Run. Options are 'Build' (Default), 'Rebuild', 'Clean', 'Deploy'")]
        [CmdletBinding(PositionalBinding=$false)]
        [ValidateSet('Build', 'Rebuild', 'Clean', 'Deploy')]
        [string]
        $Target = 'Build',

        [Parameter(ParameterSetName = 'IDEMode', HelpMessage = "Launch Visual Studio IDE")]
        [CmdletBinding(PositionalBinding=$false)]
        [switch]
        $Ide
    )

    <#
        Parameter mapping:
            [string] $productDisplayVersion,    # 16.8.0, 15.9.24 etc.              $VisualStudioBuildVersion
            [string] $edition,                  # Professional, Enterprise etc.     $VisualStudioEdition
            [string] $productLineVersion,       # 2015, 2017, 2019 etc.             $VisualStudioVersion
            [string] $productLine) {            # Dev15, Dev16 etc.                 $VisualStudioCodeName
    #>
    
    <#
    Per documentation at https://docs.microsoft.com/en-us/visualstudio/ide/reference/devenv-command-line-switches?view=vs-2019: 

        Commands that begin with devenv are handled by the devenv.com utility, which delivers output through standard system streams,
        such as stdout and stderr. The utility determines the appropriate I/O redirection when it captures output, for example to a .txt
        file.

        Alternatively, commands that begin with devenv.exe can use the same switches, but the devenv.com utility is bypassed. Using
        devenv.exe directly prevents output from appearing on the console.
    
    We need to redirect and capture stdout/stderr; therefore use devenv.com 
    #>
    [string]$command = 'devenv.com'  
    [string[]]$augmentedArguments = @()

    if ($SolutionFile) {
        # $SolutionFile is optional in -IdeMode, so it could be empty
        $augmentedArguments += $SolutionFile
    }

    [string[]]$allowedTargets = @('/Build', '/Rebuild', '/Clean', '/Deploy')
    if ($Arguments -and (Compare-Object $allowedTargets $Arguments -PassThru -IncludeEqual -ExcludeDifferent)) {
        # $allowedTargets INTERSECT $Arguments != $null
        # $Arguments supersedes $Target
        if ($Ide) {
            # In -Ide mode, do not no targets are allowed
            $Arguments = $Arguments | Where-Object {
                $allowedTargets -inotcontains $_
            }
        }
        $augmentedArguments += $Arguments
    } else {
        if (-not [string]::IsNullOrWhiteSpace($Target) -and (-not $Ide)) {
            # Include $Target only when NOT($Ide)
            [string]$Target = '/' + $Target.Trim()
            $augmentedArguments += $Target
        }
        
        if ($Arguments -and $Arguments.Count -gt 0) {
            $augmentedArguments += $Arguments
        }
    }

    [VsDevCmd]::new($VisualStudioBuildVersion, $VersionMatchingRule -as [VersionMatchingRule], $VisualStudioEdition, $VisualStudioVersion, $VisualStudioCodeName, $RequiredComponents).Start_BuildCommand($command, $augmentedArguments, $Interactive)

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
        System.String[]. Invoke-VsDevCommand returns an array of strings that represents the output of executing the application/command
        with the given arguments
    .PARAMETER Command
        Application/Command to execute in the VS Developer Command Prompt Environment
    .PARAMETER Arguments
        Arguments to pass to Application/Command being executed
    .PARAMETER VisualStudioEdition
        Selects Visual Studio Development Environment based on Edition
        Valid values are 'Community', 'Professional', 'Enterprise', 'TeamExplorer', 'WDExpress', 'BuildTools', 'TestAgent', 'TestController', 'TestProfessional', 'FeedbackClient', '*'
        Defaults to '*' (any edition)
    .PARAMETER VisualStudioVersion
        Selects Visual Studio Development Environment based on Version (2015, 2017, 2019 etc.)
    .PARAMETER VisualStudioCodename
        Selects Visual Studio Development Environment based on Version CodeName (Dev14, Dev15, Dev16 etc.)
    .PARAMETER VisualStudioBuildVersion
        Selects Visual Studio Development Environment based on Build Version (e.g., "15.9.25", "16.8.0").
        A prefix is sufficient (e.g., "15", "15.9", "16" etc.)
    .PARAMETER VersionMatchingRule
        Identifies the rule for matching 'VisualStudioBuildVersion' parameter. Valid values are {'Like', 'ExactMatch', 'NewestGreaterThan'} 
        
        - 'Like' (Default) is similar to powershell's '-like' operator
        - 'ExactMatch' looks for an exact version match
        - 'NewestGreaterThan' interprets the supplied version as a number and identifies a Visual Studio installation whose version is greater-than-or-equal to the requested version (the highest available version is selected)
    .PARAMETER RequiredComponents
        List of required components. See https://aka.ms/vs/workloads for list of edition-specific workload ID's
    .PARAMETER Interactive
        Runs in interactive mode. Useful for running programs like cmd.exe, pwsh.exe, powershell.exe or csi.exe in the Visual Studio Developer Command Prompt Environment
    .PARAMETER Target
        Build Target to Run. Options are 'Build' (Default), 'Rebuild', 'Clean', 'Deploy'
    .PARAMETER Ide
        Launch Visual Studio IDE
        If $Target parameter or a commandline option related to build like /Build, /Clean, /Deploy, /Rebuild is specified, they would be ignored
    #>
}

Set-Alias -Name ivdc -Value Invoke-VsDevCommand
Set-Alias -Name vsdevcmd -Value Invoke-VsDevCommand

Set-Alias -Name imb -Value Invoke-MsBuild
Set-Alias -Name msbuild -Value Invoke-MsBuild


Set-Alias -Name vsbuild -Value Invoke-VsBuild
Set-Alias -Name ivb -Value Invoke-VsBuild
Set-Alias -Name devenv -Value Invoke-VsBuild

Export-ModuleMember Invoke-VsDevCommand
Export-ModuleMember -Alias ivdc
Export-ModuleMember -Alias vsdevcmd

Export-ModuleMember Invoke-MsBuild
Export-ModuleMember -Alias imb
Export-ModuleMember -Alias msbuild


Export-ModuleMember Invoke-VsBuild
Export-ModuleMember -Alias vsbuild
Export-ModuleMember -Alias ivb
Export-ModuleMember -Alias devenv