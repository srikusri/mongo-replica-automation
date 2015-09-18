#This script will install MongoDB
#if you get restriction error try "Set-ExecutionPolicy RemoteSigned" or "Set-ExecutionPolicy Unrestricted" in powershell before running this script
#To use run this script in windows powershell and execute 
#Standalone:
#.\mongodb.ps1 -path <mongodb-data-folder>
#Replication
#On PRIMARY: .\mongodb.ps1 -path <mongodb-data-folder> -primary
#On SECONDARY: .\mongodb.ps1 -path <mongodb-data-folder>  -primaryhost <hostname-of-PRIMARY-system>
#Replication with Auth
#On PRIMARY: .\mongodb.ps1 -path <mongodb-data-folder> -primary -auth -password <your-password>
#On SECONDARY: .\mongodb.ps1 -path <mongodb-data-folder>  -primaryhost <hostname-of-PRIMARY-system> -auth -password <your-password>
param([string]$path="C:\mongodb",[switch]$primary = $false,[string]$primaryhost,[switch]$auth = $false,[string]$password="password")

$mongoDbPath = $path
write-output "Installing MongoDB at '$mongoDbPath'"

$mongoDbConfigPath = "$mongoDbPath\mongod.conf"
$replicaScript = "$mongoDbPath\replica.js" 
$url = "https://fastdl.mongodb.org/win32/mongodb-win32-x86_64-2008plus-2.6.11.zip" 
$zipFile = "$mongoDbPath\mongo.zip" 
$unzippedFolderContent ="$mongoDbPath\mongodb-win32-x86_64-2008plus-2.6.11"

if ((Test-Path -path $mongoDbPath) -eq $True)
{ 
	write-host "Seems you already installed MongoDB"
	exit 
}

write-output "creating required directories"
md $mongoDbPath 
md "$mongoDbPath\log" 
md "$mongoDbPath\data" 
md "$mongoDbPath\data\db"

if($auth){
	if($primary) {
		write-output "`r`nGenerating key file with random data at $mongoDbPath\mongo.key"
		$chars = [Char[]]"abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
		($chars | Get-Random -Count 50) -join "" > $mongoDbPath\mongo.key
		Copy-Item $mongoDbPath\mongo.key .	
	}
	if($primaryhost) {
		Copy-Item "mongo.key" $mongoDbPath
	}
}

write-output "`r`ncreating mongodb config file"
[System.IO.File]::AppendAllText("$mongoDbConfigPath", "storage:`r`n    dbPath: $mongoDbPath\data\db`r`nsystemLog:`r`n    destination: file`r`n    path: $mongoDbPath\log\mongo.log`r`n    logAppend: true`r`nreplication:`r`n    replSetName: mongo-replica`r`nnet:`r`n    http:`r`n        enabled: false")
if($primaryhost){
	if($auth && $password){
		[System.IO.File]::AppendAllText("$mongoDbConfigPath", "`r`nsecurity:`r`n    keyFile: $mongoDbPath\mongo.key")
	}
}

write-output "downloading mongodb from $url please wait"
$webClient = New-Object System.Net.WebClient 
$webClient.DownloadFile($url,$zipFile)

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

if($primary) {
	write-output "Settingup Mongodb replica set"
	& $mongoDBPath\bin\mongo.exe --eval "rs.initiate();quit();";	
	if($auth && $password){
		& net stop mongodb
		Start-Sleep -s 10
		[System.IO.File]::AppendAllText("$mongoDbConfigPath", "`r`nsecurity:`r`n    keyFile: $mongoDbPath\mongo.key")
		write-output "Settingup Mongodb replica set with auth"
		[System.IO.File]::AppendAllText("$replicaScript", "db = db.getSiblingDB('admin');`r`ndb.createUser({user: `"siteUserAdmin`", pwd: `"$password`", roles: [ { role: `"userAdminAnyDatabase`", db: `"admin`" } ]});")
		[System.IO.File]::AppendAllText("$replicaScript", "`r`ndb.auth(`"siteUserAdmin`", `"$password`");")
		& net start mongodb
		Start-Sleep -s 10
		& $mongoDBPath\bin\mongo.exe $replicaScript	
	}
}

if($primaryhost){
	$primaryhost = $primaryhost+":27017";
	$secondary = $env:computername+":27017";
	write-output "Adding $secondary to Mongodb replica set"
	if($auth && $password){
		& $mongoDBPath\bin\mongo.exe $primaryhost --eval "db = db.getSiblingDB(`"admin`");db.auth(`"siteRootAdmin`", `"$password`");rs.add(`'$secondary`');quit();"
	}else{
		& $mongoDBPath\bin\mongo.exe $primaryhost --eval "rs.add(`'$secondary`');quit();"	
	}	
}
