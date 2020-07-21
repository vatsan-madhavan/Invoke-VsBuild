# VsDevCmd
Powershell Module to run an application/command (including MSBuild) within VS Developer Command Prompt environment. 

`VsDevCmd.psm1` module exports two key functions:

- `Invoke-VsDevCommand`
  - Aliases: `vsdevcmd`, `ivdc`
- `Invoke-MsBuild`
  - Aliases: `msbuild`, `imb`

## `Invoke-VsDevCommand`

`Invoke-VsDevCommand` can run any application in the *Visual Studio Developer Command Prompt* environment. It's most useful for invoking applications like `msbuild`, `lib`, `csi` etc. 

It can also be used to run command-prompt like applications like `cmd.exe`, `powershell.exe`, and `pwsh.exe` in `-Interactive` mode. 

If multiple versions of Visual Studio are installed side-by-side on a system, this command allows selection of a specific environment for running commands by specifying the version of the Visual Studio from which the corresponding *Developer Command Prompt* environment should be used. 

`Get-Help -Detailed` or `Get-Help -Full` provides full details of how to use this function. 

## `Invoke-MsBuild`

`Invoke-MsBuild` is a special versionof `Invoke-VsDevCommand` which runs `msbuild.exe` from within the *Visual Studio Developer Command Prompt* environment. 

All the applicable capabilities of `Invoke-VsDevCommand` are available in `Invoke-MsBuild`. `Get-Help` can provide full details along with examples. 
