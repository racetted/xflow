proc setGlobalValue { key value } {
   #global GLOBAL_LIST
   #set GLOBAL_LIST($key) $value
   SharedData_setMiscData ${key} ${value}
}

proc getGlobalValue {key} {
   #global GLOBAL_LIST
   #set value $GLOBAL_LIST($key)
   #return $value
   set value [SharedData_getMiscData ${key}]
}

# parent is where the user has clicked
proc Utils_positionWindow { top {parent ""} } {
   if { $parent != "" } {
      set POSITION_X [winfo pointerx $parent]
      set POSITION_Y [winfo pointery $parent]
   } else {
      set POSITION_X [expr [winfo pointerx .] + [winfo screenwidth .]/4]
      set POSITION_Y [expr [winfo pointery .] + [winfo screenheight .]/8]
   }
   wm geometry $top +${POSITION_X}+${POSITION_Y}
}

proc Utils_bindMouseWheel { widget units_value } {
   bind $widget <4> [list ${widget} yview scroll -${units_value} units] 
   bind $widget <5> [list ${widget} yview scroll +${units_value} units] 
}

proc Utils_normalCursor { w } {
   if { [winfo exists $w] } {
      catch {
         $w configure -cursor {}
         update idletasks
      }
   }
}

proc Utils_busyCursor { w } {
   if { [winfo exists $w] } {
      $w configure -cursor watch
      update idletasks
   }
}


proc Utils_raiseError { parent title err_msg } {
   tk_messageBox -icon error -parent $parent -title $title -message $err_msg
}

proc Utils_fatalError { parent title err_msg } {
   wm withdraw .
   Utils_raiseError $parent $title $err_msg
   exit 0
}

# input 20100903.18:50:24
# returns 18:50:24
# I'm using the dot as a separator
proc Utils_getTimeFromDatestamp { datestamp_field } {
   return [string range ${datestamp_field} [expr [string first . ${datestamp_field}] + 1] end]
}

# input 20100903.18:50:24
# returns 20100903
# I'm using the dot as a separator
proc Utils_getDateFromDatestamp { datestamp_field } {
   return [string range ${datestamp_field} 0 [expr [string first . ${datestamp_field}] -1] ]
}

# input hh:mm:ss
# returns hh, if hh=09 returns 9
proc Utils_getHourFromTime { timevalue  { keep_zero "no" } } {
   set splittedTime [split ${timevalue} :]
   set hourValue [lindex ${splittedTime} 0]

   if { ${keep_zero} == "no" } {
      # convert 09 to 9
      scan ${hourValue} %d hourValue
   }
   return ${hourValue}
}


proc Utils_isListEqual { list_a list_b } {
   set isEqual false
   set count [llength ${list_a}]
   set counter 0
   set done false
   if { [llength ${list_a}] > 0 && [llength ${list_a}] == [llength ${list_b}] } {
      while { ${done} == "false" } {
         if { [lindex ${list_a} ${counter}] != [lindex ${list_b} ${counter}] } {
            ::log::log debug "[lindex ${list_a} ${counter}] != [lindex ${list_b} ${counter}]"
            break
         }
         incr counter
         if { ${count} == ${counter} } {
            set done true
         }
      }
   }

   if { ${counter} == ${count} } {
      set isEqual true
   }

   return ${isEqual}
}

# shortcut for the Utils_isOverlap
proc Utils_isListOverlap { coord1 coord2 } {
   set isOverlap [Utils_isOverlap [lindex ${coord1} 0] [lindex ${coord1} 1] \
                                  [lindex ${coord1} 2] [lindex ${coord1} 3] \
                                  [lindex ${coord2} 0] [lindex ${coord2} 1] \
                                  [lindex ${coord2} 2] [lindex ${coord2} 3]]
   return ${isOverlap}
}

# test if two rectangles overlap each other
# b1x1 b1y1 b1x2 b1y2 is the coordinates of the first box
# b2x1 b2y1 b2x2 b2y2 is the coordinates of the second box
proc Utils_isOverlap { b1x1 b1y1 b1x2 b1y2 b2x1 b2y1 b2x2 b2y2 } {
   ::log::log debug "Utils_isOverlap b1x1:$b1x1 b1y1:$b1y1 b1x2:$b1x2 b1y2:$b1y2 b2x1:$b2x1 b2y1:$b2y1 b2x2:$b2x2 b2y2:$b2y2"
   set xOverlap 0
   set yOverlap 0
   set isOverlap 0
   if { ([expr ${b1x1} >= ${b2x1}] && [expr ${b1x1} <= ${b2x2}]) ||
      ([expr ${b1x2} >= ${b2x1}] && [expr ${b1x2} <= ${b2x2}]) } {
      ::log::log debug "Utils_isOverlap xOverlap 1"
      set xOverlap 1
   }
   if { ([expr ${b1y1} >= ${b2y1}] && [expr ${b1y1} <= ${b2y2}]) ||
      ([expr ${b1y2} >= ${b2y1}] && [expr ${b1y2} <= ${b2y2}]) } {
      ::log::log debug "Utils_isOverlap yOverlap 1"
      set yOverlap 1
   }
   if { ${yOverlap} && ! ${xOverlap} } {
      # if y overlap and one box is entirely within the other on the x axias,
      # we have overlap
      if { [expr ${b1x1} <= ${b2x1}] && [expr ${b1x2} >= ${b2x1}] ||
           [expr ${b2x1} <= ${b1x1}] && [expr ${b2x2} >= ${b1x1}] } {
         set xOverlap 1
         ::log::log debug "Utils_isOverlap xOverlap 1 within"
      }
   }
   if { ${xOverlap} && ! ${yOverlap} } {
      # if x overlap and one box is entirely within the other on the y axis,
      # we have overlap
      if { [expr ${b1y1} <= ${b2y1}] && [expr ${b1y2} >= ${b2y1}] ||
           [expr ${b2y1} <= ${b1y1}] && [expr ${b2y2} >= ${b1y1}] } {
         ::log::log debug "Utils_isOverlap yOverlap 1 within"
         set yOverlap 1
      }
   }
   # if one box is entirely in the other one, we have an overlap
   if { ( [expr ${b1x1} <= ${b2x1}] && [expr ${b1x2} >= ${b2x1}] &&
             [expr ${b1y1} <= ${b2y1}] && [expr ${b1y2} >= ${b2y1}] ) ||
        ( [expr ${b2x1} <= ${b1x1}] && [expr ${b2x2} >= ${b1x1}] &&
             [expr ${b2y1} <= ${b1y1}] && [expr ${b2y2} >= ${b1y1}] ) } {
      set xOverlap 1
      set yOverlap 1
   }

   if { ${xOverlap} && ${yOverlap} } {
      set isOverlap 1
   }

   return ${isOverlap}
}

proc Utils_getCurrentTime {} {
   set currentTime [clock format [clock seconds] -format "%H:%M" -gmt 1]
}

proc Utils_getCurrentTime {} {
   set currentTime [clock format [clock seconds] -format "%H:%M" -gmt 1]
}

# input hh:mm:ss
# returns mm, if mm=08 returns 8
proc Utils_getMinuteFromTime { timevalue { keep_zero "no" } } {
   set splittedTime [split ${timevalue} :]
   set minuteValue [lindex ${splittedTime} 1]

   if { ${keep_zero} == "no" } {
      # convert 09 to 9
      scan ${minuteValue} %d minuteValue
   }
   return ${minuteValue}
}

proc Utils_getNonPaddedValue { value } {
   scan ${value} %d value
   return ${value}
}

# only meant to be used for hours
proc Utils_getPaddedValue { value } {
   if { [::tcl::mathop::< ${value} 10] &&  [::tcl::mathop::>= ${value} 0] 
        && [string length ${value}] != "2" } {
      return "0${value}"
   }
   return ${value}
}

proc Utils_getVisibleDatestampValue { date } {
   set newValue [string range $date 0 9]
   return ${newValue}
}

proc Utils_getRealDatestampValue { date } {
   set newValue ${date}0000
   return ${newValue}
}

proc Utils_getHourFromDatestamp { _datestamp } {
   return [string range ${_datestamp} 8 9]
}

proc Utils_launchShell { mach exp_path init_dir title {cmd ""} } {
    global env
    if { $cmd != "" } {
	set userCmd "$cmd;"
    } else {
	set userCmd ""
    }
    puts "xterm -ls -T ${title} -e \"ssh -t -Y ${mach} 'cd ${init_dir}; export SEQ_EXP_HOME=${exp_path}; ${userCmd} bash --login -i'\""
    exec ksh -c "xterm -ls -T ${title} -e \"ssh -t -Y ${mach} 'cd ${init_dir}; export SEQ_EXP_HOME=${exp_path}; ${userCmd} bash --login -i'\"" & 
}

proc Utils_goBrowser { url } {
   set browser [SharedData_getMiscData BROWSER]
   if { ${browser} == "" } {
      set browser firefox
   }
   puts "Utils_goBrowser exec ${browser} ${url}"
   exec ${browser} ${url} &
}

proc Utils_setDebugOn {} {
   ::log::lvSuppress info 0
   ::log::lvSuppress debug 0
}

proc Utils_setDebugOff {} {
   ::log::lvSuppress info 1
   ::log::lvSuppress debug 1
}

# initialize application log file
# if needed. It uses the shared variable
# APP_LOG_FILE. The variable is shared among all
# threads i.e. overview, msg center and exp threads
#
# Only levels notice and higher are currently logged.
# By default debug level is off and even in on mode,
# it goes to standard out and not log file.
proc Utils_logInit {} {
   global APP_LOGFILE env
   
   set sharedAppLogFile [SharedData_getMiscData APP_LOG_FILE]
   set debugOn [SharedData_getMiscData DEBUG_TRACE]

   # sharedAppLogFile is used to log write operations to log file
   # it does not log info or debug level messages

   # info and debug level goes to standard out, not logged
   if { ${debugOn} == 1 } {
      Utils_setDebugOn
   } else {
      Utils_setDebugOff
   }

   if { ${sharedAppLogFile} != "" } {
      # allow log message level "notice" to be logged
      # using xflow_logMessage proc
      set APP_LOGFILE ${sharedAppLogFile}
      # by default, if log is enabled we log only the following levels
      ::log::lvSuppress error 0
      ::log::lvSuppress warning 0
      ::log::lvSuppress notice 0

      ::log::lvCmd notice Utils_logMessage 
      ::log::lvCmd warning Utils_logMessage 
      ::log::lvCmd error Utils_logMessage 
   }
}

# short to send the content of a file to the log file
# mainly used on a submit for instance where the content of the submit
# output is logged
proc Utils_logFileContent { _level _filename } {
   set logMsg ""
   # log only if level is enabled
   if { [::log::lvIsSuppressed ${_level}] == 0 } {
      if { [file exists ${_filename}] } {
         ::log::log ${_level} "------------------------------------"
         set fileid [ open ${_filename} r ]
         flush stdout
         while {[gets ${fileid} line] >= 0} {
            lappend logMsg "\n${line}"
         }
         catch { close ${fileid} }
         if { ${logMsg} != "" } {
            ::log::log ${_level} ${logMsg}
         }
         ::log::log ${_level} "------------------------------------"
      } else {
         ::log::log warning "Utils_logFileContent(): Cannot open file: $_{filename}"
      }
   }
}

# this is called as callback for each ::log::log notice | warning | error level
# inserts the message in the log file
proc Utils_logMessage { _level _message } {
   global APP_LOGFILE
   if { [info exists APP_LOGFILE] } {
      set currentTimeSeconds [clock seconds]
      set dateString [clock format $currentTimeSeconds -gmt 1]
      if [ catch {
         set fileId [open $APP_LOGFILE a 0664]
         puts $fileId "$dateString:${_message}"
         catch { close $fileId }
      } err_message ] {
         puts "Utils_logMessage ERROR:${err_message}"
      }
   }
}

#setGlobalValue SEQ_BIN [Sequencer_getPath]
#setGlobalValue SEQ_UTILS_BIN [Sequencer_getUtilsPath]
#setGlobalValue DEBUG_TRACE 1

