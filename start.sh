#!/usr/bin/env bash
set -e
PORT="${1:-8000}"
exec /home/droid/j9.7/bin/jconsole -js "0!:0 <'/home/droid/j-sensor-hub/server.ijs'" "start_server ${PORT}"
