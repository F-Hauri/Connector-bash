# Connector-bash

In order to avoid multiple forks to some regular tools like `date`, `bc`
and any *line-by-line* converter, based on

    mkfifo /tmp/myFifoForBc
    exec 5> >(bc -l >/tmp/myFifoForBc)
    exec 6</tmp/myFifoForBc
    rm /tmp/myFifoForBc

Then

    echo "3*4" >&5
    read -u 6 foo
    echo $foo
    12

    echo >&5 "pi=4*a(1)"
    echo >&5 "2*pi*12"
    read -u 6 foo
    echo $foo
    75.39822368615503772256

There is a function for building I/O connectors:

    . shell_connector.sh
    newConnector /usr/bin/bc "-l" 1 1
    myBc '4*a(1)' PI
    declare -p PI
    declare -- PI="3.14159265358979323844"

And for tools able to answer *0* or *many* lines, like *SQL Clients*, there is another function:

    ostty=$(stty -g) && stty -echo
    newSqlConnector /usr/bin/mysql "-h hostOrIp -p'$(head -n1)' -B database"
    stty $ostty
    myMysql answer 'SELECT * FROM mytable;'
    declare -p answer_h answer
 
where both variables are *arrays*, first one `answer_h` will hole header of answer and `answer` is the complete answer.
