#This script will install MongoDB
#if you get restriction error try "Set-ExecutionPolicy RemoteSigned" or "Set-ExecutionPolicy Unrestricted" in powershell before running this script
#To use run this script in windows powershell and execute 
#Standalone:
#.\mongodb_upgrade.ps1 -currpath <current-mongodb-bin-folder> -dbpath <mongodb-data-folder> [-port <dbport> -dbname <dbname>]
#With auth
#.\mongodb_upgrade.ps1 -currpath <current-mongodb-bin-folder> -dbpath <mongodb-data-folder> -auth -username <username> -password <password> [-port <dbport> -dbname <dbname>] 
param([string]$currpath="",[string]$dbpath = "",[switch]$auth = $false,[string]$username="",[string]$password="",[string]$port=27017,[string]$dbname="social")

$mongoDbPath = $path
write-output "Updating MongoDB at '$mongoDbPath'"
if ((Test-Path -path $currpath) -eq "") { 
	write-host "Please provide current mongodb binary path with -currpath"
	exit 
}
if ((Test-Path -path $dbpath) -eq "") { 
	write-host "Please provide current mongodb data folder path with -dbpath"
	exit 
}
if ($auth) { 
	if($username -eq "") {
		write-host "Please provide mongodb username for social db"
		exit 
	}
	if($password -eq "") {
		write-host "Please provide mongodb password for social db"
		exit 
	}
}
$bkup = "$dbpath\backup"
$mongoDbPath = "$dbpath\new"
md $bkup
if($auth) {
	& $currpath\mongodump.exe --port $port --username $username --password $password --db $dbname --out $bkup
} else {
	& $currpath\mongodump.exe --port $port  --db $dbname --out $bkup
}

& net stop mongodb
& $currpath\mongod.exe --remove

$mongoDbConfigPath = "$mongoDbPath\mongod.conf"

$zipFile = "$mongoDbPath\mongo.zip" 
$unzippedFolderContent ="$mongoDbPath\mongodb-win32-x86_64-2008plus-3.0.6"

write-output "creating required directories"
md $mongoDbPath 
md "$mongoDbPath\log" 
md "$mongoDbPath\data" 
md "$mongoDbPath\data\db"

write-output "`r`ncreating mongodb config file"
[System.IO.File]::AppendAllText("$mongoDbConfigPath", "storage:`r`n    dbPath: $mongoDbPath\data\db`r`n    engine: wiredTiger`r`nsystemLog:`r`n    destination: file`r`n    path: $mongoDbPath\log\mongo.log`r`n    logAppend: true`r`nnet:`r`n    port: $port`r`n    http:`r`n        enabled: false")

write-output "Copying mongodb binaries"
Copy-Item "mongo.zip" $mongoDbPath

$shellApp = New-Object -com shell.application 
$destination = $shellApp.namespace($mongoDbPath) 
$destination.Copyhere($shellApp.namespace($zipFile).items())

write-output "unziping files..."
Copy-Item "$unzippedFolderContent\*" $mongoDbPath -recurse

write-output "removing unwanted files..."
Remove-Item $unzippedFolderContent -recurse -force 
Remove-Item $zipFile -recurse -force

write-output "installing mongodb service"
& $mongoDBPath\bin\mongod.exe --config $mongoDbConfigPath --install

write-output "Starting Mongodb"
& net start mongodb
Start-Sleep -s 20
& $mongoDBPath\bin\mongorestore  --port $port $bkup