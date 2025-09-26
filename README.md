SOS Analyze (Modified Version)

This is a tweaked version of the original Qikfix/sos_analyze script.
It still works the same way (analyzing sosreport data from RHEL and Satellite servers), but I changed how the output looks and added a few extras.

 What’s Different
1. Visual Changes
Colors
 - Green = OK, Yellow = Warning, Red = Fail.
 - Section titles are bold and easier to spot
Section Breaks
 - Big dividers and labels so you can see where each group of checks starts.
Indented Output
 - Sub-results like logs or process lists are pushed in a bit so they’re easier to read.

2. Output Format
Tables Look Cleaner
 - Lines up columns so they don’t jump around if names/paths are long.
Tags/Labels at the Start
 - Each section shows the category and the command/file it came from.

3. Extra Details
Highlighting
 - Words like error, ERROR, [E], warning, WARNING, [W] show up in color, etc..
SELinux Status
 - Enforcing, Permissive, and Disabled stand out in different colors.
Disk & Memory
 - Shown in neat columns and converted to GB/MB instead of raw numbers.
Packages
 - Package info shows up in table form with versions side by side.
