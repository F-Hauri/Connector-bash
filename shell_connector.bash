#!/bin/bash

mkBound() {
    # Building some uniq 30 random char string from 12 $RANDOM values:
    # RANDOM is 15 bits. 15 x 2 = 30 bits -> 5 x 6 bits char
    local -n result=${1:-bound}
    local _Bash64_refstr _out= _l _i _num
    printf -v _Bash64_refstr "%s" {0..9} {a..z} {A..Z} @ _ 0
    for ((_l=6;_num=(RANDOM<<15|RANDOM),_l--;));do
        for ((_i=0;_i<30;_i+=6));do
            _out+=${_Bash64_refstr:(_num>>_i)&63:1}
        done
    done
    printf -v result -- "--%s-%s-%s-%s-%s-%s-" ${_out:0:7} \
           ${_out:7:4} ${_out:11:4} ${_out:15:4} \
           ${_out:19:4} ${_out:23};
}    

# instanciator for myXxx() function associated to a started and long-running
# instance of the requested command and arguments and initial input data
# (the command will be associated to two descriptors XXIN and XXOUT, local to
#  the instanciated function)
newConnector() {
    local command="$1" cmd=${1##*/} args="$2" check="$3" verif="$4"
    shift 4
    local initfile input
    local -n cinfd=${cmd^^}IN coutfd=${cmd^^}OUT

    coproc stdbuf -o0 $command $args 2>&1
    cinfd=${COPROC[1]} coutfd=$COPROC 

    for initfile ;do
	cat >&${cinfd} $initfile
    done

    source <(echo "my${cmd^}() {
		local -n result=\${2:-${cmd}Out}
		echo >&\${${cmd^^}IN} \"\$1\" &&
		read -u \${${cmd^^}OUT} -t 3 result
		((\$#>1)) || echo \$result
		}"
	)

    my${cmd^} $check input
    [ "$input" = "$verif" ] ||
	printf >&2 "WARNING: Don't match! '%s' <> '%s'.\n" "$verif" "$input"
}


# SQL Connector
# Stronger, because output length is not fixed, could by empty.
# this work with "sqlite", but also with "mysql", "mariadb" or "postgresql"
declare bound sqlreqbound SQLIN SQLOUT SQLERR lastsqlread
newSqlConnector() {
    local command="$1" cmd=${1##*/} args check="$3" verif="$4" COPROC
    IFS=' ' read -a args <<<"$2"
    local -n _sqlin=SQLIN _sqlout=SQLOUT
    mkBound bound
    case $cmd in
        psql ) sqlreqbound='EXTRACT(\047EPOCH\047 FROM now())' ;;
        mysql|mariadb ) sqlreqbound='UNIX_TIMESTAMP()' ;;
        sqlite* ) sqlreqbound='STRFTIME(\047%%s\047,DATETIME(\047now\047))' ;;
        * ) echo >&2 "WARNING '$cmd' not known as SQL client";;
    esac
    
    exec {SQLERR}<> <(: p)
    coproc stdbuf -o0 $command "${args[@]}" 2>&$SQLERR
    _sqlin=${COPROC[1]} _sqlout=$COPROC 
}
mySqlReq() {
    # return nothing but set two (or tree if error) variables: `$1`, containing
    # sql answer and `${1}_h` containing header fields and ${1}_e for
    # errors if        .
    local -n result=$1 result_h=${1}_h result_e=${1}_e
    result=() result_h=''  result_e=()
    local line head=""
    shift

    ### Send request and request for outputing bound...
    printf >&$SQLIN '%s;\nSELECT '"${sqlreqbound}"' AS "%s";\n' "$@" $bound

    read -ru $SQLOUT line
    if [ "$line" != "$bound" ] ;then
	IFS=$'\t' read -a result_h <<< "$line";
	while read -ru $SQLOUT line && [ "$line" != "$bound" ] ;do
	    result+=("$line")
	done
    fi
    read -ru $SQLOUT line
    lastsqlread="$line"
    # then once bound readed without timeout, we could read SQLERR
    # read -t 0 don't read, but success only if data available
    if read -u $SQLERR -t 0 ;then
	while read -ru $SQLERR -t .02 line;do
	    result_e+=("$line")
	done
    fi
}
    
# newSqlConnector /usr/bin/sqlite3 $'-separator \t -header /dev/shm/test.sqlite'
# newSqlConnector /usr/bin/psql $'-Anh hostname -F \t --pset=footer=off user'
# newSqlConnector /usr/bin/mysql  '-h hostname -B -p database'
