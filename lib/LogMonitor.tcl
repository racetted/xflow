# touches a file for each experiment; it serves as a timestamp for to be used
# for the find -newer command; used to know log files that have changed since the
# last check
proc LogMonitor_setLastCheckTime { _exp_path _time_in_seconds } {
   global SESSION_TMPDIR
   set expPathKey [SharedData_getExpData ${_exp_path} EXP_PATH_KEY]
   ::log::log debug "LogMonitor_setLastCheckTime touch ${SESSION_TMPDIR}/${expPathKey}.last_checked_file"
   set timeFormat [clock format ${_time_in_seconds} -format "%y%m%d%H%M.%S"]
   exec -ignorestderr touch ${SESSION_TMPDIR}/${expPathKey}.last_checked_file -t ${timeFormat}
}

proc LogMonitor_getLastCheckFile { _exp_path } {
   global SESSION_TMPDIR
   set expPathKey [SharedData_getExpData ${_exp_path} EXP_PATH_KEY]
   return ${SESSION_TMPDIR}/${expPathKey}.last_checked_file
}

# look for new log files created under SEQ_EXP_HOME/logs
# for all display groups from the overview
proc LogMonitor_checkNewLogFiles {} {
   ::log::log debug "LogMonitor_checkNewLogFiles"
   # puts "LogMonitor_checkNewLogFiles START:[exec date]"
   # check every 30 secs
   set nextCheckTime 30000

   if { [ catch {
      set displayGroups [ExpXmlReader_getGroups]
      # I'm adding a delay of 1 second between each display group
      # Without the delay, the execution was too intensive and 
      # was blocking user interaction at the GUI level
      set count 1000
      foreach displayGroup $displayGroups {
         after $count [list LogMonitor_checkGroupNewLogFiles ${displayGroup}]
	 set count [expr $count + 1000]
      }

   } message ] } {
      ::log::log notice "ERROR: LogMonitor_checkNewLogFiles() ${message} "
      puts stderr "ERROR: LogMonitor_checkNewLogFiles() ${message}"
   }

   # puts "LogMonitor_checkNewLogFiles DONE:[exec date]"
   after ${nextCheckTime} [list LogMonitor_checkNewLogFiles]
}

# check new exp log files for a specific displayGroup
proc LogMonitor_checkGroupNewLogFiles { displayGroup } {
   # puts "LogMonitor_checkNewLogFileOneGroup displayGroup:$displayGroup [exec date]"
   set expList [$displayGroup cget -exp_list]
   foreach expPath $expList {
      set checkDir ${expPath}/logs/
      if { [file readable ${checkDir}] } {
         set lastCheckedFile [LogMonitor_getLastCheckFile ${expPath}]
         set lastCheckedTime [file mtime ${lastCheckedFile}]
         set newLastChecked [clock seconds]
         catch { exec -ignorestderr ls ${checkDir} > /dev/null }
	 set modifiedFiles ""
	 if { [ catch {
            # set modifiedFiles [exec find ${checkDir} -maxdepth 1 -type f -name "*_nodelog" -newerct [clock format ${lastCheckedTime}] -exec basename \{\} \;]
	    # -newerct not available on 32 bits find version
            set modifiedFiles [exec  -ignorestderr find ${checkDir} -maxdepth 1 -type f -name "*_nodelog" -newer ${lastCheckedFile} -exec basename \{\} \;]
         } errMsg] } {
	    ::log::log notice "ERROR: () LogMonitor_checkGroupNewLogFiles $errMsg"
	    puts stderr "ERROR: LogMonitor_checkGroupNewLogFiles() $errMsg"
	 }

         foreach modifiedFile ${modifiedFiles} {

            ::log::log debug  "LogMonitor_checkGroupNewLogFiles processing ${expPath} ${modifiedFile}..."
            set seqDatestamp [string range [file tail ${modifiedFile}] 0 13]
            if { [Utils_validateRealDatestamp ${seqDatestamp}] == true } {
               # look see if we have a thread monitoring this log file, if not create one
               set expThreadId [SharedData_getExpThreadId ${expPath} ${seqDatestamp}]

	       # wake the datestamp in case it is an old one being rerun
	       OverviewExpStatus_reactivateDatestamp ${expPath} ${seqDatestamp}

               if { ${expThreadId} == "" } {
                  ::log::log notice "LogMonitor_checkGroupNewLogFiles(): getting thread for ${expPath} ${seqDatestamp}"
                  # if there is already a thread for this datestamp, we don't do anything
                  set expThreadId [ThreadPool_getNextThread]
                  ::log::log notice "LogMonitor_checkGroupNewLogFiles(): got thread id ${expThreadId} for ${expPath} ${seqDatestamp}"
                  # force reread of log file from start
                  SharedData_setExpThreadId ${expPath} ${seqDatestamp} ${expThreadId}

                  OverviewExpStatus_addStatusDatestamp ${expPath} ${seqDatestamp}

                  ::log::log notice "LogMonitor_checkGroupNewLogFiles(): setExpThreadId ${expThreadId} for ${expPath} ${seqDatestamp} DONE"
                  ::log::log notice "LogMonitor_checkGroupNewLogFiles(): LogReader_startExpLogReader ${expPath} ${seqDatestamp}"
                  thread::send -async ${expThreadId} "LogReader_startExpLogReader ${expPath} \"${seqDatestamp}\" all" SendDone
		  vwait SendDone
                  ::log::log notice "LogMonitor_checkGroupNewLogFiles(): LogReader_startExpLogReader ${expPath} ${seqDatestamp} DONE"
               }

            } else {
               ::log::log notice "ERROR: LogMonitor_checkGroupNewLogFiles():Found invalid log file format: ${expPath} ${modifiedFile}"
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

# look for new log files created under SEQ_EXP_HOME/logs
# for one exp only... used to check multiple concurrent datestamps
# within standalone xflow
proc LogMonitor_checkOneExpNewLogFiles { _exp_path } {
   global LogMonitorOneExpDatestamps
   ::log::log debug "LogMonitor_checkOneExpNewLogFiles"
   # check every 5 secs
   set nextCheckTime 5000

   set checkDir ${_exp_path}/logs/
   if { [file readable ${checkDir}] } {
      # puts "LogMonitor_checkNewLogFiles checking ${checkDir}"
      set lastCheckedFile [LogMonitor_getLastCheckFile ${_exp_path}]
      set lastCheckedTime [file mtime ${lastCheckedFile}]
      set newLastChecked [clock seconds]
      catch { exec -ignorestderr ls ${checkDir} > /dev/null }
      set modifiedFiles ""
      if { [ catch {
         set modifiedFiles [exec -ignorestderr find ${checkDir} -maxdepth 1 -type f -name "*_nodelog" -newer ${lastCheckedFile} -exec basename \{\} \;]
      } errMsg] } {
	 ::log::log notice "ERROR: LogMonitor_checkOneExpNewLogFiles() $errMsg"
	 puts stderr "ERROR: LogMonitor_checkOneExpNewLogFiles() $errMsg"
      }
      foreach modifiedFile ${modifiedFiles} {
         ::log::log debug  "LogMonitor_checkOneExpNewLogFiles processing ${_exp_path} ${modifiedFile}..."
         set seqDatestamp [string range [file tail ${modifiedFile}] 0 13]
         if { [Utils_validateRealDatestamp ${seqDatestamp}] == true } {
            # see if we have monitored this datestamp already
            if { [LogMonitor_addOneExpDatestamp ${_exp_path} ${seqDatestamp}] == true } {
	       thread::send [thread::id] "xflow_newDatestampFound ${_exp_path} ${seqDatestamp}"
            }
         } else {
            ::log::log notice "ERROR: LogMonitor_checkOneExpNewLogFiles():Found invalid log file format: ${_exp_path} ${modifiedFile}"
         }
      }
      if { [expr ${newLastChecked} - ${lastCheckedTime}] > 300 } {
         # to go around nfs latency, I only change the checked time every 5 minutes
	 LogMonitor_setLastCheckTime ${_exp_path} ${newLastChecked}
      }
   }

   after ${nextCheckTime} [list LogMonitor_checkOneExpNewLogFiles ${_exp_path}]
}

proc LogMonitor_addOneExpDatestamp { _exp_path _datestamp } {
   global LogMonitorOneExpDatestamps
   set isAdded false
   if { ! [info exists LogMonitorOneExpDatestamps] } {
      set LogMonitorOneExpDatestamps [list ${_datestamp}]
      set isAdded true
   } elseif { [lsearch ${LogMonitorOneExpDatestamps} ${_datestamp}] == -1 } {
      # add new datestamp to beginning
      set LogMonitorOneExpDatestamps [linsert ${LogMonitorOneExpDatestamps} 0 ${_datestamp}]
      set isAdded true
   }
   return ${isAdded}
}

# process log *_nodelog files that have been modified within the _deltaTime window.
# _deltaTime must be a valid date format that can be used with the "-mmin" option of find
# returns a list of files {log_file1 log_file2...} if found else returns empty list
# 
proc LogMonitor_getDatestamps { _exp_path _deltaTime } {
   set checkDir ${_exp_path}/logs/
   set modifiedFiles {}
   if { [file readable ${checkDir}] } {
      #puts "LogMonitor_getDatestamps exec find ${checkDir} -maxdepth 1 -type f -name \"*_nodelog\" -newerct ${_deltaTime} -exec basename \{\} \;"
      set modifiedFiles [exec -ignorestderr  find ${checkDir} -maxdepth 1 -name "*\[0-9\]_nodelog" -mmin ${_deltaTime} -exec basename \{\} \; | cut -c 1-14]
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
   catch { set newestFile [eval exec -ignorestderr $env(SEQ_XFLOW_BIN)/../etc/getNewestDatestamp ${_exp_path}] }
   return ${newestFile}
}

proc LogMonitor_createLogFile { _exp_path _datestamp } {
   set logfile ${_exp_path}/logs/${_datestamp}_nodelog
   set top_logfile ${_exp_path}/logs/${_datestamp}_toplog
   if { ! [file exists $logfile] && [file writable ${_exp_path}/logs/] } {
      puts "LogMonitor_createLogFile creating $logfile"
      ::log::log notice "LogMonitor_createLogFile() creating file: $logfile"
      close [open $logfile a]
   }
   if { ! [file exists $top_logfile] && [file writable ${_exp_path}/logs/] } {
      puts "LogMonitor_createLogFile creating $top_logfile"
      ::log::log notice "LogMonitor_createLogFile() creating file: $top_logfile"
      close [open $top_logfile a]
   }
}

# the log file is considered inactive if it has not been modified for 
# the last hour
proc LogMonitor_isLogFileActive { _exp_path _datestamp {_idleThreshold 60} } {
   if { ${_datestamp} == "" } {
      return false
   }

   if { [LogMonitor_getDatestampModTime ${_exp_path} ${_datestamp}] < [clock add [clock seconds] -${_idleThreshold} minutes] } {
      return false
   }
   return true
}

# the log has not been modified within the last 13 hours i.e. out of overview visible space
proc LogMonitor_isLogFileObsolete { _exp_path _datestamp } {
   if { ${_datestamp} == "" } {
      return false
   }

   if { [LogMonitor_getDatestampModTime ${_exp_path} ${_datestamp}] > [clock add [clock seconds] -13 hours] } {
      return false
   }

   return true
}

