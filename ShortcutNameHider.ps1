# Param needed for script to know if it has restarted itself in administrator or not.
param(
    [switch]$ElevatedRestart
)

# Get the current user's username
$username = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name.Split("\")[-1]

# Set source and destination folders for user
$sourceFolderUser = "C:\Users\$username\Desktop"
$destinationFolder = "C:\Users\$username\Desktopbackup"

# Set source and destination folders for public
$sourceFolderPublic = "C:\Users\Public\Desktop"
$destinationFolderPublic = "C:\Users\Public\DesktopBackup"

Function FindModified {
    param (
        [string]$location,
        [string]$path
    )
    Write-Host "`nScanning $location desktop for shortcut files..."

    # Retrieve existing empty shortcuts (.lnk and .url with only spaces in name)
    $existingEmptyShortcuts = Get-ChildItem -Path $path -Force |
    Where-Object { $_.Extension -in ".lnk", ".url" -and $_.BaseName -match "^\s+$" }

    # Separate counts for .lnk and .url files
    $existingLnkCount = ($existingEmptyShortcuts | Where-Object { $_.Extension -eq ".lnk" }).Count
    $existingUrlCount = ($existingEmptyShortcuts | Where-Object { $_.Extension -eq ".url" }).Count

    Write-Host "Found $existingLnkCount pre-modified .lnk files and $existingUrlCount pre-modified .url files on $location desktop."
    
    return @{ ExistingLnkCnt = $existingLnkCount; ExistingUrlCnt = $existingUrlCount }
}

Function FindNew {
    param (
        [string]$location,
        [string]$path
    )
    # Get all new shortcuts (.lnk and .url), excluding existing empty ones
    $newShortcuts = Get-ChildItem -Path $path -Force |
    Where-Object { $_.Extension -in ".lnk", ".url" -and $_.BaseName -notmatch "^\s+$" }

    $newShortcutsAmnt = $newShortcuts.count

    Write-Host "Found $newShortcutsAmnt shortcuts that have not been renamed on $location desktop." 

    return $newShortcuts
}

Function BackupNRename {
    param (
        [int]$ExistingCnt,
        [array]$newFiles,
        [string]$destinationFolder
    )
    $i = $existingCnt + 1
    foreach ($file in $newFiles) {
    Copy-Item -Path $file.FullName -Destination $destinationFolder -Force
    $newName = (" " * $i) + $file.Extension
    Rename-Item -Path $file.FullName -NewName $newName -Force
    Write-Host "Renamed: '$($file.Name)' to '$newName'"
    $i++
    }
}

Function Elevate {
    #takes in an input so that script knows wich function to auto-execute after restart
    param (
        [int]$commandToRestart
    )
    
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Verbose "Not running as administrator. Restarting with elevation..." -Verbose
        Start-Process pwsh.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -$commandToRestart"
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

Function Summary {
    param (
        [switch]$includePublic
    )
    Write-Host "`nProcessing complete!"
    Write-Host "Backup folder: $destinationFolder"
    if(!$includePublic){Write-Host "Public Backup folder: $destinationFolderPublic"}
    Write-Host "$($lnkFilesUser.Count + $lnkFilesPublic.Count) .lnk files and $($urlFilesUser.Count + $urlFilesPublic.Count) .url files were renamed."
    Write-Host "Total already existing empty shortcuts: $($userModCnt.ExistingLnkCnt + $publicModCnt.ExistingLnkCnt) .lnk, $($userModCnt.ExistingUrlCnt + $publicModCnt.ExistingUrlCnt) .url."
    Write-Host "------------------------------------------------"
}

Function RemoveIcon {
    # Define blank icon 
    $imageBase64 = "AAABAAEAEBAAAAEAIABoBAAAFgAAACgAAAAQAAAAIAAAAAEAIAAAAAAAQAQAAAAAAAAAAAAAAAAAAAAAAAD//wECAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAf/8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAA=="
    $imageFolderLocation = "C:\ProgramData\ShortcutHider" # Define location for image file to be saved
    $imageFileLocation = $imageFolderLocation + "\BlankIconForHidingShortcutArrow.ico" # Define file location
    $registryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons" # Define registry path
    $registryPropertyName = '29' # Define name of proprty
    $registryPropertyType = 'String' # Define property type

    # test if image file exists, otherwise create it
    if (Test-Path $imageFileLocation){
        Write-Host "Icon already exists"
    }
    else {
        Write-Host "Will save the needed icon at " $imageFileLocation

        # make directory to store icon
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

do {
    if (!$switchInput -or !$ElevatedRestart) {
        Write-Host "
    1. Remove the names of all icons [Affects all users of computer] [Administrator permissions needed]
    2. Remove the names of only the icons on your personal desktop
    3. TBD Workaround to remove all shortcut names without affecting other users [Administrator permissions needed]
    4. Remove the shortcut arrow from shortcuts [Affects all users of computer] [Administrator permissions needed]
    5. Remove the shortcut arrow from shortcuts and restart explorer [Affects all users of computer] [Administrator permissions needed] [Save documents first]
    6. TBD Remove UAC icon from shortcuts [Affects all users of computer] [Administrator permissions needed]
    7. TBD Remove name from recycling bin
    8. TBD Remove recycling bin
    9. TBD Put shortcut icon back [Affects all users of computer] [Administrator permissions needed] [Save documents first]
    
    0. exit"
        $switchInput = Read-Host "Select a number"
    }

    Clear-Host

    switch ($switchInput)
    {
        0 {exit}
        1 { 
            Elevate -commandToRestart 1
            makeBackupFolder -folderToBackup $destinationFolder
            makeBackupFolder -folderToBackup $destinationFolderPublic
            # Find the count of already modified
            $userModCnt = FindModified -location $username -path $sourceFolderUser
            $publicModCnt = FindModified -location "Public" -path $sourceFolderPublic
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
            BackupNRename -ExistingCnt $userModCnt.ExistingLnkCnt -newFiles $lnkFilesUser -destinationFolder $destinationFolder
            BackupNRename -ExistingCnt $userModCnt.ExistingUrlCnt -newFiles $urlFilesUser -destinationFolder $destinationFolder
            BackupNRename -ExistingCnt $publicModCnt.ExistingLnkCnt -newFiles $lnkFilesPublic -destinationFolder $destinationFolderPublic
            BackupNRename -ExistingCnt $publicModCnt.ExistingUrlCnt -newFiles $urlFilesPublic -destinationFolder $destinationFolderPublic
            Summary -includePublic "true"}
        2 {
            Elevate -commandToRestart 1
            makeBackupFolder -folderToBackup $destinationFolder
            # Find the count of already modified
            $userModCnt = FindModified -location $username -path $sourceFolderUser
            # Find the array of new icons
            $userNewArr = FindNew -location $username -path $sourceFolderUser
            # Split up arrays into .url and .lnk
            $lnkFilesUser = $userNewArr | Where-Object { $_.Extension -eq ".lnk" }
            $urlFilesUser = $userNewArr | Where-Object { $_.Extension -eq ".url" }
            Write-Host "Identified $($lnkFilesUser.Count) new .lnk files and $($urlFilesUser.Count) new .url files for processing in $username."
            # Backup and rename
            BackupNRename -ExistingCnt $userModCnt.ExistingLnkCnt -newFiles $lnkFilesUser -destinationFolder $destinationFolder
            BackupNRename -ExistingCnt $userModCnt.ExistingUrlCnt -newFiles $urlFilesUser -destinationFolder $destinationFolder
            Summary -includePublic "false"}
        3 {}
        4 {RemoveIcon}
        5 {RemoveIcon; stop-process -name explorer}
        6 {}
        7 {}
        8 {}
        9 {
            if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons") {
                Remove-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons"
                stop-process -name explorer
            } else {
                Write-Host "The icon should already be back. Try restarting the computer if it is still missing"
            }
        }
    }
} while ($true)