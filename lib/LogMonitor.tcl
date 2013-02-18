#!/home/binops/afsi/ssm/domain2/tcl-tk_8.5.11_linux26-i686/bin/wish8.5

# touches a file for each experiment; it serves as a timestamp for to be used
# for the find -newer command; used to know log files that have changed since the
# last check
proc LogMonitor_setLastCheckTime { _exp_path _time_in_seconds } {
   global SESSION_TMPDIR
   set expPathKey [SharedData_getExpData ${_exp_path} EXP_PATH_KEY]
   ::log::log debug "LogMonitor_setLastCheckTime touch ${SESSION_TMPDIR}/${expPathKey}.last_checked_file"
   set timeFormat [clock format ${_time_in_seconds} -format "%y%m%d%H%M.%S"]
   exec touch ${SESSION_TMPDIR}/${expPathKey}.last_checked_file -t ${timeFormat}
}

proc LogMonitor_getLastCheckFile { _exp_path } {
   global SESSION_TMPDIR
   set expPathKey [SharedData_getExpData ${_exp_path} EXP_PATH_KEY]
   return ${SESSION_TMPDIR}/${expPathKey}.last_checked_file
}

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
            # set lastCheckedTime [SharedData_getExpData ${expPath} LAST_CHECKED_TIME]
	    set lastCheckedFile [LogMonitor_getLastCheckFile ${expPath}]
            set lastCheckedTime [file mtime ${lastCheckedFile}]
            set newLastChecked [clock seconds]
            catch { exec ls ${checkDir} > /dev/null }
	    set modifiedFiles ""
	    if { [ catch {
               # set modifiedFiles [exec find ${checkDir} -maxdepth 1 -type f -name "*_nodelog" -newerct [clock format ${lastCheckedTime}] -exec basename \{\} \;]
	       # -newerct not available on 32 bits find version
               set modifiedFiles [exec find ${checkDir} -maxdepth 1 -type f -name "*_nodelog" -newer ${lastCheckedFile} -exec basename \{\} \;]
            } errMsg] } {
	       ::log::log notice "ERROR: LogMonitor_checkNewLogFiles() $errMsg"
	       puts "ERROR: LogMonitor_checkNewLogFiles() $errMsg"
	    }
            foreach modifiedFile ${modifiedFiles} {
               ::log::log debug  "LogMonitor_checkNewLogFiles processing ${expPath} ${modifiedFile}..."
               set seqDatestamp [string range [file tail ${modifiedFile}] 0 13]
               if { [Utils_validateRealDatestamp ${seqDatestamp}] == true } {
                  # look see if we have a thread monitoring this log file, if not create one
                  set expThreadId [SharedData_getExpThreadId ${expPath} ${seqDatestamp}]
                  if { ${expThreadId} == "" } {
                     ::log::log notice "LogMonitor_checkNewLogFiles(): getting thread for ${expPath} ${seqDatestamp}"
                     # if there is already a thread for this datestamp, we don't do anything
                     set expThreadId [ThreadPool_getNextThread]
                     ::log::log notice "LogMonitor_checkNewLogFiles(): got thread id ${expThreadId} for ${expPath} ${seqDatestamp}"
                     #puts "LogMonitor_checkNewLogFiles set log file offset to 0"
                     # force reread of log file from start
                     SharedData_setExpThreadId ${expPath} ${seqDatestamp} ${expThreadId}

                     ::log::log notice "LogMonitor_checkNewLogFiles(): setExpThreadId ${expThreadId} for ${expPath} ${seqDatestamp} DONE"
                     ::log::log notice "LogMonitor_checkNewLogFiles(): LogReader_startExpLogReader ${expPath} ${seqDatestamp}"
                     thread::send -async ${expThreadId} "LogReader_startExpLogReader ${expPath} \"${seqDatestamp}\" all" LogReaderDone
		     vwait LogReaderDone
                     #thread::send ${expThreadId} "LogReader_startExpLogReader ${expPath} \"${seqDatestamp}\" all"
                     ::log::log notice "LogMonitor_checkNewLogFiles(): LogReader_startExpLogReader ${expPath} ${seqDatestamp} DONE"
                  }
               } else {
                  ::log::log notice "ERROR: LogMonitor_checkNewLogFiles():Found invalid log file format: ${expPath} ${modifiedFile}"
                  # puts "LogMonitor_checkNewLogFiles(): Found invalid log file format: ${modifiedFile}"
               }
            }
            if { [expr ${newLastChecked} - ${lastCheckedTime}] > 300 } {
               # to go around nfs latency, I only change the checked time every 5 minutes
	       LogMonitor_setLastCheckTime ${expPath} ${newLastChecked}
            }
         }
      }
   }

   after ${nextCheckTime} [list LogMonitor_checkNewLogFiles]
}

# process log *_nodelog files that have been modified within the _deltaTime window.
# _deltaTime must be a valid date format that can be used with the "-mmin" option of find
# returns a list of files {log_file1 log_file2...} if found else returns empty list
# 
proc LogMonitor_getDatestamps { _exp_path _deltaTime } {
   set checkDir ${_exp_path}/logs
   set modifiedFiles {}
   if { [file readable ${checkDir}] } {
      #puts "LogMonitor_getDatestamps exec find ${checkDir} -maxdepth 1 -type f -name \"*_nodelog\" -newerct ${_deltaTime} -exec basename \{\} \;"
      # set modifiedFiles [exec find ${checkDir} -maxdepth 1 -name "*\[0-9\]_nodelog" -newerct ${_deltaTime} -exec basename \{\} \; | cut -c 1-14]
      set modifiedFiles [exec find ${checkDir} -maxdepth 1 -name "*\[0-9\]_nodelog" -mmin ${_deltaTime} -exec basename \{\} \; | cut -c 1-14]
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
   set mtime 0
   set logfile ${_exp_path}/logs/${_datestamp}_nodelog
   if { [file readable ${logfile}] } {
      set mtime [file mtime ${logfile}]
   }
   return ${mtime}
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
   if { ${_datestamp} == "" } {
      return false
   }

   if { [LogMonitor_getDatestampModTime ${_exp_path} ${_datestamp}] < [clock add [clock seconds] -1 hours] } {
      return false
   }
   return true
}