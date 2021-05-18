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
# Directory for writing output files
ALIGNOUTDIR="alignout/"
# How many tracks to try (out of the top 20 returns from YT)
NUMTOTRY=10

# How to run audfprint
AUDFPRINT="audfprint -dbase \"${FPRINTDBASE}\" -matchmincount 20 -quiet 1 -warpmax 0.015 -matchmaxret 1"

# Work directory - assign default
: ${TMPDIR:=/tmp}
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
SEARCH=`echo $KEYWORDS | sed -e "s/[^ ]* //" | sed -e "s/'/%27/" -e "s/[- '!&][- '!&]*/ /g" | tr ' ' '+'`
# just 1st page for now - top 20 hits
page=1
# have to pass through uniq because each ID extracts twice
wget -q "http://www.youtube.com/results?search_query=${SEARCH}&page=${page}" -O - | grep 'watch[?]' | sed -e "s/.*v=//" -e 's/".*//'| grep -v '&' | uniq > $IDLISTFILE

# Download them
files=""
for f in `head -$NUMTOTRY $IDLISTFILE`; do 
    ytdlout=`youtube-dl --restrict-filenames -f 18 -o ${TMPDIR}'/%(title)s-%(id)s.%(ext)s' -- $f | grep Destination`
    if [ ! -z "$ytdlout" ]; then
	thisfile=`echo $ytdlout | awk '{print $3}'`
	files="$files $thisfile"
	echo "Downloaded $thisfile"
    else
	echo "Failed to download $f"
    fi
done
# Run them each against audfprint to see which fits best
$AUDFPRINT -match $files > $AUDFPRINTOUT
# Get the name of the best-matching mp4 file
BESTMP4LINE=`grep "mp4" $AUDFPRINTOUT | sed -e 's/\(.*\) \([0-9][0-9]* [-0-9.][-0-9.]*\)/\2 \1/' | sort -n | tail -1`
if [ -z "$BESTMP4LINE" ]; then
    echo "Best match: nothing found for \"$KEYWORDS\""
else
    echo "Best match:" $BESTMP4LINE
    BESTMP4=`echo $BESTMP4LINE | sed -e "s/\.mp4.*/.mp4/" -e "s@.* @@" `
    # Run it again with alignout to actually extract the file
    $AUDFPRINT -match $BESTMP4 -alignoutdir ${ALIGNOUTDIR}
fi
# Clean up
rm $files $IDLISTFILE $AUDFPRINTOUT
