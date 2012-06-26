proc DEBUG { output {level 2} } {
   global DEBUG_TRACE DEBUG_LEVEL
   set debugOn [getGlobalValue "DEBUG_TRACE"]
   set debugLevel [getGlobalValue "DEBUG_LEVEL"]
   if { $DEBUG_TRACE == "1" && $DEBUG_LEVEL >= $level} {
      puts "$output"
      flush stdout
   }
}

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
            DEBUG "[lindex ${list_a} ${counter}] != [lindex ${list_b} ${counter}]" 5
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
   DEBUG "Utils_isOverlap b1x1:$b1x1 b1y1:$b1y1 b1x2:$b1x2 b1y2:$b1y2 b2x1:$b2x1 b2y1:$b2y1 b2x2:$b2x2 b2y2:$b2y2" 5
   set xOverlap 0
   set yOverlap 0
   set isOverlap 0
   if { ([expr ${b1x1} >= ${b2x1}] && [expr ${b1x1} <= ${b2x2}]) ||
      ([expr ${b1x2} >= ${b2x1}] && [expr ${b1x2} <= ${b2x2}]) } {
      DEBUG "Utils_isOverlap xOverlap 1" 5
      set xOverlap 1
   }
   if { ([expr ${b1y1} >= ${b2y1}] && [expr ${b1y1} <= ${b2y2}]) ||
      ([expr ${b1y2} >= ${b2y1}] && [expr ${b1y2} <= ${b2y2}]) } {
      DEBUG "Utils_isOverlap yOverlap 1" 5
      set yOverlap 1
   }
   if { ${yOverlap} && ! ${xOverlap} } {
      # if y overlap and one box is entirely within the other on the x axias,
      # we have overlap
      if { [expr ${b1x1} <= ${b2x1}] && [expr ${b1x2} >= ${b2x1}] ||
           [expr ${b2x1} <= ${b1x1}] && [expr ${b2x2} >= ${b1x1}] } {
         set xOverlap 1
         DEBUG "Utils_isOverlap xOverlap 1 within" 5
      }
   }
   if { ${xOverlap} && ! ${yOverlap} } {
      # if x overlap and one box is entirely within the other on the y axis,
      # we have overlap
      if { [expr ${b1y1} <= ${b2y1}] && [expr ${b1y2} >= ${b2y1}] ||
           [expr ${b2y1} <= ${b1y1}] && [expr ${b2y2} >= ${b1y1}] } {
         DEBUG "Utils_isOverlap yOverlap 1 within" 5
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

# must be 10 digits values yyyymmddhh
proc Utils_validateVisibleDatestamp { _datestamp } {
   if { [string length ${_datestamp}] != 10 } {
      return false
   }
   if [ catch { clock scan ${_datestamp} } message ] {
      return false
   }
   return true
}

proc Utils_validateRealDatestamp { _datestamp } {
   if { [string length ${_datestamp}] != 14 } {
      return false
   }
   if [ catch { clock scan ${_datestamp} } message ] {
      return false
   }
   return true
}

proc Utils_getVisibleDatestampValue { date } {
   set newValue [string range $date 0 9]
   return ${newValue}
}

#proc Utils_getRealDatestampValue { date } {
#   set newValue ${date}0000
#   return ${newValue}
#}

proc Utils_getRealDatestampValue { _datestamp } { 
   set newDateStamp ${_datestamp}
   # the format of the log file is 14 digits
   if { [string length ${_datestamp}] < 14 } {
      set padNumber [expr 14 - [string length ${_datestamp}]]
      set newDateStamp "${_datestamp}[join [lrepeat ${padNumber} 0] ""]"
   }
   return ${newDateStamp}
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

#setGlobalValue SEQ_BIN [Sequencer_getPath]
#setGlobalValue SEQ_UTILS_BIN [Sequencer_getUtilsPath]
#setGlobalValue DEBUG_TRACE 1
#setGlobalValue DEBUG_LEVEL 5

