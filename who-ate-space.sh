#!/usr/bin/env bash

# This script is for Mac OS.
# Use it to get biggest files and folders in your home directory.

echo "##### Big files ####"
find ~/ -type f  -size +1G -exec ls -lh {} + 2> /dev/null



echo "#### Big folders ####"
SAVEIFS=$IFS
IFS=$'\n'

for i in $(du -h -d 1 ~/ 2> /dev/null | gsort -h | tail -10 | cut -f 2)
do echo "$i" ---------------------------------
   du -h -d 1 "$i" 2> /dev/null | gsort -h | grep '[0-9]G\>'| tail -10
done

IFS=$SAVEIFS
