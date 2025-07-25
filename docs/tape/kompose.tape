#!/usr/bin/env -S PS1='\$ ' vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
Require "make"
Require "docker"
Set Shell "bash"
Set FontSize 15
Set Width 1300
Set Height 5180
Set TypingSpeed .21
Set PlaybackSpeed 3
Set CursorBlink false
Type "./demos/cmk/kompose.cmk clean create deploy test"
Enter
Sleep 450
Screenshot img/kompose.png