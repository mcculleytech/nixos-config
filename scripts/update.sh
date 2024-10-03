#!/usr/bin/env bash

help_message() {
	cat << EOF
A script to update nix servers remotely

Usage: $0 [args]

Options:
  -h	Display help message
  -s	update single server
  -f	update all servers listed in file
EOF
}

if [ $# -eq 0 ]; then
	help_message
	exit 0
fi


while getopts ":h:s:f:" opt;
do
	case ${opt} in
		h) 
		   help_message
		   exit 0
		   ;;
		s) 
		   server=${OPTARG}	
		   nixos-rebuild switch --flake .\#${server} --target-host root@${server}
		   ;;
		f) # WIP 
		   filename=${OPTARG}
	   	   echo $filename	   
		   ;;
	  	?)
		   echo "Invalid Argument: -${OPTARG}" >&2
	   	   help_message
		   exit 1
		   ;;
		:)
            	   echo "Option -${OPTARG} requires an argument." >&2
                   help_message
                   exit 1
            	   ;;
	esac
done


