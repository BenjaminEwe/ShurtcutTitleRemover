param(
    [String]$commandToRun
)

Set-StrictMode -Version Latest

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$username = $env:USERNAME
$sourceFolderUser = "C:\Users\$username\Desktop"
$destinationFolderUser = "C:\Users\$username\.DesktopBackup"
$sourceFolderPublic = "C:\Users\Public\Desktop"
$destinationFolderPublic = "C:\Users\Public\.DesktopBackup"

# Precon:   None
# Input:    Desktop to check
# Output:   Array of all shortcuts (.lnk and .url)
# Note:     Finds all shortcuts in a given folder and adds them to array. 
Function Get-Shortcuts {
    param (
        [String]$folderToBackup
    )
    $FolderItemArr = Get-ChildItem -Path $folderToBackup
    $shortcutArr = [System.Collections.ArrayList]::new()

    Write-Debug "List of items found in folder $folderToBackup `n $FolderItemArr"

    foreach ($item in $FolderItemArr) {
        if ($item.Extension -in @(".lnk", ".url")) {
            $shortcutArr.Add($item) | Out-Null
        }
    }
    Write-Debug "Shortcuts array produced. List of items in the `$shortcutArr"
    foreach ($item in $shortcutArr) {
        Write-Debug $item
    }

    return $shortcutArr
}

# Precon:   (Hard) Make-BackupFolder must have been run to ensure the backupfolder exists
# Input:    Array of shortcuts, destination to backup to
# Note:     This finds all the shortcuts in the arrays whose names are *not* just spaces, and makes a backup copy of them @ backupDest.
Function Backup-Shortcuts {
    param (
        [array]$shortcutArr,
        [string]$backupDest
    )

    foreach ($file in $shortcutArr) {
        Write-Debug "Backing up $file"
        if (!($file.BaseName -match '^ +$')) {
            Write-Debug "$file seems to be a real name, backing up the shortcut"
            Copy-Item -Path $file.FullName -Destination $backupDest
        }
    }

    Write-Debug "Shortcuts have been backed up to $backupDest"
}

# Precon:   (soft) Shortcuts should be backed up first if backups are desired
# Input:    Array of all shortcuts to be renamed
# Note:     Renames all the shortcuts to increasingly long empty names.
Function Rename-Shortcuts {
    param (
        [array]$shortcutArr,
        [String]$folderToBackup
    )

    # First renames shortcuts to name that is improbable to already exist to avoid conflicts.
    $shortcutCnt = 0;
    foreach ($file in $shortcutArr) {
        Write-Debug "renaming $file"
        $shortcutCnt++
        Rename-Item -Path $file.FullName -NewName ("RESERVED_BY_SHORTCUT-NAME-HIDER-" + $shortcutCnt + $file.Extension)
    }
    Write-Debug "Shortcuts have been renamed to temporary strings"


    $shortcutArr = Get-Shortcuts -folderToBackup $folderToBackup # Build new array of the newly renamed shortcuts

    $urlCnt = 0; $lnkCnt = 0;
    foreach ($file in $shortcutArr) {
        Write-Debug "renaming $file"
        if ($file.Extension -eq ".lnk") {
            $lnkCnt++
            Rename-Item -Path $file.FullName -NewName ((" " * $lnkCnt) + $file.Extension)

        } elseif ($file.Extension -eq ".url") {
            $urlCnt++
            Rename-Item -Path $file.FullName -NewName ((" " * $urlCnt) + $file.Extension)
        }
    }
    Write-Debug "Shortcuts have been renamed to empty strings"
}

Function Elevate {
    # Takes in an input so that script knows which function to auto-execute after restart
    param (
        [String]$commandToRestart
    )
    
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Verbose "Not running as administrator. Restarting with elevation..." -Verbose
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -commandToRun $commandToRestart"
        exit
    }
}

Function Make-BackupFolder {
    param (
        [string]$folderToBackup
    )
    # Ensure backup folder exists, make new if not
    if (!(Test-Path $folderToBackup)) { 
        New-Item -Path $folderToBackup -ItemType Directory | Out-Null
        $folder = Get-Item -Path $folderToBackup 
        $folder.Attributes = "Hidden"
        Write-Debug "Created backup folder: $folderToBackup"
    } else {
        Write-Debug "Backup folder already exists: $folderToBackup"
    }
}

Function Remove-Icon {
    # Define blank icon 
    $imageBase64 = "AAABAAEAEBAAAAEAIABoBAAAFgAAACgAAAAQAAAAIAAAAAEAIAAAAAAAQAQAAAAAAAAAAAAAAAAAAAAAAAD//wECAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAf/8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAA=="
    $imageFolderLocation = "C:\ProgramData\ShortcutHider"
    $imageFileLocation = $imageFolderLocation + "\BlankIconForHidingShortcutArrow.ico"
    $registryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons" # Registry path for shortcut icon
    $registryPropertyName = '29' # The property for the shortcut icon - magic number is MSFT's choice
    $registryPropertyType = 'String' # Property type

    # test if image file exists, otherwise create it
    if (Test-Path $imageFileLocation){
        Write-Debug "Icon already exists"
    } else {
        Write-Debug "Will save the needed icon at $imageFileLocation"
        New-Item -Path $imageFolderLocation -ItemType Directory | Out-Null

        #Decode Base64 to directory
        $bytes = [Convert]::FromBase64String($imageBase64)
        [System.IO.File]::WriteAllBytes($imageFileLocation, $bytes)
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
        # finds if there already is a value named 29
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

Function Remove-Recycling-Bin {
    if((Test-Path -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\NonEnum) -eq $false) {
        New-Item -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies -Name "NonEnum"
    }
    Set-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\NonEnum -Name "{645FF040-5081-101B-9F08-00AA002F954E}" -Value 1 -Type DWord
    Restart-Explorer
    Write-Debug "Recycling bin has been hidden from desktop"
}

Function Restore-RecyclingBin {
    # Put recycling bin on desktop
    if (Test-Path -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\NonEnum) {
        Remove-Item -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\NonEnum
    }
    
    # Restore the name of the recycling bin
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CLSID\{645FF040-5081-101B-9F08-00AA002F954E}" -Name *

    Restart-Explorer
    Write-Debug "Recycling Bin has been restored"
}

Function Rename-RecyclingBin {
    $recyclingPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CLSID\{645FF040-5081-101B-9F08-00AA002F954E}"
    if(Test-Path -Path $recyclingPath) {
        Set-ItemProperty -Path $recyclingPath -Name "(Default)" -Value " " -Force | Out-Null
        Restart-Explorer
        Write-Debug "Recycling bin has been renamed"
    } else {
        Write-Warning "Something seems to be wrong. Either the script is outdated or there are some weird problems with your recycling bin"
    }
}

Function Restore-IconNames {
    $shortcutsUser = Get-Shortcuts -folderToBackup $destinationFolderUser
    $shortcutsPublic = Get-Shortcuts -folderToBackup $destinationFolderPublic

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

    $shortcutArrUser = Get-Shortcuts -folderToBackup $sourceFolderUser
    foreach ($file in $shortcutArrUser) {
        if ($file.BaseName -match '^ +$') {
            Write-Debug "Removing $file with empty name from desktop"
            Move-Item -Path $file.FullName -Destination $destinationFolderUser -Force
        }
    }

    if ($isAdmin) {
        $shortcutArrPublic = Get-Shortcuts -folderToBackup $sourceFolderPublic
        foreach ($file in $shortcutArrPublic) {
            if ($file.BaseName -match '^ +$') {
                Write-Debug "Removing $file with empty name from desktop"
                Move-Item -Path $file.FullName -Destination $destinationFolderPublic -Force
            }
        }
        Write-Debug "Empty-named shortcuts have been removed from desktop"
    }
}

Function Restart-Explorer {
    Write-Host "The windows explorer will need to be restarted for changes to take effect. `n Press Y to restart now, or N to restart later manually."
    $response = Read-Host "(Y/N)"
    if ($response -eq "Y" -or $response -eq "y") {
        Stop-Process -Name explorer -Force
        Start-Sleep -Milliseconds 200
        if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) {
            Start-Process explorer
        }
    } else {
        Write-Host "Changes will take effect next time you reboot your computer."   
    }
}

$fullLineLength = 69
Function Print-MenuLine {
    param (
        [string]$line,
        [boolean]$adminNotice,
        [int]$subLevel
    )
    $thisLineLength = $fullLineLength - $line.Length
    Write-Host " ║ " -NoNewLine
    while ($subLevel -gt 0) {
        $subLevel--
        Write-Host (" " * 2) -NoNewline
        $thisLineLength -= 2
    }

    Write-Host $line -NoNewLine
    if ($adminNotice -and -not $isadmin) {
        Write-Host " [Admin]" -NoNewline -ForegroundColor DarkYellow
        $thisLineLength -= 8
    }
    Write-Host (" " * $thisLineLength) -NoNewline
    Write-Host "║"
}

function Show-Menu {
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
    Print-MenuLine
    Print-MenuLine -line "Options marked with 🌐 affect all users of this computer"
    Print-MenuLine -line ""
    Print-MenuLine -line "Icon Names:"
    Print-MenuLine -line "A1 - Remove all icon names 🌐" -subLevel 1 -adminNotice $true
    Print-MenuLine -line "A2 - Remove personal desktop icon names" -subLevel 1
    Print-MenuLine
    Print-MenuLine -line "Shortcut Arrow:"
    Print-MenuLine -line "B  - Remove shortcut arrow 🌐" -subLevel 1 -adminNotice $true
    Print-MenuLine
    #Print-MenuLine -line "UAC Shield:"
    #Print-MenuLine -line "C1 - Remove UAC shield from shortcuts 🌐?" - $subLevel 1 -adminNotice $true
    #Print-MenuLine
    Print-MenuLine -line "Recycle Bin:"
    Print-MenuLine -line "D1 - Remove Recycle Bin name" -subLevel 1
    Print-MenuLine -line "D2 - Remove Recycle Bin shortcut" -subLevel 1
    Print-MenuLine
    Print-MenuLine -line "Restore Defaults:"
    Print-MenuLine -line "U1 - Restore shortcut arrow 🌐" -subLevel 1 -adminNotice $true
    Print-MenuLine -line "U2 - Restore Recycle Bin" -subLevel 1
    Print-MenuLine -line "U3 - Restore Icon names" -subLevel 1
    Print-MenuLine
    Print-MenuLine -line "0  - Exit"
    Write-Host " ╚══════════════════════════════════════════════════════════════════════╝"
}


do {
    if ((Test-Path variable:commandToRun) -and ($commandToRun -ne "")) {
        Write-Host "$commandToRun"
        $switchInput = $commandToRun
        $commandToRun = ""
    } else {
        Show-Menu
        $switchInput = Read-Host "Select an option"
        Clear-Host
    }

    switch ($switchInput)
    {
        0 {exit}
        A1 { 
            Elevate -commandToRestart "A1"

            $shortcutsUser = Get-Shortcuts -folderToBackup $sourceFolderUser
            $shortcutsPublic = Get-Shortcuts -folderToBackup $sourceFolderPublic
            Make-BackupFolder -folderToBackup $destinationFolderUser
            Make-BackupFolder -folderToBackup $destinationFolderPublic
            Backup-Shortcuts -shortcutArr $shortcutsUser -backupDest $destinationFolderUser
            Backup-Shortcuts -shortcutArr $shortcutsPublic -backupDest $destinationFolderPublic
            Rename-Shortcuts -shortcutArr $shortcutsUser -folderToBackup $sourceFolderUser
            Rename-Shortcuts -shortcutArr $shortcutsPublic -folderToBackup $sourceFolderPublic
        }
        A2 {
            $shortcutsUser = Get-Shortcuts -folderToBackup $sourceFolderUser
            Make-BackupFolder -folderToBackup $destinationFolderUser
            Backup-Shortcuts -shortcutArr $shortcutsUser -backupDest $destinationFolderUser
            Rename-Shortcuts -shortcutArr $shortcutsUser -folderToBackup $sourceFolderUser
        }
        B {
            Elevate -commandToRestart "B"

            Remove-Icon
            Restart-Explorer
        }
        D1 {Rename-RecyclingBin}
        D2 {Remove-Recycling-Bin}
        U1 {
            Elevate -commandToRestart "U1"

            if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons") {
                Remove-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons"
                Restart-Explorer
            } else {
                Write-Host "The icon should already be back. Try restarting the computer if it is still missing"
            }
        }
        U2 {Restore-RecyclingBin}
        U3 {Restore-IconNames}
    }
} while ($true)