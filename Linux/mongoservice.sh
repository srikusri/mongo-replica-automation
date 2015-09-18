#!/bin/sh 
#MONGOBIN -> point to mongod binary. 
 
MONGOBIN="/var/mongodb/bin/mongod" 
 
do_start() 
{ 
   echo "Starting MongoDB!"; 
   eval "$MONGOBIN -f /etc/mongod.conf"; 
} 
 
do_stop() 
{ 
   echo "Stopping MongoDB!" 
   eval "$MONGOBIN -f /etc/mongod.conf --shutdown"; 
} 
 
case "$1" in 
   start) 
      do_start 
      ;; 
   stop) 
      do_stop 
      ;; 
esac 
 
exit 0