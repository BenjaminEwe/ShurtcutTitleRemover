# ShurtcutTitleRemover
Powershell script that removes the names of the icons on your desktop.


Before removing shortcut titles:
![Corrupted File](Images/before.png)

After removing shortcut titles:
![Corrupted File](Images/After.png)

The script works by renaming the files to invisible characters. Feel free to open an issue if you have a more elegant solution.
A backup is made of all files before modifying them to make it easier to undo.

## How to undo
Just copy the backed up files to the desktop folders and delete the renamed ones

Backup location for the useraccounts shortcuts: %USERPROFILE%/DesktopBackup

Backup location for the public (shared) shortcuts: %Public%/Desktopbackup

## Notes
### Shortcut arrow
Many guides reccomend setting the shortcut icon to ```%windir%\System32\shell32.dll,-50```
While this often works largely fine it can cause the iconcache.db to corrupt. This can lead to the shortcut arrow being replaced by a giant black box, or shortcuts losing their icons instead becoming blank files. Setting it to a custom blank icon seems to be more stable.

![Corrupted File](Images/corrupted.png)

