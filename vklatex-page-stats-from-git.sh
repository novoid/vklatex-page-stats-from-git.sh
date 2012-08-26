#!/bin/sh
## Time-stamp: <2012-08-26 16:12:05 vk>
## author:  Karl Voit, scripts@Karl-Voit.at
## license: GPL v3 or later
## URL:     https://github.com/novoid/vklatex-page-stats-from-git.sh
FILENAME=$(basename $0)

## This script collects the history of page lengths from a git-reposirtory
## that holds a LaTeX document.
##
## With those numbers, you are able to derive a histogram of the development
## of the document size measured in page numbers.
##
## Just "grep" the lines starting with "RESULT" from LOGFILE.
##
## external tools needed:
## - date
## - pdfinfo
## - awk
## - git

## OPEN ISSUES:
## - COMPILECOMMAND and recognizing sub-PID that is not ending in time does not
##   work properly -> results in RESULT lines without page numbers and wrong DEBUG output


## folder where the LaTeX document resides and the COMPILECOMMAND should be invoked
TEXDIR="${1}"

## file where the logs should be written to (better do outside of TEXDIR)
##   - old LOGFILE will be deleted prior to a new run!
LOGFILE="${1}/../${FILENAME}.log"

## command to generate the PDF file
##   - previous PDF files will be deleted by this script!
##   - choose to remove old temporary files (for not interfering with current compilation)
#COMPILECOMMAND="make clean; make pdf"
## NOTE: using COMPILECOMMAND as variable does have an issue I could not resolve yet:
##       eval ${COMPILECOMMAND} & myPID=$!  ... gets the PID of the eval command, not
##       the COMPILECOMMAND. Therefore this command has to be modified further down in
##       the script!

## time to wait for compilation process to end
##   - value should higher than the longest successful compilation time
##   - if this sleep phase is over and the COMPILECOMMAND did 
##     not finish, no pdf result gets logged -> don't make it too short
WAITFORCOMPILING="35"


## ================================================================== ##
## ================================================================== ##
## ================================================================== ##


if [ "x${1}" = "x" ]; then
    echo
    echo "$0: please give me a folder as argument"
    echo
    exit 1
fi
if [ ! -d "${1}" ]; then
    echo
    echo "$0: ${1} must be an existing folder"
    echo "  ... containing a git repository of a LaTeX document"
    echo
    exit 2
fi

rm ${LOGFILE}    ## remove old logfile (otherwise new data would be appended)
cd "${TEXDIR}"   ## change, to where the action is!

debug()
{
    time_now=`date '+%Y-%m-%dT%H:%M:%S'`
    echo "DEBUG: ${time_now} $@"               ## write to stdout
    echo "DEBUG: ${time_now} $@" >> ${LOGFILE} ## append to LOGFILE
}

logf()
{
    echo "$@"                ## write to stdout
    echo "$@" >> ${LOGFILE}  ## append to LOGFILE
}

logf "output of:     ${0} ${@}"
logf "using folder:  ${TEXDIR}"
logf "using logfile: ${LOGFILE}"

number_of_commits=`git rev-list master|wc -l`
duration_minutes=`echo "${number_of_commits} * ${WAITFORCOMPILING} / 60" | bc`
logf "this run will take approximately ${duration_minutes} minutes (starting with `date '+%Y-%m-%dT%H:%M:%S'`)"

for commit in $(git rev-list master)   ## start with current commit and go backward
do
    debug "-----------------"

    ## get day of current commit
    day=`git rev-list --timestamp --pretty="%ad" --date=short $commit | head -n 2 | tail -n 1`
    ## get time of current commit
    time=`git rev-list --timestamp --pretty="%ad" ${commit} | head -n 2 | tail -n 1 | awk '{ print $4 }'`
    ## form an ISO timestamp of commit
    date="${day}T${time}"

    ## be nice and tell the user where we are
    debug "commit ${commit} from $date"

    ## get the commit
    git checkout ${commit} 2>>${LOGFILE} || debug "ERROR while checkout"
    debug "checked out ${commit}"

    debug "removing old PDF files ..."
    rm -f *pdf  2>>${LOGFILE} || debug "ERROR while rm pdf"

    debug "starting compilation process in background ..."
    #eval "${COMPILECOMMAND} &"   FIXXME -> using this method leads to wrong PID in $!
    make clean; make pdf &
    makepid=$!  ## remember sub-process-ID
    debug "sub-PID of make: ${makepid}   (waiting ${WAITFORCOMPILING} seconds ...)"

    ## wait for finishing compilation
    sleep ${WAITFORCOMPILING}

    ## check, if COMPILECOMMAND is still running   FIXXME: does not work (see list of ISSUES)
    number_of_processes=`ps xauwww|grep -v grep|grep "${makepid}"|wc -l`
    debug "number of processes still running: ${number_of_processes}"

    ## if compilation is finished in time ...
    if [ "x${number_of_processes}" = "x0" ]; then
	debug "finished in time (not killing ${makepid})"
	ls -la *pdf >> ${LOGFILE}
	pagenum=`pdfinfo *pdf | grep Pages | awk '{ print $2 }'`
	logf "RESULT: $commit $date $pagenum"
    else
	## if compilation has not finished (ongoing or stopped) ...
	debug "${makepid} did not finish. killing ..."
	kill ${makepid} 2>> ${LOGFILE}
	debug "killed ${makepid}"
	logf "RESULT: $commit $date aborted"
	pagenum=`pdfinfo *pdf | grep Pages | awk '{ print $2 }'`
	logf "backup: $commit $date $pagenum"
    fi
done

logf "checking out master (again)"
git checkout master
logf "${FILENAME} finished successfully.    (logged to \"${LOGFILE}\")"
exit 0
#end
