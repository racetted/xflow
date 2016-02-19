# The procedures in this file enables the creation and use
# of a singleton logger to write to the application log file.
# The FileLogger_log is called everytime a "::log::log notice" statement is used
# within the application.
proc FileLogger_createThread { logfile } {
   set threadID [thread::create {

      global env this_id
      package require log
      source $env(SEQ_XFLOW_BIN)/../lib/SharedData.tcl
      source $env(SEQ_XFLOW_BIN)/../lib/FileLogger.tcl

      if {  [SharedData_getMiscData OVERVIEW_MODE] == true } {
         puts "FileLoggerCreated set FileLoggerCreated true"
         thread::send -async [SharedData_getMiscData OVERVIEW_THREAD_ID]  "set FileLoggerCreated true"
      }
      # enter event loop
      thread::wait
   }]
   puts "FileLoggerCreated thread creation done ..."
   return ${threadID}
}

proc FileLogger_log { _level args } {
   set threadID [SharedData_getMiscData FILE_LOGGER_THREAD]
   if { ${threadID} != "" } {
      if { ${threadID} != [thread::id] } {
         thread::send ${threadID} "FileLogger_log ${_level} [list ${args}]"
      } else {
         set logFile [SharedData_getMiscData APP_LOG_FILE]
         if { ${logFile} != "" } {
            set currentTimeSeconds [clock seconds]
            set dateString [clock format $currentTimeSeconds -gmt 1]
            if [ catch {
               set fileId [open ${logFile} a 0664]
               puts $fileId "$dateString:${args}"
               catch { close $fileId }
            } err_message ] {
               puts stderr "---------------------------------------- ERROR! ----------------------------------------"
               puts stderr "FileLogger_log ERROR:${err_message}"
            }
         }
      }
   } else {
      puts stderr "FileLogger_log ERROR: Cannot find FileLogger thread id."
   }
}
