proc DEBUG { output {level 2} } {
   global DEBUG_ON DEBUG_LEVEL
   #set debugOn [getGlobalValue "DEBUG_TRACE"]
   #set debugLevel [getGlobalValue "DEBUG_LEVEL"]
   if { $DEBUG_ON && $DEBUG_LEVEL >= $level} {
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

proc bindMouseWheel { widget } {
   #puts "bindMouseWheel widget:$widget"
   bind $widget <4> {
      if {!$tk_strictMotif} {
         %W yview scroll -5 units
         #puts "bindMouseWheel yview -5 called"
      }
   }
   bind $widget <5> {
      if {!$tk_strictMotif} {
         %W yview scroll 5 units
         #puts "bindMouseWheel yview +5 called"
      }
   }
}

proc normalCursor { w } {
   if { [winfo exists $w] } {
      catch {
         # $w configure -cursor arrow
         $w configure -cursor ""
         update idletasks
      }
   }
}

proc busyCursor { w } {
   if { [winfo exists $w] } {
      $w configure -cursor watch
      #blt::busy hold $w
      update idletasks
   }
}


proc raiseError { parent title err_msg } {
   tk_messageBox -icon error -parent $parent -title $title -message $err_msg
}

proc FatalError { parent title err_msg } {
   wm withdraw .
   raiseError $parent $title $err_msg
   exit 0
}

proc quit { {message ""} } {
   if { !($message == "") } {
      DEBUG "Error:$message" 4
   }
   DEBUG "Application Exits!" 4
   exit
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
         set xOverlap 1
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

proc Utils_getPaddedValue { value } {
   if { [::tcl::mathop::< ${value} 10] &&  [::tcl::mathop::>= ${value} 0]} {
      return "0${value}"
   }
   return ${value}
}


#setGlobalValue SEQ_BIN [Sequencer_getPath]
#setGlobalValue SEQ_UTILS_BIN [Sequencer_getUtilsPath]
#setGlobalValue DEBUG_TRACE 1
#setGlobalValue DEBUG_LEVEL 5

