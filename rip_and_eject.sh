#!/bin/bash

# This script automates the process of ripping music CDs using abcde.
# It rips the CD, organizes the files, ejects the CD, and waits for a new one.

while true; do
  echo "Checking for a CD in the drive..."

  # The `eject -T` command checks the status of the CD tray.
  # Exit status 0: Tray is closed and a disc is present.
  # Exit status 1: Tray is open.
  # Exit status 2: Tray is closed and empty.
  TRAY_STATUS=$(eject -T >/dev/null; echo $?)

  if [ "$TRAY_STATUS" -eq 0 ]; then
    echo "CD detected. Starting the ripping process..."

    # Rip the CD using abcde with the following options:
    # -o flac: Sets the output format to FLAC for high-quality audio.
    # -N: Enables non-interactive mode.
    # -x: Ejects the CD after the ripping process is complete.
    # -a default,clean: Performs the default actions (rip, encode, tag, move, playlist)
    #                  and cleans up temporary files afterward.
    # -O: Defines the output format for the directory and file structure.
    #     Spaces in album and artist names are replaced with underscores.
    abcde -o flac -N -x -a default,clean -O '''${ALBUMFILE// /_}--${ARTISTFILE// /_}/${TRACKNUM}.${TRACKFILE}'''

    echo "Ripping process complete. The CD has been ejected."
    echo "Please insert a new CD and close the tray to continue."

  elif [ "$TRAY_STATUS" -eq 2 ]; then
    echo "The CD tray is empty. The script will now exit."
    break
  else
    echo "The CD tray is open. Please insert a CD and close the tray."
    # Wait for 5 seconds before checking again to avoid excessive messages.
    sleep 5
  fi
done
