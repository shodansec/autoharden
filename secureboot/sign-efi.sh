#!/usr/bin/sh

sbsign --key $(pwd)/DB.key --cert $(pwd)/DB.crt --output $1 $1
