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
proc Utils_Editor_Activation   {title tmpfile position parent_top} {
   global POPUP_ACTIVATION_IDS POPUP_ACTIVATION_COUNTER
   
   set fichier ${tmpfile}_out
   set popup_activ false
   if { $POPUP_ACTIVATION_COUNTER($tmpfile) > 15 || [file exists  ${fichier}]} {
      if { [info exists POPUP_ACTIVATION_IDS(${tmpfile})] } {
         after cancel $POPUP_ACTIVATION_IDS(${tmpfile})
         unset POPUP_ACTIVATION_IDS(${tmpfile})
         set   POPUP_ACTIVATION_COUNTER(${tmpfile})  0
       }
       if {[file exists  ${fichier}]} {
          TextEditor_createWindow "$title" ${tmpfile} ${position} ${parent_top}
          set popup_activ true
          catch { [exec -ignorestderr rm -f ${tmpfile}_out]}
          catch { [exec -ignorestderr rm -f ${tmpfile}] }
       }
   } else {
      incr POPUP_ACTIVATION_COUNTER(${tmpfile})
   }
   if { $popup_activ == false} {
     catch { set POPUP_ACTIVATION_IDS(${tmpfile}) [after 2000 [list Utils_Editor_Activation "$title" ${tmpfile} ${position} ${parent_top}]]}
   }
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

proc Utils_getMsgCenter_Info { _exp_path key key2} {
   global msg_info_List
   set value ""
   if { [info exists msg_info_List(${_exp_path}_${key}_${key2})] } {
     set value $msg_info_List(${_exp_path}_${key}_${key2})
   } 
   return ${value}
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

# input datestamp: yyyyMMddhhmm00
# returns yyMMdd in clock format 
proc Utils_getDayClockFromDatestamp { datestamp } {
   set dayOnly [string range ${datestamp} 0 7]
   set clockValue [clock scan ${dayOnly} -format "%Y%m%d"]

   return ${clockValue}
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

   ::log::log debug "Utils_isOverlap returns ${isOverlap}"
   return ${isOverlap}
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
proc Utils_validateVisibleDatestamp { _datestamp {_visibleLen 10} } {
   if { [string length ${_datestamp}] != ${_visibleLen} } {
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

# retrieves datestamp format based on visible length
# datestampVisibleLen: length of visible datestamp
# what:                if what = scan, returns scan format as needed by "clock scan"
#                      if what = display, returns format as seen by user i.e. yyyymmdd
#
proc Utils_getDatestampFormat { datestampVisibleLen what } {
   set value ""
   set defaultScanFormat "%Y%m%d%H"
   set defaultDisplayFormat "yyyymmddhh"
   switch ${datestampVisibleLen} {
      10 {
         set scanFormat ${defaultScanFormat}
	 set displayFormat ${defaultDisplayFormat}
      }
      12 {
         set scanFormat "%Y%m%d%H%M"
	 set displayFormat "yyyymmddhhMM"
      }
      14 {
         set scanFormat "%Y%m%d%H%M%S"
	 set displayFormat "yyyymmddhhMMSS"
      }
      default {
         set scanFormat ${defaultScanFormat}
	 set displayFormat ${defaultDisplayFormat}
      }
   }

   switch ${what} {
      scan {
         set value ${scanFormat}
      }
      display {
         set value ${displayFormat}
      }
   }

   return ${value}
}

proc Utils_getVisibleDatestampValue { date {length 10} } {
   set newValue [string range $date 0 [expr ${length} -1]]
   return ${newValue}
}

proc Utils_getRealDatestampValue { _datestamp } { 
   set newDateStamp ${_datestamp}
   # the format of the log file is 14 digits
   if { [string length ${_datestamp}] < 14 } {
      set padNumber [expr 14 - [string length ${_datestamp}]]
      set newDateStamp "${_datestamp}[join [lrepeat ${padNumber} 0] ""]"
   }
   return ${newDateStamp}
}

# returns hour value from yyyymmddhh*
proc Utils_getHourFromDatestamp { _datestamp } {
   return [string range ${_datestamp} 8 9]
}

# returns a datestamp in the form yyymmddhh0000 
# the hh value is the given datestamp_hour
# the delta_day is a positive or negative number of days
# relative to the current date.
# If I want tomorrow's datestamp, delta_day is 1
# If I want today's datestamp, delta_day is 0
# If I want yesterday's datestamp, delta_day is -1
proc Utils_getDatestamp { datestamp_hour delta_day } {
   set dateTime [clock add [clock seconds] ${delta_day} days]
   set formattedDatestamp [clock format ${dateTime} -format {%Y%m%d}]${datestamp_hour}0000
   return ${formattedDatestamp}
}

#returns day of week from Sakamoto's algorithm
proc Utils_getDayOfWeekFromDatestamp { _datestamp } {
    set year [string trimleft [string range ${_datestamp} 0 3] 0]
    set month [string trimleft [string range ${_datestamp} 4 5] 0]
    set day [string trimleft [string range ${_datestamp} 6 7] 0]
    # Sakamoto's algorithm for day of week
    set timelist { 0 3 2 5 0 3 5 1 4 6 2 4 }
    if { $month < 3 } {
       set year [expr $year - 1]    
    }
    return [expr ($year + $year/4 - $year/100 + $year/400 + [lindex $timelist [expr $month-1]] + $day) % 7 ]
}

proc Utils_launchShell { mach exp_path init_dir title {cmd ""} } {
    global env
    if { $cmd != "" } {
	set userCmd "$cmd;"
    } else {
	set userCmd ""
    }
    puts "xterm -ls -T ${title} -e \"ssh -t -Y ${mach} 'cd ${init_dir}; export SEQ_EXP_HOME=${exp_path}; ${userCmd} bash --login -i'\""
    exec -ignorestderr ksh -c "xterm -ls -T ${title} -e \"ssh -t -Y ${mach} 'cd ${init_dir}; export SEQ_EXP_HOME=${exp_path}; ${userCmd} bash --login -i'\"" & 
}

proc Utils_goBrowser { url } {
   set browser [SharedData_getMiscData BROWSER]
   if { ${browser} == "" } {
      set browser firefox
   }
   puts "Utils_goBrowser exec ${browser} ${url}"
   exec -ignorestderr ${browser} ${url} &
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

      # ::log::lvCmd notice Utils_logMessage 
      # ::log::lvCmd warning Utils_logMessage 
      # ::log::lvCmd error Utils_logMessage 
      ::log::lvCmd notice FileLogger_log 
      ::log::lvCmd warning FileLogger_log 
      ::log::lvCmd error FileLogger_log 
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
         ::log::log warning "Utils_logFileContent(): Cannot open file: ${_filename}"
      }
   }
}
proc Utils_createTmpDir {} {
   global env SESSION_TMPDIR
   if { ! [info exists SESSION_TMPDIR] } {
      set thisPid [thread::id]
      set userTmpDir [SharedData_getMiscData USER_TMP_DIR]
      if { ${userTmpDir} != "default" } {
         if { ! [file isdirectory ${userTmpDir}] } {
            Utils_fatalError . "Xflow Startup Error" "Invalid user configuration in .maestrorc file. Directory ${userTmpDir} does not exists!"
         }
         set rootTmpDir ${userTmpDir}
      } else {
         if { ! [info exists env(TMPDIR)] } {
            Utils_fatalError . "Xflow Startup Error" "TMPDIR environment variable does not exists!"
         }
         set rootTmpDir $env(TMPDIR)
      }
      set id [clock seconds]
      set myTmpDir ${rootTmpDir}/maestro_${thisPid}_${id}
      if { [file exists ${myTmpDir}] } {
         ::log::log debug "Utils_createTmpDir deleting ${myTmpDir}"
         file delete -force ${myTmpDir}
      }
      ::log::log debug "Utils_createTmpDir creating ${myTmpDir}"
      puts "Utils_createTmpDir creating ${myTmpDir}"
      file mkdir ${myTmpDir}
      set SESSION_TMPDIR ${myTmpDir}
   }
}

# this function displays plugins on the toolbar
proc Utils_createPluginToolbar { parent parentToolbar pluginEnv } {
   # plugin is child of main toolbar frame
   if { [SharedData_getMiscData OVERVIEW_MODE] == false || 
        ( [SharedData_getMiscData OVERVIEW_MODE] == true && ${parent} == "xflow" ) } {
      # if xflow standalone true || overview launching exp flow
      set toolbarW ${parentToolbar}.plugintoolbar
   } else {
      # overview plugin
      set toolbarW ${parentToolbar}.label.plugintoolbar
   }

   frame ${toolbarW} -bd 1
   
   # add all plugins with icons defined
   set count 0
   set pluginWidgets ""
   set pluginList [SharedData_getMiscData PLUGINS]
   foreach pluginInfo ${pluginList} { 
       if { [dict get ${pluginInfo} parent] == ${parent} } {
	   if { [file exists [dict get ${pluginInfo} icon]] && [dict get ${pluginInfo} helptext] != "" } {
	       set pluginButton ${toolbarW}.plugin$count
	       image create photo ${pluginButton}_img -file [dict get ${pluginInfo} icon]
	       button $pluginButton -image  ${pluginButton}_img  -command [ list Utils_runPluginCommandCallback \
			${pluginEnv} [dict get ${pluginInfo} script] [dict get ${pluginInfo} terminal] ] -relief flat 
	       ::tooltip::tooltip ${pluginButton} [dict get ${pluginInfo} helptext]
	       set pluginWidgets "${pluginWidgets} ${pluginButton}"
	       incr count
	   } else {
	       ::log::log debug [concat "Utils_createPluginToolbar: Icon " [dict get ${pluginInfo} icon] " does not exist, or helptext not defined in  [dict get ${pluginInfo} file]. Not loading it to taskbar."]
	   }
       }
   }
   if { ${pluginWidgets} != "" } {
      eval grid ${pluginWidgets} -sticky w -padx 2 
   }

   # the main toolbar frame contains 2 different toolbars
   # the plugin toolbar sits in column 1.. the core toolbar sits on column 0
   return ${toolbarW}

}

# this function loads the plugin menu items
proc Utils_showPluginMenu { parent parentMenu exp_path datestamp pluginEnv } {
    set pluginList [SharedData_getMiscData PLUGINS]
    if { ${pluginList} == "" } { return }

    # basic environment setup
    set sep ";"
    if { ${pluginEnv} == "" } { set sep "" }
    set fullPluginEnv "export SEQ_EXP_HOME=${exp_path}; export SEQ_DATE=${datestamp}${sep} ${pluginEnv}"

    # add all plugins with menuitems defined
    set pluginMenu ""
    foreach pluginInfo ${pluginList} {
	if { [dict get ${pluginInfo} parent] == ${parent} } {
	    if { [dict get ${pluginInfo} menuitem] != "" } {
		if { ${pluginMenu} == "" } {
		    set pluginMenu ${parentMenu}.plugin_menu
		    ${parentMenu} add cascade -label "Plugins" -underline 0 -menu [menu ${pluginMenu}]
		}
		${pluginMenu} add command -label [dict get ${pluginInfo} menuitem] -command [ list Utils_runPluginCommandCallback \
			${fullPluginEnv} [dict get ${pluginInfo} script] [dict get ${pluginInfo} terminal]]
	    } else {
	    ::log::log debug [concat "Utils_showPluginMenu: The menuitem entry is not defined in " [dict get ${pluginInfo} file] ". Not loading it to popup menu."]
	    }
	}
    }
}

proc Utils_runPluginCommandCallback { pluginEnv command terminal } {

   global env
   set id [clock seconds]
   set init_dir /tmp/\${USER}/\$$
   set mach  $env(HOST) 
   if { $command != "" } {
       set userCmd "$command"
   } else {
       set userCmd ""
   }
   set sep ";"
   if { ${pluginEnv} == "" } {set sep ""}
   set SEQ_MAESTRO_RC [SharedData_getMiscData RC_FILE]

   set title $userCmd
   puts "cmd=$command"
   ::log::log debug "Utils_runPluginCommandCallback ksh -c $userCmd"
   if { $terminal > 0 } {
       set cmd_str "xterm -ls -T '${title}' -e \"export SEQ_MAESTRO_RC=${SEQ_MAESTRO_RC}; export TMPDIR=${init_dir}; mkdir ${init_dir}; ${pluginEnv}${sep} cd ${init_dir}; ${userCmd}; bash --login -i\""
   } else {
       set cmd_str "export SEQ_MAESTRO_RC=${SEQ_MAESTRO_RC}; export TMPDIR=${init_dir}; mkdir ${init_dir}; ${pluginEnv}${sep} cd ${init_dir}; ${userCmd} 2>&1"
   }
   puts $cmd_str
   exec -ignorestderr ksh -c $cmd_str &
}
