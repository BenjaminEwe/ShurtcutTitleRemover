# ShurtcutTitleRemover
PowerShell script that can remove the:
- Names of shortcuts
- Shortcut arrow
- Name of the recycle bin
- Recycle bin from desktop

To run script open PowerShell and paste:

```(New-Object Net.WebClient).DownloadString("https://raw.githubusercontent.com/BenjaminEwe/ShurtcutTitleRemover/refs/heads/main/ShortcutNameHider.ps1") | iex```

![NoTitlesNoArrowNoBinName](Images/NoTitlesNoArrowNoBinName.png)

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