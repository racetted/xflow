#!/home/binops/afsi/ssm/domain2/tcl-tk_8.5.11_linux26-i686/bin/wish8.5

# look for new log files created under SEQ_EXP_HOME/logs
proc LogMonitor_checkNewLogFiles {} {
   global THREAD_FULL_EVENT
   puts "LogMonitor_checkNewLogFiles"
   if { ! [info exists THREAD_FULL_EVENT] } {
      set THREAD_FULL_EVENT false
   }
   # check every 5 secs
   set nextCheckTime 5000
   set displayGroups [record show instances DisplayGroup]
   foreach displayGroup $displayGroups {
      set expList [$displayGroup cget -exp_list]
      foreach expPath $expList {
         set checkDir ${expPath}/logs
         if { [file readable ${checkDir}] } {
            puts "LogMonitor_checkNewLogFiles checking ${checkDir}"
            set lastCheckedTime [SharedData_getSuiteData ${expPath} LAST_CHECKED_TIME]
            set newLastChecked [clock format [clock seconds]]
            set modifiedFiles [exec find ${checkDir} -maxdepth 1 -type f -name "*_nodelog" -newerct ${lastCheckedTime} -exec basename \{\} \;]
            foreach modifiedFile ${modifiedFiles} {
            puts "LogMonitor_checkNewLogFiles processing ${modifiedFile}..."
               set seqDatestamp [string range [file tail ${modifiedFile}] 0 13]
               if { [Utils_validateRealDatestamp ${seqDatestamp}] == true } {
                  # look see if we have a thread monitoring this log file, if not create one
                  set expThreadId [SharedData_getExpThreadId ${expPath} ${seqDatestamp}]
                  if { ${expThreadId} == "" } {
                     # if there is already a thread for this datestamp, we don't do anything
                     set expThreadId [ThreadPool_getThread]
                     if { ${expThreadId} == "" } {
                        # not able to get a thread from the pool
                        # reset check time to previous time
                        set newLastChecked [SharedData_getSuiteData ${expPath} LAST_CHECKED_TIME]
                        # post the event to warn user if not warned yet
                        if { ${THREAD_FULL_EVENT} != true } {
                           puts "LogMonitor_checkNewLogFiles posting THREAD_FULL_EVENT"
                           set THREAD_FULL_EVENT true
                           # check in 30 seconds to leave some time for user to shutdown flows
                           set nextCheckTime 30000
                        }
                     } else {
                        set suiteRecord [::SuiteNode::formatSuiteRecord ${expPath}]
                        catch { SuiteInfo ${suiteRecord} -suite_path ${expPath} }

                        puts "LogMonitor_checkNewLogFiles set log file offset to 0"
                        # force reread of log file from start
                        SharedData_setExpDatestampOffset ${expPath} ${seqDatestamp} 0

                        puts "LogMonitor_checkNewLogFiles Overview_startExpLogReader..."
                        thread::send ${expThreadId} "Overview_startExpLogReader ${expPath} ${suiteRecord} \"${seqDatestamp}\" true"
                     }
                  }
               } else {::log::log notice "Found invalid log file format: ${modifiedFile}"
                  puts "LogMonitor_checkNewLogFiles(): Found invalid log file format: ${modifiedFile}"
               }
            }
            SharedData_setSuiteData ${expPath} LAST_CHECKED_TIME ${newLastChecked}
         }
      }
   }

   set LastChecked [clock format [clock seconds]]
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

# returns datestamps of log files that have been modified since the last number of hours
#proc LogMonitor_getDatestamps { _exp_path _hour } {
#   global env
#   set newestFile ""
   #catch { set newestFile [eval exec ls -t [glob -tails -directory ${_exp_path}/logs *_nodelog] | head -1 | xargs basename | cut -c 1-14 ] }
#   catch { set newestFile [eval exec $env(SEQ_XFLOW_BIN)/../etc/getNewestDatestamp ${_exp_path}] }
#   return ${newestFile}
#}

proc LogMonitor_getFormattedDatestamp { _datestamp } { 
   set newDateStamp ${_datestamp}
   # the format of the log file is 14 digits
   if { [string length ${_datestamp}] < 14 } {
      set padNumber [expr 14 - [string length ${_datestamp}]]
      set newDateStamp "${_datestamp}[join [lrepeat ${padNumber} 0] ""]"
   }
   return ${newDateStamp}
}

proc isLogFileExists { _exp_path _logfile } {
   global ExpLogFiles
   set isExists false
   if { [array exists ExpLogFiles] } {
      if { [array get ExpLogFiles(${_exp_path})] != "" } {
         set logFiles $ExpLogFiles(${_exp_path})
         if { [lsearch -exact ${logFiles} ${_logfile}] != -1 } {
            set isExists true
         }
      }
   }
   return ${isExists}
}

proc addNewLogFile { _exp_path _logfile } {
   global ExpLogFiles
   if { [array exists ExpLogFiles] } {
      if { [array get ExpLogFiles(${_exp_path})] != "" } {
         set logFiles $ExpLogFiles(${_exp_path})
         if { [lsearch -exact ${logFiles} ${_logfile}] == -1 } {
            lappend logFiles ${_logfile}
         }
      } else {
         lappend logFiles ${_logfile}
      }
      set ExpLogFiles(${_exp_path}) ${logFiles}
   } else {
      array set ExpLogFiles {}
      set ExpLogFiles(${_exp_path}) ${_logfile}
   }
}

proc LogMonitor_createLogFile { _exp_path _datestamp } {
      puts "LogMonitor_createLogFile"
   set logfile ${_exp_path}/logs/${_datestamp}_nodelog
   if { ! [file exists $logfile] && [file writable ${_exp_path}/logs/] } {
      puts "LogMonitor_createLogFile creating $logfile"
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

#LogMonitor_checkNewLogFiles