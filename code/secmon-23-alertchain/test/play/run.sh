#!/bin/bash

alertchain.latest play -d ../policy -s ./scenario -o output
opa test -v .
