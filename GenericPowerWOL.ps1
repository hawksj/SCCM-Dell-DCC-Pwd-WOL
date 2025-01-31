# Created by Sam Hawkins to deploy Dell Command | Configure executables and reliably and accurately report error codes to SCCM
##############################################################################################################################
# View error codes at https://web.archive.org/web/20230128174109/https://www.dell.com/support/kbdoc/en-us/000147084/dell-command-configure-error-codes

$PwExePath = $PSScriptRoot + "\multiplatform_GenericSetupPass_x64.exe" #$PSScriptRoot is an automatic variable set to the directory the script is stored in  (in this case, a random folder in ccmcache)
$PowerExePath = $PSScriptRoot + "\multiplatform_GenericPowerWOL_x64.exe" #Append the file name to the directory to form a full file path

$KeepLogsFor_Days = 4 #how many days to keep logs before deleting them
$ExitCode = 1 #default error code

Function ArchiveLogFiles {
    $CurrentLog = "GenericSetupPass_$((Get-Date).ToString('yyyy-MM-dd_HH-mm-ss')).log" #sets new file name describing the log file and with today's date and time to separate it from the others
    New-Item -Name $CurrentLog -ItemType file -Path C:\HSFC\Logs\ -Force | Out-Null # as above
    $SetupPassLogName = (Get-ChildItem *GenericSetupPass*.txt) #find log file in the current directory and store object in a variable

    Try {
        Add-Content -Path C:\HSFC\Logs\$CurrentLog -Value (Get-Content($SetupPassLogName)) #try to read current log file, then copy the contents to the archive with the current time
    }
    Catch {
        Add-Content -Path C:\HSFC\Logs\$CurrentLog -Value ("$($_.InvocationInfo.Line) $($_.Exception.Message) `n Log file (probably) not found during execution") #if the file doesn't exist, PS will exit with error. this is to catch the error and write content to the archive
    }

    $CurrentLog = "GenericPowerWOL_$((Get-Date).ToString('yyyy-MM-dd_HH-mm-ss')).log" #performs the exact same process as above but for the other log file
    New-Item -Name $CurrentLog -ItemType file -Path C:\HSFC\Logs\ -Force | Out-Null
    $PowerWOLLogName = (Get-ChildItem *GenericPowerWOL*.txt)

    Try {
        Add-Content -Path C:\HSFC\Logs\$CurrentLog -Value (Get-Content($PowerWOLLogName))
    }
    Catch {
        Add-Content -Path C:\HSFC\Logs\$CurrentLog -Value ("$($_.InvocationInfo.Line) $($_.Exception.Message) `n Log file (probably) not found during execution")
    }

    Remove-Item $PSScriptRoot\*.txt #once logs are archived, delete all existing logs. We only want the most recent execution, previous logs will confuse the script when reading the exit code
}

Function DeleteArchivedLogs {
    Get-ChildItem -Path C:\HSFC\Logs\*.log -Force | Where-Object { $_.CreationTime -lt ((Get-Date).AddDays(-$KeepLogsFor_Days)) } | Remove-Item -Force #find every log file, filter that to those that were created more than $KeepLogsFor_Days ago, delete all that are filtered
}


Function SetBIOSPassword {
    If (!(Test-Path -Path "C:\HSFC\pwset.txt")) { #check if set password exe has already been applied

        Start-Process -wait $PwExePath #execute the file to set the BIOS password on machines without one
        $SetupPassLogName = (Get-ChildItem *GenericSetupPass*.txt) #find the log file and store the object in a variable

        if (($SetupPassLogName | Select-String -Quiet -CaseSensitive "Vendor Software Return Code: 141")) { #141 is the error code when the exe can't reach the BIOS with ACPI (this may mean the BIOS is too old, requires update)
            $ExitCode = 322141 #exit code specifying issue with ACPI
        }
        elseif ($SetupPassLogName | Select-String -Quiet -CaseSensitive "Vendor Software Return Code: 140") {
            $ExitCode = 322140 #exit code specifying issue with ACPI
        }
        else {
            New-Item -Name pwset.txt -ItemType file -Path C:\HSFC\ -Force | Out-Null #the exe will report failure if the password is already set. If the failure wasn't caused by ACPI, it's probably already set so make the text file
        }
    }
    return $ExitCode
}

Function SetBIOSSettings {
    If (!(Test-Path -Path "C:\HSFC\wolset.txt")) { #check if WOL settings have already been applied

        Start-Process -wait $PowerExePath #execute the file to set all other BIOS settings (WOL, sleep, etc)
        $PowerWOLLogName = (Get-ChildItem *GenericPowerWOL*.txt) #find the log file and store the object in a variable

        If ($PowerWOLLogName | Select-String -Quiet -CaseSensitive "Vendor Software Return Code: 0") { #read the log and check for success message
            New-Item -Name wolset.txt -ItemType file -Path C:\HSFC\ -Force | Out-Null #if the log reports success, write the confirmation file
            $ExitCode = 0 #set success exit code
        }
        Else { 
            $LogFileContents = @(Get-Content $PowerWOLLogName) #if the exe doesn't exit with code 0, read the entire contents of the log and store it in a variable
            Foreach ($line in $LogFileContents) {
                If ($line -like "*Vendor Software Return Code:*") { #search through every line of the log file and look for the line that contains the exit code
                    $VendorReturnCode = @($line.Split(" "))[-1] #split the line by spaces and read the last entry in the resulting array, which is only the exit code
                }
            }
            
            $ExitCode = [int]("322" + $VendorReturnCode) #return 322 (specifying Dell Command Configre/DCC error code), followed by the actual exit code
        }
    }
    return $ExitCode
}

ArchiveLogFiles
DeleteArchivedLogs
$ExitCode = SetBIOSPassword
$ExitCode = SetBIOSSettings

[System.Environment]::Exit($ExitCode) #exit the script with the set exit code
