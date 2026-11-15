<#
    .SYNOPSIS
        Applies Windows optimization settings defined in an XML configuration file.
    .DESCRIPTION
        Reads an XML file containing optimization items (registry, services, scheduled tasks,
        store apps, file/folder operations, PowerShell scripts) and applies them based on the
        detected OS version. Results are written to the console and a tab-separated log file.
        Requires an elevated, 64-bit PowerShell session. Store apps are removed for all users
        and also from the provisioned image, so they do not return for new profiles.
        Use -WhatIf to list what would be applied without changing anything.
    .PARAMETER FilePath
        Path to the XML configuration file. Defaults to Windows.xml in the script directory.
    .PARAMETER ExcludeOrder
        Array of Order numbers to skip. Matching items are shown inline as Skipped.
    .PARAMETER IncludeOrder
        Array of Order numbers to include. If specified, only matching items are processed.
    .PARAMETER LogPath
        Directory where the tab-separated log file is written (timestamp, level, type, item, message).
        Defaults to $Env:ProgramData\WorkspaceOptimizer\Logs and is created when missing.
        Falls back to $Env:Temp if the specified path is not writable.
        A folder under $Env:ProgramData is restricted to administrators and SYSTEM, and is
        refused when it is a link or was created by a non-administrator.
    .PARAMETER LogLevel
        Controls which entries are written to the log file.
          Info    - Errors, warnings, successes, and all item results (default)
          Verbose - Same as Info (kept for compatibility)
          Debug   - Adds all detail including script output
    .PARAMETER Detailed
        When specified, prints PowerShell script output to the console regardless of LogLevel.
        Equivalent to the console output behavior of -LogLevel Verbose, without changing what is logged.
    .EXAMPLE
        .\Invoke-WindowsOptimization.ps1

        This runs the optimization with default settings, applying all items in Windows.xml and logging Info-level results to a timestamped log file in $Env:ProgramData\WorkspaceOptimizer\Logs.
    .EXAMPLE
        .\Invoke-WindowsOptimization.ps1 -ExcludeOrder 60,70 -LogLevel Verbose

        This runs the optimization while skipping items with Order 60 and 70, and logs all successes, skips, and errors to the log file.
    .EXAMPLE
        .\Invoke-WindowsOptimization.ps1 -LogPath 'C:\Logs' -LogLevel Debug

        This runs the optimization with detailed logging, including script outputs, and attempts to write the log file to C:\Logs. If C:\Logs is not writable, it falls back to the temp directory.
    .EXAMPLE
        .\Invoke-WindowsOptimization.ps1 -IncludeOrder 10,20,30

        This runs only the optimization items with Order 10, 20, and 30, and logs Info-level results to the log file.
    .EXAMPLE
        .\Invoke-WindowsOptimization.ps1 -WhatIf

        This lists every item that would be applied, without changing the system. Items are reported as Skipped (WhatIf).
    .NOTES
        Function  : Invoke-WindowsOptimization
        Author    : John Billekens
        Copyright : Copyright (c) John Billekens Consultancy
        Version   : 2026.1115.1600

        Exit codes:
          0 - All items succeeded or were skipped
          1 - Fatal error: XML file missing, platform unknown, not elevated, or 32-bit host on a 64-bit OS
          2 - One or more items failed, or the DefaultUser hive could not be unloaded
          3 - No OS entry in the XML matched this machine, so nothing was applied
#>
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$FilePath = (Join-Path -Path $PSScriptRoot -ChildPath 'Windows.xml'),

    [Parameter(Mandatory = $false)]
    [Alias('Exclude')]
    [int[]]$ExcludeOrder = @(),

    [Parameter(Mandatory = $false)]
    [Alias('Include')]
    [int[]]$IncludeOrder = @(),

    [Parameter(Mandatory = $false)]
    [string]$LogPath = (Join-Path -Path $Env:ProgramData -ChildPath 'WorkspaceOptimizer\Logs'),

    [Parameter(Mandatory = $false)]
    [switch]$SkipWarning,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Info', 'Verbose', 'Debug')]
    [string]$LogLevel = 'Info',

    [Parameter(Mandatory = $false)]
    [switch]$Detailed
)


$ProgressPreference = 'SilentlyContinue'

$script:ScriptVersion = '2026.1115.1600'

# A 32-bit host sees a redirected registry and file system, so changes would land in the wrong place
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    Write-Host 'Error: this is a 32-bit PowerShell host on a 64-bit OS. Run the script with the 64-bit host, for example %SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe' -ForegroundColor Red
    exit 1
}

# Ensure HKU: PSDrive is available (no-op if already present)
$null = New-PSDrive -PSProvider Registry -Name HKU -Root HKEY_USERS -ErrorAction SilentlyContinue -WhatIf:$false

$script:DefaultUserMounted = $false
$script:DefaultUserMountError = $null
$script:HiveUnloadFailed = $false
$script:ProvisionedPackages = $null
$script:InstalledPackageNames = $null

# Full paths, so an elevated run never picks up a same-named program from PATH
$script:RegExe = Join-Path -Path $Env:SystemRoot -ChildPath 'System32\reg.exe'
$script:WindowsPowerShellExe = Join-Path -Path $Env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'


#region Logging

function Initialize-LogFile {
    param([string]$Directory)

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $fileName = "WindowsOptimization_$timestamp.log"

    # Standard users can create folders under ProgramData, so a log folder there is only used
    # when an administrator owns every level of it, and it is then closed to everyone else
    $programData = [System.IO.Path]::GetFullPath($Env:ProgramData).TrimEnd('\')
    $adminSids = @('S-1-5-32-544', 'S-1-5-18')
    $trustedOwners = $adminSids + [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value

    foreach ($dir in @($Directory, $Env:Temp)) {
        try {
            if (-not (Test-Path -LiteralPath $dir)) {
                New-Item -Path $dir -ItemType Directory -Force -ErrorAction Stop -WhatIf:$false | Out-Null
            }
            $folder = Get-Item -LiteralPath $dir -Force -ErrorAction Stop

            if ($folder.FullName.StartsWith("$programData\", [System.StringComparison]::OrdinalIgnoreCase)) {
                $level = $folder
                while ($level.FullName.Length -gt $programData.Length) {
                    $owner = (Get-Acl -LiteralPath $level.FullName -ErrorAction Stop).GetOwner([System.Security.Principal.SecurityIdentifier]).Value
                    if (($level.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -or $owner -notin $trustedOwners) {
                        throw "'$($level.FullName)' is a link or is not owned by an administrator"
                    }
                    $level = $level.Parent
                }

                $acl = Get-Acl -LiteralPath $folder.FullName -ErrorAction Stop
                $acl.SetAccessRuleProtection($true, $false)
                foreach ($rule in @($acl.Access)) { $null = $acl.RemoveAccessRule($rule) }
                foreach ($sid in $adminSids) {
                    $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new(
                            [System.Security.Principal.SecurityIdentifier]$sid, 'FullControl', 'ContainerInherit, ObjectInherit', 'None', 'Allow'))
                }
                Set-Acl -LiteralPath $folder.FullName -AclObject $acl -ErrorAction Stop -WhatIf:$false
            }

            # CreateNew, so a file planted under this name is never opened
            $candidate = Join-Path $folder.FullName $fileName
            [System.IO.File]::Open($candidate, [System.IO.FileMode]::CreateNew).Close()
            return $candidate
        } catch {
            Write-Warning "Log folder '$dir' was not used: $($_.Exception.Message)"
            continue
        }
    }
    return $null
}

function Write-LogHeader {
    if ($null -eq $script:LogFile) { return }
    try {
        $header = @(
            "Date       : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            "RunId      : $($script:RunId)"
            "Version    : $($script:ScriptVersion)"
            "User       : $Env:USERDOMAIN\$Env:USERNAME"
            "Host       : $Env:COMPUTERNAME"
            "OS         : $($script:LogContext['os'])"
            "Build      : $($script:LogContext['build'])"
            "LogLevel   : $($script:LogLevel)"
            "---"
        )
        $header | Add-Content -Path $script:LogFile -Encoding UTF8 -WhatIf:$false
    } catch { }
}

$script:LogFile = Initialize-LogFile -Directory $LogPath
if ($null -eq $script:LogFile) {
    Write-Warning "No writable log location found ('$LogPath' and '$Env:Temp'). Logging is disabled."
}
$script:LogLevel = $LogLevel
$script:RunId = [System.Guid]::NewGuid().ToString()
$script:LogContext = @{}  # populated after OS detection

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Debug')]
        [string]$Level = 'Info',
        [string]$Type = '',
        [string]$Item = ''
    )

    if ($null -eq $script:LogFile) { return }

    $write = switch ($script:LogLevel) {
        'Info' { $Level -in @('Error', 'Warning', 'Success', 'Info') }
        'Verbose' { $Level -in @('Error', 'Warning', 'Success', 'Info') }
        'Debug' { $true }
    }
    if (-not $write) { return }

    try {
        $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')`t$Level`t$Type`t$Item`t$Message"
        $line | Add-Content -Path $script:LogFile -Encoding UTF8 -WhatIf:$false
    } catch { }
}

#endregion Logging

#region Output

# Column widths - "[ ScheduledTask ]" = 2 brackets + 2 spaces + 11 chars = 15 + 2 = 17... kept at 15 usable
$script:TypeColumnWidth = 15   # "[ ScheduledTask ]" - 2 brackets + 2 spaces + 11 chars
$script:Separator = ' '  # space between type column and item name
$script:DotChar = '.'
$script:MinDots = 3    # always at least 3 dots before the status
$script:IndentWidth = $script:TypeColumnWidth + 1 + $script:Separator.Length  # indent for error lines

function Get-ConsoleWidth {
    try {
        $w = $Host.UI.RawUI.WindowSize.Width
        if ($w -gt 40) { return $w }
    } catch { }
    return 120
}

function Write-ItemLine {
    param(
        [string]$TypeLabel,
        [string]$Name,
        [string]$StatusText,
        [string]$StatusColor
    )

    $consoleWidth = (Get-ConsoleWidth) - 5
    $typeFormatted = '[ {0,-11} ]' -f $TypeLabel
    $prefix = $typeFormatted + $script:Separator

    $availableForNameAndDots = $consoleWidth - $prefix.Length - $StatusText.Length - 1
    $nameMaxLen = $availableForNameAndDots - $script:MinDots
    $displayName = if ($Name.Length -gt $nameMaxLen) {
        $Name.Substring(0, [Math]::Max($nameMaxLen - 3, 1)) + '...'
    } else {
        $Name
    }

    $dotCount = [Math]::Max($availableForNameAndDots - $displayName.Length, $script:MinDots)
    $dots = $script:DotChar * $dotCount

    Write-Host $prefix -ForegroundColor DarkCyan -NoNewline
    Write-Host $displayName -ForegroundColor Cyan -NoNewline
    Write-Host (' ' + $dots + ' ') -ForegroundColor DarkGray -NoNewline
    Write-Host $StatusText -ForegroundColor $StatusColor
}

function Write-ItemResult {
    [CmdletBinding()]
    param(
        [string]$TypeLabel,
        [string]$Name,
        [PSCustomObject]$Result
    )

    # Determine status text and color
    switch ($Result.Status) {
        'Success' { $statusText = 'Success' ; $statusColor = 'Green' }
        'Skipped' { $statusText = $Result.Message ; $statusColor = 'DarkGray' }
        'Failed' { $statusText = 'Failed'  ; $statusColor = 'Red' }
        default { $statusText = $Result.Status  ; $statusColor = 'Yellow' }
    }

    Write-ItemLine -TypeLabel $TypeLabel -Name $Name -StatusText $statusText -StatusColor $statusColor

    # For failures: wrap error message over up to 3 indented lines
    if ($Result.Status -eq 'Failed' -and -not [string]::IsNullOrWhiteSpace($Result.Message)) {
        $indent = ' ' * $script:IndentWidth
        $maxLineLen = (Get-ConsoleWidth) - 5 - $indent.Length - 1
        $words = $Result.Message -split '\s+'
        $lines = [System.Collections.Generic.List[string]]::new()
        $current = ''

        foreach ($word in $words) {
            if ($current.Length -eq 0) {
                $current = $word
            } elseif (($current.Length + 1 + $word.Length) -le $maxLineLen) {
                $current += ' ' + $word
            } else {
                $lines.Add($current)
                $current = $word
                if ($lines.Count -ge 2) { break }
            }
        }
        if ($current.Length -gt 0) { $lines.Add($current) }

        foreach ($line in $lines) {
            Write-Host ($indent + $line) -ForegroundColor Red
        }
    }
}

#endregion Output

#region Helper Functions

function Get-SystemPlatform {
    <#
    .SYNOPSIS
        Identifies the underlying platform, accounting for nested virtualization.
    .DESCRIPTION
        Inspects Win32_ComputerSystem and Win32_BIOS for hypervisor signatures.
        Works across AWS (HVM domU), Azure, VMware, and physical hardware.
    #>
    [CmdletBinding()]
    param()

    try {
        $CS = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $BIOS = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop

        $Manufacturer = $CS.Manufacturer
        $Model = $CS.Model
        $BIOSVersion = $BIOS.Version
        $SerialNumber = $BIOS.SerialNumber

        # Comprehensive list of VM signatures (Manufacturer, Model, or BIOS)
        $VmSignatures = @(
            'VMware',
            'Virtual',
            'HVM domU',
            'Hyper-V',
            'Xen',
            'KVM',
            'QEMU',
            'Parallels',
            'Amazon EC2',
            'AWS',
            'Google',
            'Nutanix',
            'AHV',
            'Bochs',
            'innotek'
        )

        # Serial numbers are free-form on physical hardware, so only match known VM prefixes
        $SerialPrefixes = @('VMware-', 'Parallels-')

        $IsVirtual = $false
        $Identification = "Physical"

        # Check all relevant fields for any VM signature
        foreach ($Sig in $VmSignatures) {
            if ($Manufacturer -like "*$($Sig)*" -or $Model -like "*$($Sig)*" -or $BIOSVersion -like "*$($Sig)*") {
                $IsVirtual = $true
                $Identification = "Virtual ($($Sig))"
                break
            }
        }
        if (-not $IsVirtual) {
            foreach ($Prefix in $SerialPrefixes) {
                if ($SerialNumber -like "$($Prefix)*") {
                    $IsVirtual = $true
                    $Identification = "Virtual ($($Prefix.TrimEnd('-')))"
                    break
                }
            }
        }
        return [PSCustomObject]@{
            IsVirtual    = $IsVirtual
            Platform     = $Identification
            Manufacturer = $Manufacturer
            Model        = $Model
            BIOSVersion  = $BIOSVersion
            SerialNumber = $SerialNumber
        }
    } catch {
        throw "Failed to identify platform: $($_.Exception.Message)"
    }
}

function New-ActionResult {
    [CmdletBinding()]
    param(
        [ValidateSet('Success', 'Skipped', 'Failed')]
        [string]$Status,
        [string]$Message = ''
    )
    [PSCustomObject]@{ Status = $Status ; Message = $Message }
}

function Invoke-PowerShellAction {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.Xml.XmlElement]$Item
    )

    $engine = if ([string]::IsNullOrWhiteSpace($Item.PowerShell.Engine)) { 'powershell' } else { $Item.PowerShell.Engine.Trim().ToLower() }
    # The XML adapter returns a plain string for text-only elements, so read the node itself
    $scriptNode = $Item.SelectSingleNode('PowerShell/Script')
    $script = if ($scriptNode) { $scriptNode.InnerText } else { $null }

    if ([string]::IsNullOrWhiteSpace($script)) {
        Write-Log -Level 'Error' -Type 'PowerShell' -Item $Item.Name -Message 'Script is empty'
        return New-ActionResult -Status 'Failed' -Message 'Script is empty'
    }

    Write-ItemLine -TypeLabel 'PoSh Script' -Name $Item.Name -StatusText 'Started' -StatusColor 'Cyan'

    # 'powershell' only means Windows PowerShell 5.1 in-process when this script is
    # itself running under Windows PowerShell 5.1. Otherwise (e.g. this script running
    # under pwsh), run powershell.exe as a child process so Engine=powershell reliably
    # means Windows PowerShell 5.1 regardless of the host.
    $hostExe = if ($engine -eq 'powershell' -and $PSVersionTable.PSEdition -eq 'Core') { $script:WindowsPowerShellExe } else { $null }

    # pwsh / powershell (cross-engine) - child process (different binary), output always printed and logged
    if ($engine -eq 'pwsh' -or $hostExe) {
        $exeName = if ($hostExe) { $hostExe } else { 'pwsh' }
        $exePath = if (Get-Command $exeName -ErrorAction SilentlyContinue) { $exeName } else { $null }
        if (-not $exePath) {
            Write-Log -Level 'Error' -Type 'PowerShell' -Item $Item.Name -Message "$exeName not found on this system"
            return New-ActionResult -Status 'Failed' -Message "$exeName not found on this system"
        }
        $tmpOut = $null
        $tmpErr = $null
        try {
            $tmpOut = [System.IO.Path]::GetTempFileName()
            $tmpErr = "$tmpOut.err"
            $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($script))
            $proc = Start-Process -FilePath $exePath `
                -ArgumentList @('-NonInteractive', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encodedCommand) `
                -RedirectStandardOutput $tmpOut `
                -RedirectStandardError $tmpErr `
                -NoNewWindow -Wait -PassThru

            $outLines = @(if (Test-Path -LiteralPath $tmpOut) { Get-Content -LiteralPath $tmpOut })
            $errLines = @(if (Test-Path -LiteralPath $tmpErr) { Get-Content -LiteralPath $tmpErr })

            foreach ($line in $outLines) { Write-Host $line -ForegroundColor White ; Write-Log -Level 'Info' -Type 'PowerShell' -Item $Item.Name -Message "OUT:  $line" }
            foreach ($line in $errLines) { Write-Host $line -ForegroundColor Red   ; Write-Log -Level 'Error' -Type 'PowerShell' -Item $Item.Name -Message "ERR:  $line" }

            if ($proc.ExitCode -ne 0 -or $errLines.Count -gt 0) {
                $errMsg = if ($errLines.Count -gt 0) { $errLines[0] } else { "Exit code $($proc.ExitCode)" }
                Write-Log -Level 'Error' -Type 'PowerShell' -Item $Item.Name -Message $errMsg
                return New-ActionResult -Status 'Failed' -Message $errMsg
            }

            Write-Log -Level 'Success' -Type 'PowerShell' -Item $Item.Name -Message 'Script executed successfully'
            return New-ActionResult -Status 'Success'
        } catch {
            Write-Log -Level 'Error' -Type 'PowerShell' -Item $Item.Name -Message $_.Exception.Message
            return New-ActionResult -Status 'Failed' -Message $_.Exception.Message
        } finally {
            foreach ($tmpFile in @($tmpOut, $tmpErr)) {
                if ($tmpFile) { Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue }
            }
        }
    }

    # powershell - runspace in current process (host is already Windows PowerShell 5.1)
    $rs = $null
    $ps = $null
    try {
        $rs = [RunspaceFactory]::CreateRunspace()
        $rs.ApartmentState = 'STA'
        $rs.ThreadOptions = 'ReuseThread'
        $rs.Open()

        $ps = [PowerShell]::Create()
        $ps.Runspace = $rs
        $null = $ps.AddScript($script)
        $results = $ps.Invoke()

        $showOutput = $Detailed.IsPresent -or $script:LogLevel -in @('Verbose', 'Debug')
        $logLines = [System.Collections.Generic.List[string]]::new()

        foreach ($o in $results) {
            $text = if ($o -is [string]) { $o } else { ($o | Out-String).Trim() }
            if ($text) {
                if ($showOutput) { Write-Host $text -ForegroundColor White }
                $logLines.Add("OUT:  $text")
            }
        }

        foreach ($o in $ps.Streams.Information) {
            $text = if ($o.MessageData -is [System.Management.Automation.HostInformationMessage]) {
                $o.MessageData.Message
            } else { "$($o.MessageData)" }
            if ($text) {
                if ($showOutput) { Write-Host $text -ForegroundColor White }
                $logLines.Add("INFO: $text")
            }
        }

        foreach ($o in $ps.Streams.Warning) {
            $text = "$o"
            if ($showOutput) { Write-Host $text -ForegroundColor Yellow }
            $logLines.Add("WARN: $text")
        }

        foreach ($o in $ps.Streams.Error) {
            $text = "$o"
            if ($showOutput) { Write-Host $text -ForegroundColor Red }
            $logLines.Add("ERR:  $text")
        }

        # Native commands do not write to the error stream on failure, only set the exit code
        $exitCode = $rs.SessionStateProxy.GetVariable('LASTEXITCODE')
        $hasErrors = $ps.Streams.Error.Count -gt 0
        $hasFailed = $hasErrors -or ($null -ne $exitCode -and $exitCode -ne 0)
        $errMsg = if ($hasErrors) { "$($ps.Streams.Error[0])" } elseif ($hasFailed) { "Exit code $exitCode" } else { '' }

        foreach ($line in $logLines) { Write-Log -Level 'Info' -Type 'PowerShell' -Item $Item.Name -Message $line }

        if ($hasFailed) {
            Write-Log -Level 'Error' -Type 'PowerShell' -Item $Item.Name -Message $errMsg
            return New-ActionResult -Status 'Failed' -Message $errMsg
        }

        Write-Log -Level 'Success' -Type 'PowerShell' -Item $Item.Name -Message 'Script executed successfully'
        return New-ActionResult -Status 'Success'
    } catch {
        Write-Log -Level 'Error' -Type 'PowerShell' -Item $Item.Name -Message $_.Exception.Message
        return New-ActionResult -Status 'Failed' -Message $_.Exception.Message
    } finally {
        if ($ps) { $ps.Dispose() }
        if ($rs) { $rs.Dispose() }
    }
}

function Invoke-FileFolderAction {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.Xml.XmlElement]$Item
    )

    $rawType = $Item.FileFolder.ItemType
    $action = $Item.FileFolder.Action
    $path = $Item.FileFolder.Path

    $pathType = switch ($rawType) {
        'Folder' { 'Container' }
        'File' { 'Leaf' }
        default {
            Write-Log -Level 'Error' -Type 'FileFolder' -Item $Item.Name -Message "Unknown ItemType '$rawType'"
            return New-ActionResult -Status 'Failed' -Message "Unknown ItemType '$rawType'"
        }
    }

    # Guard against an empty XML field turning into a recursive delete of the wrong location
    $pathProblem = if ([string]::IsNullOrWhiteSpace($path)) {
        'Path is empty'
    } elseif ($path.Trim() -notmatch '^(?:[A-Za-z]:[\\/]|\\\\)') {
        "Path must be absolute: $path"
    } else {
        # Resolve . and .. first, otherwise C:\Windows\.. gets past the root check
        $fullPath = try { [System.IO.Path]::GetFullPath($path.Trim()) } catch { $null }
        $trimmedPath = "$fullPath".TrimEnd('\', '/')
        if (-not $fullPath) {
            "Path is not valid: $path"
        } elseif ($trimmedPath -match '^[A-Za-z]:$' -or $trimmedPath -match '^\\\\[^\\]+(?:\\[^\\]+)?$') {
            "Refusing to act on a drive or share root: $path"
        }
    }
    if ($pathProblem) {
        Write-Log -Level 'Error' -Type 'FileFolder' -Item $Item.Name -Message $pathProblem
        return New-ActionResult -Status 'Failed' -Message $pathProblem
    }
    $path = $fullPath

    switch ($action) {
        'Remove' {
            if (-not (Test-Path -LiteralPath $path -PathType $pathType)) {
                Write-Log -Level 'Info' -Type 'FileFolder' -Item $Item.Name -Message "Skipped - path not found: $path"
                return New-ActionResult -Status 'Skipped' -Message 'Skipped (not found)'
            }
            try {
                Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
                Write-Log -Level 'Success' -Type 'FileFolder' -Item $Item.Name -Message "Removed: $path"
                return New-ActionResult -Status 'Success'
            } catch {
                Write-Log -Level 'Error' -Type 'FileFolder' -Item $Item.Name -Message $_.Exception.Message
                return New-ActionResult -Status 'Failed' -Message $_.Exception.Message
            }
        }
        'Rename' {
            $newName = $Item.FileFolder.NewName
            if ([string]::IsNullOrWhiteSpace($newName)) {
                Write-Log -Level 'Error' -Type 'FileFolder' -Item $Item.Name -Message 'NewName is empty'
                return New-ActionResult -Status 'Failed' -Message 'NewName is empty'
            }
            if (-not (Test-Path -LiteralPath $path -PathType $pathType)) {
                Write-Log -Level 'Info' -Type 'FileFolder' -Item $Item.Name -Message "Skipped - path not found: $path"
                return New-ActionResult -Status 'Skipped' -Message 'Skipped (not found)'
            }
            try {
                Rename-Item -LiteralPath $path -NewName $newName -ErrorAction Stop
                Write-Log -Level 'Success' -Type 'FileFolder' -Item $Item.Name -Message "Renamed to: $newName"
                return New-ActionResult -Status 'Success'
            } catch {
                Write-Log -Level 'Error' -Type 'FileFolder' -Item $Item.Name -Message $_.Exception.Message
                return New-ActionResult -Status 'Failed' -Message $_.Exception.Message
            }
        }
        default {
            Write-Log -Level 'Error' -Type 'FileFolder' -Item $Item.Name -Message "Unknown Action '$action'"
            return New-ActionResult -Status 'Failed' -Message "Unknown Action '$action'"
        }
    }
}

function Invoke-ServiceAction {
    param (
        [Parameter(Mandatory = $true)]
        [System.Xml.XmlElement]$Item
    )

    $serviceName = $Item.Service.Name
    $action = $Item.Service.Action

    $validStartupTypes = @('Disabled', 'Manual', 'Automatic', 'AutomaticDelayedStart', 'Boot', 'System')
    if ($action -notin $validStartupTypes) {
        Write-Log -Level 'Error' -Type 'Service' -Item $Item.Name -Message "Unknown Action '$action'"
        return New-ActionResult -Status 'Failed' -Message "Unknown Action '$action'"
    }

    try {
        $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if (-not $svc) {
            Write-Log -Level 'Info' -Type 'Service' -Item $Item.Name -Message "Skipped - service not found: $serviceName"
            return New-ActionResult -Status 'Skipped' -Message 'Skipped (service not found)'
        }

        # Get-Service reports delayed-autostart services as plain 'Automatic'; the
        # delayed flag only exists in the registry, so check it there.
        $currentStartType = $svc.StartType
        if ($currentStartType -eq 'Automatic') {
            $delayedFlag = Get-ItemPropertyValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName" -Name 'DelayedAutostart' -ErrorAction SilentlyContinue
            if ($delayedFlag -eq 1) {
                $currentStartType = 'AutomaticDelayedStart'
            }
        }

        if ($currentStartType -eq $action) {
            Write-Log -Level 'Info' -Type 'Service' -Item $Item.Name -Message "Skipped - already $action"
            return New-ActionResult -Status 'Skipped' -Message "Skipped (already $action)"
        }
        Set-Service -Name $serviceName -StartupType $action -ErrorAction Stop
        Write-Log -Level 'Success' -Type 'Service' -Item $Item.Name -Message "Set to $action"
        return New-ActionResult -Status 'Success'
    } catch {
        Write-Log -Level 'Error' -Type 'Service' -Item $Item.Name -Message $_.Exception.Message
        return New-ActionResult -Status 'Failed' -Message $_.Exception.Message
    }
}

function Invoke-RegistryAction {
    param (
        [Parameter(Mandatory = $true)]
        [System.Xml.XmlElement]$Item
    )

    $regHive = $Item.Registry.Hive.TrimEnd('\')
    $regName = $Item.Registry.Name
    $regValue = $Item.Registry.Value
    $regType = $Item.Registry.Type
    $regAction = $Item.Registry.Action

    # An empty Name is the key's default value, which the registry provider addresses as '(default)'
    $propName = if ([string]::IsNullOrEmpty($regName)) { '(default)' } else { $regName }

    # Combine Hive + Path, then normalize to PowerShell PSDrive format (insert colon after hive root)
    $rawPath = if ([string]::IsNullOrWhiteSpace($Item.Registry.Path)) { $regHive } else { "$regHive\$($Item.Registry.Path)" }
    $regPath = $rawPath -replace '^(HK[A-Z_]+)\\', '$1:\'

    # Anything else is not a registry drive, and the provider cmdlets below would treat it as a file path
    if ($regPath -notmatch '^(?:HKLM|HKCU|HKU):\\') {
        Write-Log -Level 'Error' -Type 'Registry' -Item $Item.Name -Message "Unsupported registry location: $rawPath"
        return New-ActionResult -Status 'Failed' -Message "Unsupported registry location: $rawPath"
    }

    # Values are read and deleted through the .NET key, where '' is the default value. The
    # provider's -Name takes wildcards, and * [ ] are valid characters in a value name
    $valueName = "$regName"

    # Lazily mount the DefaultUser hive on first use
    if ($regPath -like 'HKU:\DefaultUser*' -and -not $script:DefaultUserMounted) {
        if (-not $script:DefaultUserMountError) {
            try {
                Mount-DefaultUserHive
            } catch {
                $script:DefaultUserMountError = "DefaultUser hive mount failed: $($_.Exception.Message)"
            }
        }
        if ($script:DefaultUserMountError) {
            Write-Log -Level 'Error' -Type 'Registry' -Item $Item.Name -Message $script:DefaultUserMountError
            return New-ActionResult -Status 'Failed' -Message $script:DefaultUserMountError
        }
    }

    try {
        switch ($regAction) {
            'SetValue' {
                if (-not (Test-Path -LiteralPath $regPath)) {
                    New-Item -Path $regPath -Force -ErrorAction Stop | Out-Null
                }
                $regKey = Get-Item -LiteralPath $regPath -ErrorAction Stop
                $previousText = if ($regKey.GetValueNames() -contains $valueName) { "$($regKey.GetValue($valueName) -join ',')" } else { 'not present' }
                $regKey.Close()
                Write-Log -Level 'Info' -Type 'Registry' -Item $Item.Name -Message "Previous value of $regPath\$propName : $previousText"
                Set-ItemProperty -LiteralPath $regPath -Name $propName -Value $regValue -Type $regType -Force -ErrorAction Stop
                Write-Log -Level 'Success' -Type 'Registry' -Item $Item.Name -Message "Set $regPath\$propName = $regValue ($regType)"
                return New-ActionResult -Status 'Success'
            }
            'DeleteKey' {
                if (-not (Test-Path -LiteralPath $regPath)) {
                    Write-Log -Level 'Info' -Type 'Registry' -Item $Item.Name -Message "Skipped - key not found: $regPath"
                    return New-ActionResult -Status 'Skipped' -Message 'Skipped (key not found)'
                }
                Remove-Item -LiteralPath $regPath -Force -ErrorAction Stop
                Write-Log -Level 'Success' -Type 'Registry' -Item $Item.Name -Message "Deleted key: $regPath"
                return New-ActionResult -Status 'Success'
            }
            'DeleteKeyRecursively' {
                if (-not (Test-Path -LiteralPath $regPath)) {
                    Write-Log -Level 'Info' -Type 'Registry' -Item $Item.Name -Message "Skipped - key not found: $regPath"
                    return New-ActionResult -Status 'Skipped' -Message 'Skipped (key not found)'
                }
                Remove-Item -LiteralPath $regPath -Recurse -Force -ErrorAction Stop
                Write-Log -Level 'Success' -Type 'Registry' -Item $Item.Name -Message "Deleted key recursively: $regPath"
                return New-ActionResult -Status 'Success'
            }
            'DeleteValue' {
                if (-not (Test-Path -LiteralPath $regPath)) {
                    Write-Log -Level 'Info' -Type 'Registry' -Item $Item.Name -Message "Skipped - key not found: $regPath"
                    return New-ActionResult -Status 'Skipped' -Message 'Skipped (key not found)'
                }
                $regKey = (Get-Item -LiteralPath $regPath -ErrorAction Stop).OpenSubKey('', $true)
                try {
                    if ($regKey.GetValueNames() -notcontains $valueName) {
                        Write-Log -Level 'Info' -Type 'Registry' -Item $Item.Name -Message "Skipped - value not found: $regPath\$propName"
                        return New-ActionResult -Status 'Skipped' -Message 'Skipped (value not found)'
                    }
                    Write-Log -Level 'Info' -Type 'Registry' -Item $Item.Name -Message "Deleting $regPath\$propName, current value: $($regKey.GetValue($valueName) -join ',')"
                    $regKey.DeleteValue($valueName)
                } finally {
                    $regKey.Close()
                }
                Write-Log -Level 'Success' -Type 'Registry' -Item $Item.Name -Message "Deleted value: $regPath\$propName"
                return New-ActionResult -Status 'Success'
            }
            default {
                Write-Log -Level 'Error' -Type 'Registry' -Item $Item.Name -Message "Unknown Action '$regAction'"
                return New-ActionResult -Status 'Failed' -Message "Unknown Action '$regAction'"
            }
        }
    } catch {
        Write-Log -Level 'Error' -Type 'Registry' -Item $Item.Name -Message $_.Exception.Message
        return New-ActionResult -Status 'Failed' -Message $_.Exception.Message
    }
}

function Invoke-ScheduledTaskAction {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.Xml.XmlElement]$Item
    )

    $taskName = $Item.ScheduledTask.Name
    $taskPath = $Item.ScheduledTask.Path.TrimEnd('\')
    $action = $Item.ScheduledTask.Action

    if ($action -notin @('Disabled', 'Enabled')) {
        Write-Log -Level 'Error' -Type 'ScheduledTask' -Item $Item.Name -Message "Unknown Action '$action'"
        return New-ActionResult -Status 'Failed' -Message "Unknown Action '$action'"
    }

    try {
        $existing = Get-ScheduledTask -TaskPath "$taskPath\" -TaskName $taskName -ErrorAction SilentlyContinue
        if (-not $existing) {
            Write-Log -Level 'Info' -Type 'ScheduledTask' -Item $Item.Name -Message "Skipped - task not found: $taskPath\$taskName"
            return New-ActionResult -Status 'Skipped' -Message 'Skipped (task not found)'
        }
        if ($action -eq 'Disabled') {
            $null = Disable-ScheduledTask -TaskPath "$taskPath\" -TaskName $taskName -ErrorAction Stop
        } else {
            $null = Enable-ScheduledTask -TaskPath "$taskPath\" -TaskName $taskName -ErrorAction Stop
        }
        Write-Log -Level 'Success' -Type 'ScheduledTask' -Item $Item.Name -Message "Set to $action"
        return New-ActionResult -Status 'Success'
    } catch {
        Write-Log -Level 'Error' -Type 'ScheduledTask' -Item $Item.Name -Message $_.Exception.Message
        return New-ActionResult -Status 'Failed' -Message $_.Exception.Message
    }
}

function Invoke-StoreAppAction {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.Xml.XmlElement]$Item
    )
    $ProgressPreference = 'SilentlyContinue'
    $appName = $Item.StoreApp.Name

    try {
        $removedInstalled = $false

        # Listing packages takes seconds, so list the names once and only query an app that is in it
        # A name that was removed since stays in the list, which costs a query but is never wrong
        if ($null -eq $script:InstalledPackageNames) {
            $script:InstalledPackageNames = @(
                @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue) + @(Get-AppxPackage -ErrorAction SilentlyContinue) |
                    ForEach-Object { $_.Name } | Sort-Object -Unique
            )
        }
        if (@($script:InstalledPackageNames -like $appName).Count -gt 0) {
            $currentUserPkg = Get-AppxPackage -Name $appName -ErrorAction SilentlyContinue
            if ($currentUserPkg) {
                $null = $currentUserPkg | Remove-AppxPackage -ErrorAction Stop
                $removedInstalled = $true
            }

            $allUsersPkg = Get-AppxPackage -AllUsers -Name $appName -ErrorAction SilentlyContinue
            if ($allUsersPkg) {
                $null = $allUsersPkg | Remove-AppxPackage -AllUsers -ErrorAction Stop
                $removedInstalled = $true
            }
        }

        # The provisioned copy would otherwise reinstall the app for every new profile
        # Querying the image takes seconds, so do it once for all StoreApp items
        if ($null -eq $script:ProvisionedPackages) {
            $script:ProvisionedPackages = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop)
        }
        $provisionedPkg = @($script:ProvisionedPackages | Where-Object { $_.DisplayName -like $appName })
        if ($provisionedPkg.Count -gt 0) {
            $provisionedParams = @{ Online = $true ; ErrorAction = 'Stop' }
            if ((Get-Command -Name 'Remove-AppxProvisionedPackage').Parameters.ContainsKey('AllUsers')) {
                $provisionedParams['AllUsers'] = $true
            }
            $null = $provisionedPkg | Remove-AppxProvisionedPackage @provisionedParams
            # Or a later item matching the same package would try to remove it again and fail
            $script:ProvisionedPackages = @($script:ProvisionedPackages | Where-Object { $_.DisplayName -notlike $appName })
        }

        if ($removedInstalled -or $provisionedPkg.Count -gt 0) {
            $removedParts = @()
            if ($removedInstalled) { $removedParts += 'installed' }
            if ($provisionedPkg.Count -gt 0) { $removedParts += 'provisioned' }
            Write-Log -Level 'Success' -Type 'StoreApp' -Item $Item.Name -Message "Removed ($($removedParts -join ' and ')): $appName"
            return New-ActionResult -Status 'Success'
        } else {
            Write-Log -Level 'Info' -Type 'StoreApp' -Item $Item.Name -Message "Skipped - not installed or provisioned: $appName"
            return New-ActionResult -Status 'Skipped' -Message 'Skipped (not installed)'
        }
    } catch {
        $msg = if ($_.Exception.Message -like '*This app is part of Windows and cannot be uninstalled*') {
            'App is part of Windows and cannot be uninstalled'
        } else {
            $_.Exception.Message
        }
        Write-Log -Level 'Error' -Type 'StoreApp' -Item $Item.Name -Message $msg
        return New-ActionResult -Status 'Failed' -Message $msg
    }
}

#endregion Helper Functions

#region DefaultUser Hive

function Mount-DefaultUserHive {
    [CmdletBinding()]
    param ()
    # Force-unmount if already present (handles stale/crashed mounts)
    if (Test-Path 'HKU:\DefaultUser') {
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
        $unloadResult = & $script:RegExeunload 'HKU\DefaultUser' 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "HKU\DefaultUser already exists and could not be unloaded: $unloadResult"
        }
    }

    # The Default profile can be relocated, so read it from ProfileList and fall back to the standard path
    $defaultProfile = $null
    try {
        $defaultProfile = [Environment]::ExpandEnvironmentVariables((Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' -Name 'Default' -ErrorAction Stop))
    } catch {
        $defaultProfile = $null
    }
    if ([string]::IsNullOrWhiteSpace($defaultProfile)) { $defaultProfile = 'C:\Users\Default' }

    $datFile = Join-Path -Path $defaultProfile -ChildPath 'NTUSER.DAT'
    if (-not (Test-Path -Path $datFile -PathType Leaf)) {
        throw "Default user hive not found: $datFile"
    }

    $loadResult = & $script:RegExeload 'HKU\DefaultUser' $datFile 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to mount DefaultUser hive: $loadResult"
    }

    $script:DefaultUserMounted = $true
    Write-Log -Level 'Info' -Message "Mounted DefaultUser hive ($datFile -> HKU\DefaultUser)"
}

function Dismount-DefaultUserHive {
    [CmdletBinding()]
    param ()
    if (-not $script:DefaultUserMounted) { return }

    $unloaded = $false
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
        Start-Sleep -Seconds 1  # give it a moment to release handles before unmounting

        $unloadResult = & $script:RegExeunload 'HKU\DefaultUser' 2>&1
        if ($LASTEXITCODE -eq 0) {
            $unloaded = $true
            break
        }
        Write-Log -Level 'Warning' -Message "Unmount DefaultUser hive failed (attempt $attempt of 3): $unloadResult"
    }

    if ($unloaded) {
        Write-Log -Level 'Info' -Message 'Unmounted DefaultUser hive'
    } else {
        $script:HiveUnloadFailed = $true
        Write-Warning "Could not unmount DefaultUser hive: $unloadResult"
        Write-Log -Level 'Error' -Message "Failed to unmount DefaultUser hive: $unloadResult"
    }

    $script:DefaultUserMounted = $false
}

#endregion DefaultUser Hive


#region Type Map

$typeMap = @{
    FileFolder    = @{ Function = 'Invoke-FileFolderAction'    ; DisplayName = 'File/Folder' }
    Service       = @{ Function = 'Invoke-ServiceAction'       ; DisplayName = 'Service' }
    Registry      = @{ Function = 'Invoke-RegistryAction'      ; DisplayName = 'Registry' }
    ScheduledTask = @{ Function = 'Invoke-ScheduledTaskAction' ; DisplayName = 'Sched. Task' }
    PowerShell    = @{ Function = 'Invoke-PowerShellAction'    ; DisplayName = 'PoSh Script' }
    StoreApp      = @{ Function = 'Invoke-StoreAppAction'      ; DisplayName = 'Store App' }
}

#endregion Type Map

#region Load XML

if (Test-Path -Path $FilePath) {
    # A template needs neither a DTD nor external entities, and both can pull in outside content
    # XmlTextReader rather than XmlReader.Create, which would turn CRLF inside values into LF
    $xml = [System.Xml.XmlDocument]::new()
    $xml.XmlResolver = $null
    $reader = [System.Xml.XmlTextReader]::new((Convert-Path -Path $FilePath))
    $reader.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $reader.XmlResolver = $null
    try {
        $xml.Load($reader)
    } finally {
        $reader.Dispose()
    }
} else {
    Write-Host "Error: XML file not found at $FilePath" -ForegroundColor Red
    exit 1
}

#endregion Load XML

#region OS Detection

if ($SkipWarning.IsPresent -eq $false ) {
    Write-Warning "By running this script, you acknowledge that it will make changes to your system based on the definitions in the XML file. It's recommended to review the XML content and ensure you have backups or restore points as needed before proceeding. To suppress this warning in future runs, use the -SkipWarning switch."
}

$osDetails = Get-CimInstance -ClassName Win32_OperatingSystem
try {
    $machineDetails = Get-SystemPlatform
} catch {
    Write-Host "Error: $($_.Exception.Message). Cannot tell whether this is a physical or virtual machine, so nothing was applied." -ForegroundColor Red
    Write-Log -Level 'Error' -Message "Platform detection failed: $($_.Exception.Message)"
    exit 1
}
$currentBuild = $osDetails.BuildNumber
$isServer = $osDetails.ProductType -ne 1

Write-Verbose "Current OS build: $currentBuild  |  IsServer: $isServer  |  IsVirtual: $($machineDetails.IsVirtual)  |  Platform: $($machineDetails.Platform)"

$serverOSValue = if ($isServer) { 1 } else { 0 }

$xpath = "//OS[ServerOS = $serverOSValue and Builds/BuildStartsWith[starts-with('$currentBuild', .)]]"
$osNode = $xml.SelectSingleNode($xpath)

if ($null -eq $osNode) {
    Write-Warning "No matching OS found for build: $currentBuild"
    $OS = $null
    $OSName = "$($osDetails.Caption) (Build $currentBuild)"
} else {
    $OS = $osNode.Tag
    $OSName = $osNode.Name
    Write-Verbose "Matched OS: $OSName"
}

# Populate log context now that OS is known
$script:LogContext['os'] = $OSName
$script:LogContext['build'] = $currentBuild

Write-LogHeader
Write-Log -Level 'Info' -Message "Script started"

if ($script:LogFile) {
    Write-Host ''
    Write-Host "Log     : $($script:LogFile)" -ForegroundColor DarkGray
}

if ($IncludeOrder.Count -gt 0) {
    Write-Host "Include      : $($IncludeOrder -join ', ')" -ForegroundColor DarkGray
}
if ($ExcludeOrder.Count -gt 0) {
    Write-Host "Exclude      : $($ExcludeOrder -join ', ')" -ForegroundColor DarkGray
}

#endregion OS Detection

#region Execute Items

if ($null -eq $OS) {
    Write-Warning "No specific optimizations defined for: $OSName"
} else {
    $allItems = @(
        $xml.Items.Item |
            Where-Object { $_.OS.$OS.Execute -eq '1' } |
            Sort-Object -Property { [int]$_.Order }, Name
    )

    $excludedCount = 0
    $successCount = 0
    $skippedCount = 0
    $failedCount = 0

    Write-Host ''
    Write-Host "Template     : $($FilePath)" -ForegroundColor White
    Write-Host "Name         : $($xml.Items.Metadata.Name)"
    Write-Host "Version      : $($xml.Items.Metadata.Version)"
    Write-Host "OS           : $OSName (Build $currentBuild)" -ForegroundColor White
    Write-Host "Model        : $($machineDetails.Model)" -ForegroundColor White
    Write-Host "Manufacturer : $($machineDetails.Manufacturer)" -ForegroundColor White
    Write-Host "Platform     : $($machineDetails.Platform)" -ForegroundColor White
    Write-Host "Items        : $($allItems.Count)" -ForegroundColor White
    Write-Host "Logfile      : $($script:LogFile)" -ForegroundColor White
    Write-Host ''

    try {
        foreach ($item in $allItems) {
            $type = $item.Type

            # Included by order - skip items not in the include list
            if ($IncludeOrder.Count -gt 0 -and [int]$item.Order -notin $IncludeOrder) {
                $excludedCount++
                $label = if ($typeMap.ContainsKey($type)) { $typeMap[$type].DisplayName } else { $type.Substring(0, [Math]::Min($type.Length, 11)) }
                $result = New-ActionResult -Status 'Skipped' -Message "Skipped (not in IncludeOrder)"
                Write-ItemResult -TypeLabel $label -Name $item.Name -Result $result
                Write-Log -Level 'Info' -Type $type -Item $item.Name -Message "Excluded by IncludeOrder (order $($item.Order))"
                continue
            }

            # Excluded by order - show inline in sorted position
            if ($ExcludeOrder.Count -gt 0 -and [int]$item.Order -in $ExcludeOrder) {
                $excludedCount++
                $label = if ($typeMap.ContainsKey($type)) { $typeMap[$type].DisplayName } else { $type.Substring(0, [Math]::Min($type.Length, 11)) }
                $result = New-ActionResult -Status 'Skipped' -Message "Skipped (excluded order $($item.Order))"
                Write-ItemResult -TypeLabel $label -Name $item.Name -Result $result
                Write-Log -Level 'Info' -Type $type -Item $item.Name -Message "Excluded by ExcludeOrder (order $($item.Order))"
                continue
            }

            # Physical/Virtual check - absent node treated as 0
            $osItemNode = $item.OS.$OS
            if ($machineDetails.IsVirtual) {
                if ($osItemNode.Virtual -ne '1') {
                    $skippedCount++
                    $label = if ($typeMap.ContainsKey($type)) { $typeMap[$type].DisplayName } else { $type.Substring(0, [Math]::Min($type.Length, 11)) }
                    $result = New-ActionResult -Status 'Skipped' -Message 'Skipped (N/A for Virtual)'
                    Write-ItemResult -TypeLabel $label -Name $item.Name -Result $result
                    Write-Log -Level 'Info' -Type $type -Item $item.Name -Message 'Skipped (N/A for Virtual)'
                    continue
                }
            } else {
                if ($osItemNode.Physical -ne '1') {
                    $skippedCount++
                    $label = if ($typeMap.ContainsKey($type)) { $typeMap[$type].DisplayName } else { $type.Substring(0, [Math]::Min($type.Length, 11)) }
                    $result = New-ActionResult -Status 'Skipped' -Message 'Skipped (N/A for Physical)'
                    Write-ItemResult -TypeLabel $label -Name $item.Name -Result $result
                    Write-Log -Level 'Info' -Type $type -Item $item.Name -Message 'Skipped (N/A for Physical)'
                    continue
                }
            }

            # Unknown type
            if (-not $typeMap.ContainsKey($type)) {
                $failedCount++
                $result = New-ActionResult -Status 'Failed' -Message "Unknown item type '$type'"
                Write-ItemResult -TypeLabel $type.Substring(0, [Math]::Min($type.Length, 11)) -Name $item.Name -Result $result
                Write-Log -Level 'Error' -Type $type -Item $item.Name -Message "Unknown item type '$type'"
                continue
            }

            if (-not $PSCmdlet.ShouldProcess($item.Name, "$type $($item.$type.Action)".Trim())) {
                $skippedCount++
                $result = New-ActionResult -Status 'Skipped' -Message 'Skipped (WhatIf)'
                Write-ItemResult -TypeLabel $typeMap[$type].DisplayName -Name $item.Name -Result $result
                Write-Log -Level 'Info' -Type $type -Item $item.Name -Message 'Skipped (WhatIf)'
                continue
            }

            Write-Verbose "Dispatching '$($item.Name)' -> $($typeMap[$type].Function)"

            $result = & $typeMap[$type].Function -Item $item
            Write-ItemResult -TypeLabel $typeMap[$type].DisplayName -Name $item.Name -Result $result

            switch ($result.Status) {
                'Success' { $successCount++ }
                'Skipped' { $skippedCount++ }
                'Failed' { $failedCount++ }
            }
        }

        Write-Log -Level 'Info' -Message "Script completed - Success: $successCount, Skipped: $skippedCount, Failed: $failedCount, Excluded: $excludedCount, Included: $($IncludeOrder.Count), Total: $($allItems.Count)"

        # Summary
        Write-Host ''
        Write-Host "Results : " -ForegroundColor White -NoNewline
        Write-Host "$successCount succeeded" -ForegroundColor Green -NoNewline
        Write-Host "  |  " -ForegroundColor DarkGray -NoNewline
        Write-Host "$skippedCount skipped" -ForegroundColor DarkGray -NoNewline
        Write-Host "  |  " -ForegroundColor DarkGray -NoNewline
        Write-Host "$failedCount failed" -ForegroundColor $(if ($failedCount -gt 0) { 'Red' } else { 'DarkGray' })
        if ($excludedCount -gt 0) {
            Write-Host "          $excludedCount excluded by ExcludeOrder" -ForegroundColor DarkGray
        }
        if ($IncludeOrder.Count -gt 0) {
            Write-Host "          $($IncludeOrder.Count) included by IncludeOrder" -ForegroundColor DarkGray
        }
        Write-Host ''
    } finally {
        Dismount-DefaultUserHive
    }
}

# Exit only after the finally above has unmounted the hive
$exitCode = if ($null -eq $OS) { 3 } elseif ($failedCount -gt 0 -or $script:HiveUnloadFailed) { 2 } else { 0 }
Write-Log -Level 'Info' -Message "Exit code $exitCode"
exit $exitCode

# SIG # Begin signature block
# MII6AgYJKoZIhvcNAQcCoII58zCCOe8CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAnqv+IXBr23d1W
# X+NOTgmv5OqtXC9rEZoxKicKeeY1BKCCIiYwggXMMIIDtKADAgECAhBUmNLR1FsZ
# lUgTecgRwIeZMA0GCSqGSIb3DQEBDAUAMHcxCzAJBgNVBAYTAlVTMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xSDBGBgNVBAMTP01pY3Jvc29mdCBJZGVu
# dGl0eSBWZXJpZmljYXRpb24gUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAy
# MDAeFw0yMDA0MTYxODM2MTZaFw00NTA0MTYxODQ0NDBaMHcxCzAJBgNVBAYTAlVT
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xSDBGBgNVBAMTP01pY3Jv
# c29mdCBJZGVudGl0eSBWZXJpZmljYXRpb24gUm9vdCBDZXJ0aWZpY2F0ZSBBdXRo
# b3JpdHkgMjAyMDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBALORKgeD
# Bmf9np3gx8C3pOZCBH8Ppttf+9Va10Wg+3cL8IDzpm1aTXlT2KCGhFdFIMeiVPvH
# or+Kx24186IVxC9O40qFlkkN/76Z2BT2vCcH7kKbK/ULkgbk/WkTZaiRcvKYhOuD
# PQ7k13ESSCHLDe32R0m3m/nJxxe2hE//uKya13NnSYXjhr03QNAlhtTetcJtYmrV
# qXi8LW9J+eVsFBT9FMfTZRY33stuvF4pjf1imxUs1gXmuYkyM6Nix9fWUmcIxC70
# ViueC4fM7Ke0pqrrBc0ZV6U6CwQnHJFnni1iLS8evtrAIMsEGcoz+4m+mOJyoHI1
# vnnhnINv5G0Xb5DzPQCGdTiO0OBJmrvb0/gwytVXiGhNctO/bX9x2P29Da6SZEi3
# W295JrXNm5UhhNHvDzI9e1eM80UHTHzgXhgONXaLbZ7LNnSrBfjgc10yVpRnlyUK
# xjU9lJfnwUSLgP3B+PR0GeUw9gb7IVc+BhyLaxWGJ0l7gpPKWeh1R+g/OPTHU3mg
# trTiXFHvvV84wRPmeAyVWi7FQFkozA8kwOy6CXcjmTimthzax7ogttc32H83rwjj
# O3HbbnMbfZlysOSGM1l0tRYAe1BtxoYT2v3EOYI9JACaYNq6lMAFUSw0rFCZE4e7
# swWAsk0wAly4JoNdtGNz764jlU9gKL431VulAgMBAAGjVDBSMA4GA1UdDwEB/wQE
# AwIBhjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBTIftJqhSobyhmYBAcnz1AQ
# T2ioojAQBgkrBgEEAYI3FQEEAwIBADANBgkqhkiG9w0BAQwFAAOCAgEAr2rd5hnn
# LZRDGU7L6VCVZKUDkQKL4jaAOxWiUsIWGbZqWl10QzD0m/9gdAmxIR6QFm3FJI9c
# Zohj9E/MffISTEAQiwGf2qnIrvKVG8+dBetJPnSgaFvlVixlHIJ+U9pW2UYXeZJF
# xBA2CFIpF8svpvJ+1Gkkih6PsHMNzBxKq7Kq7aeRYwFkIqgyuH4yKLNncy2RtNwx
# AQv3Rwqm8ddK7VZgxCwIo3tAsLx0J1KH1r6I3TeKiW5niB31yV2g/rarOoDXGpc8
# FzYiQR6sTdWD5jw4vU8w6VSp07YEwzJ2YbuwGMUrGLPAgNW3lbBeUU0i/OxYqujY
# lLSlLu2S3ucYfCFX3VVj979tzR/SpncocMfiWzpbCNJbTsgAlrPhgzavhgplXHT2
# 6ux6anSg8Evu75SjrFDyh+3XOjCDyft9V77l4/hByuVkrrOj7FjshZrM77nq81YY
# uVxzmq/FdxeDWds3GhhyVKVB0rYjdaNDmuV3fJZ5t0GNv+zcgKCf0Xd1WF81E+Al
# GmcLfc4l+gcK5GEh2NQc5QfGNpn0ltDGFf5Ozdeui53bFv0ExpK91IjmqaOqu/dk
# ODtfzAzQNb50GQOmxapMomE2gj4d8yu8l13bS3g7LfU772Aj6PXsCyM2la+YZr9T
# 03u4aUoqlmZpxJTG9F9urJh4iIAGXKKy7aIwggbAMIIEqKADAgECAhMzAAodowCw
# ZKca+kIUAAAACh2jMA0GCSqGSIb3DQEBDAUAMFoxCzAJBgNVBAYTAlVTMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKzApBgNVBAMTIk1pY3Jvc29mdCBJ
# RCBWZXJpZmllZCBDUyBFT0MgQ0EgMDQwHhcNMjYxMTE0MDE0MzI5WhcNMjYxMTE3
# MDE0MzI5WjCBgzELMAkGA1UEBhMCTkwxFjAUBgNVBAgTDU5vb3JkLUJyYWJhbnQx
# EjAQBgNVBAcTCVNjaGlqbmRlbDEjMCEGA1UEChMaSm9obiBCaWxsZWtlbnMgQ29u
# c3VsdGFuY3kxIzAhBgNVBAMTGkpvaG4gQmlsbGVrZW5zIENvbnN1bHRhbmN5MIIB
# ojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAjRnPAM1HGRP8RkFjl8tNLv0x
# cyLNOGRhuQ2YoXCTooma6WC8caZo9eOvEaO6xUjlQH+nZb5DC1/nACRk0bPdWcbK
# MmaGAQD6qLzVl/ttwffV6i3l3ZVT3JNRcMHmc6+H5N0fjvFWiJC7iIBIsEr1v04+
# FZS5k0ZVkxaqdPgsDvKxhH/AGoupTNGqMjXs9t4dwXWa6SMaQropzksYMpeYP/+j
# We7Ah3+6AwZQjm9kQ/LjzBJhIs138tVQpjQ4bBPRE1kBnp4vFUKvU5oGBaA5I+iI
# RdJOEo8ttzFy6bWWR+aLKGCN/njSuMqrCnXB9eRfMCm+kgnyf7H//IzduXRTpM2j
# uEtWZsoT1foV3/aj2+IJHiFcwfFdp11iB8pAmOzwg76fOECZpfLoFOyybZaBXLWs
# ng/7upkf2OsIpkfng2qaxPo7aj+Ro5XzvxGophuvJ8835BLh3QfWbvFXr2AWtTJV
# icAwgjcnjSUa4wEZepeOknfS/7ymh/pfJ5/HcdbxAgMBAAGjggHTMIIBzzAMBgNV
# HRMBAf8EAjAAMA4GA1UdDwEB/wQEAwIHgDA6BgNVHSUEMzAxBgorBgEEAYI3YQEA
# BggrBgEFBQcDAwYZKwYBBAGCN2HK9PELgrHSgxH33KNOluu6MTAdBgNVHQ4EFgQU
# lDlLuBZhlAF0s1R0rpcjZip3jMYwHwYDVR0jBBgwFoAUmvFUd3UMhxY3RqCs3nn5
# 9H/BeOkwZwYDVR0fBGAwXjBcoFqgWIZWaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraW9wcy9jcmwvTWljcm9zb2Z0JTIwSUQlMjBWZXJpZmllZCUyMENTJTIwRU9D
# JTIwQ0ElMjAwNC5jcmwwdAYIKwYBBQUHAQEEaDBmMGQGCCsGAQUFBzAChlhodHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMElE
# JTIwVmVyaWZpZWQlMjBDUyUyMEVPQyUyMENBJTIwMDQuY3J0MFQGA1UdIARNMEsw
# SQYEVR0gADBBMD8GCCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20v
# cGtpb3BzL0RvY3MvUmVwb3NpdG9yeS5odG0wDQYJKoZIhvcNAQEMBQADggIBACTh
# 0JmWfriAlx28CwSOx0kd+LbEXq6pj2cITCzL4H4NXvohJnyVpmNddoiU5+eHazAs
# WFjqmt/NFqBmZbrOwOxnx754XZ0wACqCw40wAVDqC2ykkBZH2OZ0mQv0i7cOWg5t
# gnKlc9NYz2jRZfc5jpbg0u18cjwJ9pqyisSMfjtVJvAG+cOVJIuHSDU8YRz9oj6N
# eKDfB78PfB1oBdJD9RcSgBQxxaYiBO/Qhs1AGP/xZYfWrBV7aYBI09DCM86kvA9z
# BqV+LDv7tmIooaquJylQzZqmiFZKkZrVo0qSMAqUAyDO+EBGXvZ/FqMACHHHzbVR
# hWJO/Tjm3K7iClZuJBFKdp88e7BfIXeHSf1zcb9KhRf96oGV7Sema5uYcQlOdtAf
# IDVYtvDMDncZUVC/eAbD56XZyio0gZ5vMh1uVDLeh2Zu9IS8owY7Cd3p3kko+M90
# RPH6UExvdVa4KHfsmb63awBxoVFDxAnfK1CPrYovC13SqXsfQneQrOabU3i4WmiQ
# uvKnL2522vbjaBx+tz7HyKbny8V6ECvX7m1ecyrUOiaqjlb13nUiALsZvkAF9Te6
# duD3GwdPQ0THR3QtO+yAZtnBgG08NxSIJ7wxy0Kgoee2dmvjtBYwr8NsFItt76Q0
# HexACe46I+E/hU/xKURVojo4x6wlLqxG4fidcS9HMIIGwDCCBKigAwIBAgITMwAK
# HaMAsGSnGvpCFAAAAAodozANBgkqhkiG9w0BAQwFADBaMQswCQYDVQQGEwJVUzEe
# MBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSswKQYDVQQDEyJNaWNyb3Nv
# ZnQgSUQgVmVyaWZpZWQgQ1MgRU9DIENBIDA0MB4XDTI2MTExNDAxNDMyOVoXDTI2
# MTExNzAxNDMyOVowgYMxCzAJBgNVBAYTAk5MMRYwFAYDVQQIEw1Ob29yZC1CcmFi
# YW50MRIwEAYDVQQHEwlTY2hpam5kZWwxIzAhBgNVBAoTGkpvaG4gQmlsbGVrZW5z
# IENvbnN1bHRhbmN5MSMwIQYDVQQDExpKb2huIEJpbGxla2VucyBDb25zdWx0YW5j
# eTCCAaIwDQYJKoZIhvcNAQEBBQADggGPADCCAYoCggGBAI0ZzwDNRxkT/EZBY5fL
# TS79MXMizThkYbkNmKFwk6KJmulgvHGmaPXjrxGjusVI5UB/p2W+Qwtf5wAkZNGz
# 3VnGyjJmhgEA+qi81Zf7bcH31eot5d2VU9yTUXDB5nOvh+TdH47xVoiQu4iASLBK
# 9b9OPhWUuZNGVZMWqnT4LA7ysYR/wBqLqUzRqjI17PbeHcF1mukjGkK6Kc5LGDKX
# mD//o1nuwId/ugMGUI5vZEPy48wSYSLNd/LVUKY0OGwT0RNZAZ6eLxVCr1OaBgWg
# OSPoiEXSThKPLbcxcum1lkfmiyhgjf540rjKqwp1wfXkXzApvpIJ8n+x//yM3bl0
# U6TNo7hLVmbKE9X6Fd/2o9viCR4hXMHxXaddYgfKQJjs8IO+nzhAmaXy6BTssm2W
# gVy1rJ4P+7qZH9jrCKZH54NqmsT6O2o/kaOV878RqKYbryfPN+QS4d0H1m7xV69g
# FrUyVYnAMII3J40lGuMBGXqXjpJ30v+8pof6Xyefx3HW8QIDAQABo4IB0zCCAc8w
# DAYDVR0TAQH/BAIwADAOBgNVHQ8BAf8EBAMCB4AwOgYDVR0lBDMwMQYKKwYBBAGC
# N2EBAAYIKwYBBQUHAwMGGSsGAQQBgjdhyvTxC4Kx0oMR99yjTpbrujEwHQYDVR0O
# BBYEFJQ5S7gWYZQBdLNUdK6XI2Yqd4zGMB8GA1UdIwQYMBaAFJrxVHd1DIcWN0ag
# rN55+fR/wXjpMGcGA1UdHwRgMF4wXKBaoFiGVmh0dHA6Ly93d3cubWljcm9zb2Z0
# LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMElEJTIwVmVyaWZpZWQlMjBDUyUy
# MEVPQyUyMENBJTIwMDQuY3JsMHQGCCsGAQUFBwEBBGgwZjBkBggrBgEFBQcwAoZY
# aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQl
# MjBJRCUyMFZlcmlmaWVkJTIwQ1MlMjBFT0MlMjBDQSUyMDA0LmNydDBUBgNVHSAE
# TTBLMEkGBFUdIAAwQTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQu
# Y29tL3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRtMA0GCSqGSIb3DQEBDAUAA4IC
# AQAk4dCZln64gJcdvAsEjsdJHfi2xF6uqY9nCEwsy+B+DV76ISZ8laZjXXaIlOfn
# h2swLFhY6prfzRagZmW6zsDsZ8e+eF2dMAAqgsONMAFQ6gtspJAWR9jmdJkL9Iu3
# DloObYJypXPTWM9o0WX3OY6W4NLtfHI8CfaasorEjH47VSbwBvnDlSSLh0g1PGEc
# /aI+jXig3we/D3wdaAXSQ/UXEoAUMcWmIgTv0IbNQBj/8WWH1qwVe2mASNPQwjPO
# pLwPcwalfiw7+7ZiKKGqricpUM2apohWSpGa1aNKkjAKlAMgzvhARl72fxajAAhx
# x821UYViTv045tyu4gpWbiQRSnafPHuwXyF3h0n9c3G/SoUX/eqBle0npmubmHEJ
# TnbQHyA1WLbwzA53GVFQv3gGw+el2coqNIGebzIdblQy3odmbvSEvKMGOwnd6d5J
# KPjPdETx+lBMb3VWuCh37Jm+t2sAcaFRQ8QJ3ytQj62KLwtd0ql7H0J3kKzmm1N4
# uFpokLrypy9udtr242gcfrc+x8im58vFehAr1+5tXnMq1Domqo5W9d51IgC7Gb5A
# BfU3unbg9xsHT0NEx0d0LTvsgGbZwYBtPDcUiCe8MctCoKHntnZr47QWMK/DbBSL
# be+kNB3sQAnuOiPhP4VP8SlEVaI6OMesJS6sRuH4nXEvRzCCBygwggUQoAMCAQIC
# EzMAAAAXJ0UJC4uHr8YAAAAAABcwDQYJKoZIhvcNAQEMBQAwYzELMAkGA1UEBhMC
# VVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjE0MDIGA1UEAxMrTWlj
# cm9zb2Z0IElEIFZlcmlmaWVkIENvZGUgU2lnbmluZyBQQ0EgMjAyMTAeFw0yNjAz
# MjYxODExMzFaFw0zMTAzMjYxODExMzFaMFoxCzAJBgNVBAYTAlVTMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKzApBgNVBAMTIk1pY3Jvc29mdCBJRCBW
# ZXJpZmllZCBDUyBFT0MgQ0EgMDQwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIK
# AoICAQCCx2T+Aw9mKgGVzJ+Tq0PMn49G3itIsYpbx7ClLSRHFe1RELdPcZ1sIqWO
# hsSfy6yyqEapClGH9Je9FXA1cQgZvvpQbkg+QInVLr/0EPrVBCwrM96lbRI2PxNe
# CwXG9LsyW2hG6KQgintDmNCBo4zpDIr377plVdSliZm6UB7rHwmvBnR02QT6tnrq
# Wq2ihzB6lRJVTEzuh0OafzIMeMnYM0+x+ve5EOLHdfiq+HXiMf9Jb7YLHtYgyHIi
# JA7bTWLqFSLGaTh7ZlbxbsLXA91OOroEpv7OjzFuu3tkpC9FflA4Dp2Euq4+qPmx
# UqfGp+TX0gLRJp9NJOzzILjcTD3rkFFFbxUv1xyg6avivFDLtoKBhM2Td138umE1
# pNOacanuSYtPHIeQHmB6haFi64avLBLwTTAm/Rbit860cFXR72wq+5Qh4hSmezHq
# KXERWPpVBe+APrJ4Iqc+aPeMmIkoCWZQO22HnLNFUFSXjiwyIbgvlH/LIAJEqTaf
# TzxDZgKhlLU7zr6gwsq3WNpcYQI6NuxWnwh3VVDDyF7onQqKs5Ll7bleVN0Y8Vvq
# gE45ppyBbvwqN/Run5fMCCRz3aYMY0kZhKO92eP7t4zHqZ5bQMAgZ0tE2Pz/jb0w
# iykUF/PcoOqqk3vVLiRDYst6vd3GEMNzMpUUvQcvBG46+COIbwIDAQABo4IB3DCC
# AdgwDgYDVR0PAQH/BAQDAgGGMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBSa
# 8VR3dQyHFjdGoKzeefn0f8F46TBUBgNVHSAETTBLMEkGBFUdIAAwQTA/BggrBgEF
# BQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9z
# aXRvcnkuaHRtMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMBIGA1UdEwEB/wQI
# MAYBAf8CAQAwHwYDVR0jBBgwFoAU2UEpsA8PY2zvadf1zSmepEhqMOYwcAYDVR0f
# BGkwZzBloGOgYYZfaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwv
# TWljcm9zb2Z0JTIwSUQlMjBWZXJpZmllZCUyMENvZGUlMjBTaWduaW5nJTIwUENB
# JTIwMjAyMS5jcmwwfQYIKwYBBQUHAQEEcTBvMG0GCCsGAQUFBzAChmFodHRwOi8v
# d3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMElEJTIw
# VmVyaWZpZWQlMjBDb2RlJTIwU2lnbmluZyUyMFBDQSUyMDIwMjEuY3J0MA0GCSqG
# SIb3DQEBDAUAA4ICAQCQdVoZ/U0m38l2iKaZFlsxavptpoOLyaR1a9ZK2TSF1kOn
# FJhMDse6KkCgsveoiEjXTVc6Xt86IKHn76Nk5qZB0BXv2iMRQ2giAJmYvZcmstoZ
# qfB2M3Kd5wnJhUJOtF/b6HsqSelY6nhrF06zor1lDmDQixBZcLB9zR1+RKQso1je
# kNxYuUk+HaN3k1S57qk0O//YbkwU0mELCW04N5vICMZx5T5c7Nq/7uLvbVhCdD7f
# 2bZpA4U7vOkB1ooB4AaER3pjoJ0Mad5LFyi6Na9p9Zu/hrLeOjU5FItS5Yxsqvlf
# XxAThJ176CmkYstKRmytSHZ7JhKRfV6e9Zftk/ODb/CK4pGVAVqsOf4337bQGrOH
# HCQ3IvN9gmnUuDh8JdvbheoWPHxIN1GB5sUiY584tXN7xdD8LCSsRqJvQ8e7a3gZ
# WTgViugRs1QWq+N0G9Nje6JHlN1CjJehge+H5PGktJja+juGEr0P+ukSkcL6qaZx
# FQTh3SDI71lvW++3bl/Ezd6SO8N9Udw+reoyvRHCyTiSsplZQSBTVJdPmo3qCpGu
# yHFtPo5CBn3/FPTiqJd3M9BHoqKd0G9Kmg6fGcAvFwnLNXA2kov727wRljL3ypfq
# L7iAT/Ynpxul6RwHRlcOf9dDGg1RRvr92NP/CWVXIb68geR2rvU/NsfmtjF1wDCC
# B54wggWGoAMCAQICEzMAAAAHh6M0o3uljhwAAAAAAAcwDQYJKoZIhvcNAQEMBQAw
# dzELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjFI
# MEYGA1UEAxM/TWljcm9zb2Z0IElkZW50aXR5IFZlcmlmaWNhdGlvbiBSb290IENl
# cnRpZmljYXRlIEF1dGhvcml0eSAyMDIwMB4XDTIxMDQwMTIwMDUyMFoXDTM2MDQw
# MTIwMTUyMFowYzELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjE0MDIGA1UEAxMrTWljcm9zb2Z0IElEIFZlcmlmaWVkIENvZGUgU2ln
# bmluZyBQQ0EgMjAyMTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBALLw
# wK8ZiCji3VR6TElsaQhVCbRS/3pK+MHrJSj3Zxd3KU3rlfL3qrZilYKJNqztA9OQ
# acr1AwoNcHbKBLbsQAhBnIB34zxf52bDpIO3NJlfIaTE/xrweLoQ71lzCHkD7A4A
# s1Bs076Iu+mA6cQzsYYH/Cbl1icwQ6C65rU4V9NQhNUwgrx9rGQ//h890Q8JdjLL
# w0nV+ayQ2Fbkd242o9kH82RZsH3HEyqjAB5a8+Ae2nPIPc8sZU6ZE7iRrRZywRmr
# KDp5+TcmJX9MRff241UaOBs4NmHOyke8oU1TYrkxh+YeHgfWo5tTgkoSMoayqoDp
# HOLJs+qG8Tvh8SnifW2Jj3+ii11TS8/FGngEaNAWrbyfNrC69oKpRQXY9bGH6jn9
# NEJv9weFxhTwyvx9OJLXmRGbAUXN1U9nf4lXezky6Uh/cgjkVd6CGUAf0K+Jw+GE
# /5VpIVbcNr9rNE50Sbmy/4RTCEGvOq3GhjITbCa4crCzTTHgYYjHs1NbOc6brH+e
# KpWLtr+bGecy9CrwQyx7S/BfYJ+ozst7+yZtG2wR461uckFu0t+gCwLdN0A6cFtS
# RtR8bvxVFyWwTtgMMFRuBa3vmUOTnfKLsLefRaQcVTgRnzeLzdpt32cdYKp+dhr2
# ogc+qM6K4CBI5/j4VFyC4QFeUP2YAidLtvpXRRo3AgMBAAGjggI1MIICMTAOBgNV
# HQ8BAf8EBAMCAYYwEAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYEFNlBKbAPD2Ns
# 72nX9c0pnqRIajDmMFQGA1UdIARNMEswSQYEVR0gADBBMD8GCCsGAQUFBwIBFjNo
# dHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL0RvY3MvUmVwb3NpdG9yeS5o
# dG0wGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwDwYDVR0TAQH/BAUwAwEB/zAf
# BgNVHSMEGDAWgBTIftJqhSobyhmYBAcnz1AQT2ioojCBhAYDVR0fBH0wezB5oHeg
# dYZzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwvTWljcm9zb2Z0
# JTIwSWRlbnRpdHklMjBWZXJpZmljYXRpb24lMjBSb290JTIwQ2VydGlmaWNhdGUl
# MjBBdXRob3JpdHklMjAyMDIwLmNybDCBwwYIKwYBBQUHAQEEgbYwgbMwgYEGCCsG
# AQUFBzAChnVodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01p
# Y3Jvc29mdCUyMElkZW50aXR5JTIwVmVyaWZpY2F0aW9uJTIwUm9vdCUyMENlcnRp
# ZmljYXRlJTIwQXV0aG9yaXR5JTIwMjAyMC5jcnQwLQYIKwYBBQUHMAGGIWh0dHA6
# Ly9vbmVvY3NwLm1pY3Jvc29mdC5jb20vb2NzcDANBgkqhkiG9w0BAQwFAAOCAgEA
# fyUqnv7Uq+rdZgrbVyNMul5skONbhls5fccPlmIbzi+OwVdPQ4H55v7VOInnmezQ
# EeW4LqK0wja+fBznANbXLB0KrdMCbHQpbLvG6UA/Xv2pfpVIE1CRFfNF4XKO8XYE
# a3oW8oVH+KZHgIQRIwAbyFKQ9iyj4aOWeAzwk+f9E5StNp5T8FG7/VEURIVWArbA
# zPt9ThVN3w1fAZkF7+YU9kbq1bCR2YD+MtunSQ1Rft6XG7b4e0ejRA7mB2IoX5hN
# h3UEauY0byxNRG+fT2MCEhQl9g2i2fs6VOG19CNep7SquKaBjhWmirYyANb0RJSL
# WjinMLXNOAga10n8i9jqeprzSMU5ODmrMCJE12xS/NWShg/tuLjAsKP6SzYZ+1Ry
# 358ZTFcx0FS/mx2vSoU8s8HRvy+rnXqyUJ9HBqS0DErVLjQwK8VtsBdekBmdTbQV
# oCgPCqr+PDPB3xajYnzevs7eidBsM71PINK2BoE2UfMwxCCX3mccFgx6UsQeRSdV
# VVNSyALQe6PT12418xon2iDGE81OGCreLzDcMAZnrUAx4XQLUz6ZTl65yPUiOh3k
# 7Yww94lDf+8oG2oZmDh5O1Qe38E+M3vhKwmzIeoB1dVLlz4i3IpaDcR+iuGjH2Td
# aC1ZOmBXiCRKJLj4DT2uhJ04ji+tHD6n58vhavFIrmcxghcyMIIXLgIBATBxMFox
# CzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKzAp
# BgNVBAMTIk1pY3Jvc29mdCBJRCBWZXJpZmllZCBDUyBFT0MgQ0EgMDQCEzMACh2j
# ALBkpxr6QhQAAAAKHaMwDQYJYIZIAWUDBAIBBQCgXjAQBgorBgEEAYI3AgEMMQIw
# ADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAvBgkqhkiG9w0BCQQxIgQgufbD
# bR+3sMl81DPT898g+BqMWQE3s78MqtmtabMTYhcwDQYJKoZIhvcNAQEBBQAEggGA
# h4iSRHmCGfzEzFukT/5ToYrMGbMXNs74XJF+TAKkecevWZWEn4JkVJRctFr7YR3G
# m8zEJu+36VaxErOe2bq+F5Z+gB9UHfQpW381N+JUq+sX3fAu8tOzKomGIRBng7ne
# HUUhEgMtP2e/qY62vYvYdhPoO+7jnstCSvNayEoILEHQrXRj7J94yGHWjxjf5uPD
# GtzFIbye1ZF4yRkFobs7crqd/Iq3xiVCeMrXxg74j2u9H8LemOEiNQJ1O8Vf41hm
# YKnr0bP0VMicoXm+4Vl+YcZPxlrRXklpxPLCIfvCiyY5LvjJSH6PrmfWnNXkbdiK
# yn5B3cUiaV07OFiOC6z7bO+mDlIW63tq2H3q+xnNupVfMwmR4k/e6eAqr+WxubUv
# EcaDfXviheAm9O8uyTe7bzuqqmyLA73XM9b3UUdREEZoQi3yDS2KNEj4vlBD7xMb
# 3nF66mYrJcG3H9swn5UP3D+3OL9lcqdMh4dzlmbKzFZALSBEOi86vegJ9E/okKZP
# oYIUsjCCFK4GCisGAQQBgjcDAwExghSeMIIUmgYJKoZIhvcNAQcCoIIUizCCFIcC
# AQMxDzANBglghkgBZQMEAgEFADCCAWoGCyqGSIb3DQEJEAEEoIIBWQSCAVUwggFR
# AgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUDBAIBBQAEIJ28D5vr4L3Nkn/rj+3j
# hMf1+U/wFgOdQhlzytz6sWpbAgZq80sCG9UYEzIwMjYxMTE1MTUwMDU2Ljk0NVow
# BIACAfSggemkgeYwgeMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRl
# ZDEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjdCMUEtMDVFMC1EOTQ3MTUwMwYD
# VQQDEyxNaWNyb3NvZnQgUHVibGljIFJTQSBUaW1lIFN0YW1waW5nIEF1dGhvcml0
# eaCCDykwggeCMIIFaqADAgECAhMzAAAABeXPD/9mLsmHAAAAAAAFMA0GCSqGSIb3
# DQEBDAUAMHcxCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9y
# YXRpb24xSDBGBgNVBAMTP01pY3Jvc29mdCBJZGVudGl0eSBWZXJpZmljYXRpb24g
# Um9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAyMDAeFw0yMDExMTkyMDMyMzFa
# Fw0zNTExMTkyMDQyMzFaMGExCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBQdWJsaWMgUlNBIFRp
# bWVzdGFtcGluZyBDQSAyMDIwMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKC
# AgEAnnznUmP94MWfBX1jtQYioxwe1+eXM9ETBb1lRkd3kcFdcG9/sqtDlwxKoVIc
# aqDb+omFio5DHC4RBcbyQHjXCwMk/l3TOYtgoBjxnG/eViS4sOx8y4gSq8Zg49RE
# Af5huXhIkQRKe3Qxs8Sgp02KHAznEa/Ssah8nWo5hJM1xznkRsFPu6rfDHeZeG1W
# a1wISvlkpOQooTULFm809Z0ZYlQ8Lp7i5F9YciFlyAKwn6yjN/kR4fkquUWfGmMo
# pNq/B8U/pdoZkZZQbxNlqJOiBGgCWpx69uKqKhTPVi3gVErnc/qi+dR8A2MiAz0k
# N0nh7SqINGbmw5OIRC0EsZ31WF3Uxp3GgZwetEKxLms73KG/Z+MkeuaVDQQheang
# OEMGJ4pQZH55ngI0Tdy1bi69INBV5Kn2HVJo9XxRYR/JPGAaM6xGl57Ei95HUw9N
# V/uC3yFjrhc087qLJQawSC3xzY/EXzsT4I7sDbxOmM2rl4uKK6eEpurRduOQ2hTk
# mG1hSuWYBunFGNv21Kt4N20AKmbeuSnGnsBCd2cjRKG79+TX+sTehawOoxfeOO/j
# R7wo3liwkGdzPJYHgnJ54UxbckF914AqHOiEV7xTnD1a69w/UTxwjEugpIPMIIE6
# 7SFZ2PMo27xjlLAHWW3l1CEAFjLNHd3EQ79PUr8FUXetXr0CAwEAAaOCAhswggIX
# MA4GA1UdDwEB/wQEAwIBhjAQBgkrBgEEAYI3FQEEAwIBADAdBgNVHQ4EFgQUa2ko
# OjUvSGNAz3vYr0npPtk92yEwVAYDVR0gBE0wSzBJBgRVHSAAMEEwPwYIKwYBBQUH
# AgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0
# b3J5Lmh0bTATBgNVHSUEDDAKBggrBgEFBQcDCDAZBgkrBgEEAYI3FAIEDB4KAFMA
# dQBiAEMAQTAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFMh+0mqFKhvKGZgE
# ByfPUBBPaKiiMIGEBgNVHR8EfTB7MHmgd6B1hnNodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBJZGVudGl0eSUyMFZlcmlmaWNh
# dGlvbiUyMFJvb3QlMjBDZXJ0aWZpY2F0ZSUyMEF1dGhvcml0eSUyMDIwMjAuY3Js
# MIGUBggrBgEFBQcBAQSBhzCBhDCBgQYIKwYBBQUHMAKGdWh0dHA6Ly93d3cubWlj
# cm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwSWRlbnRpdHklMjBW
# ZXJpZmljYXRpb24lMjBSb290JTIwQ2VydGlmaWNhdGUlMjBBdXRob3JpdHklMjAy
# MDIwLmNydDANBgkqhkiG9w0BAQwFAAOCAgEAX4h2x35ttVoVdedMeGj6TuHYRJkl
# FaW4sTQ5r+k77iB79cSLNe+GzRjv4pVjJviceW6AF6ycWoEYR0LYhaa0ozJLU5Yi
# +LCmcrdovkl53DNt4EXs87KDogYb9eGEndSpZ5ZM74LNvVzY0/nPISHz0Xva71Qj
# D4h+8z2XMOZzY7YQ0Psw+etyNZ1CesufU211rLslLKsO8F2aBs2cIo1k+aHOhrw9
# xw6JCWONNboZ497mwYW5EfN0W3zL5s3ad4Xtm7yFM7Ujrhc0aqy3xL7D5FR2J7x9
# cLWMq7eb0oYioXhqV2tgFqbKHeDick+P8tHYIFovIP7YG4ZkJWag1H91KlELGWi3
# SLv10o4KGag42pswjybTi4toQcC/irAodDW8HNtX+cbz0sMptFJK+KObAnDFHEsu
# kxD+7jFfEV9Hh/+CSxKRsmnuiovCWIOb+H7DRon9TlxydiFhvu88o0w35JkNbJxT
# k4MhF/KgaXn0GxdH8elEa2Imq45gaa8D+mTm8LWVydt4ytxYP/bqjN49D9NZ81co
# E6aQWm88TwIf4R4YZbOpMKN0CyejaPNN41LGXHeCUMYmBx3PkP8ADHD1J2Cr/6tj
# uOOCztfp+o9Nc+ZoIAkpUcA/X2gSMkgHAPUvIdtoSAHEUKiBhI6JQivRepyvWcl+
# JYbYbBh7pmgAXVswggefMIIFh6ADAgECAhMzAAAAWXzacemNXvXAAAAAAABZMA0G
# CSqGSIb3DQEBDAUAMGExCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBQdWJsaWMgUlNBIFRpbWVz
# dGFtcGluZyBDQSAyMDIwMB4XDTI2MDEwODE4NTkwMVoXDTI3MDEwNzE4NTkwMVow
# geMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsT
# JE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMe
# blNoaWVsZCBUU1MgRVNOOjdCMUEtMDVFMC1EOTQ3MTUwMwYDVQQDEyxNaWNyb3Nv
# ZnQgUHVibGljIFJTQSBUaW1lIFN0YW1waW5nIEF1dGhvcml0eTCCAiIwDQYJKoZI
# hvcNAQEBBQADggIPADCCAgoCggIBAKYu5/40eEX+hT+5jFa146bid3dA4LnXYntv
# kP3CGw4LGARFhnvLMSJ/VtsubzDaeFnm7yb2KSM70WmHQprdCVqpvUH7l0uB4jNw
# 7urLoAR9kKHLE0VlMlDStDSxUBI3qwsdrjvdmvV0k+9/njuDEiSlzJTf7Dowd1K3
# bO4beRyaFhR+Y8tymECOqlOAffYrG2wZdVM51+QSBSe+PEykr8C6OnnqSipuF8fZ
# vCb6/huk0Zm6ZwsaixSHIAT2IEGvS7c63Im8jV3a8R0K6i2yiw0NNlnTSpwy/Zfv
# 7iwsLBwhfbjBTn+XOl6mPzDXQQ3V+SRP9xXbGKOsBTxzGid7aKAHw3o4Ahl9UGWL
# H9kNP3VUokE6JYkjlfpuUGZ6gQyqDewfxD4VoYIlopt4HZ0xQvqajuJx+cr8LR/I
# Z56gLLmwyMzde5+vtjBoilry/gSZwVGwgkvkIgpKPBQHGsSB0y3szr7Y7wEb6v0y
# Zal1XUvWnnz3inTaSWsCFrLPVwVmXy3ncY5/d25VpOkht+m697GWNbvsNOhAOHRa
# ftE9j/hhkoM6RsyJfBLnhqMcA/wcavf5oj5NeyRQdGZeLKcls9csKS3sBUzPidxx
# 2iiNH9CPaDq/bLJEOXasYohXMnRinu+fUk81s8VO7DQSF6ffn5oqSHoV8lf1Ax6u
# +kdShb8BAgMBAAGjggHLMIIBxzAdBgNVHQ4EFgQUj5bnC18D0vlnSRhCOiODGGuX
# NnYwHwYDVR0jBBgwFoAUa2koOjUvSGNAz3vYr0npPtk92yEwbAYDVR0fBGUwYzBh
# oF+gXYZbaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwvTWljcm9z
# b2Z0JTIwUHVibGljJTIwUlNBJTIwVGltZXN0YW1waW5nJTIwQ0ElMjAyMDIwLmNy
# bDB5BggrBgEFBQcBAQRtMGswaQYIKwYBBQUHMAKGXWh0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwUHVibGljJTIwUlNBJTIw
# VGltZXN0YW1waW5nJTIwQ0ElMjAyMDIwLmNydDAMBgNVHRMBAf8EAjAAMBYGA1Ud
# JQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDBmBgNVHSAEXzBdMFEG
# DCsGAQQBgjdMg30BATBBMD8GCCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20vcGtpb3BzL0RvY3MvUmVwb3NpdG9yeS5odG0wCAYGZ4EMAQQCMA0GCSqG
# SIb3DQEBDAUAA4ICAQBEMhzC/ZcjpG/zURE7z2Yp5vrUxUjsE5Xa3t/2RGvESwvb
# msk3bLHhSFAajgo2XQ8xoGDP3sUhKCLPeICSbkVv6V8sSp8fJ8Jos6yrawf2YVis
# 8tcV+OO7U9S6JGPQzpmPncfzQc4ne1fqZ4+HiKabIDEoFdddQT2Egkk9fzxCY/EZ
# 52avJ27dSfrI/IDmyn9V10O3iQpg2F+C9vNTrk7nVgoDoHa9+Q3pYr0IHGnSmt5i
# rgGT436zo5WnXP8FxMhswH1aiyiSZiVzhor10C9C52cP3C8/PEoMKUXstLjoPO0T
# MkeW/1Fr186KXD45QRgBo0xImgtWTdzWFnlD+p7+iDBIuSrNcRXDRYuq/aYZaDhW
# SI0SYdPIWVh5XvXuWA31a8oQ0SO+oPa3Nk80k0864wiiyJ1KsbSnaaefg9vspegh
# rpY8ljCwxfCUtx5HQRNgAJOI8IKACK4d014Mk0hlRO0lQVRHegqIg29K6Xqkc360
# W2ZJGUcstlKokkVj6KAHjGyrLRPzepYfiZUJq4gXyxbpvKb1XJ2FN2682aUoNXo9
# RyRK1ch0f66k6+yj88kzvuC7+vJWtNDs/UpIM6Hhm0kU64JUJ7MMEQcAc7kpft7G
# m7YeRK+oKgqUgYXCfmzbX8nJXJZnPa8ADWVsIqsuNAxCI0CZXkULofqo5Be6zzGC
# A9QwggPQAgEBMHgwYTELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFB1YmxpYyBSU0EgVGltZXN0
# YW1waW5nIENBIDIwMjACEzMAAABZfNpx6Y1e9cAAAAAAAFkwDQYJYIZIAWUDBAIB
# BQCgggEtMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQx
# IgQg9B+IQZ8eQWwJUuaEDQQ2bNqfzLE7gRGix9WipIU5d0Ewgd0GCyqGSIb3DQEJ
# EAIvMYHNMIHKMIHHMIGgBCDLRbqx24bpscXEJ+Hjj9xrcUVw7R8OyyMfSB2YGK3+
# vDB8MGWkYzBhMQswCQYDVQQGEwJVUzEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUHVibGljIFJTQSBUaW1lc3RhbXBp
# bmcgQ0EgMjAyMAITMwAAAFl82nHpjV71wAAAAAAAWTAiBCAQ3lA8bXpDDjmDoEuW
# 6NmCOgKbolZuS9syo+CZYwu9kTANBgkqhkiG9w0BAQsFAASCAgBHG/8FVFK273Rw
# uMWi2kPB//5UyAkY7PRjWhSIQzSRr4RdUJXc+MQZWzx209wtSbI0PcR6kRJx6r39
# 90ntkCYmwKTCqFNWf5IhtLJ5UVhC6YnoBxwr7Y2j+zcxCFjbFl5Z/s3mL+QJi6g4
# 9/1Fk4GIOcik+yB9J+0fkAAM4T+8G8cfDJSprOSEVu9PkWX2b5HH4yiKRP4hJ1gY
# Q6f2icOMyebIUkBWkrHYSuFI89FTznxB9iN/FW0RT1h9lqnFvr+V7/t0hA0ssgP+
# rBiuoMcezqEkxktHj6NjLTf56XZzx6P92KIlSsj1+iNw9rO3Vl7REhhOYnTeyZmq
# RrpQjuHUPbg0NpIW4nmv1903WgJOy8I549gRphgMrxea2+6/2kUaeEKsuBDQflfx
# pgRG5dzQMBQovo6e+5C47HGSqrooOgVsrvcC/w5X24UfzbYoE0RN7DY9X5ZvXz1i
# w21CpuHULsZWPfRQJk7rIjhZz/7X/GAZ0ChJbaUOf+nC9BScYXxYI9fYnP+Ai8SZ
# +nqRbPE4l3kvq2RrYThkg8Cyd/rOBf9/ugWzzaGS0IgpG/6NNCN2SocnLxJ7BYqN
# CwXdvUuIcpG92Eg8uC5ia62iZpxPaku+f0oZV95al2+LZO48TtVk5kmVfszW97nU
# 13+e3FCMAOCp7nY32zeq1TH0Pa5+xw==
# SIG # End signature block
