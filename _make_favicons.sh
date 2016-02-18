#!/bin/sh

# Quick script to make favicons

# Sizes to make
sizes=( '192x192'
        '160x160'
	'96x96'
	'16x16'
	'32x32'
)

if [ -z "$1" ]; then
	echo 'No source file specified'
	exit 1
fi

for size in $sizes; do
	convert "$1" -resize "$size" "favicon-$size.png"
done
