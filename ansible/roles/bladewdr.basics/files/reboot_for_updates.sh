#!/usr/bin/env bash

if [ -f /var/run/reboot-required ]; then
    shutdown -r now
fi
