highest_id=0
for processed in audfprint-v0.9/alignout/*; do
    id=`echo $processed | cut -c 25-28`
    if [ "$id" -gt "$highest_id" ]; then
        highest_id=$id
    fi
done

echo "Processed up to id: ${highest_id}"

for f in  `cat idlist.txt`; do
    n=`grep $f id_plus_artist_title.txt`
    echo "------ $n"
    id=`echo $n | cut -c 1-4`
    name=`echo $n | cut -c 5-`
    
    if [ "$id" -le "$highest_id" ]; then
        continue
    fi
    
    ./scrape-yt-match-fprint.sh "$name" > tmp.out
    grep "Best match:" tmp.out
    # sleep 30
done
