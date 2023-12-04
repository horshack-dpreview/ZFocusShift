#!/bin/bash
#
# zfocusshiftshpoc - Proof-of-Concept for automated focus-shift shooting on Nikon Z bodies
#

set -u

# user parameters
stackShotFilenameBase="/mnt/hgfs/downloads/stack/focusShift"
stackFocusIncrement=15          # internal camera focus movement amount. not the same as width value for in-camera implementation 
exiftool=~/exiftool/exiftool    # set to just "exiftool" to use the version in the system path
gphoto2=gphoto2                 # set to just "gphoto2" to use the version in the system path

# internal parameters
tmpdir="/tmp"
tmpShotFilename="${tmpdir}/tempFocusShiftShot"
rack_focus_wait_time_secs=2

#
# methods
#
gphoto2Exec() { # gphoto2Exec(args...)
    local args=("$@")
    retVal=$($gphoto2 --quiet ${args[@]} 2>&1) 
}
exiftoolExec() { # exiftoolExec(args...)
    local args=("$@")
    retVal=$($exiftool ${args[@]})
}
getExifTag() { # getExifTag(filename, tagname)
    local filename=$1
    local exifTag=$2
    exiftoolExec "-s3 -$exifTag $filename" 
}
setFocus() { # setFocus(value)
    gphoto2Exec --set-config manualfocusdrive=$1
}
setFocusRackedInfinity() { # setFocusRackedInfinity()
    # note: we expect an error because we're using a known-too-large increment to force to infinity
    setFocus 30000; sleep $rack_focus_wait_time_secs
}
setFocusRackedMFD() { # setFocusRackedMFD()
    # note: we expect an error because we're using a known-too-large decrement to force to MFD 
    setFocus -30000; sleep $rack_focus_wait_time_secs
}
takePhoto() { # takePhoto(filename)
    local filename=$1
    gphoto2Exec --set-config capturetarget=0 --capture-image-and-download --filename="$filename" --force-overwrite
}
takeTempPhoto() { # takeTempPhoto()
    local filename=$tmpShotFilename
    rm -rf "$filename"
    takePhoto "$filename"
    retVal="$filename"
}
takeTempPhotoAndGetLensPosition() { # takeTempPhotoAndGetLensPosition()
    takeTempPhoto
    getExifTag $retVal "LensPositionAbsolute";
}

#
#############################################################################
#
# script functional starting point 
#

#
# determine absolute lens position for both infnity and MFD. These values are needed to calculate the
# relative focus steps between two absolute focus positions
#
echo -n "Racking focus to Infinity..."; setFocusRackedInfinity
echo -n "Taking photo..."; takeTempPhotoAndGetLensPosition; lensPosInfnity=$retVal
echo "Lens position at infinity: ${lensPosInfnity}"

echo -n "Racking focus to MFD..."; setFocusRackedMFD
echo -n "Taking photo..."; takeTempPhotoAndGetLensPosition; lensPosMFD=$retVal
echo "Lens position at MFD: ${lensPosMFD}"

#
# prompt user to set focus to near and far portions of the stack. we take a photo for
# both steps so that we can extract the absolute lens position of each
#
read -sp "**** Set focus to near point. Press enter when done... "; echo
echo -n "Taking photo..."; takeTempPhotoAndGetLensPosition; lensPosStackNear=$retVal
echo "Lens position at near point: ${lensPosStackNear}"

read -sp "**** Set focus to far point. Press enter when done... "; echo
echo -n "Taking photo..."; takeTempPhotoAndGetLensPosition; lensPosStackFar=$retVal
echo "Lens position at far point: ${lensPosStackFar}"

#
# focus to MFD, then do relative focus movement to get to near point
#
echo -n "Racking focus to MFD (${lensPosMFD})..."; setFocusRackedMFD
lensStepsToNearPointFromMFD=$((lensPosMFD - lensPosStackNear))
echo -n "Setting focus to near point (${lensPosStackNear}) from MFD by moving $lensStepsToNearPointFromMFD steps..."
setFocus $lensStepsToNearPointFromMFD; sleep $rack_focus_wait_time_secs; echo

#
# do focus stack. # images = (near-far pos) / focus increment + 1, rounded up in case not evenly divisible
#
numShots=$(echo "scale=0; $(( (lensPosStackNear-lensPosStackFar+(stackFocusIncrement-1))/stackFocusIncrement+1 ))" | bc -l )
echo -e "\nTaking $numShots shots from lens position $lensPosStackNear to $lensPosStackFar in focus increments of $stackFocusIncrement"
for ((i=0; i<numShots; i++)); do
    printf -v stackShotFilename "${stackShotFilenameBase}_%03d_of_%03d.jpg" $((i+1)) $numShots
    echo -en "\tTaking photo $((i+1))/$numShots to $stackShotFilename..."; takePhoto "$stackShotFilename"
    if ((i < numShots-1)); then  # more shots to take?
        echo -n "Moving focus $stackFocusIncrement steps..."; setFocus $stackFocusIncrement
    fi
    echo
done

