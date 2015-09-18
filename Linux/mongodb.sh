#!/bin/sh
#To use run this script in windows powershell and execute 
#Standalone:
#./mongodb.sh <mongodb-data-folder>
#Replication
#On PRIMARY: ./mongodb.sh <mongodb-data-folder> primary
#On SECONDARY: ./mongodb.sh <mongodb-data-folder> secondary <hostname-of-PRIMARY-system>
#Replication with AUTH
#On PRIMARY: ./mongodb.sh <mongodb-data-folder> primary "" auth <your-password>
#On SECONDARY: ./mongodb.sh <mongodb-data-folder> secondary <hostname-of-PRIMARY-system> auth <your-password>

MONGOPATH="$HOME/"
PRIMARY=0
PRIMARYHOST=""
AUTH=0
PASSWORD="password"

if [ ! -z "$1" ]
then
	MONGOPATH=$1
fi

if [ "$2" = "primary" ]
then
	PRIMARY=1
fi

if [ ! -z "$3" ]
then
	PRIMARYHOST=$3
fi

if [ "$4" = "auth" ]
then
	AUTH=1
fi

if [ ! -z "$5" ]
then
	PASSWORD=$5
fi

echo "Installing MongoDB at '$MONGOPATH'"

#wget https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-2.6.11.tgz
tar -xf "mongodb-linux-x86_64-2.6.11.tgz"
mkdir -p /var/mongodb/
mv ./mongodb-linux-x86_64-2.6.11/* /var/mongodb/
ln -nfs /var/mongodb/bin/mongod /usr/local/sbin

echo "creating required directories: $MONGOPATH, $MONGOPATH/data, $MONGOPATH/log"
# Ensures the required folders exist for MongoDB to run properly
eval "mkdir -p $MONGOPATH/data"
eval "mkdir -p $MONGOPATH/log"

if [ $AUTH = 1 ]
then
	if [ $PRIMARY = 1 ]
	then
		echo "Generating key file with random data at $MONGOPATH/mongo.key"
		tr -cd '[:alnum:]' < /dev/urandom | fold -w50 | head -n1 > "$MONGOPATH/mongo.key"
		cp "$MONGOPATH/mongo.key" .
	fi
	if [ ! -z "$PRIMARYHOST" ]
	then
		cp "mongo.key" "$MONGOPATH"
	fi
	chmod 700 "$MONGOPATH/mongo.key"
fi

echo "creating mongo config"
printf "storage:\n    dbPath: %s/data\nsystemLog:\n    destination: file\n    path: %s/log/mongod.log\n    logAppend: true
\nprocessManagement:\n    fork: true\nreplication:\n    replSetName: myitsocial\nnet:\n    http:\n        enabled: false" "$MONGOPATH" "$MONGOPATH" > /etc/mongod.conf
if [ ! -z "$PRIMARYHOST" ]
then
	if [ $AUTH = 1 ]
	then
		printf "\nsecurity:\n    keyFile: %s/mongo.key" "$MONGOPATH" >> /etc/mongod.conf
	fi
fi

echo "creating mongodb service"
# Renames it to mongodb and makes it executable
cp ./mongoservice.sh /etc/init.d/mongodb
cd /etc/init.d/ || exit
chmod +x mongodb

# Starts up MongoDB right now
/etc/init.d/mongodb start
sleep 10s

if [ $PRIMARY = 1 ]
then
	echo "setting up mongodb for HA"
	eval "/var/mongodb/bin/mongo --eval 'rs.initiate();quit();'"
	if [ $AUTH = 1 ]
	then
		printf "setting up mongodb for HA with auth\n"
		/etc/init.d/mongodb stop
		sleep 10s
		{
			printf "\nsecurity:\n    keyFile: %s/mongo.key" "$MONGOPATH" >> /etc/mongod.conf
			
			printf "db = db.getSiblingDB('admin');\ndb.createUser({user: \"siteUserAdmin\", pwd: \"%s\", roles: [ { role: \"userAdminAnyDatabase\", db: \"admin\" } ]});" "$PASSWORD"
			printf "\ndb.auth(\"siteUserAdmin\", \"%s\");" "$PASSWORD"
			printf "\ndb.createUser({user: \"siteRootAdmin\",	pwd: \"%s\", roles: [{ role: \"root\", db: \"admin\" }]});" "$PASSWORD"
			printf "\ndb = db.getSiblingDB('social');"
			printf "\ndb.createUser({user: \"socialUser\",	pwd: \"%s\", roles: [{ role: \"dbOwner\", db: \"social\" }]});" "$PASSWORD"
			printf "\ndb.createUser({user: \"esUser\",	pwd: \"%s\", roles: [{ role: \"read\", db: \"social\" }, { role: \"read\", db: \"admin\" }, { role: \"read\", db: \"local\" }]});" "$PASSWORD"
		} >"$MONGOPATH/replica.js"
		/etc/init.d/mongodb start
		sleep 10s
		eval "/var/mongodb/bin/mongo $MONGOPATH/replica.js" 
	fi
fi

if [ ! -z "$PRIMARYHOST" ]
then
	echo "adding $HOSTNAME:27017 to mongodb replicaset"
	secondary="$HOSTNAME:27017"
	if [ $AUTH = 1 ]
	then
		eval "/var/mongodb/bin/mongo $PRIMARYHOST:27017 --eval 'db = db.getSiblingDB(\"admin\");db.auth(\"siteRootAdmin\", \"$PASSWORD\");rs.add(\"$secondary\");quit();'"
	else
		eval "/var/mongodb/bin/mongo $PRIMARYHOST:27017 --eval 'rs.add(\"$secondary\");quit();'"
	fi
fi

#rm -rf /var/mongodb/ /mongodata/ /etc/mongod.conf /etc/init.d/mongodb