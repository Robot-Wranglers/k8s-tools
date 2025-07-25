#!/usr/bin/env -S PS1='\$ ' vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
Require "make"
Require "docker"
Set Shell "bash"
Set FontSize 15
Set Width 1024
Set Height 7000
Set TypingSpeed .21
Set PlaybackSpeed 3
Set CursorBlink false
Type "./demos/argo-wf.mk clean create deploy test"
Enter
Sleep 560
Screenshot img/argo-wf.png