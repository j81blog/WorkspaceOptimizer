# Under Windows PowerShell 5.1 $IsWindows is undefined, which silently skips the
# Authenticode tests on Windows instead of running them.
#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '..\..\public\Invoke-WindowsOptimization.ps1' | Resolve-Path | Select-Object -ExpandProperty Path
    $script:Bytes = [System.IO.File]::ReadAllBytes($script:ScriptPath)
    $script:Text = [System.IO.File]::ReadAllText($script:ScriptPath)
    $script:Lines = $script:Text -split "`r`n|`n"

    $script:SigStartIndex = ($script:Lines | Select-String -SimpleMatch '# SIG # Begin signature block' | Select-Object -First 1).LineNumber
}

Describe 'Invoke-WindowsOptimization.ps1' {

    Context 'PowerShell validity' {

        It 'parses without syntax errors' {
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $script:ScriptPath, [ref]$null, [ref]$errors)

            $errors | ForEach-Object { $_.Message } | Should -BeNullOrEmpty
        }

        It 'declares comment-based help with a synopsis' {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $script:ScriptPath, [ref]$null, [ref]$null)
            $help = $ast.GetHelpContent()

            $help | Should -Not -BeNullOrEmpty
            $help.Synopsis | Should -Not -BeNullOrEmpty
        }

        It 'declares a description' {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $script:ScriptPath, [ref]$null, [ref]$null)
            $ast.GetHelpContent().Description | Should -Not -BeNullOrEmpty
        }

        It 'stamps the same version in .NOTES and in $script:ScriptVersion' {
            # vite reads $script:ScriptVersion for the About dialog, so the two drifting
            # apart publishes a version the script itself does not report.
            $notes = [regex]::Match($script:Text, 'Version\s*:\s*(\d[\d.]*)').Groups[1].Value
            $variable = [regex]::Match($script:Text, '\$script:ScriptVersion\s*=\s*''([^'']+)''').Groups[1].Value

            $notes | Should -Not -BeNullOrEmpty
            $variable | Should -Not -BeNullOrEmpty
            $notes | Should -Be $variable
        }
    }

    Context 'Encoding and line endings' {

        It 'starts with a UTF-8 BOM' {
            # Without it PowerShell guesses the encoding, and a different guess than the
            # signer made produces different bytes.
            $script:Bytes[0..2] | Should -Be @(0xEF, 0xBB, 0xBF)
        }

        It 'uses CRLF for every line ending' {
            $bare = 0
            for ($i = 0; $i -lt $script:Bytes.Length; $i++) {
                if ($script:Bytes[$i] -eq 0x0A -and ($i -eq 0 -or $script:Bytes[$i - 1] -ne 0x0D)) {
                    $bare++
                }
            }

            # Fails if .gitattributes stops marking this file -text and autocrlf strips the CR.
            $bare | Should -Be 0 -Because 'a bare LF anywhere invalidates the signature'
        }

        It 'uses CRLF inside the signature block specifically' {
            $script:SigStartIndex | Should -Not -BeNullOrEmpty

            $sigText = ($script:Text -split '# SIG # Begin signature block')[1]
            $sigBytes = [System.Text.Encoding]::UTF8.GetBytes($sigText)
            $bare = 0
            for ($i = 0; $i -lt $sigBytes.Length; $i++) {
                if ($sigBytes[$i] -eq 0x0A -and ($i -eq 0 -or $sigBytes[$i - 1] -ne 0x0D)) {
                    $bare++
                }
            }
            $bare | Should -Be 0
        }

        It 'contains no non-ASCII characters in the code' {
            # Multi-byte characters such as the em-dash hash differently the moment any tool
            # rewrites the file without the BOM.
            $codeLines = $script:Lines[0..($script:SigStartIndex - 2)]
            $offenders = @()
            for ($i = 0; $i -lt $codeLines.Count; $i++) {
                foreach ($ch in $codeLines[$i].ToCharArray()) {
                    if ([int][char]$ch -gt 127) {
                        $offenders += "line $($i + 1): U+{0:X4} '$ch'" -f [int][char]$ch
                    }
                }
            }
            $offenders | Should -BeNullOrEmpty
        }
    }

    Context 'Authenticode signature' {

        It 'has a signature block' {
            $script:Text | Should -Match '# SIG # Begin signature block'
            $script:Text | Should -Match '# SIG # End signature block'
        }

        It 'has a signature block that decodes as base64' {
            $body = $script:Lines[$script:SigStartIndex..($script:Lines.Count - 1)] |
                Where-Object { $_ -match '^# ' -and $_ -notmatch '# SIG # (Begin|End)' } |
                ForEach-Object { $_ -replace '^# ', '' }

            { [Convert]::FromBase64String(($body -join '')) } | Should -Not -Throw
        }

        It 'verifies as Valid' -Skip:(-not $IsWindows) {
            (Get-AuthenticodeSignature $script:ScriptPath).Status | Should -Be 'Valid'
        }

        It 'carries a timestamp countersignature' -Skip:(-not $IsWindows) {
            # The signing certificate is short-lived by design, so never assert its expiry.
            # The timestamp is what keeps the signature valid past it.
            (Get-AuthenticodeSignature $script:ScriptPath).TimeStamperCertificate |
                Should -Not -BeNullOrEmpty
        }
    }
}
