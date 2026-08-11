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
        Version   : 2026.811.2030

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

$script:ScriptVersion = '2026.811.2030'

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
        Write-Log -Level 'Warning' -Type 'PowerShell' -Item $Item.Name -Message 'Skipped - empty script'
        return New-ActionResult -Status 'Skipped' -Message 'Skipped (empty script)'
    }

    Write-ItemLine -TypeLabel 'PoSh Script' -Name $Item.Name -StatusText 'Started' -StatusColor 'Cyan'

    # 'powershell' only means Windows PowerShell 5.1 in-process when this script is
    # itself running under Windows PowerShell 5.1. Otherwise (e.g. this script running
    # under pwsh), run powershell.exe as a child process so Engine=powershell reliably
    # means Windows PowerShell 5.1 regardless of the host.
    $hostExe = if ($engine -eq 'powershell' -and $PSVersionTable.PSEdition -eq 'Core') { 'powershell' } else { $null }

    # pwsh / powershell (cross-engine) - child process (different binary), output always printed and logged
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

    # powershell - runspace in current process (host is already Windows PowerShell 5.1)
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
                Write-Log -Level 'Info' -Type 'FileFolder' -Item $Item.Name -Message "Skipped - path not found: $path"
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
                Write-Log -Level 'Info' -Type 'FileFolder' -Item $Item.Name -Message "Skipped - path not found: $path"
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
                    Write-Log -Level 'Info' -Type 'Registry' -Item $Item.Name -Message "Skipped - key not found: $regPath"
                    return New-ActionResult -Status 'Skipped' -Message 'Skipped (key not found)'
                }
                Remove-Item -Path $regPath -Force -ErrorAction Stop
                Write-Log -Level 'Success' -Type 'Registry' -Item $Item.Name -Message "Deleted key: $regPath"
                return New-ActionResult -Status 'Success'
            }
            'DeleteKeyRecursively' {
                if (-not (Test-Path -Path $regPath)) {
                    Write-Log -Level 'Info' -Type 'Registry' -Item $Item.Name -Message "Skipped - key not found: $regPath"
                    return New-ActionResult -Status 'Skipped' -Message 'Skipped (key not found)'
                }
                Remove-Item -Path $regPath -Recurse -Force -ErrorAction Stop
                Write-Log -Level 'Success' -Type 'Registry' -Item $Item.Name -Message "Deleted key recursively: $regPath"
                return New-ActionResult -Status 'Success'
            }
            'DeleteValue' {
                if (-not (Test-Path -Path $regPath)) {
                    Write-Log -Level 'Info' -Type 'Registry' -Item $Item.Name -Message "Skipped - key not found: $regPath"
                    return New-ActionResult -Status 'Skipped' -Message 'Skipped (key not found)'
                }
                $existingProp = Get-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue
                if ($null -eq $existingProp) {
                    Write-Log -Level 'Info' -Type 'Registry' -Item $Item.Name -Message "Skipped - value not found: $regPath\$regName"
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
            Write-Log -Level 'Info' -Type 'StoreApp' -Item $Item.Name -Message "Skipped - not installed: $appName"
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

# SIG # Begin signature block
# MII6AQYJKoZIhvcNAQcCoII58jCCOe4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCClbJ0ctqfjQVzl
# 9zkvDskxgOmRkhPGH6KiN0XNygGhwaCCIiYwggXMMIIDtKADAgECAhBUmNLR1FsZ
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
# 03u4aUoqlmZpxJTG9F9urJh4iIAGXKKy7aIwggbAMIIEqKADAgECAhMzAASf/cQv
# b4nhuhvyAAAABJ/9MA0GCSqGSIb3DQEBDAUAMFoxCzAJBgNVBAYTAlVTMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKzApBgNVBAMTIk1pY3Jvc29mdCBJ
# RCBWZXJpZmllZCBDUyBBT0MgQ0EgMDQwHhcNMjYwODEwMjAwODAxWhcNMjYwODEz
# MjAwODAxWjCBgzELMAkGA1UEBhMCTkwxFjAUBgNVBAgTDU5vb3JkLUJyYWJhbnQx
# EjAQBgNVBAcTCVNjaGlqbmRlbDEjMCEGA1UEChMaSm9obiBCaWxsZWtlbnMgQ29u
# c3VsdGFuY3kxIzAhBgNVBAMTGkpvaG4gQmlsbGVrZW5zIENvbnN1bHRhbmN5MIIB
# ojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAo6GSCbQz1muNtCtOVl/WOoLi
# g+P685dMM/QtObSFVgA6hFO4dz25ck4OCZ1m5RF6/cme3r5yFPV0GCuBHh4WUilJ
# 8EGq6sfvcg+7ObDF7IxtH4Nk45XQEqz6JVOvHydtyll+FtwTQdH9eOBxKYOwxTsf
# uWBuDuCsD4RwxMEgc2jp7F8f+Me/hq7iSsd2NZNKNfWF44C58C81nx9+I+V8KH4w
# +DFEPYm9vTCzEEJRt7tad2DH0TZYHKq62rxHsX1IEIm5hgDnnlR9SS4UQdr+9eDC
# rRuGCPmtFbiw2VxIX8EKTkLorG6rn92c8iNl5CxYxZ4ENOEgUke1WDJ1os5b2b9b
# SGdOshDc/Fk8YNbwZBJeo2E+/t74B2cmHGI96x+3Vd8QKfyqFrSRrmKaQ6mfLVln
# aOPIwhTkaD25KGOgWlvz3Kx+UIil9P3ZR8Iik8/pT0OoJzLM91ntLuUyOGi0rJE8
# AepfkUmu3iIXNbVpAjYG0cxheG9+owrZjCyZ3/jFAgMBAAGjggHTMIIBzzAMBgNV
# HRMBAf8EAjAAMA4GA1UdDwEB/wQEAwIHgDA6BgNVHSUEMzAxBgorBgEEAYI3YQEA
# BggrBgEFBQcDAwYZKwYBBAGCN2HK9PELgrHSgxH33KNOluu6MTAdBgNVHQ4EFgQU
# wRstNDBztzQ4ngJWO6y+SBkcfY4wHwYDVR0jBBgwFoAUayVB3vtrfP0YgAotf492
# XapzPbgwZwYDVR0fBGAwXjBcoFqgWIZWaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraW9wcy9jcmwvTWljcm9zb2Z0JTIwSUQlMjBWZXJpZmllZCUyMENTJTIwQU9D
# JTIwQ0ElMjAwNC5jcmwwdAYIKwYBBQUHAQEEaDBmMGQGCCsGAQUFBzAChlhodHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMElE
# JTIwVmVyaWZpZWQlMjBDUyUyMEFPQyUyMENBJTIwMDQuY3J0MFQGA1UdIARNMEsw
# SQYEVR0gADBBMD8GCCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20v
# cGtpb3BzL0RvY3MvUmVwb3NpdG9yeS5odG0wDQYJKoZIhvcNAQEMBQADggIBAMDW
# sD2HQSDBh9lqHZE6QNPW0TBhnMpAzz0juCXsZy9NtFq6CjzbIkhkFcHoXOaFuovB
# +hqjjBFKfRirGglo6sdjcIUZrRtTU00bXrE9uGqFMsbht2LZpZsdTZzuwRryIuXz
# /65nhYwMXANNMPNWZtj84tHLqtyH7p0KpRdH+qfoiOaB9YcmGW+WrUUWXKJ9vw6B
# SIyNlWTtDW0nG01TXDvnjZOEwUNoikUjjMZeqTzIEeS6zdvk+KB1CYu5yVMxR1qS
# qnUNvUd/VU0TZ/lCwa2oBiqTcp3j4cwa4xrhcDbfVFTTTeVqw9SvLkGWaIvzLzzO
# Fe+fh1kMtgDmBNsxGilrdr2iNkYoc6LTXdxmXqHU6QyeQMoJxFzKWtfHarggdX7W
# oBRQatjDRromDvuobQJEjgB6YwEMS9MbFRGocQKYyss/Km5A6oPyfDbYa2PeFWXi
# c8377aMa7whg/QiNXkE5wtkoACH69cvrSdh/wyCQ9t4bkiMvF4id653zPIrfSqhr
# zd4meVsIBwgCKDUyR+C+jqxc6vMSDsDpTZMLAi5/Nxn5H15vydFm80E4VXEnJHb7
# gQgqA4OJmaOpAYW31OC3u4NB7aZDyADkyUYVjc1bUUWu19TNF4OfunF/DsCrK/QZ
# u+fVYLK2m2Ctry1pOsFnja6IUrxle0jWw3HRrRjkMIIGwDCCBKigAwIBAgITMwAE
# n/3EL2+J4bob8gAAAASf/TANBgkqhkiG9w0BAQwFADBaMQswCQYDVQQGEwJVUzEe
# MBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSswKQYDVQQDEyJNaWNyb3Nv
# ZnQgSUQgVmVyaWZpZWQgQ1MgQU9DIENBIDA0MB4XDTI2MDgxMDIwMDgwMVoXDTI2
# MDgxMzIwMDgwMVowgYMxCzAJBgNVBAYTAk5MMRYwFAYDVQQIEw1Ob29yZC1CcmFi
# YW50MRIwEAYDVQQHEwlTY2hpam5kZWwxIzAhBgNVBAoTGkpvaG4gQmlsbGVrZW5z
# IENvbnN1bHRhbmN5MSMwIQYDVQQDExpKb2huIEJpbGxla2VucyBDb25zdWx0YW5j
# eTCCAaIwDQYJKoZIhvcNAQEBBQADggGPADCCAYoCggGBAKOhkgm0M9ZrjbQrTlZf
# 1jqC4oPj+vOXTDP0LTm0hVYAOoRTuHc9uXJODgmdZuURev3Jnt6+chT1dBgrgR4e
# FlIpSfBBqurH73IPuzmwxeyMbR+DZOOV0BKs+iVTrx8nbcpZfhbcE0HR/XjgcSmD
# sMU7H7lgbg7grA+EcMTBIHNo6exfH/jHv4au4krHdjWTSjX1heOAufAvNZ8ffiPl
# fCh+MPgxRD2Jvb0wsxBCUbe7Wndgx9E2WByqutq8R7F9SBCJuYYA555UfUkuFEHa
# /vXgwq0bhgj5rRW4sNlcSF/BCk5C6Kxuq5/dnPIjZeQsWMWeBDThIFJHtVgydaLO
# W9m/W0hnTrIQ3PxZPGDW8GQSXqNhPv7e+AdnJhxiPesft1XfECn8qha0ka5imkOp
# ny1ZZ2jjyMIU5Gg9uShjoFpb89ysflCIpfT92UfCIpPP6U9DqCcyzPdZ7S7lMjho
# tKyRPAHqX5FJrt4iFzW1aQI2BtHMYXhvfqMK2Ywsmd/4xQIDAQABo4IB0zCCAc8w
# DAYDVR0TAQH/BAIwADAOBgNVHQ8BAf8EBAMCB4AwOgYDVR0lBDMwMQYKKwYBBAGC
# N2EBAAYIKwYBBQUHAwMGGSsGAQQBgjdhyvTxC4Kx0oMR99yjTpbrujEwHQYDVR0O
# BBYEFMEbLTQwc7c0OJ4CVjusvkgZHH2OMB8GA1UdIwQYMBaAFGslQd77a3z9GIAK
# LX+Pdl2qcz24MGcGA1UdHwRgMF4wXKBaoFiGVmh0dHA6Ly93d3cubWljcm9zb2Z0
# LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMElEJTIwVmVyaWZpZWQlMjBDUyUy
# MEFPQyUyMENBJTIwMDQuY3JsMHQGCCsGAQUFBwEBBGgwZjBkBggrBgEFBQcwAoZY
# aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQl
# MjBJRCUyMFZlcmlmaWVkJTIwQ1MlMjBBT0MlMjBDQSUyMDA0LmNydDBUBgNVHSAE
# TTBLMEkGBFUdIAAwQTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQu
# Y29tL3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRtMA0GCSqGSIb3DQEBDAUAA4IC
# AQDA1rA9h0EgwYfZah2ROkDT1tEwYZzKQM89I7gl7GcvTbRaugo82yJIZBXB6Fzm
# hbqLwfoao4wRSn0YqxoJaOrHY3CFGa0bU1NNG16xPbhqhTLG4bdi2aWbHU2c7sEa
# 8iLl8/+uZ4WMDFwDTTDzVmbY/OLRy6rch+6dCqUXR/qn6IjmgfWHJhlvlq1FFlyi
# fb8OgUiMjZVk7Q1tJxtNU1w7542ThMFDaIpFI4zGXqk8yBHkus3b5PigdQmLuclT
# MUdakqp1Db1Hf1VNE2f5QsGtqAYqk3Kd4+HMGuMa4XA231RU003lasPUry5BlmiL
# 8y88zhXvn4dZDLYA5gTbMRopa3a9ojZGKHOi013cZl6h1OkMnkDKCcRcylrXx2q4
# IHV+1qAUUGrYw0a6Jg77qG0CRI4AemMBDEvTGxURqHECmMrLPypuQOqD8nw22Gtj
# 3hVl4nPN++2jGu8IYP0IjV5BOcLZKAAh+vXL60nYf8MgkPbeG5IjLxeIneud8zyK
# 30qoa83eJnlbCAcIAig1Mkfgvo6sXOrzEg7A6U2TCwIufzcZ+R9eb8nRZvNBOFVx
# JyR2+4EIKgODiZmjqQGFt9Tgt7uDQe2mQ8gA5MlGFY3NW1FFrtfUzReDn7pxfw7A
# qyv0Gbvn1WCytptgra8taTrBZ42uiFK8ZXtI1sNx0a0Y5DCCBygwggUQoAMCAQIC
# EzMAAAAWMZKNkgJle5oAAAAAABYwDQYJKoZIhvcNAQEMBQAwYzELMAkGA1UEBhMC
# VVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjE0MDIGA1UEAxMrTWlj
# cm9zb2Z0IElEIFZlcmlmaWVkIENvZGUgU2lnbmluZyBQQ0EgMjAyMTAeFw0yNjAz
# MjYxODExMjlaFw0zMTAzMjYxODExMjlaMFoxCzAJBgNVBAYTAlVTMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKzApBgNVBAMTIk1pY3Jvc29mdCBJRCBW
# ZXJpZmllZCBDUyBBT0MgQ0EgMDQwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIK
# AoICAQDKVfrI2+gJMM/0bQ5OVKNdvOASzLbUUMvXuf+Vl7YGuofPaZHVo3gMHF5i
# nT+GMSpIcfIZ9qtXU1UG68ry8vNbQtOL4Nm30ifXpqI1+ByiAWLO1YT0WnzG7XPO
# uoTeeWsNZv5FmjxCsReBZvyzyzCyXZbu1EQfJxWTH4ebUwtAiW9rqMf9eDj/wYhi
# EfNteJV3ZFeibD2ztCHr9JhFdd97XbnCHgQoTIqc02X5xlRKtUGBa++OtHBBjiJ/
# uwBnzTkqu4FjpZjQeJtrmda+ur1CT2jflWIB/ypn7u7V9tvW9wJbJYt/H2EtJ0GO
# NWxJZ7TEu8jWPindOO3lzPP7UtzS/mVDV94HucWaltmsra6zSG8BoEJ87IM8QSb7
# vfm/O41FhYkUv89WIj5ES2O4kxyiMSfe95CMivCuYrRP2hKvx7egPMrWgDDBkxML
# grKZO9hRNUMm8vk3w5b9SogHOyJVhxyFm8aFXfIxgqDF4S0g4bhbhnzljmSlCLlu
# mMZcXFGDjpF2tNoAu3VGFGYtHtTSNVKvZpgB3b4ynaoDkbPf+Wg4523jt4VneasB
# gZhC1srZI2NCnCBBfgjLq04pqEKAWEohyW2K29KSkkHvt5VaE1ac3Yt+oyiOzMS5
# 7tXwQDJLGvLg/OXFO0VNvczDndfIfXYExB/ab2PuMSwd5VIBOwIDAQABo4IB3DCC
# AdgwDgYDVR0PAQH/BAQDAgGGMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRr
# JUHe+2t8/RiACi1/j3ZdqnM9uDBUBgNVHSAETTBLMEkGBFUdIAAwQTA/BggrBgEF
# BQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9z
# aXRvcnkuaHRtMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMBIGA1UdEwEB/wQI
# MAYBAf8CAQAwHwYDVR0jBBgwFoAU2UEpsA8PY2zvadf1zSmepEhqMOYwcAYDVR0f
# BGkwZzBloGOgYYZfaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwv
# TWljcm9zb2Z0JTIwSUQlMjBWZXJpZmllZCUyMENvZGUlMjBTaWduaW5nJTIwUENB
# JTIwMjAyMS5jcmwwfQYIKwYBBQUHAQEEcTBvMG0GCCsGAQUFBzAChmFodHRwOi8v
# d3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMElEJTIw
# VmVyaWZpZWQlMjBDb2RlJTIwU2lnbmluZyUyMFBDQSUyMDIwMjEuY3J0MA0GCSqG
# SIb3DQEBDAUAA4ICAQAG1VBeVHTVRBljlcZD3IiMxwPyMjQyLNaEnVu5mODm2hRB
# JfH8GsBLATmrHAc8F47jmk5CnpUPiIguCbw6Z/KVj4Dsoiq228NSLMLewFfGMri7
# uwNGLISC5ccp8vUdADDEIsS2dE+QI9OwkDpv3XuUD7d+hAgcLVcMOl1AsfEZtsZe
# nhGvSYUrm/FuLq0BqEGL9GXM5c+Ho9q8o+Vn/S+GWQN2y+gkRO15s0kI05nUpq/d
# OD4ri9rgVs6tipEd0YZqGgD+CZNiaZWrDTOQbNPncd2F9qOsUa20miYruoT5PwJA
# aI+QQiTE2ZJeMJOkOpzhTUgqVMZwZidEUZKCqudaeQA08WwnkQMfKyHzaU8j48UL
# cU4hUwvMsv7fSurOe9GAdRQCPvF8WcSK5oDHe8VVJM4tv6KKCm91HqLx9JamBgRI
# 6R2SfY3nu26EGznu0rCg/769z8xWm4PVcC2ZaL6VlKVqFp1NsN8YqMyf5t+bbGVb
# 09noFKcJG/UwyGlxRmQBlfeBUQx5/ytlzZzsEnhrJF9fTAfje8j3OdX5lEnePTFQ
# LRlvzZFBqUXnIeQKv3fHQjC9m2fo/Z01DII/qp3d8LhGVUW0BCG04fRwHJNH8iqq
# CG/qofMv+kym2AxBDnHzNgRjL60JOFiBgiurvLhYQNhB95KWojFA6shQnggkMTCC
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
# aC1ZOmBXiCRKJLj4DT2uhJ04ji+tHD6n58vhavFIrmcxghcxMIIXLQIBATBxMFox
# CzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKzAp
# BgNVBAMTIk1pY3Jvc29mdCBJRCBWZXJpZmllZCBDUyBBT0MgQ0EgMDQCEzMABJ/9
# xC9vieG6G/IAAAAEn/0wDQYJYIZIAWUDBAIBBQCgXjAQBgorBgEEAYI3AgEMMQIw
# ADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAvBgkqhkiG9w0BCQQxIgQgF42J
# Qf1sSw1wEajgU4/ZE/O5rbHZ4X8sMZVPuf3/ZEcwDQYJKoZIhvcNAQEBBQAEggGA
# IOLwsoXHKX0G3tPSwEzyBpVJSzxMAbPvMOFrAixG6w+jWYgw+43rXBtZqZKTZoSO
# b+17EP89hRVM9OOf2CsaLzeBiWUzLp4pqp4RphCWaWtazP0tuU8BKOG+Kmz2cA9M
# FkQ7lVWoiZ05UqFHLGlHQQwhT3mbbD4EFg2JYCpODikzoBkqQheFTb1OBU3aJz4H
# s5QS4ypWCmVr0J4TcLIX8WuU0gqQOzZQDLsw/pbrQAcp5HhZAEqWRDx/IQQnyZL4
# l486f5sGKQylsXGdZGIIVALQ0P1YuIu5uq7EtUpJLWXSaL4ajInanrHequO/KM/R
# M22MsyBwG/D97f0D3JKfsCWj/6QNAoX7Sd2DFA3wFR/oFUqhrzYWzV3VnQzjaMGk
# KpgY8+T4RNlbiXFD6o5nyVWgaDN17ek2UEEKWr0TCuwyLVVmUeTaXOm1Y6zed3DZ
# 3I290QG7Lq7O14izYjsI3ZL9Ux0PSh6XV8yCbv4UXOmqKFJhJjMvy+UO+0TCtmoW
# oYIUsTCCFK0GCisGAQQBgjcDAwExghSdMIIUmQYJKoZIhvcNAQcCoIIUijCCFIYC
# AQMxDzANBglghkgBZQMEAgEFADCCAWkGCyqGSIb3DQEJEAEEoIIBWASCAVQwggFQ
# AgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUDBAIBBQAEIPO4oBWXPP5vVkRN+heS
# 7HqTk1Oz4kYrmT7VHcVhGlelAgZqddInL9IYEjIwMjYwODExMjAzODE3Ljk3WjAE
# gAIB9KCB6aSB5jCB4zELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEtMCsGA1UECxMkTWljcm9zb2Z0IElyZWxhbmQgT3BlcmF0aW9ucyBMaW1pdGVk
# MScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046N0ExQS0wNUUwLUQ5NDcxNTAzBgNV
# BAMTLE1pY3Jvc29mdCBQdWJsaWMgUlNBIFRpbWUgU3RhbXBpbmcgQXV0aG9yaXR5
# oIIPKTCCB4IwggVqoAMCAQICEzMAAAAF5c8P/2YuyYcAAAAAAAUwDQYJKoZIhvcN
# AQEMBQAwdzELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjFIMEYGA1UEAxM/TWljcm9zb2Z0IElkZW50aXR5IFZlcmlmaWNhdGlvbiBS
# b290IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDIwMB4XDTIwMTExOTIwMzIzMVoX
# DTM1MTExOTIwNDIzMVowYTELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFB1YmxpYyBSU0EgVGlt
# ZXN0YW1waW5nIENBIDIwMjAwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoIC
# AQCefOdSY/3gxZ8FfWO1BiKjHB7X55cz0RMFvWVGR3eRwV1wb3+yq0OXDEqhUhxq
# oNv6iYWKjkMcLhEFxvJAeNcLAyT+XdM5i2CgGPGcb95WJLiw7HzLiBKrxmDj1EQB
# /mG5eEiRBEp7dDGzxKCnTYocDOcRr9KxqHydajmEkzXHOeRGwU+7qt8Md5l4bVZr
# XAhK+WSk5CihNQsWbzT1nRliVDwunuLkX1hyIWXIArCfrKM3+RHh+Sq5RZ8aYyik
# 2r8HxT+l2hmRllBvE2Wok6IEaAJanHr24qoqFM9WLeBUSudz+qL51HwDYyIDPSQ3
# SeHtKog0ZubDk4hELQSxnfVYXdTGncaBnB60QrEuazvcob9n4yR65pUNBCF5qeA4
# QwYnilBkfnmeAjRN3LVuLr0g0FXkqfYdUmj1fFFhH8k8YBozrEaXnsSL3kdTD01X
# +4LfIWOuFzTzuoslBrBILfHNj8RfOxPgjuwNvE6YzauXi4orp4Sm6tF245DaFOSY
# bWFK5ZgG6cUY2/bUq3g3bQAqZt65KcaewEJ3ZyNEobv35Nf6xN6FrA6jF9447+NH
# vCjeWLCQZ3M8lgeCcnnhTFtyQX3XgCoc6IRXvFOcPVrr3D9RPHCMS6Ckg8wggTrt
# IVnY8yjbvGOUsAdZbeXUIQAWMs0d3cRDv09SvwVRd61evQIDAQABo4ICGzCCAhcw
# DgYDVR0PAQH/BAQDAgGGMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRraSg6
# NS9IY0DPe9ivSek+2T3bITBUBgNVHSAETTBLMEkGBFUdIAAwQTA/BggrBgEFBQcC
# ARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9zaXRv
# cnkuaHRtMBMGA1UdJQQMMAoGCCsGAQUFBwMIMBkGCSsGAQQBgjcUAgQMHgoAUwB1
# AGIAQwBBMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAUyH7SaoUqG8oZmAQH
# J89QEE9oqKIwgYQGA1UdHwR9MHsweaB3oHWGc2h0dHA6Ly93d3cubWljcm9zb2Z0
# LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMElkZW50aXR5JTIwVmVyaWZpY2F0
# aW9uJTIwUm9vdCUyMENlcnRpZmljYXRlJTIwQXV0aG9yaXR5JTIwMjAyMC5jcmww
# gZQGCCsGAQUFBwEBBIGHMIGEMIGBBggrBgEFBQcwAoZ1aHR0cDovL3d3dy5taWNy
# b3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBJZGVudGl0eSUyMFZl
# cmlmaWNhdGlvbiUyMFJvb3QlMjBDZXJ0aWZpY2F0ZSUyMEF1dGhvcml0eSUyMDIw
# MjAuY3J0MA0GCSqGSIb3DQEBDAUAA4ICAQBfiHbHfm21WhV150x4aPpO4dhEmSUV
# pbixNDmv6TvuIHv1xIs174bNGO/ilWMm+Jx5boAXrJxagRhHQtiFprSjMktTliL4
# sKZyt2i+SXncM23gRezzsoOiBhv14YSd1Klnlkzvgs29XNjT+c8hIfPRe9rvVCMP
# iH7zPZcw5nNjthDQ+zD563I1nUJ6y59TbXWsuyUsqw7wXZoGzZwijWT5oc6GvD3H
# DokJY401uhnj3ubBhbkR83RbfMvmzdp3he2bvIUztSOuFzRqrLfEvsPkVHYnvH1w
# tYyrt5vShiKheGpXa2AWpsod4OJyT4/y0dggWi8g/tgbhmQlZqDUf3UqUQsZaLdI
# u/XSjgoZqDjamzCPJtOLi2hBwL+KsCh0Nbwc21f5xvPSwym0Ukr4o5sCcMUcSy6T
# EP7uMV8RX0eH/4JLEpGyae6Ki8JYg5v4fsNGif1OXHJ2IWG+7zyjTDfkmQ1snFOT
# gyEX8qBpefQbF0fx6URrYiarjmBprwP6ZObwtZXJ23jK3Fg/9uqM3j0P01nzVygT
# ppBabzxPAh/hHhhls6kwo3QLJ6No803jUsZcd4JQxiYHHc+Q/wAMcPUnYKv/q2O4
# 44LO1+n6j01z5mggCSlRwD9faBIySAcA9S8h22hIAcRQqIGEjolCK9F6nK9ZyX4l
# hthsGHumaABdWzCCB58wggWHoAMCAQICEzMAAABbSrWNQTJt3HQAAAAAAFswDQYJ
# KoZIhvcNAQEMBQAwYTELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFB1YmxpYyBSU0EgVGltZXN0
# YW1waW5nIENBIDIwMjAwHhcNMjYwMTA4MTg1OTA1WhcNMjcwMTA3MTg1OTA1WjCB
# 4zELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEtMCsGA1UECxMk
# TWljcm9zb2Z0IElyZWxhbmQgT3BlcmF0aW9ucyBMaW1pdGVkMScwJQYDVQQLEx5u
# U2hpZWxkIFRTUyBFU046N0ExQS0wNUUwLUQ5NDcxNTAzBgNVBAMTLE1pY3Jvc29m
# dCBQdWJsaWMgUlNBIFRpbWUgU3RhbXBpbmcgQXV0aG9yaXR5MIICIjANBgkqhkiG
# 9w0BAQEFAAOCAg8AMIICCgKCAgEAkFTMFtueUNd57QHQoPkbj/jvm2EXJ9y0LK4R
# JNZBe+UuLhbH+13apR16riJ156DpVaGI4d+7fAlXhNQZJG2qH0JyvUGaIEq/2K4W
# mAfIgG7lDHfxmzHCUV5dVL5mokkqddFsM1B1xhKgL/pzSFAn88fnQMFENCQ9dXDI
# WLMutEf0CWsl5SDsEp5PbfN+1Lz8o4ku8QRsc4XqlI5jdlWmtlRZtaNbBFOagdpD
# 8Ty+ta0s3IQn5vTz1VbUiStre3gZMHlZvLcIvUrbNicDEEi9p+wowXKP065cdxM8
# owOgVIx5qYb0wo4xvq6gbU+N2cOCws/oQ4xFLOssvuMQPWZsH1FJ31+G3L4dCvq9
# mCwGfqhTL5hOk1UuyTB21QzzZZgCQ/O2U63cCIvSrJXv9TeP+6re8cyM8zTDTfjQ
# zns16LSDgEJwy3R1uqhz3VWAJvf/fqwdAA2ie2fUc4XaguTzX3RBFLjeKwdWtrwf
# yx/n4aWohixiIIpfTgdmI7NlbzbqdUjp377yXJN5aamP3RRr249smFWPATeiHq07
# nXTJKqZIxIsQ3Tuncht7cToEBvbD3etbNvbr52lK2FsoXiQCmh+oGxY9fgwS0cpI
# 5+0+ZVMJDju2CGtW4eJr2Nj4eyPTWbgpbha2SZWbcvqExkQIxriyMzEBfP5tf8Am
# FZN7pNkCAwEAAaOCAcswggHHMB0GA1UdDgQWBBTv8upSVZZiFcl1fCBgrHhvwa/S
# tjAfBgNVHSMEGDAWgBRraSg6NS9IY0DPe9ivSek+2T3bITBsBgNVHR8EZTBjMGGg
# X6BdhltodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3Nv
# ZnQlMjBQdWJsaWMlMjBSU0ElMjBUaW1lc3RhbXBpbmclMjBDQSUyMDIwMjAuY3Js
# MHkGCCsGAQUFBwEBBG0wazBpBggrBgEFBQcwAoZdaHR0cDovL3d3dy5taWNyb3Nv
# ZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBQdWJsaWMlMjBSU0ElMjBU
# aW1lc3RhbXBpbmclMjBDQSUyMDIwMjAuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0l
# AQH/BAwwCgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQDAgeAMGYGA1UdIARfMF0wUQYM
# KwYBBAGCN0yDfQEBMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0
# LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTAIBgZngQwBBAIwDQYJKoZI
# hvcNAQEMBQADggIBAAAf7N35cqHg7FdgxYWa2CKVcBAZy06MJQHXD+4GIL85dwfc
# hrj9dt1SErMVtqJNsgTq9hkp3Wni7uco4uRrDKYAxXK47stKXqssq21kjIuFaNMr
# TNc7PS7jEur35tG0EQom8DqwPmcnAfUg7rPViLPK4hGhqUwKdutSLF9bFCfhMCY3
# u326T5fYVROERrd7DNHCG0b7HBoBssyTFGZHbgmd9d3VXEqj3T6btbO6i/3pS6DH
# nBl17CIgibVlZOPiUIke6nrv0tw5ru0DEkyKlVpKW1Af1+b1M4pzOV/G1a4FwtTh
# 25l+rCCwguwfs8yRxfXPBDNAPTIC0+GdjP0o0bXbltf6KKU57VLxEeq/ZtsGkylq
# jiRxS9Ajp0yApG8WabV4tuFI05CmUMxMYPW01V00aQj3qNS762uhSNYwyLjpNB8E
# AfG0NOlGEi7/zu8BVDxnpEeEXF6zPgR3klOFohBEDLoZw78mT5DMPOhnRqtEiQiw
# YnutmA5UCPH1y1/DyUf1F+NzAHfB0YFg0w1UmpClRqLZNp11/mlfNNkQciosQXnd
# KsGMh4iehCs/tTlWVeIxCzF7At0g2sATaXZNHcoGKRv5FBHKBtOnyOPbKILQ0JTA
# b4r6d2CU3lExteMVbpoprn1er5vxfMr8Mr4Am2A6keAm/xCuTrYD63A5Us6mMYID
# 1DCCA9ACAQEweDBhMQswCQYDVQQGEwJVUzEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUHVibGljIFJTQSBUaW1lc3Rh
# bXBpbmcgQ0EgMjAyMAITMwAAAFtKtY1BMm3cdAAAAAAAWzANBglghkgBZQMEAgEF
# AKCCAS0wGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEi
# BCCipVbuqNUl2ZBRDxSSS4GsvMEyP8+vJSfc+mCTqvhWSzCB3QYLKoZIhvcNAQkQ
# Ai8xgc0wgcowgccwgaAEIC8xA1VdnRvTHGUbDxf/cgTJs5u5PprlbV3rUJb5wYPv
# MHwwZaRjMGExCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9y
# YXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBQdWJsaWMgUlNBIFRpbWVzdGFtcGlu
# ZyBDQSAyMDIwAhMzAAAAW0q1jUEybdx0AAAAAABbMCIEICgrB/vzMvUsuYrq84ZT
# 8TOCA29Hl10vfWwddGM3YPEWMA0GCSqGSIb3DQEBCwUABIICAAW9mhuzV3dSnDOo
# qVYcO4U7HEPELDFNAE7chrhW17OyMYo2uOAOH1M4H7GEmwyE+fPU1Sz8VPpfdSUg
# OhRNUGmLJA34/SxyYLV/lRaoUBFHN7s0Vaus3wRK+hgqqlJMQwAmp7cTOZXdW+zB
# xG10ugvFNMyLxXiC6jrd87oeYzqrRujUgh4SoXRaFy/3X729E3rZQ2sg+I3Dunvf
# 5gx8u/v9/F3CHW6CIgUQ33Wj6LkPcguFrHmeC67atvEBW7YphGHU81BDocRrft0V
# lVI5JPmbZbpejrtIHtgHcz+Qj0iuWUKizkzSpZXUTCzdup2F2CnjNl/3co0xhhVX
# 2lD2b1eLw3TTB43DB9sZyLA/t6XEA9MR57O0q5cOnf/0PxxavXqB2aN+HfcEaexT
# 2n9tiyvqI1OZs+0lj18z3BZjkPwgjY6Df7VVhJEsdDcQ3DVLu2REISPyYhMkDHSs
# smc9AAEzPBOkhOraM9XTkHuLzpSd9J5zltf9/3+CG2VC5ye11UG0gQEIMeYk/wtF
# qweBtEGkFvHHVj2rcBJLRuK9/PX5KNSofXCi+Sy3rYilryARLk/wtLOitpGAOeDs
# Km9FGbifny+iSt5rQMGL5N3wwGVUCR4rRPRGJdWyUsL3VaBIQBlNAFyKxn0Ja5dV
# fgEIH+UMQbHS8tbuszzFb4bXpjsV
# SIG # End signature block
