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

