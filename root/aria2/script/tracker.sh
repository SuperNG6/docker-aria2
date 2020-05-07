#!/bin/bash

INFO="[\033[32mINFO\033[0m]"
ERROR="[\033[31mERROR\033[0m]"
echo && echo -e "$INFO Get trackers ..."
aria2_conf="/config/aria2.conf"
# https://github.com/ngosang/trackerslist
#tracker=$(wget -qO- https://raw.githubusercontent.com/ngosang/trackerslist/master/trackers_all.txt | awk NF | sed ":a;N;s/\n/,/g;ta")
# https://github.com/XIU2/TrackersListCollection
tracker=$(wget -qO- https://cdn.jsdelivr.net/gh/XIU2/TrackersListCollection/all.txt | awk NF | sed ":a;N;s/\n/,/g;ta")
[ -z $tracker ] && echo -e "
$ERROR Unable to get trackers, network failure or invalid links." && exit 1
echo -e "
--------------------[TRACKERS]--------------------
${tracker}
--------------------[TRACKERS]--------------------
"
[ ${aria2_conf} == "cat" ] && exit 0
echo -e "$INFO Adding trackers to '${aria2_conf}' ..." && echo
if [ ! -f ${aria2_conf} ]; then
    echo -e "$ERROR '${aria2_conf}' does not exist."
    exit 1
else
    [ -z $(grep "bt-tracker=" ${aria2_conf}) ] && echo "bt-tracker=" >>${aria2_conf}
    sed -i "s@^\(bt-tracker=\).*@\1${tracker}@" ${aria2_conf} && echo -e "$INFO Trackers added successfully!"
fi
