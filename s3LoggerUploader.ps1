function twoDigit ($num){
    #Receives a number and returns a two digit string representing the number
    $num = $num.ToString()
    If ($num.length -lt 2){
        $num = '0'+ $num
    }
    $num
}

#Set global variables for directory traverse
$year = get-date -format yyyy
$currentMonth = get-date -format MM
$previousMonth = twoDigit($currentMonth - 1)
$currentDay = get-date -format dd
$previousDay = twoDigit($currentDay - 1)
$currentHour = get-date -format HH
$curMonDir = "C:\Upload\"+$year+"-"+$currentMonth
$prevMonDir = "C:\Upload\"+$year+"-"+$previousMonth

# Set the AWS user credentials and the name of the S3 bucket
$accessKey = ''
$secretKey = ''
$s3Bucket = ''

function log($filename){
    #logs the uploaded time and S3 object name for each file
    [string]$tmp = get-date
    write-host $filename
    $log = $tmp + "                 " + $filename
    Add-Content C:\Upload\log.txt $log
}

function isActiveLog ($filename){
    #checks to see if the log is the one currently being written to
    return ($currentHour -eq $filename.Substring(21,2))
}
    
function upload ($s3Keyname, $backupName){
    <#Upload file to S3 and call log function
    Reuires the key/value pair for S3 and the path/filename where the file to be uploaded is stored
    Assumes you have global variables for your S3 bucket and AWS keys#>
    Write-S3Object -BucketName $s3Bucket -Key $s3Keyname -File $backupName -AccessKey $accessKey -SecretKey $secretKey
    log($s3Keyname)
}


function handleFiles($keyPrefix, $keyPrefix2){
    $loco = "C:\Upload\" + $keyPrefix + "\" + $keyPrefix2
    Set-Location $loco
    # Get the mp3 files in the day directory              
        Get-ChildItem *.mp3 | ForEach-Object {
            $backupName = $_.Name
            #skip the log currently being written
            if (!(isActiveLog($backupName))){
                <# Convert time portion of the logger filename to UTC format
                   We are not renaming the file locally because Windows does not support colons in filenames
                   We are renaming the file as it is written to S3 using the $s3Keyname variable #>
                $offset = Get-Date -UFormat "%Z"
                $s3Keyname = $keyPrefix + "/" + $keyPrefix2 + "/" + $backupName.Substring(0,23) + ":00:00" + $offset + ":00.mp3"
                upload $s3Keyname $backupName
                Rename-Item -path ($loco + "\" + $backupName) -NewName $backupName.Replace('.mp3','.log')
                }
            }
}

function handleMonth($monthFolder){
#Finds all day folders in the month folder and passes the month & day folders to the handleFiles function
    $loco = "C:\Upload\" + $monthFolder
    #Change location to the year/month directory
    Set-Location $loco
    Get-ChildItem | Foreach-Object {
            if ($_.PSIsContainer) { #Checks if there are "day" subdirectores to loop through in the "year/month" directory
                # Capture the name of the day folder
                $dayFolder = $_.name
                handleFiles $monthFolder $dayFolder
            }
    }
}

function deleteUploadedLogs ($directory){
    # Takes a month folder as a parameter
    # deletes log files older than 3 days
    # Get all the files in the folder and subfolders | foreach file
    Get-ChildItem $directory -Recurse -File | foreach{
        # if creationtime is 'le' (less or equal) than 3 days
        if ($_.CreationTime -le (Get-Date).AddDays(-3)){
            # remove the item
            Remove-Item $_.fullname -Force
        }
}
}

function deleteEmptyDayFolders ($directory){
    # Takes a month folder as a parameter
    # Deletes empty folders and subfolders -- folders become empty as a result of deleteUploadedLogs
    # Do not use against C:\Upload -- it will delete any empty folders in the directory
    Get-ChildItem $directory -directory -recurse | Where { (gci $_.fullName).count -eq 0 } | select -expandproperty FullName | Foreach-Object { Remove-Item $_ }
}

function deleteMonthFolder ($directory, $DD){
    # Takes month folder and day in DD format as parameters
    # Deletes the folder if it is the 4th day of the month
    if ($DD -eq '04'){
        Remove-Item $directory -recurse -force
    }
}

####### Begin Controller #######

#If a folder for the previous month exists
If (test-path($prevMonDir)){
    handleMonth($year+"-"+$previousMonth)
    deleteUploadedLogs($prevMonDir)
    deleteEmptyDayFolders ($prevMonDir)
    deleteMonthFolder $prevMonDir $currentDay
}
#process current month's folder
handleMonth($year+"-"+$currentMonth)
deleteUploadedLogs($curMonDir)
deleteEmptyDayFolders ($curMonDir)
