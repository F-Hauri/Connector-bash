#!/bin/bash

# Connector fifos directory
read TMPDIR < <(mktemp -d /dev/shm/bc_shell_XXXXXXX)

fd=1
# find next free fd
nextFd() {
    while [ -e /dev/fd/$fd ];do ((fd++)) ;done
}

# instanciator for myXxx() function associated to a started and long-running
# instance of the requested command and arguments and initial input data
# (the command will be associated to two descriptors IN and OUT, local to
#  the instanciated function)
newConnector() {
    local command="$1" cmd=${1##*/} args="$2" check="$3" verif="$4"
    local initfile cinfd=${cmd^^}IN coutfd=${cmd^^}OUT FIFO=$TMPDIR/$cmd input
    shift 4
    mkfifo $FIFO
    nextFd
    eval "exec $fd> >(LANG=C stdbuf -o0 $command $args >$FIFO 2>&1) ; $cinfd=$fd;"
    nextFd
    eval "exec $fd<$FIFO;$coutfd=$fd;"
    
    for initfile ;do
	cat >&${!cinfd} $initfile
    done

    source <(echo "my${cmd^}() {
		local in;
 		echo >&${!cinfd} \"\$1\" &&
 		read -u ${!coutfd} \${2:-in};
 		((\$#==2)) || echo \$in;
		}"
       )

    my${cmd^} $check input
    [ "$input" = "$verif" ] ||
	printf >&2 "WARNING: Don't match! '%s' <> '%s'.\n" "$verif" "$input"
    rm $FIFO
}

# SQL Connector
# Stronger, because output length is not fixed, could by empty.
declare bound SQLIN SQLOUT SQLERR lastsqlread
newSqlConnector() {
    local command="$1" cmd=${1##*/} args="$2" check="$3" verif="$4"
    # this work with "sqlite", but also with "mysql", "mariadb" or "postgresql"

    # First building some uniq bound string
    local _Bash64_refstr _out=-- _l _i _num
    printf -v _Bash64_refstr "%s" {0..9} {a..z} {A..Z} @ _ 0
    for ((_l=6;_l--;));do
	_num=$((RANDOM<<15|RANDOM))
	for ((_i=0;_i<30;_i+=6));do
	    _out+=${_Bash64_refstr:(_num>>_i)&63:1}
	done
    done
    printf -v bound "%s-%s-%s-%s-%s" ${_out:0:8} \
	   ${_out:8:4} ${_out:12:4} ${_out:16:4} ${_out:20};
    # Initiate long running sqlite with 2 output feeds.
    FIFOUT=$TMPDIR/sqlout
    FIFERR=$TMPDIR/sqlerr
    mkfifo $FIFOUT
    mkfifo $FIFERR
    nextFd
    eval "exec $fd> >(stdbuf -o0 $command $args >$FIFOUT 2>$FIFERR)"
    SQLIN=$fd
    nextFd
    eval "exec $fd<$FIFOUT;"
    SQLOUT=$fd
    nextFd
    eval "exec $fd<$FIFERR;"
    SQLERR=$fd
    rm $FIFOUT $FIFERR
}

# newSqlConnector /usr/bin/sqlite3 "-separator $'\t' -header /dev/shm/test.sqlite"
# newSqlConnector /usr/bin/psql    "-Anh hostname -F $'\t' --pset=footer=off user"
# newSqlConnector /usr/bin/mysql   "-h hostname -B -p database"

mySqlite() {
    # return nothing but errors via stderr (comment `echo >&2` line and
    # uncomment previous line with `eval ${result}_e` for changing this
    # behaviour) this set two (or tree if error) variables: `$1` containing
    # sql answer and `${1}_h` containing header fields (and ${1}_e for
    # errors if uncommented).
    local result=$1 line head=""
    shift
    echo >&$SQLIN "$@" # Send command request, then

    ### Ask for outputing bound... This for sqlite:
    echo >&$SQLIN "SELECT STRFTIME('%s',DATETIME('now')) AS \"$bound\";"
    ### This for psql:
    #  echo >&$SQLIN "SELECT EXTRACT('EPOCH' FROM now()) AS \"$bound\";"
    ### This for mysql:
    #  echo >&$SQLIN "SELECT UNIX_TIMESTAMP() AS \"$bound\";"

    read -ru $SQLOUT line
    if [ "$line" != "$bound" ] ;then
	IFS=$'\t' read -a ${result}_h <<< "$line";
	while read -ru $SQLOUT line && [ "$line" != "$bound" ] ;do
	    eval "$result+=(\"\$line\")"
	done
    fi
    read -ru $SQLOUT line
    lastsqlread="$line"
    # then once bound readed without timeout, we could read SQLERR with
    # very short timeout
    while read -ru $SQLERR -t .0002 line;do
	# eval "${result}_e+=(\"\$line\")"
	echo >&2 "$line"
    done
}
myPsql() {
    local result=$1 line head="";shift ; echo >&$SQLIN "$@";
    echo >&$SQLIN "SELECT EXTRACT('EPOCH' FROM now()) AS \"$bound\";"
    read -ru $SQLOUT line
    if [ "$line" != "$bound" ] ;then
	IFS=$'\t' read -a ${result}_h <<< "$line";
	while read -ru $SQLOUT line && [ "$line" != "$bound" ] ;do
	    eval "$result+=(\"\$line\")"
	done
    fi
    read -ru $SQLOUT line
    lastsqlread="$line"
    while read -ru $SQLERR -t .0002 line;do
	echo >&2 "$line"
    done
}
myMysql() {
    local result=$1 line head="" ;shift
    echo >&$SQLIN "$@"; echo >&$SQLIN "SELECT UNIX_TIMESTAMP() AS \"$bound\";"
    read -ru $SQLOUT line
    if [ "$line" != "$bound" ] ;then
	IFS=$'\t' read -a ${result}_h <<< "$line";
	while read -ru $SQLOUT line && [ "$line" != "$bound" ] ;do
	    eval "$result+=(\"\$line\")"
	done; fi
    read -ru $SQLOUT line
    lastsqlread="$line"
    while read -ru $SQLERR -t .0002 line;do echo >&2 "$line";done
}

# As each fifo used by connectors are already deleted, just drop
# fifo's directory on exit.
trap "rmdir $TMPDIR;exit" 0 1 2 3 6 9 15
