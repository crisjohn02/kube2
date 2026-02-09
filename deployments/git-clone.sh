#!/bin/bash

if [[ "$1" == "" ]]; then
    logger "Script called without param"
    exit 1
fi

git clone "github.com:ssr-platforms/${1}.git"