<#
.SYNOPSIS
A script to allow user to hide shortcut names on desktop, hide shortcut arrows, and hide/rename recycle bin.

.DESCRIPTION
This PowerShell script provides a menu-driven interface to hide shortcut names on the desktop by renaming them to empty strings, 
thereby making them appear not to have names. 
It also allows hiding the shortcut arrow overlay on shortcut icons by modifying the Windows registry to use a blank icon. 
Additionally, the script can hide or rename the Recycle Bin on the desktop. 
The script supports backing up original shortcut names before renaming, and restoring them later if needed. 
Some operations require administrator privileges.

.EXAMPLE
    PS C:\> .\ShortcutNameHider.ps1

.NOTES
    Author: Benjamin Ewe
    Date: November 2025
    Version: 2.0
    Script Purpose: Declutter user desktop
    Dependencies: None
    Target Platform: Windows PowerShell 5.1 or later

.LINK
    License: MIT
    https://opensource.org/license/MIT
    Source Code:
    https://github.com/BenjaminEwe/ShortcutTitleRemover

#>


param(
    [string]$commandToRun
)

Set-StrictMode -Version Latest

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$username = $env:USERNAME

$sourceFolderUser = [Environment]::GetFolderPath('Desktop')
$destinationFolderUser = Join-Path (Split-Path $sourceFolderUser -Parent) '.DesktopBackup'

$sourceFolderPublic = [System.Environment]::GetFolderPath('CommonDesktopDirectory')
$destinationFolderPublic = Join-Path (Split-Path $sourceFolderPublic -Parent) '.DesktopBackup'

<#
.SYNOPSIS
Finds all files of type .url or .lnk from parameter folder

.DESCRIPTION
Scans the specified folder for shortcut files (.lnk and .url extensions) and returns them as an array.

.PARAMETER path
A string path to the folder to find shortcuts in

.OUTPUTS
System.Array
An array of shortcut file objects from parameter folder.

.EXAMPLE
$shortcuts = Get-Shortcuts C:\Path\To\Folder

.NOTES
Only returns files with .lnk or .url extensions.
#>
function Get-Shortcuts {
    param (
        [string]$path
    )
    $folderItemArr = Get-ChildItem -Path $path
    $shortcutArr = @()

    Write-Debug "List of items found in folder $path `n $folderItemArr"

    foreach ($item in $folderItemArr) {
        if ($item.Extension -in @(".lnk", ".url")) {
            $shortcutArr += $item
        }
    }
    Write-Debug "Shortcuts array produced. List of items in the `$shortcutArr"
    foreach ($item in $shortcutArr) {
        Write-Debug $item
    }

    return $shortcutArr
}

<#
.SYNOPSIS
Creates backup copies of shortcuts with non-empty names

.DESCRIPTION
Copies shortcuts that have real names (not just spaces) to a backup location before they are renamed.
This allows restoration later if needed.

.PARAMETER shortcutArr
Array of shortcuts to backup

.PARAMETER path
Destination folder for backup copies

.EXAMPLE
Backup-Shortcuts -shortcutArr $shortcuts -Path $destinationFolder

.NOTES
New-BackupFolder must have been called to ensure backup folder exists.
#>
function Backup-Shortcuts {
    param (
        [array]$shortcutArr,
        [string]$path
    )

    foreach ($file in $shortcutArr) {
        Write-Debug "Backing up $file"
        if (!($file.BaseName -match '^ +$')) {
            Write-Debug "$file seems to be a real name, backing up the shortcut"
            try { 
                Copy-Item -Path $file.FullName -Destination $path 
            } catch {
                Write-Warning "Failed to back up $file $_`nWill restart the script to avoid renaming any shortcuts."
                Start-Sleep -Seconds 5
                Invoke-Restart -commandToRun "ERROR_BACKUP_COPY_FAILED"
            } 
        }
    }

    Write-Debug "Shortcuts have been backed up to $path"
}

<#
.SYNOPSIS
Renames shortcuts to increasingly long empty names

.DESCRIPTION
Renames shortcuts to names consisting only of spaces. First renames to temporary names to avoid conflicts,
then renames to progressively longer space-only names. .lnk and .url files are numbered separately.

.PARAMETER shortcutArr
Array of shortcuts to rename

.PARAMETER path
Path containing the shortcuts

.EXAMPLE
Rename-Shortcuts -shortcutArr $shortcuts -Path $sourceFolder

.NOTES
Uses a two-pass approach: first to temporary names to avoid conflicts, then to space-only names.
Shortcuts ought to be backed up before renaming to allow restoration.
#>
function Rename-Shortcuts {
    param (
        [array]$shortcutArr,
        [string]$path
    )

    # First renames shortcuts to name that is improbable to already exist to avoid conflicts.
    $shortcutCnt = 0
    foreach ($file in $shortcutArr) {
        Write-Debug "renaming $file"
        $shortcutCnt++
        try {
            Rename-Item -Path $file.FullName -NewName ("RESERVED_BY_SHORTCUT-NAME-HIDER-" + $shortcutCnt + $file.Extension)
        } catch {
            Write-Warning "Failed to rename $file to temporary name: $_`nWill restart the script to abort renaming."
            Start-Sleep -Seconds 5
            Invoke-Restart -commandToRun "ERROR_RENAME_TEMP"
        }

    }
    Write-Debug "Shortcuts have been renamed to temporary strings"


    $shortcutArr = Get-Shortcuts $path # Build new array of the newly renamed shortcuts

    $urlCnt = 0; $lnkCnt = 0;
    foreach ($file in $shortcutArr) {
        try {
            Write-Debug "renaming $file"
            if ($file.Extension -eq ".lnk") {
                $lnkCnt++
                Rename-Item -Path $file.FullName -NewName ((" " * $lnkCnt) + $file.Extension)

            } elseif ($file.Extension -eq ".url") {
                $urlCnt++
                Rename-Item -Path $file.FullName -NewName ((" " * $urlCnt) + $file.Extension)
            }
        } catch {
            Write-Warning "Failed to rename $file to empty name: $_`nWill restart the script to abort renaming."
            Start-Sleep -Seconds 5
            Invoke-Restart -commandToRun "ERROR_RENAME_EMPTY"
        }
    }
    Write-Debug "Shortcuts have been renamed to empty strings"
}

<#
.SYNOPSIS
Elevates script to administrator privileges

.DESCRIPTION
Checks if the script is running with administrator privileges and restarts it elevated if not.
The script exits after relaunching with elevation.

.PARAMETER commandToRun
Command to execute after elevation. This is passed to the elevated instance.

.EXAMPLE
Invoke-Restart -commandToRun "B" -adminRestart $true

.NOTES
Uses Start-Process with -Verb RunAs to request elevation.
The calling script will exit after launching the elevated instance.
#>
function Invoke-Restart {
    param (
        [string]$commandToRun,
        [boolean]$adminRestart = $false
    )
    
    if ($adminRestart -and -not $isAdmin) {
        Write-Verbose "Not running as administrator. Restarting with elevation..." -Verbose
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -commandToRun $commandToRun"
        exit
    }
    elseif (-not $adminRestart) {
        Write-Debug "Restarting without elevation with command $commandToRun"
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -commandToRun $commandToRun"
        exit
    } else {
        Write-Debug "Already running as administrator, no need to restart"
    }
}

<#
.SYNOPSIS
Creates a hidden backup folder at specified path

.DESCRIPTION
Creates a backup folder if it doesn't exist and sets it as hidden. If the folder already exists, no action is taken.

.PARAMETER path
Path where backup folder should be created

.EXAMPLE
New-BackupFolder $destinationFolder

.NOTES
The created folder will have the Hidden attribute set.
#>
function New-BackupFolder {
    param (
        [string]$path
    )
    # Ensure backup folder exists, make new if not
    if (!(Test-Path $path)) { 
        try {
            New-Item -Path $path -ItemType Directory | Out-Null
            $folder = Get-Item -Path $path 
            $folder.Attributes = "Hidden"
        } catch {
            Write-Warning "Failed to create backup folder at $path $_`nWill restart the script to abort renaming."
            Start-Sleep -Seconds 5
            Invoke-Restart -commandToRun "ERROR_CREATE_BACKUP_FOLDER"
        }
        Write-Debug "Created backup folder: $path"
    } else {
        Write-Debug "Backup folder already exists: $path"
    }
}

<#
.SYNOPSIS
Hides the shortcut arrow by modifying registry

.DESCRIPTION
Creates or modifies registry entries to replace the shortcut arrow with a blank icon.
Creates the blank icon file if it doesn't exist. Requires administrator privileges.

.EXAMPLE
Hide-ShortcutArrow

.NOTES
Modifies HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons registry key.
Creates a blank icon at C:\ProgramData\ShortcutHider\BlankIconForHidingShortcutArrow.ico.
Requires administrator privileges.
#>
function Hide-ShortcutArrow {
    # Define blank icon 
    $imageBase64 = "AAABAAEAEBAAAAEAIABoBAAAFgAAACgAAAAQAAAAIAAAAAEAIAAAAAAAQAQAAAAAAAAAAAAAAAAAAAAAAAD//wECAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAf/8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAA=="
    $imageFolderLocation = "C:\ProgramData\ShortcutHider"
    $imageFileLocation = $imageFolderLocation + "\BlankIconForHidingShortcutArrow.ico"
    $registryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons" # Registry path for shortcut icon
    $registryPropertyName = '29' # The number for the shortcut arrow.
    $registryPropertyType = 'String' # Property type

    # Test if image file exists, otherwise create it
    if (Test-Path $imageFileLocation){
        Write-Debug "Icon already exists"
    } else {
        Write-Debug "Will save the needed icon at $imageFileLocation"
        try {
            New-Item -Path $imageFolderLocation -ItemType Directory | Out-Null
            #Decode Base64 to directory
            $bytes = [Convert]::FromBase64String($imageBase64)
            [System.IO.File]::WriteAllBytes($imageFileLocation, $bytes)
        } catch {
            Write-Warning "Failed to create icon or folder at $imageFolderLocation $_`nWill restart the script to abort renaming."
            Start-Sleep -Seconds 5
            Invoke-Restart -commandToRun "ERROR_CREATE_ICON"
        }
    }

    if (!(Test-path $registryPath)){ # In this case, the Shell-Icons key does not exist. The Key is created, and then the value is created.
        New-Item -Path $registryPath | Out-Null

        $newItemProperty = @{
            Path = $registryPath
            Name = $registryPropertyName
            PropertyType = $registryPropertyType
            Value = $imageFileLocation
        }
        New-ItemProperty @newItemProperty | Out-Null
    } elseif ((Get-Item -Path $registryPath).GetValueNames() -Contains "29") { # In this case the Shell-Icons key exists and does have a key named 29. it is modified to the new value.
        Set-ItemProperty -Path $registryPath -Name $registryPropertyName -Value $imageFileLocation -Force | Out-Null
    }
    else { # in this case the Shell-Icons key exists, but no string named 29 exists. A new one is then created
        $newItemProperty = @{
            Path = $registryPath
            Name = $registryPropertyName
            PropertyType = $registryPropertyType
            Value = $imageFileLocation
        }
        New-ItemProperty @newItemProperty | Out-Null
    }
}

<#
.SYNOPSIS
Restores the default shortcut arrow

.DESCRIPTION
Removes the registry modifications that hide the shortcut arrow, restoring Windows default behavior.
Requires administrator privileges and triggers an Explorer restart.

.EXAMPLE
Restore-ShortcutArrow

.NOTES
Removes "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons" value 29.
Requires administrator privileges.
#>
function Restore-ShortcutArrow {
    Invoke-Restart -commandToRun "U1" -adminRestart $true

    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons") {
        $props = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons"
        if ($props.PSObject.Properties.Name -contains "29") {
            Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons" -Name "29"
            Restart-Explorer
            break
        }
    }
    Write-Host "The icon should already be back. Try restarting the computer if it is still missing"
}

<#
.SYNOPSIS
Hides the Recycle Bin from the desktop

.DESCRIPTION
Creates or modifies registry entries to hide the Recycle Bin icon from the desktop.
Triggers an Explorer restart for changes to take effect.

.EXAMPLE
Hide-RecycleBin

.NOTES
Modifies HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\NonEnum registry key.
Changes take effect after Explorer is restarted.
#>
function Hide-RecycleBin {
    if((Test-Path -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\NonEnum) -eq $false) {
        New-Item -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies -Name "NonEnum" | Out-Null
    }
    Set-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\NonEnum -Name "{645FF040-5081-101B-9F08-00AA002F954E}" -Value 1 -Type DWord
    Restart-Explorer
    Write-Debug "Recycle bin has been hidden from desktop"
}

<#
.SYNOPSIS
Restores the Recycle Bin to the desktop

.DESCRIPTION
Removes registry modifications that hide the Recycle Bin and restores its default name.
Triggers an Explorer restart for changes to take effect.

.EXAMPLE
Restore-RecycleBin

.NOTES
Removes HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\NonEnum registry key to show the recycle bin.
Also restores default name by resetting HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CLSID\{645FF040-5081-101B-9F08-00AA002F954E}.
#>
function Restore-RecycleBin {
    if (Test-Path -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\NonEnum) {
        Remove-Item -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\NonEnum
    }
    
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CLSID\{645FF040-5081-101B-9F08-00AA002F954E}" -Name *

    Restart-Explorer
    Write-Debug "Recycle Bin has been restored"
}

<#
.SYNOPSIS
Renames the Recycle Bin to a space

.DESCRIPTION
Modifies the registry to change the Recycle Bin display name to a single space character.
Triggers an Explorer restart for changes to take effect.

.EXAMPLE
Rename-RecycleBin

.NOTES
Modifies HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CLSID\{645FF040-5081-101B-9F08-00AA002F954E} registry key.
#>
function Rename-RecycleBin {
    $recycleBinPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CLSID\{645FF040-5081-101B-9F08-00AA002F954E}"
    if(Test-Path -Path $recycleBinPath) {
        Set-ItemProperty -Path $recycleBinPath -Name "(Default)" -Value " " -Force | Out-Null
        Restart-Explorer
        Write-Debug "Recycle bin has been renamed"
    } else {
        Write-Warning "Something seems to be wrong. Either the script is outdated or there are some weird problems with your recycle bin"
    }
}

<#
.SYNOPSIS
Restores original shortcut names from backup

.DESCRIPTION
Copies backed-up shortcuts with their original names from the backup folder back to the desktop.
Removes shortcuts with space-only names from the desktop and moves them to backup.
Can restore both user and public desktop shortcuts if running as administrator.

.EXAMPLE
Restore-ShortcutNames

.NOTES
Restores from hidden backup folders: .DesktopBackup
Public desktop restoration requires administrator privileges.
#>
function Restore-ShortcutNames {
    if (Test-Path $destinationFolderUser) {
        Write-Debug "Backup folder for user desktop found"
        $shortcutsUser = Get-Shortcuts $destinationFolderUser
    } else {
        $shortcutsUser = @()
        Write-Warning "No backup folder found for user desktop. Cannot restore shortcut names."
    }
    
    if ((Test-Path $destinationFolderPublic) -and $isAdmin) {
        Write-Debug "Backup folder for public desktop found"
        $shortcutsPublic = Get-Shortcuts $destinationFolderPublic
    } else {
        $shortcutsPublic = @()
        if (-not $isAdmin) {
            Write-Warning "Not running as administrator, cannot restore public desktop shortcuts.`nIf public desktop shortcuts have not been modified, this is fine."
        } else {
            Write-Warning "No backup folder found for public desktop. Cannot restore shortcut names.`nIf public desktop shortcuts have not been modified, this is fine."
        }
    }

    foreach ($file in $shortcutsUser) {
        Write-Debug "Restoring $file"
        Copy-Item -Path $file.FullName -Destination "C:\Users\$username\Desktop" -Force
    }

    foreach ($file in $shortcutsPublic) {
        Write-Debug "Restoring $file"
        Copy-Item -Path $file.FullName -Destination "C:\Users\Public\Desktop" -Force
    }

    Write-Debug "Icons have been restored from backup"

    # Find all shortcuts on current desktop with entirely space names and move them to the backup folder

    $shortcutArrUser = Get-Shortcuts $sourceFolderUser
    foreach ($file in $shortcutArrUser) {
        if ($file.BaseName -match '^ +$') {
            Write-Debug "Removing $file with empty name from desktop"
            Move-Item -Path $file.FullName -Destination $destinationFolderUser -Force
        }
    }

    if ($isAdmin) {
        $shortcutArrPublic = Get-Shortcuts $sourceFolderPublic
        foreach ($file in $shortcutArrPublic) {
            if ($file.BaseName -match '^ +$') {
                Write-Debug "Removing $file with empty name from desktop"
                Move-Item -Path $file.FullName -Destination $destinationFolderPublic -Force
            }
        }
        Write-Debug "Empty-named shortcuts have been removed from desktop"
    }
}

<#
.SYNOPSIS
Restarts Windows Explorer process

.DESCRIPTION
Prompts the user to restart Windows Explorer to apply changes. If the user agrees,
stops the explorer.exe process and restarts it if it doesn't automatically restart.

.EXAMPLE
Restart-Explorer

.NOTES
Explorer typically restarts automatically, but this function ensures it does if needed.
Some changes require Explorer restart to be visible.
#>
function Restart-Explorer {
    Write-Host "The windows explorer will need to be restarted for changes to take effect. `n Press Y to restart now, or N to restart later manually."
    $response = Read-Host "(Y/N)"
    if ($response -eq "Y" -or $response -eq "y") {
        Stop-Process -Name explorer -Force
        Start-Sleep -Milliseconds 400
        if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) {
            Start-Process explorer
        }
    } else {
        Write-Host "Changes will take effect next time you reboot your computer."   
    }
}

$fullLineLength = 69

<#
.SYNOPSIS
Writes a formatted menu line

.DESCRIPTION
Outputs a single line of the menu with proper formatting, including borders, indentation,
and optional admin notices. Ensures consistent line length with padding.

.PARAMETER line
The text content to display in the menu line

.PARAMETER adminNotice
If true and not running as admin, displays [Admin] indicator

.PARAMETER subLevel
Indentation level for nested menu items (each level adds 2 spaces)

.EXAMPLE
Write-MenuLine "A1 - Remove all shortcut names" -subLevel 1 -adminNotice $true

.NOTES
Uses module-level variable $fullLineLength for consistent formatting.
#>
function Write-MenuLine {
    param (
        [string]$line,
        [boolean]$adminNotice = $false,
        [int]$subLevel = 0
    )
    $thisLineLength = $fullLineLength - $line.Length
    Write-Host " ║ " -NoNewLine
    while ($subLevel -gt 0) {
        $subLevel--
        Write-Host (" " * 2) -NoNewline
        $thisLineLength -= 2
    }

    Write-Host $line -NoNewLine
    if ($adminNotice -and -not $isAdmin) {
        Write-Host " [Admin]" -NoNewline -ForegroundColor DarkYellow
        $thisLineLength -= 8
    }
    Write-Host (" " * $thisLineLength) -NoNewline
    Write-Host "║"
}

<#
.SYNOPSIS
Displays the main menu

.DESCRIPTION
Clears the screen and displays the formatted menu with all available options.
Shows current privilege level (Administrator or Standard User) and marks options
that require elevated privileges.

.EXAMPLE
Write-Menu

.NOTES
Clears screen unless debug mode is enabled.
Menu display adjusts based on current user privileges.
#>
function Write-Menu {
    if ($DebugPreference -eq "SilentlyContinue") {
        Clear-Host
    }
    
    Write-Host ""
    Write-Host " ╔════════════════════════ ShortcutTitleRemover ════════════════════════╗" 
    Write-Host " ║ Running as: " -NoNewline -ForegroundColor Gray
    if ($isAdmin) {
        Write-Host "Administrator" -NoNewline -ForegroundColor Green
        Write-Host "                                            ║"
    } else {
        Write-Host "Standard User (some options unavailable)" -NoNewline -ForegroundColor DarkYellow
        Write-Host "                 ║"
    }
    Write-MenuLine
    Write-MenuLine "Options marked with 🌐 affect all users of this computer"
    Write-MenuLine
    Write-MenuLine "Shortcut Names:"
    Write-MenuLine "A1 - Remove all shortcut names 🌐" -subLevel 1 -adminNotice $true
    Write-MenuLine "A2 - Remove personal desktop shortcut names" -subLevel 1
    Write-MenuLine
    Write-MenuLine "Shortcut Arrow:"
    Write-MenuLine "B  - Remove shortcut arrow 🌐" -subLevel 1 -adminNotice $true
    Write-MenuLine
    #Write-MenuLine "UAC Shield:"
    #Write-MenuLine "C1 - Remove UAC shield from shortcuts 🌐?" - $subLevel 1 -adminNotice $true
    #Write-MenuLine
    Write-MenuLine "Recycle Bin:"
    Write-MenuLine "D1 - Remove recycle bin name" -subLevel 1
    Write-MenuLine "D2 - Remove recycle bin shortcut" -subLevel 1
    Write-MenuLine
    Write-MenuLine "Restore Defaults:"
    Write-MenuLine "U1 - Restore shortcut arrow 🌐" -subLevel 1 -adminNotice $true
    Write-MenuLine "U2 - Restore recycle bin" -subLevel 1
    Write-MenuLine "U3 - Restore shortcut names" -subLevel 1
    Write-MenuLine
    Write-MenuLine "0  - Exit"
    Write-Host " ╚══════════════════════════════════════════════════════════════════════╝"
}

do {
    if ($commandToRun -like "ERROR_*") {
        Write-Warning "$commandToRun"
        Write-Warning "An error occurred during the last operation. Consider opening a bug report."
        Write-Warning "Continuing to use the script may lead to unintended consequences, though no operations should have catastrophic effects."
        Start-Sleep -Seconds 10
        $commandToRun = ""
    }

    if ((Test-Path variable:commandToRun) -and ($commandToRun -ne "")) {
        Write-Host "$commandToRun"
        $switchInput = $commandToRun
        $commandToRun = ""
    } else {
        Write-Menu
        $switchInput = Read-Host "Select an option"
        if ($DebugPreference -eq "SilentlyContinue") {
            Clear-Host
        }
    }

    switch ($switchInput)
    {
        0 {exit}
        A1 { 
            Invoke-Restart -commandToRun "A1" -adminRestart $true
            $shortcutsUser = Get-Shortcuts $sourceFolderUser
            $shortcutsPublic = Get-Shortcuts $sourceFolderPublic
            New-BackupFolder $destinationFolderUser
            New-BackupFolder $destinationFolderPublic
            Backup-Shortcuts -shortcutArr $shortcutsUser -Path $destinationFolderUser
            Backup-Shortcuts -shortcutArr $shortcutsPublic -Path $destinationFolderPublic
            Rename-Shortcuts -shortcutArr $shortcutsUser -Path $sourceFolderUser
            Rename-Shortcuts -shortcutArr $shortcutsPublic -Path $sourceFolderPublic
        }
        A2 {
            $shortcutsUser = Get-Shortcuts $sourceFolderUser
            New-BackupFolder $destinationFolderUser
            Backup-Shortcuts -shortcutArr $shortcutsUser -Path $destinationFolderUser
            Rename-Shortcuts -shortcutArr $shortcutsUser -Path $sourceFolderUser
        }
        B {
            Invoke-Restart -commandToRun "B" -adminRestart $true
            Hide-ShortcutArrow
            Restart-Explorer
        }
        D1 {Rename-RecycleBin}
        D2 {Hide-RecycleBin}
        U1 {Restore-ShortcutArrow}
        U2 {Restore-RecycleBin}
        U3 {Restore-ShortcutNames}
    }
} while ($true)