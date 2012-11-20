#!/home/binops/afsi/ssm/domain2/tcl-tk_8.5.11_linux26-i686/bin/wish8.5


# look for new log files created under SEQ_EXP_HOME/logs
proc LogMonitor_checkNewLogFiles {} {
   ::log::log debug "LogMonitor_checkNewLogFiles"
   # check every 5 secs
   set nextCheckTime 5000
   set displayGroups [ExpXmlReader_getGroups]

   foreach displayGroup $displayGroups {
      set expList [$displayGroup cget -exp_list]
      foreach expPath $expList {
         set checkDir ${expPath}/logs
         if { [file readable ${checkDir}] } {
            # puts "LogMonitor_checkNewLogFiles checking ${checkDir}"
            set lastCheckedTime [SharedData_getExpData ${expPath} LAST_CHECKED_TIME]
            #set newLastChecked [clock format [clock seconds]]
            set newLastChecked [clock seconds]
            catch { exec ls ${checkDir} > /dev/null }
            set modifiedFiles [exec find ${checkDir} -maxdepth 1 -type f -name "*_nodelog" -newerct [clock format ${lastCheckedTime}] -exec basename \{\} \;]
            foreach modifiedFile ${modifiedFiles} {
               ::log::log debug  "LogMonitor_checkNewLogFiles processing ${expPath} ${modifiedFile}..."
               set seqDatestamp [string range [file tail ${modifiedFile}] 0 13]
               if { [Utils_validateRealDatestamp ${seqDatestamp}] == true } {
                  # look see if we have a thread monitoring this log file, if not create one
                  set expThreadId [SharedData_getExpThreadId ${expPath} ${seqDatestamp}]
                  if { ${expThreadId} == "" } {
                     # if there is already a thread for this datestamp, we don't do anything
                     set expThreadId [ThreadPool_getNextThread]
                     #puts "LogMonitor_checkNewLogFiles set log file offset to 0"
                     # force reread of log file from start
                     SharedData_setExpThreadId ${expPath} ${seqDatestamp} ${expThreadId}

                     #puts "LogMonitor_checkNewLogFiles LogMonitor_startExpLogReader..."
                     ::log::log notice "LogMonitor_checkNewLogFiles(): LogReader_startExpLogReader ${expPath} ${seqDatestamp}"
                     # puts "LogMonitor_checkNewLogFiles(): LogReader_startExpLogReader ${expPath} ${seqDatestamp}"
                     thread::send ${expThreadId} "LogReader_startExpLogReader ${expPath} \"${seqDatestamp}\" all"
                     ::log::log notice "LogMonitor_checkNewLogFiles(): LogReader_startExpLogReader done."
                     # puts "LogMonitor_checkNewLogFiles(): LogReader_startExpLogReader done."
                     # Overview_refreshExpLastStatus ${expPath} ${seqDatestamp}
                  }
               } else {
                  ::log::log notice "ERROR: LogMonitor_checkNewLogFiles():Found invalid log file format: ${expPath} ${modifiedFile}"
                  # puts "LogMonitor_checkNewLogFiles(): Found invalid log file format: ${modifiedFile}"
               }
            }
            if { [expr ${newLastChecked} - ${lastCheckedTime}] > 300 } {
               # to go around nfs latency, I only change the checked time every 5 minutes
               SharedData_setExpData ${expPath} LAST_CHECKED_TIME ${newLastChecked}
            }
         }
      }
   }

   after ${nextCheckTime} [list LogMonitor_checkNewLogFiles]
}

# process log *_nodelog files that have been modified within the _deltaTime window.
# _deltaTime must be a valid date format that can be used with the "-newerct" option of find
# returns a list of files {log_file1 log_file2...} if found else returns empty list
# 
proc LogMonitor_getDatestamps { _exp_path _deltaTime } {
   set checkDir ${_exp_path}/logs
   set modifiedFiles {}
   if { [file readable ${checkDir}] } {
      #puts "LogMonitor_getDatestamps exec find ${checkDir} -maxdepth 1 -type f -name \"*_nodelog\" -newerct ${_deltaTime} -exec basename \{\} \;"
      set modifiedFiles [exec find ${checkDir} -maxdepth 1 -name "*\[0-9\]_nodelog" -newerct ${_deltaTime} -exec basename \{\} \; | cut -c 1-14]
   }
   return ${modifiedFiles}
}

proc LogMonitor_isDatestampVisible { _exp_path _datestamp } {
   set fileModTime [LogMonitor_getDatestampModTime ${_exp_path} ${_datestamp}]
   if { ${fileModTime} > [clock add [clock seconds] -13 hours] } {
      return true
   }
   return false
}

# returns a decimal string giving the modifiction time of the log file
proc LogMonitor_getDatestampModTime { _exp_path _datestamp } {
   set logfile ${_exp_path}/logs/${_datestamp}_nodelog
   return [file mtime ${logfile}]
}

# return the newest log file for an experience
proc LogMonitor_getNewestDatestamp { _exp_path } {
   global env
   set newestFile ""
   #catch { set newestFile [eval exec ls -t [glob -tails -directory ${_exp_path}/logs *_nodelog] | head -1 | xargs basename | cut -c 1-14 ] }
   catch { set newestFile [eval exec $env(SEQ_XFLOW_BIN)/../etc/getNewestDatestamp ${_exp_path}] }
   return ${newestFile}
}

proc LogMonitor_createLogFile { _exp_path _datestamp } {
   set logfile ${_exp_path}/logs/${_datestamp}_nodelog
   if { ! [file exists $logfile] && [file writable ${_exp_path}/logs/] } {
      puts "LogMonitor_createLogFile creating $logfile"
      ::log::log notice "LogMonitor_createLogFile() creating file: $logfile"
      close [open $logfile a]
   }
}

# the log file is considered inactive if it has not been modified for 
# the last hour
proc LogMonitor_isLogFileActive { _exp_path _datestamp } {
   if { [LogMonitor_getDatestampModTime ${_exp_path} ${_datestamp}] < [clock add [clock seconds] -1 hours] } {
      return false
   }
   return true
}
