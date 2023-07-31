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
    printf -v result -- "--%s-%s-%s-%s-%s-%s-" "${_out:0:7}" \
	   "${_out:7:4}" "${_out:11:4}" "${_out:15:4}" \
	   "${_out:19:4}" "${_out:23}";
}

newConnector() {
    # newConnector() - Initiate a long-running subprocess for a given command and associates it with two file descriptors.
    #
    # This function sets up a long-running co-process using the provided command and arguments. It creates two
    # file descriptors XXIN and XXOUT associated with the co-process to manage data interaction, where 'XX' is the 
    # uppercase form of the command name. It also dynamically creates a function, named 'myXxx', to interact with the co-process.
    # 'Xxx' corresponds to the capitalized form of the command name.
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
    # cinfd - File descriptor for input to the co-process (XXIN).
    # coutfd - File descriptor for output from the co-process (XXOUT).
    #
    # Notes: 
    # - The function 'myXxx' sends input to the command and reads the output into the 'result' variable.
    # - The function 'myXxx' prints the result to STDOUT if there is no second argument.
    # - If the 'check' input does not yield the 'verif' output, a warning is printed to STDERR.
    local command="$1" cmd=${1##*/} args="$2" check="$3" verif="$4"
    shift 4
    local initfile input
    local -n cinfd=${cmd^^}IN coutfd=${cmd^^}OUT

    # Start a new co-process using the provided command and arguments
    # The output of the command is unbuffered (-o0 option to stdbuf)
    # This co-process can interact with the main process via its standard input and output
    coproc stdbuf -o0 "$command" "$args" 2>&1
    cinfd=${COPROC[1]} coutfd=$COPROC 

    # Feed the initialization file to the command
    for initfile ;do
	cat >&"${cinfd}" "$initfile"
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
    my"${cmd^}" "$check" input
    if [ "$input" != "$verif" ]; then
	printf >&2 "WARNING: Don't match! '%s' <> '%s'.\n" "$verif" "$input"
    fi
}

declare bound sqlreqbound SQLIN SQLOUT SQLERR lastsqlread

newSqlConnector() {
    # newSqlConnector() - Establish a connection to a specified SQL client
    # 
    # Establishes a long-running connection to an SQL client, 
    # and prepares the environment necessary for executing SQL queries on that client.
    # It supports SQLite, MySQL, MariaDB, and PostgreSQL.
    # The output length is not fixed and could be empty.
    # 
    # Synopsis:
    # newSqlConnector /usr/bin/sqlite3 $'-separator \t -header /dev/shm/test.sqlite'
    # newSqlConnector /usr/bin/psql $'-Anh hostname -F \t --pset=footer=off user'
    # newSqlConnector /usr/bin/mysql  '-h hostname -B -p database'
    #
    # Parameters:
    # $1 (command) - The command to execute (i.e., the SQL client)
    # $2 (args) - The command-line arguments for the SQL client
    # $3 (check) and $4 (verif) - Not used in the current function scope
    # 
    # Returns:
    # None directly. But it sets up SQL input and output file descriptors 
    # for subsequent interaction with the SQL client.
    #
    # Constants:
    # COPROC - Array variable from the coproc keyword in bash, holding the file descriptors for co-process.
    # SQLERR - A file descriptor for the SQL client's error stream
    # 
    # Notes: 
    # - The function assumes that the command passed to it is an executable, 
    #   so it should be validated before calling this function.
    # - If an unknown SQL client is passed, the function will print a warning but will not terminate.

    # Take the SQL client command and command arguments as input
    local command="$1" cmd=${1##*/} args check="$3" verif="$4" COPROC
    # Split the command arguments
    IFS=' ' read -a args <<<"$2"
    # Create file descriptors for SQL input and output
    local -n _sqlin=SQLIN _sqlout=SQLOUT
    # Generate a unique boundary string
    mkBound bound
    # Determine the SQL client and set `sqlreqbound` for each client
    case $cmd in
	psql ) sqlreqbound='EXTRACT(\047EPOCH\047 FROM now())' ;;
	mysql|mariadb ) sqlreqbound='UNIX_TIMESTAMP()' ;;
	sqlite* ) sqlreqbound='STRFTIME(\047%%s\047,DATETIME(\047now\047))' ;;
	* ) 
        # If the SQL client is not recognized, give a warning
        echo >&2 "WARNING '$cmd' not known as SQL client";;
    esac

    # Create a new file descriptor for SQL error stream
    exec {SQLERR}<> <(: p)
    # Start the SQL client as a co-process, with its standard error redirected to `SQLERR`
    coproc stdbuf -o0 "$command" "${args[@]}" 2>&$SQLERR
    # Store the file descriptors for the co-process's standard input and output
    _sqlin=${COPROC[1]} _sqlout=$COPROC 
}

mySqlReq() {
    # mySqlReq() - Send SQL commands to the co-process SQL client and manages responses
    #
    # This function takes the name of a variable as the first argument. It sends an SQL command
    # to the SQL client and reads the response. The function doesn't return any value but populates 
    # three variables: `$1`, containing sql answer, `${1}_h` containing header fields and `${1}_e` for errors, if any.
    #
    # Synopsis:
    # mySqlReq result "SELECT * FROM table_name"
    # echo "SELECT * FROM table_name" | mySqlReq result
    #
    # Parameters:
    # $1 - Name of the variable where the result of the SQL command will be stored.
    # $@ - SQL command to be executed.
    #
    # Returns:
    # Does not return a value but populates `$1`, `${1}_h`, and `${1}_e` variables.
    #
    # Constants:
    # sqlreqbound - A unique boundary string that separates command outputs from SQL outputs.
    #
    # Notes: 
    # - The function waits indefinitely for the SQL client to respond.
    # - The function heavily depends on the `newSqlConnector` function to create the SQL client co-process.
    # - It can handle responses from different SQL clients like sqlite, mysql, mariadb, and postgresql.
    # - It can read SQL commands from standard input if none are provided as arguments.

    # Initialize three variables for storing results, headers and any error messages.
    local -n result=$1 result_h=${1}_h result_e=${1}_e
    result=() result_h='' result_e=()
    local line head=""
    shift

    # If SQL command is provided as argument, send it to the SQL client co-process.
    # Otherwise, read SQL command from standard input and send it to the SQL client co-process.
    if (($#)) ;then
        printf >&"$SQLIN" '%s;\n' "${*%;}"
    else
        local -a _req
        mapfile -t _req
        printf >&"$SQLIN" '%s;\n' "${_req[*]%;}"
    fi

    # Request the output of the unique boundary string which was defined in the `newSqlConnector` function.
    printf >&"$SQLIN" 'SELECT '"${sqlreqbound}"' AS "%s";\n' "$bound"

    # Read the first line of the response from the SQL client co-process.
    # If the first line is not the boundary string, it is the header of the response. Read and store it in `result_h`.
    # Then, continue reading lines (which are the actual response data) until the boundary string is encountered.
    read -ru "$SQLOUT" line
    if [ "$line" != "$bound" ] ;then
        IFS=$'\t' read -a result_h <<< "$line";
        while read -ru "$SQLOUT" line && [ "$line" != "$bound" ] ;do
            result+=("$line")
        done
    fi

    # Read and store the boundary string.
    read -ru "$SQLOUT" line
    lastsqlread="$line"

    # If there are any error messages available on the SQLERR file descriptor, read them into the `result_e` variable.
    if read -u "$SQLERR" -t 0 ;then
        while read -ru "$SQLERR" -t .02 line;do
            result_e+=("$line")
        done
    fi
}
