#!/bin/bash

mkBound() {
    # mkBound() - Generate a unique boundary string
    # 
    # This function generates a unique boundary string that is used to delimit the output 
    # from sub-commands executed as co-processes, especially useful for SQL responses with variable length.
    # 
    # Parameters:
    # $1 (optional) - The name of the variable that will hold the generated boundary string. 
    #                 If not provided, defaults to a variable named "bound".
    # 
    # The generated boundary string is a sequence of 30 random alphanumeric characters and has the format: 
    # "--xxxxxxx-xxxx-xxxx-xxxx-xxxx-xxxx-", where "x" stands for a random character.
    # 
    # Constants:
    # BOUNDARY_LENGTH - The length of the boundary string to be generated.
    # BOUNDARY_ITERATIONS - The number of iterations in the loop for generating the boundary string.
    # BOUNDARY_MASK - The mask used for selecting bits from the pseudo-random numbers.
    # BOUNDARY_SHIFT - The number of bits to shift for the next character in the boundary string.
    # 
    # Notes: 
    # - Builds some uniq 30 random char string from 12 $RANDOM values:
    #   RANDOM is 15 bits. 15 x 2 = 30 bits -> 5 x 6 bits char
    # - The function uses bash's $RANDOM to generate pseudo-random numbers. This may not be suitable for 
    #   applications that require cryptographically strong random numbers.

    # Constants for boundary construction
    local BOUNDARY_LENGTH=30
    local BOUNDARY_ITERATIONS=6
    local BOUNDARY_MASK=63
    local BOUNDARY_SHIFT=6

    # Named reference to output variable
    local -n result=${1:-bound}

    # The string used for generating the boundary
    local _Bash64_refstr _out= _l _i _num
    printf -v _Bash64_refstr "%s" {0..9} {a..z} {A..Z} @ _ 0

    # Generate boundary by looping BOUNDARY_ITERATIONS times
    # Construct BOUNDARY_LENGTH chars by shifting and masking RANDOM values
    for ((_l=BOUNDARY_ITERATIONS;_num=(RANDOM<<15|RANDOM),_l--;));do
	for ((_i=0;_i<BOUNDARY_LENGTH;_i+=BOUNDARY_SHIFT));do
	    _out+=${_Bash64_refstr:(_num>>_i)&BOUNDARY_MASK:1}
	done
    done

    # Format the output into "--xxxxxxx-xxxx-xxxx-xxxx-xxxx-xxxx-"
    printf -v result -- "--%s-%s-%s-%s-%s-%s-" ${_out:0:7} \
	   ${_out:7:4} ${_out:11:4} ${_out:15:4} \
	   ${_out:19:4} ${_out:23};
}

# instanciator for myXxx() function associated to a started and long-running
# instance of the requested command and arguments and initial input data
# (the command will be associated to two descriptors XXIN and XXOUT, local to
#  the instanciated function)
newConnector() {
    # newConnector() - Initiates a long-running subprocess for a given command.
    #
    # This function sets up a long-running co-process using the provided command and arguments. It creates two
    # file descriptors associated with the co-process to manage data interaction. It also creates a function
    # dynamically that sends input to the command and reads its output.
    #
    # Parameters:
    # command - The command to be run as a co-process.
    # args - The arguments to be passed to the command.
    # check - The initial input to be sent to the co-process for verification.
    # verif - The expected output from the command when 'check' is sent as input.
    #
    # Returns:
    # None directly. However, it prints a warning message to STDERR if the verification of the co-process fails.
    #
    # Constants:
    # cinfd - File descriptor for input to the co-process.
    # coutfd - File descriptor for output from the co-process.
    #
    # Notes: 
    # - The function is named 'my' followed by the capitalized command name (e.g., myBc, myDate).
    # - The function sends input to the command and reads the output into the 'result' variable.
    # - The function prints the result to STDOUT if there is no second argument.
    # - If the 'check' input does not yield the 'verif' output, a warning is printed to STDERR.

    local command="$1" cmd=${1##*/} args="$2" check="$3" verif="$4"
    shift 4
    local initfile input
    local -n cinfd=${cmd^^}IN coutfd=${cmd^^}OUT

    # Start a new co-process using the provided command and arguments
    # The output of the command is unbuffered (-o0 option to stdbuf)
    # This co-process can interact with the main process via its standard input and output
    coproc stdbuf -o0 $command $args 2>&1
    cinfd=${COPROC[1]} coutfd=$COPROC 

    # Feed the initialization file to the command
    for initfile ;do
	cat >&${cinfd} $initfile
    done

    # Dynamically create a function that sends input to the command and reads its output
    # The function name is 'my' followed by the capitalized command name (e.g., myBc, myDate)
    # The function takes one argument, sends it to the command, and reads the response into the 'result' variable
    source /dev/stdin <<-EOF
	my${cmd^}() {
	    local -n result=\${2:-${cmd}Out} # Name reference to the output variable
	    # Send input to the command
	    echo >&\${${cmd^^}IN} "\$1" &&
	    # Read the response with a timeout of 3 seconds
	    read -u \${${cmd^^}OUT} -t 3 result
	    # If there is no second argument, print the result
	    ((\$#>1)) || echo \$result
	}
	EOF

    # Check the command by sending the 'check' input and comparing the response to 'verif'
    my${cmd^} $check input
    if [ "$input" != "$verif" ]; then
	printf >&2 "WARNING: Don't match! '%s' <> '%s'.\n" "$verif" "$input"
    fi
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
# newSqlConnector /usr/bin/sqlite3 $'-separator \t -header /dev/shm/test.sqlite'
# newSqlConnector /usr/bin/psql $'-Anh hostname -F \t --pset=footer=off user'
# newSqlConnector /usr/bin/mysql  '-h hostname -B -p database'

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
