# Invoke-VsBuild

Powershell Module to Build solutions/projects using Visual Studio, MsBuild and run applications/commands within the VS Developer Command Prompt environment. 

`Invoke-VsBuild.psm1` module exports three key functions:

- `Invoke-VsBuild`
  - Aliases: `vsbuild`, `ivb`, `devenv`
- `Invoke-MsBuild`
  - Aliases: `msbuild`, `imb`
- `Invoke-VsDevCommand`
  - Aliases: `vsdevcmd`, `ivdc`

## `Invoke-VsBuild`

`Invoke-VsBuild` builds solutions or projects using Visual Studio in a commandline environment. It can also launch Visual Studio IDE. 

## `Invoke-MsBuild`

`Invoke-MsBuild` runs `msbuild.exe` from within the *Visual Studio Developer Command Prompt* environment and can be used to build solutions/projects in a commandline environments.

All the applicable capabilities of `Invoke-VsDevCommand` are available in `Invoke-MsBuild`. `Get-Help` can provide full details along with examples. 

## `Invoke-VsDevCommand`

`Invoke-VsDevCommand` can run any application in the *Visual Studio Developer Command Prompt* environment. It's most useful for invoking applications like `msbuild`, `lib`, `csi` etc. 

It can also be used to run command-prompt like applications like `cmd.exe`, `powershell.exe`, and `pwsh.exe` in `-Interactive` mode. 

If multiple versions of Visual Studio are installed side-by-side on a system, this command allows selection of a specific environment for running commands by specifying the version of the Visual Studio from which the corresponding *Developer Command Prompt* environment should be used. 

`Get-Help -Detailed` or `Get-Help -Full` provides full details of how to use this function. 