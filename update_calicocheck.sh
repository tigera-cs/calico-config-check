#!/bin/sh

git fetch origin >/dev/null 2>&1
git rev-parse --remotes >/dev/null 2>&1

UPSTREAM=${1:-'@{u}'}
LOCAL=$(git rev-parse @)
REMOTE=$(git rev-parse "$UPSTREAM")
BASE=$(git merge-base @ "$UPSTREAM")

if [ $LOCAL = $REMOTE ]; then
    echo "Up-to-date"
elif [ $LOCAL = $BASE ]; then
    echo "Need to pull"
    read -p "Do you want to update the calico-check script?(yes/no)" reply
    case $reply in 
	    [Yy]es) echo "Updating the script file ....."
		    git pull origin master >/dev/null 2>&1 && echo "Update successfull";;
	    [Nn]o) echo "No download done" ;;
	        *) echo "Wrong answer. Print yes or no"
		   unset reply ;;
    esac
fi
