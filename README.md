# Connector-bash

Copying:
--------

As bash, this stuff is licensed under GNU GPL v3.0 or later.

Introduction:
-------------

In order to avoid multiple forks to some regular tools like `date`, `bc`
and any *line-by-line* converter, based on

    coproc bc -l

Then

    echo "3*4" >&${COPROC[1]}
    read -u $COPROC foo
    echo $foo
    12

    echo >&${COPROC[1]} "pi=4*a(1)"
    echo >&${COPROC[1]} "2*pi*12"
    read -u $COPROC foo
    echo $foo
    75.39822368615503772256

There is a function for building I/O connectors:

    . shell_connector.bash
    newConnector /usr/bin/bc "-l" 1 1
    myBc '4*a(1)' PI
    declare -p PI
    declare -- PI="3.14159265358979323844"

And for tools able to answer *0* or *many* lines, like *SQL Clients*,
there is another function:

    ostty=$(stty -g) && stty -echo
    newSqlConnector /usr/bin/mysql "-h hostOrIp -p'$(head -n1)' -B database"
    stty $ostty
    mySqlReq answer 'SELECT * FROM mytable;'
    declare -p answer answer_h answer_e

where all variables are *arrays*, first one `answer` will contain all rows,
`answer_h` will hold header and `answer_e` error messages if any..
