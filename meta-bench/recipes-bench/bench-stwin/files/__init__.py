"""The STWIN.box BLE gateway of Project 17.

Four modules, split along the lines that can be tested separately:

    bluest.py      the protocol: bytes to numbers, a pure function
    sinks.py       where a record goes: file, broker, LEDs
    supervisor.py  the state machine: scan, connect, stream, back off
    blelink.py     the only module that imports bleak

The split is what makes three of the four testable on a laptop with no
radio, no controller and no D-Bus daemon. blelink.py is the part that can
only be tested on a board, and it is deliberately the smallest.

SPDX-License-Identifier: MIT
"""
