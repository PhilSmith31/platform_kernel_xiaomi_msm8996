#!/usr/bin/env python

import datetime, sys

name = sys.argv[1]

# open text file containing the make output
f = open(name + '.txt', "r")
lines = f.readlines()
f.close()

# create a new file that is gonna contain only the warnings
fw = open(name + '_warnings.txt', "w+")
fw.write("Current time & date:\n")
fw.write(str(datetime.datetime.now()))
fw.write("\n\n")

isWarning = False

# extract warnings
for line in lines:
    if "warning: " in line:
        fw.write(line)
        fw.write("\n") 
fw.close()