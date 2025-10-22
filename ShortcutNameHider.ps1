# Param needed for script to know if it has restarted itself in administrator or not.
param(
    [switch]$ElevatedRestart
)

$username = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name.Split("\")[-1]
$sourceFolderUser = "C:\Users\$username\Desktop"
$destinationFolder = "C:\Users\$username\Desktopbackup"
$sourceFolderPublic = "C:\Users\Public\Desktop"
$destinationFolderPublic = "C:\Users\Public\DesktopBackup"

# Precon:   None
# Input:    Desktop to check (TBD)
# Output:   Array of all shortcuts (.lnk and .url)
Function getShortcuts {
    # TODO: Add parameter to allow passing of multiple desktops.
    $userDesktopArr = Get-ChildItem -Path "sourceFolderUser"
    $shortcutArr = @();

    foreach ($item in $userDesktopArr) {
        if ($item.Extension -eq ".lnk" -or $item.Extension -eq ".lnk") {
            $shortcutArr += $item
        }
    }
    Write-Host "Shortcuts array produced"

    return $shortcutArr
}

# Precon:   (Hard) makeBackupFolder must have been run to ensure the backupfolder exists
# Input:    Array of shortcuts, destination to backup to
# Output:   None
Function backup {
    param (
        [array]$shortcutArr,
        [string]$backupDest
    )

    foreach ($file in $shortcutArr) {
        if (!$file.BaseName -match '^ +$') {
            Copy-Item -Path $file.FullName -Destination $destinationFolder
        }
    }

    Write-Host "Shortcuts have been backed up"
}

# Precon:   (soft) Shortcuts should be backed up first if backups are desired
# Input:    Array of all shortcuts to be renamed
# Output:   None
Function rename {
    param (
        [array]$shortcutArr
    )

    # First renames shortcuts to name that is impropable to already exist to avoid conflicts.
    $shortcutCnt = 0;
    $renamedShortcuts = @()
    foreach ($file in $shortcutArr) {
        $shortcutCnt++
        Rename-Item -Path $file.FullName -NewName ("RESERVED_BY_SHORTCUT-NAME-HIDER-" + $shortcutCnt + $file.Extension)
        $renamedShortcuts += $file
    }
    Write-Host "Shortcuts have been renamed to temporary strings"

    $shortcutArr = getShortcuts # Build new array of the newly renamed shortcuts

    # Then renames shortcuts to the final empty name
    $urlCnt, $lnkCnt = 0;
    foreach ($file in $shortcutArr) {
        if ($file.Extension -eq ".lnk") {
            $lnkCnt++
            Rename-Item -Path $file.FullName -NewName ((" " * $lnkCnt) + $file.Extension)

        } elseif ($file.Extension -eq ".url") {
            $urlCnt++
            Rename-Item -Path $file.FullName -NewName ((" " * $urlCnt) + $file.Extension)
        }
        # Note: Could be simplified to not distinguish between .url and .lnk, but this ensures we dont run out of names as fast.
    }
    Write-Host "Shortcuts have been renamed to empty strings"
}








Function Elevate {
    # Takes in an input so that script knows wich function to auto-execute after restart
    param (
        [int]$commandToRestart
    )
    
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Verbose "Not running as administrator. Restarting with elevation..." -Verbose
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -$commandToRestart"
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
        Write-Host "Created backup folder: $folderToBackup"
    } else {
        Write-Host "Backup folder already exists: $folderToBackup"
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
        Write-Host "Icon already exists"
    } else {
        Write-Host "Will save the needed icon at " $imageFileLocation
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
    Write-Host "Recycling bin has been hidden from desktop"
}

Function RestoreRecyclingBin {
    # Put recycling bin on desktop
    if(Test-Path -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\NonEnum) {
        Remove-Item -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\NonEnum
    }
    # Revert name of recycling bin - apparently powershell is incapable of this so we have to use CMD for it
    cmd /c reg delete "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\CLSID\{645FF040-5081-101B-9F08-00AA002F954E}" /ve /f
    stop-process -name explorer
    Write-Host "Recycling Bin has been restored"
}

Function RenameRecyclingBin {
    $recyclingPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CLSID\{645FF040-5081-101B-9F08-00AA002F954E}"
    if(Test-Path -Path $recyclingPath) {
        Set-ItemProperty -Path $recyclingPath -Name "(Default)" -Value " " -Force | Out-Null
        stop-process -name explorer
        Write-Host "Recycling bin has been renamed"
    } else {
        Write-Host "Something seems to be wrong. Either the script is outdated or there are some weird problems with your recycling bin"
    }
}

do {
    if (!$switchInput -or !$ElevatedRestart) {
        Write-Host "
    --Icon names-- 
    A1. Remove the names of all icons [Affects all users] [Administrator permissions needed]
    A2. Remove the names of only the icons on your personal desktop
    A3. TBD Workaround to remove all shortcut names without affecting other users [Administrator permissions needed]
    
    --Shortcut arrow--
    B1. Remove shortcut arrow [Affects all users] [Administrator permissions needed]
    B2. Remove shortcut arrow and restart explorer [Affects all users] [Administrator permissions needed]
    
    --UAC icons--
    C1. TBD Remove UAC icon from shortcuts [Affects all users] [Administrator permissions needed]
    
    --Recycling Bin--
    D1. Remove name of recycling bin
    D2. Remove recycling bin
    
    --Restore defaults--
    U1. Restore Shortcut arrow back [Affects all users] [Administrator permissions needed]
    U2. Restore Recycling bin
    
    0. exit"
        $switchInput = Read-Host "Select an option"
    }

    Clear-Host

    switch ($switchInput)
    {
        0 {exit}
        A1 { 
            Elevate -commandToRestart 1
            makeBackupFolder -folderToBackup $destinationFolder
            makeBackupFolder -folderToBackup $destinationFolderPublic
            # Find the count of already modified
            $userLongest = FindLongestFilename -location $username -path $sourceFolderUser
            $publicLongest = FindLongestFilename -location "Public" -path $sourceFolderPublic
            # Find the array of new icons
            $userNewArr = FindNew -location $username -path $sourceFolderUser
            $publicNewArr = FindNew -location "Public" -path $sourceFolderPublic
            # Split up arrays into .url and .lnk
            $lnkFilesUser = $userNewArr | Where-Object { $_.Extension -eq ".lnk" }
            $urlFilesUser = $userNewArr | Where-Object { $_.Extension -eq ".url" }
            Write-Host "Identified $($lnkFilesUser.Count) new .lnk files and $($urlFilesUser.Count) new .url files for processing in $username."
            $lnkFilesPublic = $publicNewArr | Where-Object { $_.Extension -eq ".lnk" }
            $urlFilesPublic = $publicNewArr | Where-Object { $_.Extension -eq ".url" }
            Write-Host "Identified $($lnkFilesPublic.Count) new .lnk files and $($urlFilesPublic.Count) new .url files for processing. in public"
            # Backup and rename
            BackupNRename -existingCnt $userLongest.ExistingLnkCnt -newFiles $lnkFilesUser -destinationFolder $destinationFolder
            BackupNRename -existingCnt $userLongest.ExistingUrlCnt -newFiles $urlFilesUser -destinationFolder $destinationFolder
            BackupNRename -existingCnt $publicLongest.ExistingLnkCnt -newFiles $lnkFilesPublic -destinationFolder $destinationFolderPublic
            BackupNRename -existingCnt $publicLongest.ExistingUrlCnt -newFiles $urlFilesPublic -destinationFolder $destinationFolderPublic
            
            Summary -includePublic "true"}
        A2 {
            Elevate -commandToRestart 1
            makeBackupFolder -folderToBackup $destinationFolder
            # Find the count of already modified
            $userLongest = FindLongestFilename -location $username -path $sourceFolderUser
            # Find the array of new icons
            $userNewArr = FindNew -location $username -path $sourceFolderUser
            # Split up arrays into .url and .lnk
            $lnkFilesUser = $userNewArr | Where-Object { $_.Extension -eq ".lnk" }
            $urlFilesUser = $userNewArr | Where-Object { $_.Extension -eq ".url" }
            Write-Host "Identified $($lnkFilesUser.Count) new .lnk files and $($urlFilesUser.Count) new .url files for processing in $username."
            # Backup and rename
            BackupNRename -existingCnt $userLongest.ExistingLnkCnt -newFiles $lnkFilesUser -destinationFolder $destinationFolder
            BackupNRename -existingCnt $userLongest.ExistingUrlCnt -newFiles $urlFilesUser -destinationFolder $destinationFolder
            Summary -includePublic "false"}
        A3 {}
        B1 {RemoveIcon}
        B2 {RemoveIcon; stop-process -name explorer}
        C1 {}
        D1 {RenameRecyclingBin}
        D2 {RemoveRecyclingBin}
        U1 {
            if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons") {
                Remove-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons"
                stop-process -name explorer
            } else {
                Write-Host "The icon should already be back. Try restarting the computer if it is still missing"
            }
        }
        U2 {RestoreRecyclingBin}
    }
} while ($true)