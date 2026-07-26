<#
    .SYNOPSIS
        Applies Windows optimization settings defined in an XML configuration file.
    .DESCRIPTION
        Reads an XML file containing optimization items (registry, services, scheduled tasks,
        store apps, file/folder operations, PowerShell scripts) and applies them based on the
        detected OS version. Results are written to the console and a JSONL log file.
    .PARAMETER FilePath
        Path to the XML configuration file. Defaults to Windows.xml in the script directory.
    .PARAMETER ExcludeOrder
        Array of Order numbers to skip. Matching items are shown inline as Skipped.
    .PARAMETER IncludeOrder
        Array of Order numbers to include. If specified, only matching items are processed.
    .PARAMETER LogPath
        Directory where the JSONL log file is written.
        Defaults to $Env:Temp. Falls back to $Env:Temp if the specified path is not writable.
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

        This runs the optimization with default settings, applying all items in Windows.xml and logging Info-level results to a timestamped log file in the temp directory.
    .EXAMPLE
        .\Invoke-WindowsOptimization.ps1 -ExcludeOrder 60,70 -LogLevel Verbose

        This runs the optimization while skipping items with Order 60 and 70, and logs all successes, skips, and errors to the log file.
    .EXAMPLE
        .\Invoke-WindowsOptimization.ps1 -LogPath 'C:\Logs' -LogLevel Debug

        This runs the optimization with detailed logging, including script outputs, and attempts to write the log file to C:\Logs. If C:\Logs is not writable, it falls back to the temp directory.
    .EXAMPLE
        .\Invoke-WindowsOptimization.ps1 -IncludeOrder 10,20,30

        This runs only the optimization items with Order 10, 20, and 30, and logs Info-level results to the log file.
    .NOTES
        Function  : Invoke-WindowsOptimization
        Author    : John Billekens
        Copyright : Copyright (c) John Billekens Consultancy
        Version   : 2026.726.2145

#>
[CmdletBinding()]
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
    [string]$LogPath = $Env:Temp,

    [Parameter(Mandatory = $false)]
    [switch]$SkipWarning,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Info', 'Verbose', 'Debug')]
    [string]$LogLevel = 'Info',

    [Parameter(Mandatory = $false)]
    [switch]$Detailed
)


$ProgressPreference = 'SilentlyContinue'

$script:ScriptVersion = '2026.726.2145'

# Ensure HKU: PSDrive is available (no-op if already present)
$null = New-PSDrive -PSProvider Registry -Name HKU -Root HKEY_USERS -ErrorAction SilentlyContinue

$script:DefaultUserMounted = $false


#region Logging

function Initialize-LogFile {
    param([string]$Directory)

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $fileName = "WindowsOptimization_$timestamp.log"

    foreach ($dir in @($Directory, $Env:Temp)) {
        try {
            if (-not (Test-Path -Path $dir)) {
                New-Item -Path $dir -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }
            $candidate = Join-Path $dir $fileName
            [System.IO.File]::OpenWrite($candidate).Close()
            return $candidate
        } catch {
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
        $header | Add-Content -Path $script:LogFile -Encoding UTF8
    } catch { }
}

$script:LogFile = Initialize-LogFile -Directory $LogPath
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
        $line | Add-Content -Path $script:LogFile -Encoding UTF8
    } catch { }
}

#endregion Logging

#region Output

# Column widths — "[ ScheduledTask ]" = 2 brackets + 2 spaces + 11 chars = 15 + 2 = 17... kept at 15 usable
$script:TypeColumnWidth = 15   # "[ ScheduledTask ]" — 2 brackets + 2 spaces + 11 chars
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
            'Google'
        )

        $IsVirtual = $false
        $Identification = "Physical"

        # Check all relevant fields for any VM signature
        foreach ($Sig in $VmSignatures) {
            if ($Manufacturer -like "*$($Sig)*" -or $Model -like "*$($Sig)*") {
                $IsVirtual = $true
                $Identification = "Virtual ($($Sig))"
                break
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
        Write-Error "Failed to identify platform: $($_.Exception.Message)"
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
    $script = $Item.PowerShell.Script.'#cdata-section'

    if ([string]::IsNullOrWhiteSpace($script)) {
        Write-Log -Level 'Warning' -Type 'PowerShell' -Item $Item.Name -Message 'Skipped — empty script'
        return New-ActionResult -Status 'Skipped' -Message 'Skipped (empty script)'
    }

    Write-ItemLine -TypeLabel 'PoSh Script' -Name $Item.Name -StatusText 'Started' -StatusColor 'Cyan'

    # 'powershell' only means Windows PowerShell 5.1 in-process when this script is
    # itself running under Windows PowerShell 5.1. Otherwise (e.g. this script running
    # under pwsh), run powershell.exe as a child process so Engine=powershell reliably
    # means Windows PowerShell 5.1 regardless of the host.
    $hostExe = if ($engine -eq 'powershell' -and $PSVersionTable.PSEdition -eq 'Core') { 'powershell' } else { $null }

    # pwsh / powershell (cross-engine) — child process (different binary), output always printed and logged
    if ($engine -eq 'pwsh' -or $hostExe) {
        $exeName = if ($hostExe) { $hostExe } else { 'pwsh' }
        $exePath = if (Get-Command $exeName -ErrorAction SilentlyContinue) { $exeName } else { $null }
        if (-not $exePath) {
            Write-Log -Level 'Error' -Type 'PowerShell' -Item $Item.Name -Message "$exeName not found on this system"
            return New-ActionResult -Status 'Failed' -Message "$exeName not found on this system"
        }
        try {
            $tmpOut = [System.IO.Path]::GetTempFileName()
            $tmpErr = "$tmpOut.err"
            $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($script))
            $proc = Start-Process -FilePath $exePath `
                -ArgumentList @('-NonInteractive', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encodedCommand) `
                -RedirectStandardOutput $tmpOut `
                -RedirectStandardError $tmpErr `
                -NoNewWindow -Wait -PassThru

            $outLines = if (Test-Path $tmpOut) { Get-Content $tmpOut } else { @() }
            $errLines = if (Test-Path $tmpErr) { Get-Content $tmpErr } else { @() }
            Remove-Item $tmpOut, $tmpErr -Force -ErrorAction SilentlyContinue

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
        }
    }

    # powershell — runspace in current process (host is already Windows PowerShell 5.1)
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

        $hasErrors = $ps.Streams.Error.Count -gt 0
        $errMsg = if ($hasErrors) { "$($ps.Streams.Error[0])" } else { '' }

        $ps.Dispose()
        $rs.Dispose()

        foreach ($line in $logLines) { Write-Log -Level 'Info' -Type 'PowerShell' -Item $Item.Name -Message $line }

        if ($hasErrors) {
            Write-Log -Level 'Error' -Type 'PowerShell' -Item $Item.Name -Message $errMsg
            return New-ActionResult -Status 'Failed' -Message $errMsg
        }

        Write-Log -Level 'Success' -Type 'PowerShell' -Item $Item.Name -Message 'Script executed successfully'
        return New-ActionResult -Status 'Success'
    } catch {
        Write-Log -Level 'Error' -Type 'PowerShell' -Item $Item.Name -Message $_.Exception.Message
        return New-ActionResult -Status 'Failed' -Message $_.Exception.Message
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

    switch ($action) {
        'Remove' {
            if (-not (Test-Path -Path $path -PathType $pathType)) {
                Write-Log -Level 'Info' -Type 'FileFolder' -Item $Item.Name -Message "Skipped — path not found: $path"
                return New-ActionResult -Status 'Skipped' -Message 'Skipped (not found)'
            }
            try {
                Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
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
            if (-not (Test-Path -Path $path -PathType $pathType)) {
                Write-Log -Level 'Info' -Type 'FileFolder' -Item $Item.Name -Message "Skipped — path not found: $path"
                return New-ActionResult -Status 'Skipped' -Message 'Skipped (not found)'
            }
            try {
                Rename-Item -Path $path -NewName $newName -ErrorAction Stop
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
            Write-Log -Level 'Info' -Type 'Service' -Item $Item.Name -Message "Skipped — service not found: $serviceName"
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
            Write-Log -Level 'Info' -Type 'Service' -Item $Item.Name -Message "Skipped — already $action"
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

    # Combine Hive + Path, then normalize to PowerShell PSDrive format (insert colon after hive root)
    $rawPath = if ([string]::IsNullOrWhiteSpace($Item.Registry.Path)) { $regHive } else { "$regHive\$($Item.Registry.Path)" }
    $regPath = $rawPath -replace '^(HK[A-Z_]+)\\', '$1:\'

    # Lazily mount the DefaultUser hive on first use
    if ($regPath -like 'HKU:\DefaultUser*' -and -not $script:DefaultUserMounted) {
        try {
            Mount-DefaultUserHive
        } catch {
            Write-Log -Level 'Error' -Type 'Registry' -Item $Item.Name -Message "DefaultUser hive mount failed: $($_.Exception.Message)"
            return New-ActionResult -Status 'Failed' -Message "DefaultUser hive mount failed: $($_.Exception.Message)"
        }
    }

    try {
        switch ($regAction) {
            'SetValue' {
                if (-not (Test-Path -Path $regPath)) {
                    New-Item -Path $regPath -Force -ErrorAction Stop | Out-Null
                }
                Set-ItemProperty -Path $regPath -Name $regName -Value $regValue -Type $regType -Force -ErrorAction Stop
                Write-Log -Level 'Success' -Type 'Registry' -Item $Item.Name -Message "Set $regPath\$regName = $regValue ($regType)"
                return New-ActionResult -Status 'Success'
            }
            'DeleteKey' {
                if (-not (Test-Path -Path $regPath)) {
                    Write-Log -Level 'Info' -Type 'Registry' -Item $Item.Name -Message "Skipped — key not found: $regPath"
                    return New-ActionResult -Status 'Skipped' -Message 'Skipped (key not found)'
                }
                Remove-Item -Path $regPath -Force -ErrorAction Stop
                Write-Log -Level 'Success' -Type 'Registry' -Item $Item.Name -Message "Deleted key: $regPath"
                return New-ActionResult -Status 'Success'
            }
            'DeleteKeyRecursively' {
                if (-not (Test-Path -Path $regPath)) {
                    Write-Log -Level 'Info' -Type 'Registry' -Item $Item.Name -Message "Skipped — key not found: $regPath"
                    return New-ActionResult -Status 'Skipped' -Message 'Skipped (key not found)'
                }
                Remove-Item -Path $regPath -Recurse -Force -ErrorAction Stop
                Write-Log -Level 'Success' -Type 'Registry' -Item $Item.Name -Message "Deleted key recursively: $regPath"
                return New-ActionResult -Status 'Success'
            }
            'DeleteValue' {
                if (-not (Test-Path -Path $regPath)) {
                    Write-Log -Level 'Info' -Type 'Registry' -Item $Item.Name -Message "Skipped — key not found: $regPath"
                    return New-ActionResult -Status 'Skipped' -Message 'Skipped (key not found)'
                }
                $existingProp = Get-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue
                if ($null -eq $existingProp) {
                    Write-Log -Level 'Info' -Type 'Registry' -Item $Item.Name -Message "Skipped — value not found: $regPath\$regName"
                    return New-ActionResult -Status 'Skipped' -Message 'Skipped (value not found)'
                }
                Remove-ItemProperty -Path $regPath -Name $regName -Force -ErrorAction Stop
                Write-Log -Level 'Success' -Type 'Registry' -Item $Item.Name -Message "Deleted value: $regPath\$regName"
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
            Write-Log -Level 'Info' -Type 'ScheduledTask' -Item $Item.Name -Message "Skipped — task not found: $taskPath\$taskName"
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
        $removedAny = $false

        $currentUserPkg = Get-AppxPackage -Name $appName -ErrorAction SilentlyContinue
        if ($currentUserPkg) {
            $null = $currentUserPkg | Remove-AppxPackage -ErrorAction Stop
            $removedAny = $true
        }

        $allUsersPkg = Get-AppxPackage -AllUsers -Name $appName -ErrorAction SilentlyContinue
        if ($allUsersPkg) {
            $null = $allUsersPkg | Remove-AppxPackage -AllUsers -ErrorAction Stop
            $removedAny = $true
        }

        if ($removedAny) {
            Write-Log -Level 'Success' -Type 'StoreApp' -Item $Item.Name -Message "Removed: $appName"
            return New-ActionResult -Status 'Success'
        } else {
            Write-Log -Level 'Info' -Type 'StoreApp' -Item $Item.Name -Message "Skipped — not installed: $appName"
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
        $unloadResult = & reg unload 'HKU\DefaultUser' 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "HKU\DefaultUser already exists and could not be unloaded: $unloadResult"
        }
    }

    $datFile = 'C:\Users\Default\NTUSER.DAT'
    if (-not (Test-Path -Path $datFile -PathType Leaf)) {
        throw "Default user hive not found: $datFile"
    }

    $loadResult = & reg load 'HKU\DefaultUser' $datFile 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to mount DefaultUser hive: $loadResult"
    }

    $script:DefaultUserMounted = $true
    Write-Log -Level 'Info' -Message 'Mounted DefaultUser hive (C:\Users\Default\NTUSER.DAT -> HKU\DefaultUser)'
}

function Dismount-DefaultUserHive {
    [CmdletBinding()]
    param ()
    if (-not $script:DefaultUserMounted) { return }

    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    Start-Sleep -Seconds 1  # give it a moment to release handles before unmounting

    $unloadResult = & reg unload 'HKU\DefaultUser' 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Could not unmount DefaultUser hive: $unloadResult"
        Write-Log -Level 'Warning' -Message "Failed to unmount DefaultUser hive: $unloadResult"
    } else {
        Write-Log -Level 'Info' -Message 'Unmounted DefaultUser hive'
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
    $xml = [System.Xml.XmlDocument]::new()
    $xml.Load($FilePath)
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
$machineDetails = Get-SystemPlatform
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
    Write-Host ''

    try {
        foreach ($item in $allItems) {
            $type = $item.Type

            # Included by order — skip items not in the include list
            if ($IncludeOrder.Count -gt 0 -and [int]$item.Order -notin $IncludeOrder) {
                $excludedCount++
                $label = if ($typeMap.ContainsKey($type)) { $typeMap[$type].DisplayName } else { $type.Substring(0, [Math]::Min($type.Length, 11)) }
                $result = New-ActionResult -Status 'Skipped' -Message "Skipped (not in IncludeOrder)"
                Write-ItemResult -TypeLabel $label -Name $item.Name -Result $result
                Write-Log -Level 'Info' -Type $type -Item $item.Name -Message "Excluded by IncludeOrder (order $($item.Order))"
                continue
            }

            # Excluded by order — show inline in sorted position
            if ($ExcludeOrder.Count -gt 0 -and [int]$item.Order -in $ExcludeOrder) {
                $excludedCount++
                $label = if ($typeMap.ContainsKey($type)) { $typeMap[$type].DisplayName } else { $type.Substring(0, [Math]::Min($type.Length, 11)) }
                $result = New-ActionResult -Status 'Skipped' -Message "Skipped (excluded order $($item.Order))"
                Write-ItemResult -TypeLabel $label -Name $item.Name -Result $result
                Write-Log -Level 'Info' -Type $type -Item $item.Name -Message "Excluded by ExcludeOrder (order $($item.Order))"
                continue
            }

            # Physical/Virtual check — absent node treated as 0
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

            Write-Verbose "Dispatching '$($item.Name)' -> $($typeMap[$type].Function)"

            $result = & $typeMap[$type].Function -Item $item
            Write-ItemResult -TypeLabel $typeMap[$type].DisplayName -Name $item.Name -Result $result

            switch ($result.Status) {
                'Success' { $successCount++ }
                'Skipped' { $skippedCount++ }
                'Failed' { $failedCount++ }
            }
        }

        Write-Log -Level 'Info' -Message "Script completed — Success: $successCount, Skipped: $skippedCount, Failed: $failedCount, Excluded: $excludedCount, Included: $($IncludeOrder.Count), Total: $($allItems.Count)"

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

# SIG # Begin signature block
# MII6AgYJKoZIhvcNAQcCoII58zCCOe8CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCNtOmb+fkv3SyN
# +zYtNdcQ3JUHl5PuNno/yNBQLb8PZqCCIiYwggXMMIIDtKADAgECAhBUmNLR1FsZ
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
# 03u4aUoqlmZpxJTG9F9urJh4iIAGXKKy7aIwggbAMIIEqKADAgECAhMzAAOL1f1J
# 95r64TJvAAAAA4vVMA0GCSqGSIb3DQEBDAUAMFoxCzAJBgNVBAYTAlVTMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKzApBgNVBAMTIk1pY3Jvc29mdCBJ
# RCBWZXJpZmllZCBDUyBFT0MgQ0EgMDQwHhcNMjYwNzI0MTkyMzQ4WhcNMjYwNzI3
# MTkyMzQ4WjCBgzELMAkGA1UEBhMCTkwxFjAUBgNVBAgTDU5vb3JkLUJyYWJhbnQx
# EjAQBgNVBAcTCVNjaGlqbmRlbDEjMCEGA1UEChMaSm9obiBCaWxsZWtlbnMgQ29u
# c3VsdGFuY3kxIzAhBgNVBAMTGkpvaG4gQmlsbGVrZW5zIENvbnN1bHRhbmN5MIIB
# ojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAsAYN2yxGG17ogLg4+6ytnnn9
# R4xS04ixMpI0B+xDOi4RevyYjfWeIoisIAqJKSRHXo41EKseHBJi+Qz2tOuxP4dl
# W9NTHEkL4S4XZvWjE5wmRmZyBEYKqip28/9yGwaWQnwgk2GpRL8hCoE4d69wJ/Ix
# pBLeeJOVElwHMRt9b+78kNKNvVI11viTQ/KurhFlPZbwB8TBi5kE/GI6iYTjI7Zi
# mk5FkbBbBN6J228qUomVd0rYomJAJftbUYHHRXM6pR5254ORC+gPELKe7uLyV0K8
# qYecCRX1Q2tD/Vr394gwZyIRiKTm29Vz0mzMOHw0Qhc/twG4hPBg7ExCkgD/lojw
# JxBVA27RNQXkEHY0te5mB/VGI8//t0BkCpPkUn9s6cZmn+2ekbAWnlfmoewcZyih
# k296OR6bptpmP5sXgi+GKPGYLKJZZwjcm7csGsc4FV+Z8Kshag08HFe7J3FNzFGU
# eni9jPSp2P5Sg+meOad5Jyt+HvOPQ436gyPL4xidAgMBAAGjggHTMIIBzzAMBgNV
# HRMBAf8EAjAAMA4GA1UdDwEB/wQEAwIHgDA6BgNVHSUEMzAxBgorBgEEAYI3YQEA
# BggrBgEFBQcDAwYZKwYBBAGCN2HK9PELgrHSgxH33KNOluu6MTAdBgNVHQ4EFgQU
# atJHu/ViOBJVUqVrdhK/fYMq7XAwHwYDVR0jBBgwFoAUmvFUd3UMhxY3RqCs3nn5
# 9H/BeOkwZwYDVR0fBGAwXjBcoFqgWIZWaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraW9wcy9jcmwvTWljcm9zb2Z0JTIwSUQlMjBWZXJpZmllZCUyMENTJTIwRU9D
# JTIwQ0ElMjAwNC5jcmwwdAYIKwYBBQUHAQEEaDBmMGQGCCsGAQUFBzAChlhodHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMElE
# JTIwVmVyaWZpZWQlMjBDUyUyMEVPQyUyMENBJTIwMDQuY3J0MFQGA1UdIARNMEsw
# SQYEVR0gADBBMD8GCCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20v
# cGtpb3BzL0RvY3MvUmVwb3NpdG9yeS5odG0wDQYJKoZIhvcNAQEMBQADggIBADd/
# mMO0rkC6BJtBqA5bdQ+CMT/XQl8FWyJMMs/DmcO0NHm0s/zV65pzF2QVLPIbxOmT
# yKDqKWbmFqZANUjway3sIkf9/kBzYKY5U+vfO/EP1stIfl4JKDdKieUATmqUeg8Z
# rqc47MVjvtmrdhfeF/enph55neKI60nUXsN0KyYgNx01nFgr+lrGYiXIXNP6GxEw
# N47yZgi55PVA/blkzGpyWrHxvmz1ytERei0H+HCAldogWa1tsLWfzisGv8whAVT+
# K+px1aHXxlwsWoLaYztzL0qQMD6g7hxovusfKz6Jcbk3XNIOlNopnBZSXCyoeCZu
# sDgzgJxDiGi20rMqiv+3BOfe8cnhPsrwHo4NJ2imb4h7nqNW5P/ybUepheq56Zu5
# LVfz70B7vNH5rMULAziElS1+0Lkf0i1zl718mnUN65byth2xTkZE8oO4d1mYvN+5
# 1q44MLzQnDvRMpUpi15IzGI07huJqcOqaWCczQSt5y1LmBfBRSoEjr+kxJSFKrRH
# bawGR50ADEPGq2uGcYr0A3Ih2JJEuN9D7adCNof7mlUsXkl//0uO7KsdRwoWVInj
# Hutv5O1NhbMqXQXtkbwZiggBYpLSFp8kf2+zs1FSVgt9dagZa5DZOsuq9keUL7Bq
# +xkLz1B+Nlx0PnDvjU7JfV5r6bkbSyU4NXmN10KoMIIGwDCCBKigAwIBAgITMwAD
# i9X9Sfea+uEybwAAAAOL1TANBgkqhkiG9w0BAQwFADBaMQswCQYDVQQGEwJVUzEe
# MBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSswKQYDVQQDEyJNaWNyb3Nv
# ZnQgSUQgVmVyaWZpZWQgQ1MgRU9DIENBIDA0MB4XDTI2MDcyNDE5MjM0OFoXDTI2
# MDcyNzE5MjM0OFowgYMxCzAJBgNVBAYTAk5MMRYwFAYDVQQIEw1Ob29yZC1CcmFi
# YW50MRIwEAYDVQQHEwlTY2hpam5kZWwxIzAhBgNVBAoTGkpvaG4gQmlsbGVrZW5z
# IENvbnN1bHRhbmN5MSMwIQYDVQQDExpKb2huIEJpbGxla2VucyBDb25zdWx0YW5j
# eTCCAaIwDQYJKoZIhvcNAQEBBQADggGPADCCAYoCggGBALAGDdssRhte6IC4OPus
# rZ55/UeMUtOIsTKSNAfsQzouEXr8mI31niKIrCAKiSkkR16ONRCrHhwSYvkM9rTr
# sT+HZVvTUxxJC+EuF2b1oxOcJkZmcgRGCqoqdvP/chsGlkJ8IJNhqUS/IQqBOHev
# cCfyMaQS3niTlRJcBzEbfW/u/JDSjb1SNdb4k0Pyrq4RZT2W8AfEwYuZBPxiOomE
# 4yO2YppORZGwWwTeidtvKlKJlXdK2KJiQCX7W1GBx0VzOqUedueDkQvoDxCynu7i
# 8ldCvKmHnAkV9UNrQ/1a9/eIMGciEYik5tvVc9JszDh8NEIXP7cBuITwYOxMQpIA
# /5aI8CcQVQNu0TUF5BB2NLXuZgf1RiPP/7dAZAqT5FJ/bOnGZp/tnpGwFp5X5qHs
# HGcooZNvejkem6baZj+bF4IvhijxmCyiWWcI3Ju3LBrHOBVfmfCrIWoNPBxXuydx
# TcxRlHp4vYz0qdj+UoPpnjmneScrfh7zj0ON+oMjy+MYnQIDAQABo4IB0zCCAc8w
# DAYDVR0TAQH/BAIwADAOBgNVHQ8BAf8EBAMCB4AwOgYDVR0lBDMwMQYKKwYBBAGC
# N2EBAAYIKwYBBQUHAwMGGSsGAQQBgjdhyvTxC4Kx0oMR99yjTpbrujEwHQYDVR0O
# BBYEFGrSR7v1YjgSVVKla3YSv32DKu1wMB8GA1UdIwQYMBaAFJrxVHd1DIcWN0ag
# rN55+fR/wXjpMGcGA1UdHwRgMF4wXKBaoFiGVmh0dHA6Ly93d3cubWljcm9zb2Z0
# LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMElEJTIwVmVyaWZpZWQlMjBDUyUy
# MEVPQyUyMENBJTIwMDQuY3JsMHQGCCsGAQUFBwEBBGgwZjBkBggrBgEFBQcwAoZY
# aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQl
# MjBJRCUyMFZlcmlmaWVkJTIwQ1MlMjBFT0MlMjBDQSUyMDA0LmNydDBUBgNVHSAE
# TTBLMEkGBFUdIAAwQTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQu
# Y29tL3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRtMA0GCSqGSIb3DQEBDAUAA4IC
# AQA3f5jDtK5AugSbQagOW3UPgjE/10JfBVsiTDLPw5nDtDR5tLP81euacxdkFSzy
# G8Tpk8ig6ilm5hamQDVI8Gst7CJH/f5Ac2CmOVPr3zvxD9bLSH5eCSg3SonlAE5q
# lHoPGa6nOOzFY77Zq3YX3hf3p6YeeZ3iiOtJ1F7DdCsmIDcdNZxYK/paxmIlyFzT
# +hsRMDeO8mYIueT1QP25ZMxqclqx8b5s9crREXotB/hwgJXaIFmtbbC1n84rBr/M
# IQFU/ivqcdWh18ZcLFqC2mM7cy9KkDA+oO4caL7rHys+iXG5N1zSDpTaKZwWUlws
# qHgmbrA4M4CcQ4hottKzKor/twTn3vHJ4T7K8B6ODSdopm+Ie56jVuT/8m1HqYXq
# uembuS1X8+9Ae7zR+azFCwM4hJUtftC5H9Itc5e9fJp1DeuW8rYdsU5GRPKDuHdZ
# mLzfudauODC80Jw70TKVKYteSMxiNO4bianDqmlgnM0ErectS5gXwUUqBI6/pMSU
# hSq0R22sBkedAAxDxqtrhnGK9ANyIdiSRLjfQ+2nQjaH+5pVLF5Jf/9LjuyrHUcK
# FlSJ4x7rb+TtTYWzKl0F7ZG8GYoIAWKS0hafJH9vs7NRUlYLfXWoGWuQ2TrLqvZH
# lC+wavsZC89QfjZcdD5w741OyX1ea+m5G0slODV5jddCqDCCBygwggUQoAMCAQIC
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
# BgNVBAMTIk1pY3Jvc29mdCBJRCBWZXJpZmllZCBDUyBFT0MgQ0EgMDQCEzMAA4vV
# /Un3mvrhMm8AAAADi9UwDQYJYIZIAWUDBAIBBQCgXjAQBgorBgEEAYI3AgEMMQIw
# ADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAvBgkqhkiG9w0BCQQxIgQgvsoi
# u+7+mch9ppy9ynszhibC2xpZ6J8XsMB28xONQrEwDQYJKoZIhvcNAQEBBQAEggGA
# W+YnuM7Ba0WeuwLtUs8s75wlJrDeHfAxlbe3P9M8ltqMdzmjOPmnx9BCtTZuvkYq
# wC2pm5qtL0aMZJPUB2eMqKjKayBvAAXHZ2BsFqO1rtnzaohjEAzHGLQIizss7WCE
# nQgxmefjwgQDb2BvAJbxs2iYbzkff46OAFNnuTDxrtdkOAEFcJOw2ZsBS/IyZK7A
# P8LoGtrk1NEndCW4oRNL9MaEWWPaUiGhCyQADynIcRow7JotWmSMeEHwboW9URdn
# ncxNSnVoX6uV7L8zcujFamgwWWhnHJprJbUkcX1R3eft661H53H55IORGUsLEhvm
# ZARAX+4t8ihohTYIL1nsURIPW5aRbe4n8z/Gqe65uzlWA5deqIEqISKZzNH6Tee9
# qjt3tWc7QGR0r8HFi6HLw9Nt4tfwXXg1cscVtD1ONcocPlx+FEuyy+ACt9KzG64y
# J07hCdZqQZ3lFAD9QVy0WkOzNGctYtlIVuRgGTcr4xlbhENTfax7JVUr5iksaIBg
# oYIUsjCCFK4GCisGAQQBgjcDAwExghSeMIIUmgYJKoZIhvcNAQcCoIIUizCCFIcC
# AQMxDzANBglghkgBZQMEAgEFADCCAWoGCyqGSIb3DQEJEAEEoIIBWQSCAVUwggFR
# AgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUDBAIBBQAEIGd3EurNnHvXd2XBS1UA
# ZTo8TUVQN+j8f7ONFFsPBrcsAgZqNWdaqw0YEzIwMjYwNzI2MTkzMzA2LjQ4NVow
# BIACAfSggemkgeYwgeMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRl
# ZDEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjdBMUEtMDVFMC1EOTQ3MTUwMwYD
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
# JYbYbBh7pmgAXVswggefMIIFh6ADAgECAhMzAAAAW0q1jUEybdx0AAAAAABbMA0G
# CSqGSIb3DQEBDAUAMGExCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBQdWJsaWMgUlNBIFRpbWVz
# dGFtcGluZyBDQSAyMDIwMB4XDTI2MDEwODE4NTkwNVoXDTI3MDEwNzE4NTkwNVow
# geMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsT
# JE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMe
# blNoaWVsZCBUU1MgRVNOOjdBMUEtMDVFMC1EOTQ3MTUwMwYDVQQDEyxNaWNyb3Nv
# ZnQgUHVibGljIFJTQSBUaW1lIFN0YW1waW5nIEF1dGhvcml0eTCCAiIwDQYJKoZI
# hvcNAQEBBQADggIPADCCAgoCggIBAJBUzBbbnlDXee0B0KD5G4/475thFyfctCyu
# ESTWQXvlLi4Wx/td2qUdeq4ideeg6VWhiOHfu3wJV4TUGSRtqh9Ccr1BmiBKv9iu
# FpgHyIBu5Qx38ZsxwlFeXVS+ZqJJKnXRbDNQdcYSoC/6c0hQJ/PH50DBRDQkPXVw
# yFizLrRH9AlrJeUg7BKeT23zftS8/KOJLvEEbHOF6pSOY3ZVprZUWbWjWwRTmoHa
# Q/E8vrWtLNyEJ+b089VW1Ikra3t4GTB5Wby3CL1K2zYnAxBIvafsKMFyj9OuXHcT
# PKMDoFSMeamG9MKOMb6uoG1PjdnDgsLP6EOMRSzrLL7jED1mbB9RSd9fhty+HQr6
# vZgsBn6oUy+YTpNVLskwdtUM82WYAkPztlOt3AiL0qyV7/U3j/uq3vHMjPM0w034
# 0M57Nei0g4BCcMt0dbqoc91VgCb3/36sHQANontn1HOF2oLk8190QRS43isHVra8
# H8sf5+GlqIYsYiCKX04HZiOzZW826nVI6d++8lyTeWmpj90Ua9uPbJhVjwE3oh6t
# O510ySqmSMSLEN07p3Ibe3E6BAb2w93rWzb26+dpSthbKF4kApofqBsWPX4MEtHK
# SOftPmVTCQ47tghrVuHia9jY+Hsj01m4KW4WtkmVm3L6hMZECMa4sjMxAXz+bX/A
# JhWTe6TZAgMBAAGjggHLMIIBxzAdBgNVHQ4EFgQU7/LqUlWWYhXJdXwgYKx4b8Gv
# 0rYwHwYDVR0jBBgwFoAUa2koOjUvSGNAz3vYr0npPtk92yEwbAYDVR0fBGUwYzBh
# oF+gXYZbaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwvTWljcm9z
# b2Z0JTIwUHVibGljJTIwUlNBJTIwVGltZXN0YW1waW5nJTIwQ0ElMjAyMDIwLmNy
# bDB5BggrBgEFBQcBAQRtMGswaQYIKwYBBQUHMAKGXWh0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwUHVibGljJTIwUlNBJTIw
# VGltZXN0YW1waW5nJTIwQ0ElMjAyMDIwLmNydDAMBgNVHRMBAf8EAjAAMBYGA1Ud
# JQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDBmBgNVHSAEXzBdMFEG
# DCsGAQQBgjdMg30BATBBMD8GCCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20vcGtpb3BzL0RvY3MvUmVwb3NpdG9yeS5odG0wCAYGZ4EMAQQCMA0GCSqG
# SIb3DQEBDAUAA4ICAQAAH+zd+XKh4OxXYMWFmtgilXAQGctOjCUB1w/uBiC/OXcH
# 3Ia4/XbdUhKzFbaiTbIE6vYZKd1p4u7nKOLkawymAMVyuO7LSl6rLKttZIyLhWjT
# K0zXOz0u4xLq9+bRtBEKJvA6sD5nJwH1IO6z1YizyuIRoalMCnbrUixfWxQn4TAm
# N7t9uk+X2FUThEa3ewzRwhtG+xwaAbLMkxRmR24JnfXd1VxKo90+m7Wzuov96Uug
# x5wZdewiIIm1ZWTj4lCJHup679LcOa7tAxJMipVaSltQH9fm9TOKczlfxtWuBcLU
# 4duZfqwgsILsH7PMkcX1zwQzQD0yAtPhnYz9KNG125bX+iilOe1S8RHqv2bbBpMp
# ao4kcUvQI6dMgKRvFmm1eLbhSNOQplDMTGD1tNVdNGkI96jUu+troUjWMMi46TQf
# BAHxtDTpRhIu/87vAVQ8Z6RHhFxesz4Ed5JThaIQRAy6GcO/Jk+QzDzoZ0arRIkI
# sGJ7rZgOVAjx9ctfw8lH9RfjcwB3wdGBYNMNVJqQpUai2Taddf5pXzTZEHIqLEF5
# 3SrBjIeInoQrP7U5VlXiMQsxewLdINrAE2l2TR3KBikb+RQRygbTp8jj2yiC0NCU
# wG+K+ndglN5RMbXjFW6aKa59Xq+b8XzK/DK+AJtgOpHgJv8Qrk62A+twOVLOpjGC
# A9QwggPQAgEBMHgwYTELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFB1YmxpYyBSU0EgVGltZXN0
# YW1waW5nIENBIDIwMjACEzMAAABbSrWNQTJt3HQAAAAAAFswDQYJYIZIAWUDBAIB
# BQCgggEtMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQx
# IgQgMoYdm+pPne4CIWFo/MJMiHTxF2qQTNHV1sxpEVfdS9Ewgd0GCyqGSIb3DQEJ
# EAIvMYHNMIHKMIHHMIGgBCAvMQNVXZ0b0xxlGw8X/3IEybObuT6a5W1d61CW+cGD
# 7zB8MGWkYzBhMQswCQYDVQQGEwJVUzEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUHVibGljIFJTQSBUaW1lc3RhbXBp
# bmcgQ0EgMjAyMAITMwAAAFtKtY1BMm3cdAAAAAAAWzAiBCDYPYYbDXQVG8fES5Xd
# xINYcKeUaZ33AZ0NJV7E8tcNyTANBgkqhkiG9w0BAQsFAASCAgBuBL0uZWd7++K8
# gjBTR633SCjsmPhmdz7ZFIoGpGBA92g96PwOJ6wETGThwg8frQ737c/ZfAFNnp0E
# yO37HT4FgXl4aV/wXsZc4XPba2w31TDDotWr9MwZLk+LODXNTyHFpUSVd6i58lb/
# KQZHNKR88OClFzNojsm2aq/sLVLUD8Q7gWmqGsJMIZkiLSRd2+0yX+HSaYZJ3vhi
# W+pFbOuunWIPdIONgcZu972bRttu5/jdS96i9KF3fdnaSy2pn1etuYp4VtCjsRtI
# loMx9v4im5Kzaig7L01CFmeMKbHgTGDJsILo28SLE47yetE4hXxSEB5QMrRmKr5R
# 6HHpanx35HBxSyQnWG5SovCrEbehNePyMVRynhplaKq8wT3u9RZIfBShRsBYmzTd
# rJCy3EeYDgbGtVR2KUAb9Fjrxq5CUI5GHkmjAnOG973CXR+V5XAbsBpBq9FZEwLM
# iYlO01iWHe2fTTT+3W5jzzf9zj29PzjciWHcw/6NbViccDx8kr8NedzYIfnahj9V
# mGf7S+JG5VvpeLyoeGJ4xD6FIDE5zGFSHHJG/hrXMYl8ew6nRLRVhJkLSmDbKhdC
# 6T7vBswf9ORwMPOeFyOFc2PK3Oe8kL46+GU1Z7ji3MUvVb8IisQWJ4AhNwVcLIAT
# dHKpTGPGRCGiYmc92RCCfrHeng6Fpw==
# SIG # End signature block
