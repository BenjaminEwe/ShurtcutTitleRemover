param(
    [String]$commandToRun
)

Set-StrictMode -Version Latest


$username = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name.Split("\")[-1]
$sourceFolderUser = "C:\Users\$username\Desktop"
$destinationFolderUser = "C:\Users\$username\.DesktopBackup"
$sourceFolderPublic = "C:\Users\Public\Desktop"
$destinationFolderPublic = "C:\Users\Public\.DesktopBackup"

# Precon:   None
# Input:    Desktop to check (TBD)
# Output:   Array of all shortcuts (.lnk and .url)
# Note:     Finds all shortcuts in a given folder and adds them to array. 
Function getShortcuts {
    param (
        [String]$folderToBackup
    )
    $FolderItemArr = Get-ChildItem -Path $folderToBackup
    $shortcutArr = @();

    Write-Debug "List of items found in folder $folderToBackup `n $FolderItemArr"

    foreach ($item in $FolderItemArr) {
        if ($item.Extension -eq ".lnk" -or $item.Extension -eq ".url") {
            $shortcutArr += $item
        }
    }
    Write-Debug "Shortcuts array produced. List of items in the `$shortcutArr"
    foreach ($item in $shortcutArr) {
        Write-Debug $item
    }

    return $shortcutArr
}

# Precon:   (Hard) makeBackupFolder must have been run to ensure the backupfolder exists
# Input:    Array of shortcuts, destination to backup to
# Note:     This finds all the shortcuts in the arrays whose names are *not* just spaces, and makes a backup copy of them @ backupDest.
Function backup {
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
Function rename {
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


    $shortcutArr = getShortcuts -folderToBackup $folderToBackup # Build new array of the newly renamed shortcuts

    $urlCnt, $lnkCnt = 0;
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
    # Takes in an input so that script knows wich function to auto-execute after restart
    param (
        [String]$commandToRestart
    )
    
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Verbose "Not running as administrator. Restarting with elevation..." -Verbose
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -commandToRun $commandToRestart"
        exit
    }
 }

Function makeBackupFolder {
    param (
        [string]$folderToBackup
    )
    # Ensure backup folder exists, make new if not
    if (!(Test-Path $folderToBackup)) { 
        New-Item -Path $folderToBackup -ItemType Directory | Out-Null
        Write-Debug "Created backup folder: $folderToBackup"
    } else {
        Write-Debug "Backup folder already exists: $folderToBackup"
    }
}

Function RemoveIcon {
    # Define blank icon 
    $imageBase64 = "AAABAAEAEBAAAAEAIABoBAAAFgAAACgAAAAQAAAAIAAAAAEAIAAAAAAAQAQAAAAAAAAAAAAAAAAAAAAAAAD//wECAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAf/8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAA=="
    $imageFolderLocation = "C:\ProgramData\ShortcutHider"
    $imageFileLocation = $imageFolderLocation + "\BlankIconForHidingShortcutArrow.ico"
    $registryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons" # Registry path for shortcut icon
    $registryPropertyName = '29' # The property for the shortcut icon
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

Function RemoveRecyclingBin {
    if((Test-Path -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\NonEnum) -eq $false) {
        New-Item -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies -Name "NonEnum"
    }
    Set-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\NonEnum -Name "{645FF040-5081-101B-9F08-00AA002F954E}" -Value 1 -Type DWord
    stop-process -name explorer
    Write-Debug "Recycling bin has been hidden from desktop"
}

Function RestoreRecyclingBin {
    # Put recycling bin on desktop
    if (Test-Path -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\NonEnum) {
        Remove-Item -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\NonEnum
    }
    
    # Restore the name of the recycling bin
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CLSID\{645FF040-5081-101B-9F08-00AA002F954E}" -Name *

    stop-process -name explorer
    Write-Debug "Recycling Bin has been restored"
}

Function RenameRecyclingBin {
    $recyclingPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CLSID\{645FF040-5081-101B-9F08-00AA002F954E}"
    if(Test-Path -Path $recyclingPath) {
        Set-ItemProperty -Path $recyclingPath -Name "(Default)" -Value " " -Force | Out-Null
        stop-process -name explorer
        Write-Debug "Recycling bin has been renamed"
    } else {
        Write-Warning "Something seems to be wrong. Either the script is outdated or there are some weird problems with your recycling bin"
    }
}

Function Restore-Icons {
    Write-Host "Manually copy the icons over, and delete the ones with empty names."
    if (Test-Path $destinationFolderUser) {
        explorer $destinationFolderUser
    }
    if (Test-Path $destinationFolderPublic) {
        explorer $destinationFolderPublic
    }
}

function Show-Menu {
    if ($DebugPreference -eq "SilentlyContinue") {
        Clear-Host
    }
    
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    Write-Host ""
    Write-Host " ╔════════════════════════ ShurtcutTitleRemover ════════════════════════╗" 
    Write-Host " ║ Running as: " -NoNewline -ForegroundColor Gray
    if ($isAdmin) {
        Write-Host "Administrator" -NoNewline -ForegroundColor Green
        Write-Host "                                            ║"
    } else {
        Write-Host "Standard User (some options unavailable)" -NoNewline -ForegroundColor DarkYellow
        Write-Host "                 ║"
    }
    Write-Host " ║                                                                      ║"
    Write-Host " ║ Options marked with 🌐 affect all users of this computer             ║"
    Write-Host " ║                                                                      ║"
    Write-Host " ║ Icon Names:                                                          ║"
    Write-Host " ║   A1 - Remove all icon names 🌐" -NoNewline
    if (-not $isAdmin) {
        Write-Host " [Admin]" -NoNewline -ForegroundColor DarkYellow 
        Write-Host "                              ║"
    } else {
        Write-Host "                                      ║"
    }
    Write-Host " ║   A2 - Remove personal desktop icon names                            ║"
    Write-Host " ║                                                                      ║"
    Write-Host " ║ Shortcut Arrow:                                                      ║" 
    Write-Host " ║   B  - Remove shortcut arrow 🌐" -NoNewline
    if (-not $isAdmin) { 
        Write-Host " [Admin]" -NoNewline -ForegroundColor DarkYellow
        Write-Host "                              ║"
    } else {
        Write-Host "                                      ║"
    }
    Write-Host " ║                                                                      ║"
    #Write-Host " ║ UAC Shield:                                                          ║" 
    #Write-Host " ║   C1 - Remove UAC shield from shortcuts 🌐?" -NoNewline
    #if (-not $isAdmin) { 
    #    Write-Host " [Admin]" -NoNewline -ForegroundColor DarkYellow 
    #    Write-Host "                  ║" 
    #} else {
    #    Write-Host "                          ║"
    #}
    #Write-Host " ║                                                                      ║"
    Write-Host " ║ Recycle Bin:                                                         ║" 
    Write-Host " ║   D1 - Remove Recycle Bin name                                       ║"
    Write-Host " ║   D2 - Remove Recycle Bin shortcut                                   ║"
    Write-Host " ║                                                                      ║"
    Write-Host " ║ Restore Defaults:                                                    ║" 
    Write-Host " ║   U1 - Restore shortcut arrow 🌐" -NoNewline
    if (-not $isAdmin) { 
        Write-Host " [Admin]" -NoNewline -ForegroundColor DarkYellow 
        Write-Host "                             ║"
    } else {
        Write-Host "                                     ║"
    }
    Write-Host " ║   U2 - Restore Recycle Bin                                           ║"
    Write-Host " ║   U3 - Restore Icon names                                            ║"
    Write-Host " ║                                                                      ║"
    Write-Host " ║   0  - Exit                                                          ║"
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

            $shortcutsUser = getShortcuts -folderToBackup $sourceFolderUser
            $shortcutsPublic = getShortcuts -folderToBackup $sourceFolderPublic
            makeBackupFolder -folderToBackup $destinationFolderUser
            makeBackupFolder -folderToBackup $destinationFolderPublic
            backup -shortcutArr $shortcutsUser -backupDest $destinationFolderUser
            backup -shortcutArr $shortcutsPublic -backupDest $destinationFolderPublic
            rename -shortcutArr $shortcutsUser -folderToBackup $sourceFolderUser
            rename -shortcutArr $shortcutsPublic -folderToBackup $sourceFolderPublic
        }
        A2 {
            $shortcutsUser = getShortcuts -folderToBackup $sourceFolderUser
            makeBackupFolder -folderToBackup $destinationFolderUser
            backup -shortcutArr $shortcutsUser -backupDest $destinationFolderUser
            rename -shortcutArr $shortcutsUser -folderToBackup $sourceFolderUser
        }
        B {
            Elevate -commandToRestart "B"

            RemoveIcon
            stop-process -name explorer
        }
        D1 {RenameRecyclingBin}
        D2 {RemoveRecyclingBin}
        U1 {
            Elevate -commandToRestart "U1"

            if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons") {
                Remove-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons"
                stop-process -name explorer
            } else {
                Write-Host "The icon should already be back. Try restarting the computer if it is still missing"
            }
        }
        U2 {RestoreRecyclingBin}
        U3 {Restore-Icons}
    }
} while ($true)