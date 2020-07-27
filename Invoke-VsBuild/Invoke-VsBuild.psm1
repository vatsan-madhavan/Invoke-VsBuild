
enum VersionMatchingRule {
    ExactMatch;
    Like;
    NewestGreaterThan;
}

class VsWhereNotFoundException : System.IO.FileNotFoundException {
    VsWhereNotFoundException() : base('VsWhere not found') {}
    VsWhereNotFoundException([string]$filename) : base('VsWhere not found', $filename) {}
    VsWhereNotFoundException([string]$filename, [System.Exception]$inner): base('VsWhere not found', $filename, $inner) {}
    VsWhereNotFoundException([System.Exception]$inner): base('VsWhere not found', 'VsWhere.exe', $inner) {}
}

class VisualStudioNotFoundException : System.Exception {
    VisualStudioNotFoundException() {}
    VisualStudioNotFoundException([string]$message) : base($message) {}
    VisualStudioNotFoundException([string]$message, [System.Exception]$inner): base($message, $inner) {}
}

class VisualStudioInstanceNotMatchedException : System.Exception {
    VisualStudioInstanceNotMatchedException() {}
    VisualStudioInstanceNotMatchedException([string]$message) : base($message) {}
    VisualStudioInstanceNotMatchedException([string]$message, [System.Exception]$inner): base($message, $inner) {}
}

class UserApplicationNotFoundException : System.ArgumentException {
    UserApplicationNotFoundException() : base('Application not found') {}
    UserApplicationNotFoundException([string]$paramName) : base('Application not found', $paramName) {}
    UserApplicationNotFoundException([string] $paramName, [System.Exception]$inner): base('Application not found', $paramName, $inner) {}
}

class ProcessResult {
    [string] $ExeFile
    [string[]] $Arguments
    [int] $ExitCode
    [string] $Out
    [string] $Err
}

class ProcessHelper {
    # Courtesy https://stackoverflow.com/a/24371479/492471
    #   + Several modifications
    # Runs the specified executable and captures its exit code, stdout
    # and stderr.
    # Returns: custom object.
    [ProcessResult] static Run([String]$sExeFile,[String[]]$cArgs,[String]$sVerb ) {

        # sExeFile is a mandatory parameter
        if ((-not $sExeFile) -or (-not (Test-Path -PathType Leaf -Path $sExeFile))){
            throw New-Object System.ArgumentException 'sExeFile'
        }

        # Setting process invocation parameters.
        $oPsi = New-Object -TypeName System.Diagnostics.ProcessStartInfo
        $oPsi.CreateNoWindow = $true
        $oPsi.UseShellExecute = $false
        $oPsi.RedirectStandardOutput = $true
        $oPsi.RedirectStandardError = $true
        $oPsi.FileName = $sExeFile
        if (! [String]::IsNullOrEmpty($cArgs)) {
            $oPsi.Arguments = $cArgs
        }
        if (! [String]::IsNullOrEmpty($sVerb)) {
            $oPsi.Verb = $sVerb
        }
    
        # Creating process object.
        $oProcess = New-Object -TypeName System.Diagnostics.Process
        $oProcess.StartInfo = $oPsi
    
        # Creating string builders to store stdout and stderr.
        $oStdOutBuilder = New-Object -TypeName System.Text.StringBuilder
        $oStdErrBuilder = New-Object -TypeName System.Text.StringBuilder
    
        # Adding event handlers for stdout and stderr.
        $sScripBlock = {
            if (! [String]::IsNullOrEmpty($EventArgs.Data)) {
                $Event.MessageData.AppendLine($EventArgs.Data)
            }
        }
        $oStdOutEvent = Register-ObjectEvent -InputObject $oProcess `
            -Action $sScripBlock -EventName 'OutputDataReceived' `
            -MessageData $oStdOutBuilder
        $oStdErrEvent = Register-ObjectEvent -InputObject $oProcess `
            -Action $sScripBlock -EventName 'ErrorDataReceived' `
            -MessageData $oStdErrBuilder
    
        # Starting process.
        [Void]$oProcess.Start()
        $oProcess.BeginOutputReadLine()
        $oProcess.BeginErrorReadLine()
        [Void]$oProcess.WaitForExit()
    
        # Unregister events to retrieve process output.
        Unregister-Event -SourceIdentifier $oStdOutEvent.Name
        Unregister-Event -SourceIdentifier $oStdErrEvent.Name
    
        $oResult = [ProcessResult]::new()
        $oResult.ExeFile = $sExeFile
        $oResult.Arguments = $cArgs
        $oResult.ExitCode = $oProcess.ExitCode
        $oResult.Out = $oStdOutBuilder.ToString().Trim()
        $oResult.Err = $oStdErrBuilder.ToString().Trim()
    
        return $oResult
    }

    [ProcessResult] static Run([String]$sExeFile,[String[]]$cArgs) {
        return [ProcessHelper]::Run($sExeFile, $cArgs, $null)
    }

    [ProcessResult] static Run([String]$sExeFile) {
        return [ProcessHelper]::Run($sExeFile, $null, $null)
    }
}


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
        [string]$visualStudioInstallerPath = Join-Path "${env:ProgramFiles(x86)}\\Microsoft Visual Studio\\Installer\" $vswhereExe
        [string]$downloadPath = Join-path $InstallDir $vswhereExe
        [string]$VsWhereTempPath = Join-Path $env:TEMP $vswhereExe

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
        $vsWhereCmd = Get-Command $vswhereExe -ErrorAction SilentlyContinue
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

        $vsWhereUri = 'https://github.com/microsoft/vswhere/releases/download/2.8.4/vswhere.exe'

        if (-not (Test-Path -Path $downloadPath -PathType Leaf)) {
            Invoke-WebRequest -Uri $vsWhereUri -OutFile (Join-Path $InstallDir 'vswhere.exe')
        }

        if (-not (Test-Path -Path $downloadPath -PathType Leaf)) {
            Write-Error "$downloadPath could not not be provisioned" -ErrorAction Stop
        }

        return $downloadPath
    }

    # VsDevCmd() {
    #     $this.vsDevCmd = [VsDevCmd]::GetVsDevCmdPath($null,[VersionMatchingRule]::Like, $null, $null, $null)
    # }

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

    [PSCustomObject[]] hidden static GetProductInfo($installations) {
        [PSCustomObject[]]$info = @()
        $installations | Where-Object {
            $_.catalog
        } | ForEach-Object {
            [System.Management.Automation.SemanticVersion]$ver = [VsDevCmd]::MakeSemanticVersion($_.catalog.productSemanticVersion)
            [PSCustomObject]$record = [PSCustomObject]@{
                InstanceId         = $_.instanceId
                SemanticVersion    = $ver
                ProductId          = $_.productId
                ProductLineVersion = $_.catalog.productLineVersion
                ProductLine        = $_.catalog.ProductLine
                InstallationPath    = $_.installationPath
            }
            $info += $record
        }
        return $info
    }

    [PSCustomObject[]] static hidden GetInstancesWithRequiredComponents([string[]] $requiredComponents) {
        if ((-not $requiredComponents) -or ($requiredComponents.Length -eq 0)) {
            throw New-Object System.ArgumentException -ArgumentList "'requiredComponents' is null or empty", 'requiredComponents'
        }

        [array]$arguments = @('-prerelease', '-format', 'json') + ($requiredComponents | ForEach-Object { ('-requires', $_) })

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


        [array]$json = . "$([VsDevCmd]::vswhere)" -prerelease -legacy -format json | ConvertFrom-Json
        [PSCustomObject[]]$installs = [VsDevCmd]::GetProductInfo($json)


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
            $installsWithrequiredComponents = [VsDevCmd]::GetInstancesWithRequiredComponents($requiredComponents)

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
                throw New-Object UserApplicationNotFoundException $Command
            }

            [string] $cmd = if ($cmdObject -is [array]) { $cmdObject[0].Source } else { $cmdObject.Source }

            [ProcessResult]$result = [ProcessHelper]::Run($cmd, $Arguments)

            <#
            [string]$result = [string]::Empty
            [System.Diagnostics.Process]$p = $null
            if ($Arguments -and $Arguments.Count -gt 0) {
                $p = Start-Process -FilePath "$cmd" -ArgumentList $Arguments -NoNewWindow -OutVariable result -PassThru
            }
            else {
                $p = Start-Process -FilePath "$cmd" -NoNewWindow -OutVariable result -PassThru
            }
            if ($interactive) {
                $p.WaitForExit() | Out-Host
            }
            else {
                $p.WaitForExit()
            }
            #>

            return $result.Out
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