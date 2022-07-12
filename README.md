# Connector-bash

== We're Using GitHub Under Protest ==

This project is currently hosted on GitHub.  This is not ideal; GitHub is a
proprietary, trade-secret system that is not Free and Open Souce Software
(FOSS).  We are deeply concerned about using a proprietary system like GitHub
to develop our FOSS project.  For further version of this projects, have a look
[My web bazzar ](https://f-hauri.ch/vrac/?C=M;O=D) where most of my ideas are
still published until I made a choice for further shares...

We urge you to read about the [Give up GitHub](https://GiveUpGitHub.org)
campaign from [the Software Freedom Conservancy](https://sfconservancy.org) to
understand some of the reasons why GitHub is not a good place to host FOSS
projects.

If you are a contributor who personally has already quit using GitHub, please
[send mail to gitproj@f-hauri.ch](mailto://gitproj@f-hauri.ch) for any comment
or contributions without using GitHub directly.

Any use of this project's code by GitHub Copilot, past or present, is done
without our permission.  We do not consent to GitHub's use of this project's
code in Copilot.

![Logo of the GiveUpGitHub campaign](https://sfconservancy.org/img/GiveUpGitHub.png)

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
