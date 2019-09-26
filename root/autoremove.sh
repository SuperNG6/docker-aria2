#!/bin/bash

downloadpath='/downloads' 

filepath=$3
rdp=${filepath#${downloadpath}/}
path=${downloadpath}/${rdp%%/*}


if [ $2 -eq 0 ]
	then
		exit 0
elif [ "$path" = "$filepath" ] && [ $2 -eq 1 ]
	then
	rm -vf "$filepath".aria2
	exit 0
elif [ "$path" != "$filepath" ] && [ -e "$filepath".aria2 ]
	then
	rm -vf "$filepath".aria2
	exit 0
elif [ "$path" != "$filepath" ] && [ -e "$path".aria2 ]
	then
	rm -vf "$path".aria2
	exit 0
fi
