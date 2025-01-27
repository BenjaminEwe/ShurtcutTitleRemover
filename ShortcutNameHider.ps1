# Param needed for script to know if it has restarted itself in administrator or not.
param(
    [switch]$ElevatedRestart
)

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

# Check if the script has restarted itself
if (!$ElevatedRestart){
    # Ask if the public folder should be included
    do {
        $answer = Read-Host "Do you want to include shortcuts on public desktop? (Y/N) (say yes if you are the only user of this computer) This will prompt for administrator permissions."
        $answer = $answer.Trim().ToLower()  # Normalize input

        if ($answer -eq 'y') {
            Write-Host "Including Public..." -ForegroundColor Green
            $includePublic = 'true'

            if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
                Write-Verbose "Not running as administrator. Restarting with elevation..." -Verbose
                Start-Process pwsh.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -ElevatedRestart"
                exit
            }

            break
        } elseif ($answer -eq 'n') {
            Write-Host "Only processing user shortcuts." -ForegroundColor Green
            $includePublic = 'false'
            break
        } else {
            Write-Host "Invalid input. Please enter Y or N." -ForegroundColor Red
        }
    } while ($true)
}
else{
    $includePublic = 'true'
}

# Get the current user's username
$username = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name.Split("\")[-1]

# Set source and destination folders for user
$sourceFolderUser = "C:\Users\$username\Desktop"
$destinationFolder = "C:\Users\$username\Desktopbackup"

# Set source and destination folders for public
if ([bool]::Parse($includePublic)){
    $sourceFolderPublic = "C:\Users\Public\Desktop"
    $destinationFolderPublic = "C:\Users\Public\DesktopBackup"
}

# Ensure backup folder exists, make new if not
if (!(Test-Path $destinationFolder)) { 
    New-Item -Path $destinationFolder -ItemType Directory | Out-Null
    Write-Host "Created backup folder: $destinationFolder"
} else {
    Write-Host "Backup folder already exists: $destinationFolder"
}

# ensure backup folder exists for public, make new if not
if ([bool]::Parse($includePublic)){
    if (!(Test-Path $destinationFolderPublic)) { 
        New-Item -Path $destinationFolderPublic -ItemType Directory | Out-Null
        Write-Host "Created backup folder: $destinationFolderPublic"
    } else {
        Write-Host "Backup folder already exists: $destinationFolderPublic"
    }
}

# FindModified for users folder
$userModCnt = FindModified -location $username -path $sourceFolderUser;
# FindModified for Public folder
if ([bool]::Parse($includePublic)){
    $publicModCnt = FindModified -location "Public" -path $sourceFolderPublic;
}

# this is just for nicer formatting
Write-Host " "

# FindNew for users folder
$userNewArr = FindNew -location $username -path $sourceFolderUser;
# FindNew for Public
if ([bool]::Parse($includePublic)){
    $publicNewArr = FindNew -location "Public" -path $sourceFolderPublic;
}


# Split up the arrays into .lnk and .url
$lnkFilesUser = $userNewArr | Where-Object { $_.Extension -eq ".lnk" }
$urlFilesUser = $userNewArr | Where-Object { $_.Extension -eq ".url" }
Write-Host "Identified $($lnkFilesUser.Count) new .lnk files and $($urlFilesUser.Count) new .url files for processing in $username."

if([bool]::Parse($includePublic)){
    # Process files separately for .lnk and .url
    $lnkFilesPublic = $publicNewArr | Where-Object { $_.Extension -eq ".lnk" }
    $urlFilesPublic = $publicNewArr | Where-Object { $_.Extension -eq ".url" }
    Write-Host "Identified $($lnkFilesPublic.Count) new .lnk files and $($urlFilesPublic.Count) new .url files for processing. in public"
}

# Backup and rename users shortcuts
# .lnk
BackupNRename -ExistingCnt $userModCnt.ExistingLnkCnt -newFiles $lnkFilesUser -destinationFolder $destinationFolder
# .url
BackupNRename -ExistingCnt $userModCnt.ExistingUrlCnt -newFiles $urlFilesUser -destinationFolder $destinationFolder

# Backup and rename public shortcuts
if([bool]::Parse($includePublic)){
    # .lnk
    BackupNRename -ExistingCnt $publicModCnt.ExistingLnkCnt -newFiles $lnkFilesPublic -destinationFolder $destinationFolderPublic
    # .url
    BackupNRename -ExistingCnt $publicModCnt.ExistingUrlCnt -newFiles $urlFilesPublic -destinationFolder $destinationFolderPublic
}

# Final Summary
Write-Host "`nProcessing complete!"
Write-Host "Backup folder: $destinationFolder"
if([bool]::Parse($includePublic)){Write-Host "Public Backup folder: $destinationFolderPublic"}
Write-Host "$($lnkFilesUser.Count + $lnkFilesPublic.Count) .lnk files and $($urlFilesUser.Count + $urlFilesPublic.Count) .url files were renamed."
Write-Host "Total already existing empty shortcuts: $($userModCnt.ExistingLnkCnt + $publicModCnt.ExistingLnkCnt) .lnk, $($userModCnt.ExistingUrlCnt + $publicModCnt.ExistingUrlCnt) .url."

Write-Host "`n"

# Section for removing shortcut arrows 

do {
	$answer = Read-Host "Do you want to remove the shortcut arrow from shortcuts? (Y/N)"
	$answer = $answer.Trim().ToLower()  # Normalize input

	if ($answer -eq 'y') {
		break
	} elseif ($answer -eq 'n') {
		Write-Host "Icon shortcuts will be left alone" -ForegroundColor Green
		exit
	} else {
		Write-Host "Invalid input. Please enter Y or N." -ForegroundColor Red
	}
} while ($true)

# Define blank icon
$imageBase64 = "AAABAAEAEBAAAAEAIABoBAAAFgAAACgAAAAQAAAAIAAAAAEAIAAAAAAAQAQAAAAAAAAAAAAAAAAAAAAAAAD//wECAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAf/8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAA=="
# Define location for image file to be saved
$imageFolderLocation = "C:\ProgramData\ShortcutHider"
# Define file location
$imageFileLocation = $imageFolderLocation + "\BlankIconForHidingShortcutArrow.ico" 
# Define registry path
$registryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons"
# Define name of proprty
$registryPropertyName = '29'
# Define property type
$registryPropertyType = 'String'

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

# Get the current value of the registry key
try {$currentValueRegistry = (Get-ItemProperty -Path $registryPath -Name 29).29}
catch {$currentValueRegistry = "empty"}

if ($currentValueRegistry -eq $imageFileLocation) { # If the value is already correct
	Write-Host "the registry value has already been set"
} elseif ($currentValueRegistry -ne "empty") { # If a value exists, but is wrong - useful if user has already tried to incorrectly modify it themselves
    Set-ItemProperty -Path $registryPath -Name $registryPropertyName -Value $imageFileLocation -Force | Out-Null
}else { # if no key exists
	# Creates the key for the edit
	New-Item -Path $registryPath | Out-Null

	$newItemProperty = @{
		Path = $registryPath
		Name = $registryPropertyName
		PropertyType = $registryPropertyType
		Value = $imageFileLocation
	}
	New-ItemProperty @newItemProperty | Out-Null
}

# restart explorer if the user wishes
do {
	$answer = Read-Host "Windows explorer must be restarted for changes to be visible. Do you want to restart windows explorer now? (Y/N) (this will close file explorer windows and might give some instability if you have running apps)"
	$answer = $answer.Trim().ToLower()  # Normalize input

	if ($answer -eq 'y') {
		stop-process -name explorer
		break
	} elseif ($answer -eq 'n') {
		Write-Host "Changes will take effect on next restart" -ForegroundColor Green
		break
	} else {
		Write-Host "Invalid input. Please enter Y or N." -ForegroundColor Red
	}
} while ($true)