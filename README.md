# ShurtcutTitleRemover
PowerShell script that can remove the:
- Names of shortcuts
- Shortcut arrow
- Name of the recycle bin
- Recycle bin from desktop

To run script open PowerShell and paste:

```irm https://raw.githubusercontent.com/BenjaminEwe/ShurtcutTitleRemover/refs/heads/main/ShortcutNameHider.ps1 -OutFile $env:TEMP\SCTR.ps1; & $env:TEMP\SCTR.ps1```

![NoTitlesNoArrowNoBinName](Images/NoTitlesNoArrowNoBinName.png)

## ExecutionPolicy

If you get an error like this:

<img width="2063" height="193" alt="image" src="https://github.com/user-attachments/assets/dbc8999b-4670-47c1-9c5a-d7f60acca0e7" />

You need to run powershell as administrator and run the command ``Set-ExecutionPolicy RemoteSigned`` and press yes.


## Results
<details>
<summary>Images of some of the possible configurations</summary>

Remove titles of shortcuts:
![NoTitles](Images/NoTitles.png)
Remove Arrows
![NoArrows](Images/NoArrow.png)
Remove Titles and Arrows
![NoTitleNoArrows](Images/NoTitlesNoArrow.png)
Remove Titles, Arrows, and Recycle Bin name
![NoTitlesNoArrowNoBinName](Images/NoTitlesNoArrowNoBinName.png)

</details>

## How to undo
[Manual Restore wiki page](https://github.com/BenjaminEwe/ShortcutTitleRemover/wiki/Manual-Restore)

## How does it work
[Functionality wiki page](https://github.com/BenjaminEwe/ShortcutTitleRemover/wiki/Functionality)


## How to do these things manually
[Do it manually](https://github.com/BenjaminEwe/ShortcutTitleRemover/wiki/Do-it-manually)
