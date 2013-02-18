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

      SharedData_setMiscData FILE_LOGGER_THREAD [thread::id]

      # enter event loop
      thread::wait
   }]
}

proc FileLogger_log { _level args } {
   # puts "_level:$_level args:$args"
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
               puts "---------------------------------------- ERROR! ----------------------------------------"
               puts "FileLogger_log ERROR:${err_message}"
            }
         }
      }
   }
}