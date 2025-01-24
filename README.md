# ShurtcutTitleRemover
Powershell script that removes the names of the icons on your desktop.


Before running script:

<img width="823" alt="Before" src="https://github.com/user-attachments/assets/b7656efa-f8f4-41ac-a9ea-8fce95c3963d" />

After running script:

<img width="823" alt="After" src="https://github.com/user-attachments/assets/965ee1b2-da77-4072-a736-a8af4bc43f32" />



The script works by renaming the files to invisible characters. Feel free to open an issue if you have a more elegant solution.
A backup is made of all files before modifying them to make it easier to undo.

## How to undo
Just copy the backed up files to the desktop folders and delete the renamed ones

Backup location for the useraccounts shortcuts: %USERPROFILE%/DesktopBackup

Backup location for the public (shared) shortcuts: %Public%/Desktopbackup
