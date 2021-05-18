#!/bin/sh
# scrape-yt-match-fprint.sh
#
# Script to download likely matches from youtube and extract the best one to match 
# in an audfprint database.  Used to reconstruct audio described only by artist and 
# title plus fprint database.
#
# 2013-08-28 Dan Ellis dpwe@ee.columbia.edu 

# Name of fprint database consisting of tracks we want to reproduce
 FPRINTDBASE="billboard.mat"
#FPRINTDBASE="beatles-fprint.mat"
# Directory for writing output files
ALIGNOUTDIR="alignout/"
# How many tracks to try (out of the top 20 returns from YT)
NUMTOTRY=10


# How to run audfprint
# AUDFPRINT="python3.7 audfprint/audfprint.py"
# AUDFPRINT_OPTIONS="--dbase ${FPRINTDBASE} --min-count 20 -H 4 --max-matches 1"
# AUDFPRINT="python3.7 audfprint/audfprint.py --dbase \"${FPRINTDBASE}\" --matchmincount 20 --quiet 1 --warpmax 0.015 --matchmaxret 1"

# Work directory - assign default
: ${TMPDIR:=./audfprint-v0.9/tmp}

rm $TMPDIR/*
# Temporary files
IDLISTFILE=${TMPDIR}/ids.$$
AUDFPRINTOUT=${TMPDIR}/audfprintout.$$

if [ $# -eq 0 ]; then
  echo "Usage: $0 \"<track & artist name string>\""
  exit 1
fi

KEYWORDS=$1

# Access the youtube search page using these keywords
# format for yt query URL with + for space
#SEARCH=`echo $KEYWORDS | sed -e "s/[^ ]* //" | sed -e "s/'/%27/" -e "s/[- '!&][- '!&]*/ /g" | tr ' ' '+'`
#SEARCH=`echo $KEYWORDS | cut -c5-`
SEARCH=`echo $KEYWORDS`
# just 1st page for now - top 20 hits
page=1

youtube-dl "ytsearch20:${SEARCH}" -o ${TMPDIR}'/%(id)s.%(ext)s' -f '[height<=480,filesize<100M]+bestaudio' --ignore-errors
mp4_files=`ls audfprint-v0.9/tmp/*`

while [ $? -ne 0 ]; do
    sleep 30
    echo "Download failed, trying again..."
    youtube-dl "ytsearch20:${SEARCH}" -o ${TMPDIR}'/%(id)s.%(ext)s' -f '[height<=480,filesize<100M]+bestaudio' --ignore-errors
    mp4_files=`ls audfprint-v0.9/tmp/*`
done

files=""
for f in $mp4_files; do 
    # f_parsed=", ../tmp/${f | cut -c5-}"
    f_parsed=`echo $f | cut -c16-`
	files="$files, '$f_parsed'"
done
# Get rid of first ", "
files=`echo $files | cut -c3-`

echo "-----------------------"
# Run them each against audfprint to see which fits best
# $AUDFPRINT match $files $AUDFPRINT_OPTIONS > $AUDFPRINTOUT
# $AUDFPRINT match $files $AUDFPRINT_OPTIONS
cd audfprint-v0.9
matlab -nodisplay -nodesktop -r "audfprint('-dbase', '../billboard.mat', '-matchmincount', '20', '-warpmax', '0.015', '-matchmaxret', '1', '-match', ${files}); exit" > ../$AUDFPRINTOUT
cd ..
# Get the name of the best-matching mp4 file
BESTMP4LINE=`grep "tmp" $AUDFPRINTOUT | sed -e 's/\(.*\) \([0-9][0-9]* [-0-9.][-0-9.]*\)/\2 \1/' | sort -n | tail -1`
if [ -z "$BESTMP4LINE" ]; then
    echo "Best match: nothing found for \"$KEYWORDS\""
else
    echo "Best match:" $BESTMP4LINE
    #BESTMP4=`echo $BESTMP4LINE | sed -e "s/\.mp4.*/.mp4/" -e "s@.* @@" `
    BESTMP4=`echo $BESTMP4LINE | grep -oP 'tmp[^[:blank:]]*'`
    #BESTMP4=`echo $BESTMP4LINE | cut -d " " -f 3`
    echo "BESTFILE: ${BESTMP4}"
    echo "ALLFILES: ${files}"
    # Run it again with alignout to actually extract the file
    # $AUDFPRINT -match $BESTMP4 -alignoutdir ${ALIGNOUTDIR}
    cd audfprint-v0.9
    #matlab -nodisplay -nodesktop -r "audfprint('-dbase', '../billboard.mat', '-matchmincount', '20', '-warpmax', '0.015', '-matchmaxret', '1', '-match', '$BESTMP4'); exit"
    #matlab -nodisplay -nodesktop -r "audfprint('-dbase', '../billboard.mat', '-matchmincount', '20', '-warpmax', '0.015', '-matchmaxret', '1', '-alignoutdir', '${ALIGNOUTDIR}', '-match', '$BESTMP4'); exit"
    matlab -nodisplay -nodesktop -r "audfprint('-dbase', '../billboard.mat', '-matchmincount', '20', '-warpmax', '0.015', '-matchmaxret', '1', '-alignoutdir', '${ALIGNOUTDIR}', '-match', '$BESTMP4'); exit" > ../$AUDFPRINTOUT
    cd ..
fi
echo "Cleaning up"
# Clean up
# rm $files $IDLISTFILE $AUDFPRINTOUT
