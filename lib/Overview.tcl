#!/home/binops/afsi/ssm/sw/linux26-i686/bin/tclsh8.4
package require struct::record
package require tooltip
package require cmdline
package require Thread
namespace import ::tooltip::tooltip
namespace import ::struct::record::record
package require keynav
package require log

global env
if { ! [info exists env(SEQ_XFLOW_BIN) ] } {
   puts "Environment variable SEQ_XFLOW_BIN must be defined!"
   exit
}
# puts "SEQ_XFLOW_BIN=$env(SEQ_XFLOW_BIN)"

set lib_dir $env(SEQ_XFLOW_BIN)/../lib
puts "sua lib_dir=$lib_dir"
set auto_path [linsert $auto_path 0 $lib_dir ]

package require SuiteNode

proc Overview_setTkOptions {} {

   option add *activeBackground [SharedData_getColor ACTIVE_BG]
   option add *selectBackground [SharedData_getColor SELECT_BG]
   catch { option add *troughColor [::tk::Darken [option get . background Scrollbar] 85] }

   #ttk::style configure Xflow.Menu -background cornsilk4
}

# this function is called to advance the time group to a new hour...
# - It shifts the whole grid to the left by 1 hour
# - It deletes the hour at the far left
# - It adds a new hour at the far right
# - Every exp box is also shifted
# - An exp box disappears at the far left when its timings are off the grid
# - An exp appears at the far right when its reference timings are visible in the grid
#
# - the first time this function is called, new_hour should be empty.
# - the function wil calculate the time remaining until 
# the next hour switch and then wake up every hour to perform the same task
proc Overview_GridAdvanceHour { {new_hour ""} } {
   global graphHourX graphX graphStartX graphStartY

   set currentClock [clock seconds]
   ::log::log debug "Overview_GridAdvanceHour new_hour:${new_hour} [clock format ${currentClock}]"
   set advanceGrid true
   if { ${new_hour} == "" } {
      # first time called, calculate the time to sleep before the hour
      set advanceGrid false
      set new_hour [Utils_getNonPaddedValue [clock format ${currentClock} -format %H -gmt 1]]
      set elapsedMin [Utils_getNonPaddedValue [clock format ${currentClock} -format %M]]
      set elapsedSeconds [Utils_getNonPaddedValue [clock format ${currentClock} -format %S]]
      set elapsedInMilliSec [expr ${elapsedMin} * 60000 + ${elapsedSeconds} * 1000]
      set sleepTime [expr 3600000 - ${elapsedInMilliSec}]
   } else {
      # wake-up in an hour
      set sleepTime 3600000
   }
   if { ${new_hour} == "24" } {
      set nextHour 1
   } else {
      set nextHour [expr ${new_hour} + 1]
   }

   ::log::log debug "Overview_GridAdvanceHour sleeping for ${sleepTime} msecs before hour ${nextHour}"
   after ${sleepTime} [list Overview_GridAdvanceHour ${nextHour}]

   if { ${advanceGrid} == false } {
      return
   }

   ::log::log debug "Overview_GridAdvanceHour advancing grid hour ${new_hour}"

   set canvasW [Overview_getCanvas]

   # refresh current Time 
   set timeHour [Utils_getPaddedValue ${new_hour}]
   set currenTime "${timeHour}:00"
   Overview_setCurrentTime ${canvasW} ${currenTime}

   # delete first hour tag, the one at the far-left of the grid
   set mostLeftHour [Overview_GraphGetXOriginHour]

   ::log::log debug "Overview_GridAdvanceHour deleting hour ${mostLeftHour}"
   Overview_GraphDeleteHourLine ${canvasW} ${mostLeftHour}

   # shift the grid by 1 hour
   set gridTag grid_hour
   ${canvasW} move grid_hour -${graphHourX} 0

   ::log::log debug "Overview_GridAdvanceHour inserting hour ${mostLeftHour}"
   # insert new hour at the far-right
   Overview_GraphAddHourLine ${canvasW} 24 ${mostLeftHour}

   set xoriginDateTime [Overview_GraphGetXOriginDateTime]
   # shift all the suite boxes in the canvas
   set displayGroups [ExpXmlReader_getGroups]

   foreach displayGroup $displayGroups {
      set expList [$displayGroup cget -exp_list]
      foreach exp $expList {
      
         # move the default ones if exists (init state, waiting to be submitted, usually right side of current time line
         Overview_advanceExpDefaultBox ${canvasW} ${exp}

         set suiteRecord [::SuiteNode::formatSuiteRecord ${exp}]
         set datestamps [::SuiteNode::getDatestamps ${suiteRecord}]

         foreach datestamp ${datestamps} {
            set runBoxCoords [Overview_getRunBoxBoundaries  ${canvasW} ${suiteRecord} ${datestamp}]
            set currentX [lindex ${runBoxCoords} 0]
            set lastStatus [::SuiteNode::getLastStatus ${suiteRecord} ${datestamp}]
            set lastStatusTime [::SuiteNode::getLastStatusTime ${suiteRecord} ${datestamp}]
            set expPath [${suiteRecord} cget -suite_path]

            # is the exp thread still needed?
            set expThreadId [SharedData_getExpThreadId ${expPath} ${datestamp}]
            if { ${expThreadId} != "" && [LogMonitor_isLogFileActive ${expPath} ${datestamp}] == false } {
               if { [thread::send ${expThreadId} xflow_isXflowActive ${expPath}] == false } {
                  # the exp thread that followed this log is not needed anymore, release it    
                  ::log::log debug "Overview_GridAdvanceHour releasing exp thread for ${expPath} ${datestamp}"
                  Overview_releaseExpThread ${expThreadId} ${expPath} ${datestamp}
               }
            }
            if { [Overview_isExpBoxObsolete ${canvasW} ${expPath} ${datestamp}] == true } {
               # the end time happened prior to the x origin time,
               # shift the exp box to the left
               # first clean any data kept for the datestamp
               ::SuiteNode::removeStatusDatestamp ${suiteRecord} ${datestamp}

               # delete current box
               Overview_removeExpBox ${canvasW} [${suiteRecord} cget -suite_path] ${datestamp} ${lastStatus}

               set expBoxTag [Overview_getExpBoxTag ${expPath} ${datestamp} default false]
               set datestamp ${expBoxTag}
               set lastStatus default
            }

            Overview_updateExpBox ${canvasW} ${suiteRecord} ${datestamp} ${lastStatus} ${lastStatusTime}
            Overview_checkGridLimit 
         }
      }
   }
}

# this function returns a time value based on a grid x coordinate value
# The return format is hh:mm
# It takes into account the hour value at x origin.
proc Overview_getTimeFromCoord { x_value } {
   global graphHourX graphStartX
   set intValue [::tcl::mathfunc::entier ${x_value}]

   # get the delta_x relative to the start of the time grid
   set x [expr ${intValue} - ${graphStartX}]

   # calculate the number of hour space
   set nHour [expr ${x} / ${graphHourX}]

   # get the time at origin
   set origDateTime [Overview_GraphGetXOriginDateTime]

   # add the number of hours to the origin
   set hourDateTime [clock add ${origDateTime} ${nHour} hours]

   # get the hour value from the new date
   set hour [clock format ${hourDateTime} -format "%H" -gmt 1]

   set minute [expr (${x} % ${graphHourX}) * 60 / ${graphHourX}]
   set timeValue "[Utils_getPaddedValue ${hour}]:[Utils_getPaddedValue ${minute}]"
   return ${timeValue}
}

# returns the overview timeline x coordinate given a time value
# in the hh:mm format
# note that the return value takes into account the start of the
# x axis that is changing every hour
proc Overview_getXCoordTime { timevalue {shift_day false} } {
   global graphHourX graphStartX

   set timeHour [Utils_getHourFromTime ${timevalue}]
   set timeMinute [Utils_getMinuteFromTime ${timevalue}]

   if { ${timeHour} > 24 } {
      # return max of grid
      set xoord [expr ${graphStartX} + 24 * ${graphHourX} ]
      return ${xoord}
   }

   if { [Overview_GraphGetXOriginHour] == ${timeHour} } {
      set xcoordHour ${graphStartX}
   } else {
      # each hour has a corresponding vertical grid line
      # here we fetch the x coordinate as given by the hour grid line
      set hourTag [Overview_getGridTagHour ${timeHour}]
      set canvas [Overview_getCanvas]
      set coords [${canvas} coords ${hourTag}]
      if { ${coords} != "" } {
         set xcoordHour [::tcl::mathfunc::entier [lindex ${coords} 0]]
      } else {
         puts "Overview_getXCoordTime not exists timevalue:$timevalue  timeHour:$timeHour hourTag:$hourTag"
      }
   }

   set xcoordMin [ expr ${timeMinute} * ${graphHourX} / 60 ]
   set xcoord [ expr ${xcoordHour} + ${xcoordMin} ]

   return $xcoord
}

# refresh the current time line every minute
proc Overview_setCurrentTime { canvas { current_time "" } } {
   global graphStartX graphStartY graphHourX graphy TimeAfterId
   ::log::log debug "setCurrentTime canvas:$canvas current_time:${current_time}"
   $canvas delete current_timeline

   # setting current time
   if { ${current_time} == "" } {
      set current_time [clock format [clock seconds] -format "%H:%M" -gmt 1]
      set currentSeconds [clock format [clock seconds] -format "%S"]
      # set the first sleep time the closest to the minute update
      set sleepTime [expr (30 - [Utils_getNonPaddedValue ${currentSeconds}] % 30) * 1000]
   } else {
      set sleepTime 60000
   }
   set currentTimeCoordx [Overview_getXCoordTime ${current_time}]
   #::log::log debug "setCurrentTime current_time:${current_time} currentTimeCoordx:$currentTimeCoordx"
   set x1 ${currentTimeCoordx}
   set x2 ${currentTimeCoordx}
   set y1 [expr $graphStartY - 4]
   set y2 [expr $graphStartY + 4]
   set lineId [$canvas create line $x1 [expr $y1 - 40] $x2 [expr $y2 + $graphy + 40 ] -tag "grid_time current_timeline" -fill DarkGreen]
   ::tooltip::tooltip $canvas -item "${lineId}" "Current Time:${current_time}Z\nUpdated every 30 seconds"

   if { [$canvas gettags current_timetext] == "" } {
      $canvas create text $x1 [expr $y2 + $graphy + 45] -fill DarkGreen -anchor w -justify left -tag "grid_item current_timetext"
   }

   $canvas itemconfigure current_timetext -text "Current Time: ${current_time}Z"

   # set overview title at the same time
   Overview_setTitle [winfo toplevel ${canvas}] ${current_time}

   set TimeAfterId [after ${sleepTime} [list Overview_setCurrentTime $canvas]]
}

#
#
# this function process the exp box logic when the root experiment node
# is in init state
proc Overview_processInitStatus { canvas suite_record datestamp {status init} } {
   ::log::log debug "Overview_processInitStatus ${suite_record} ${datestamp} ${status}"
   set expPath [${suite_record} cget -suite_path]
   set statusTime [::SuiteNode::getLastStatusTime ${suite_record} ${datestamp}]
   set statusDateTime [::SuiteNode::getStatusClockValue ${suite_record} ${datestamp} init]
   set currentDateTime [clock seconds]
   set xoriginDateTime [Overview_GraphGetXOriginDateTime]
   set refStartTime [Overview_getRefTimings ${expPath} [Utils_getHourFromDatestamp ${datestamp}] start]
   set refEndTime [Overview_getRefTimings ${expPath} [Utils_getHourFromDatestamp ${datestamp}]  end]
   set refEndDateTime [clock scan ${refEndTime}]
   set currentTime [Utils_getCurrentTime]
   set shiftDay false

   if { [expr ${statusDateTime} < ${xoriginDateTime}] } {
      # start time is prior to visible hour, move it 0
      Overview_ExpCreateStartIcon ${canvas} ${suite_record} ${datestamp} [Overview_GraphGetXOriginTime]
   } else {
      Overview_ExpCreateStartIcon ${canvas} ${suite_record} ${datestamp} ${statusTime}
   }

   if { ${refEndTime} != "" } {
      if { [Overview_getXCoordTime ${currentTime}] < [Overview_getXCoordTime ${refEndTime}] } {
         # the reference end is still coming
         Overview_ExpCreateReferenceBox ${canvas} ${suite_record} ${datestamp} ${currentTime}
         Overview_ExpCreateEndIcon ${canvas} ${suite_record} ${datestamp} ${refEndTime}
      }
      proc out {} {
      if { [Overview_getXCoordTime ${currentTime}] > [Overview_getXCoordTime ${refEndTime}] } {
         # the reference end time is past already
         # Overview_ExpCreateMiddleBox ${canvas} ${suite_record} ${datestamp} ${currentTime} false true
         set newcoords [Overview_getRunBoxBoundaries  ${canvas} ${suite_record} ${datestamp}]
         set endTime [Overview_getTimeFromCoord [lindex ${newcoords} 2]]
         # Overview_ExpCreateEndIcon ${canvas} ${suite_record} ${datestamp} ${endTime}
      } else {
         Overview_ExpCreateReferenceBox ${canvas} ${suite_record} ${datestamp} ${currentTime}
         Overview_ExpCreateEndIcon ${canvas} ${suite_record} ${datestamp} ${refEndTime}
      }
      }
   } else {
      # the reference end time is still ahead
      Overview_ExpCreateMiddleBox ${canvas} ${suite_record} ${datestamp} ${currentTime} false true
      set newcoords [Overview_getRunBoxBoundaries  ${canvas} ${suite_record} ${datestamp}]
      set endTime [Overview_getTimeFromCoord [lindex ${newcoords} 2]]
      Overview_ExpCreateEndIcon ${canvas} ${suite_record} ${datestamp} ${endTime}
   }
}

proc Overview_setDefaultStatus { canvas suite_record hour } {
   ::log::log debug "Overview_setDefaultStatus ${suite_record} ${hour}"
   set expPath [${suite_record} cget -suite_path]
   set refStartTime [Overview_getRefTimings ${expPath} ${hour} start]
   set refEndTime [Overview_getRefTimings ${expPath} ${hour} end]
   if { ${refStartTime} != "" } {
      Overview_ExpCreateStartIcon ${canvas} ${suite_record} default_${hour} ${refStartTime}
      Overview_ExpCreateMiddleBox ${canvas} ${suite_record} default_${hour} ${refEndTime}
      Overview_ExpCreateEndIcon ${canvas} ${suite_record} default_${hour} ${refEndTime}
   } else {
      # we do not have exp reference timings,
      # put it at beginning of graph wherever it fits
      Overview_ExpCreateStartIcon ${canvas} ${suite_record} default_${hour} [Overview_GraphGetXOriginTime]
   }
}


# this function process the exp box logic when the root experiment node
# is in wait state
proc Overview_processWaitStatus { canvas suite_record datestamp {status wait} } {
   ::log::log debug "Overview_processWaitStatus ${suite_record} ${datestamp} ${status}"
   set expPath [${suite_record} cget -suite_path]
   set statusTime [::SuiteNode::getLastStatusTime ${suite_record} ${datestamp}]
   set statusDateTime [::SuiteNode::getStatusClockValue ${suite_record} ${datestamp} wait]
   set currentTime [Utils_getCurrentTime]
   set refEndTime [Overview_getRefTimings ${expPath} [Utils_getHourFromDatestamp ${datestamp}]  end]
   set refEndDateTime [clock scan ${refEndTime}]
   set currentDateTime [clock seconds]
   set xoriginDateTime [Overview_GraphGetXOriginDateTime]

   if { [expr ${statusDateTime} < ${xoriginDateTime}] } {
      # start time is prior to visible hour, move it 0
      Overview_ExpCreateStartIcon ${canvas} ${suite_record} ${datestamp} [Overview_GraphGetXOriginTime]
   } else {
      Overview_ExpCreateStartIcon ${canvas} ${suite_record} ${datestamp} ${statusTime}
   }

   if { ${refEndTime} != "" } {
      if { [expr ${currentDateTime} > ${refEndDateTime}] } {
         # we are late
         Overview_setExpLate ${canvas} ${suite_record} ${datestamp}
         Overview_ExpCreateMiddleBox ${canvas} ${suite_record} ${datestamp} ${currentTime} false true
         set newcoords [Overview_getRunBoxBoundaries  ${canvas} ${suite_record} ${datestamp}]
         set endTime [Overview_getTimeFromCoord [lindex ${newcoords} 2]]
         Overview_ExpCreateEndIcon ${canvas} ${suite_record} ${datestamp} ${endTime}
      } else {
         Overview_ExpCreateReferenceBox ${canvas} ${suite_record} ${datestamp} ${currentTime}
         Overview_ExpCreateEndIcon ${canvas} ${suite_record} ${datestamp} ${refEndTime}
      }
   } else {
      Overview_ExpCreateMiddleBox ${canvas} ${suite_record} ${datestamp} ${currentTime} false true
      set newcoords [Overview_getRunBoxBoundaries  ${canvas} ${suite_record} ${datestamp}]
      set endTime [Overview_getTimeFromCoord [lindex ${newcoords} 2]]
      Overview_ExpCreateEndIcon ${canvas} ${suite_record} ${datestamp} ${endTime}
   }
}

# this function process the exp box logic when the root experiment node
# is in catchup state
proc Overview_processCatchupStatus { canvas suite_record datestamp {status catchup} } {
   ::log::log debug "Overview_processCatchupStatus ${suite_record} ${datestamp} ${status}"
   set expPath [${suite_record} cget -suite_path]
   set statusTime [::SuiteNode::getLastStatusTime ${suite_record} ${datestamp}]
   set statusDateTime [::SuiteNode::getStatusClockValue ${suite_record} ${datestamp} catchup]
   set currentTime [Utils_getCurrentTime]
   set refStartTime [Overview_getRefTimings ${expPath} [Utils_getHourFromDatestamp ${datestamp}] start]
   set refEndTime [Overview_getRefTimings ${expPath} [Utils_getHourFromDatestamp ${datestamp}]  end]
   set xoriginDateTime [Overview_GraphGetXOriginDateTime]

   # I only care if the catchup time is visible
   if { [expr ${statusDateTime} > ${xoriginDateTime}] } {
      Overview_ExpCreateStartIcon ${canvas} ${suite_record} ${datestamp} ${statusTime}
      Overview_ExpCreateMiddleBox ${canvas} ${suite_record} ${datestamp} ${currentTime} false true
      set newcoords [Overview_getRunBoxBoundaries  ${canvas} ${suite_record} ${datestamp}]
      set endTime [Overview_getTimeFromCoord [lindex ${newcoords} 2]]
      Overview_ExpCreateEndIcon ${canvas} ${suite_record} ${datestamp}  ${endTime}
   } elseif { ${refStartTime} != "" } {
      Overview_ExpCreateStartIcon ${canvas} ${suite_record} ${datestamp} ${refStartTime} true
      Overview_ExpCreateMiddleBox ${canvas} ${suite_record} ${datestamp} ${refEndTime} true
      Overview_ExpCreateEndIcon ${canvas} ${suite_record} ${datestamp} ${refEndTime} true
   }
}

# this function process the exp box logic when the root experiment node
# is in submit state
proc Overview_processSubmitStatus { canvas suite_record datestamp {status submit} } {
   ::log::log debug "Overview_processSubmitStatus ${suite_record} ${datestamp} ${status}"
   set expPath [${suite_record} cget -suite_path]
   set statusTime [::SuiteNode::getLastStatusTime ${suite_record} ${datestamp}]
   set statusDateTime [::SuiteNode::getStatusClockValue ${suite_record} ${datestamp} submit]
   set currentTime [Utils_getCurrentTime]
   set refEndTime [Overview_getRefTimings ${expPath} [Utils_getHourFromDatestamp ${datestamp}]  end]
   set refEndDateTime [clock scan ${refEndTime}]
   set currentDateTime [clock seconds]
   set xoriginDateTime [Overview_GraphGetXOriginDateTime]

   if { [expr ${statusDateTime} <= ${xoriginDateTime}] } {
      # submit time is prior to visible hour, move it 0
      Overview_ExpCreateStartIcon ${canvas} ${suite_record} ${datestamp} [Overview_GraphGetXOriginTime]
   } else {
      Overview_ExpCreateStartIcon ${canvas} ${suite_record} ${datestamp} ${statusTime}
   }
   if { ${refEndTime} != "" } {
      if { [expr ${currentDateTime} > ${refEndDateTime}] } {
         # we are late
         Overview_setExpLate ${canvas} ${suite_record} ${datestamp}
         Overview_ExpCreateMiddleBox ${canvas} ${suite_record} ${datestamp} ${currentTime} false true
         set newcoords [Overview_getRunBoxBoundaries  ${canvas} ${suite_record} ${datestamp}]
         set endTime [Overview_getTimeFromCoord [lindex ${newcoords} 2]]
         Overview_ExpCreateEndIcon ${canvas} ${suite_record} ${datestamp} ${endTime}
      } else {
         Overview_ExpCreateReferenceBox ${canvas} ${suite_record} ${datestamp} ${currentTime}
         Overview_ExpCreateEndIcon ${canvas} ${suite_record} ${datestamp} ${refEndTime}
      }
   } else {
      Overview_ExpCreateMiddleBox ${canvas} ${suite_record} ${datestamp} ${currentTime} false true
      set newcoords [Overview_getRunBoxBoundaries  ${canvas} ${suite_record} ${datestamp}]
      set endTime [Overview_getTimeFromCoord [lindex ${newcoords} 2]]
      Overview_ExpCreateEndIcon ${canvas} ${suite_record} ${datestamp} ${endTime}
   }

}

# this function process the exp box logic when the root experiment node
# is in begin state
proc Overview_processBeginStatus { canvas suite_record datestamp {status begin} } {
   ::log::log debug "Overview_processBeginStatus ${suite_record} ${datestamp} ${status}"
   set expPath [${suite_record} cget -suite_path]
   set startTime [::SuiteNode::getStartTime ${suite_record} ${datestamp}]
   set xoriginDateTime [Overview_GraphGetXOriginDateTime]
   set currentTime [Utils_getCurrentTime]
   set refEndTime [Overview_getRefTimings ${expPath} [Utils_getHourFromDatestamp ${datestamp}]  end]
   set startDateTime [::SuiteNode::getStatusClockValue ${suite_record} ${datestamp} begin]

   if { ${status} == "beginx" && [${canvas} coords ${expPath}.${datestamp}.start] == "" } {
      set status begin
   }

   if { ${status} == "begin" } {
      if { [expr ${startDateTime} < ${xoriginDateTime}] } {
         # start time is prior to visible hour, move it 0
         Overview_ExpCreateStartIcon ${canvas} ${suite_record} ${datestamp} [Overview_GraphGetXOriginTime]
      } else {
         Overview_ExpCreateStartIcon ${canvas} ${suite_record} ${datestamp} ${startTime}
      }
   }
   # add middle box up to current time
   Overview_ExpCreateMiddleBox ${canvas} ${suite_record} ${datestamp} ${currentTime}

   # add reference
   if { ${refEndTime} != "" } {
      if { [Overview_getXCoordTime ${currentTime}] > [Overview_getXCoordTime ${refEndTime}] } {
         # we are late
         Overview_setExpLate ${canvas} ${suite_record} ${datestamp}
         Overview_ExpCreateEndIcon ${canvas} ${suite_record} ${datestamp} ${currentTime}
      } else {
         Overview_ExpCreateReferenceBox ${canvas} ${suite_record} ${datestamp} ${currentTime}
         Overview_ExpCreateEndIcon ${canvas} ${suite_record} ${datestamp} ${refEndTime}
      }
   } else {
         Overview_ExpCreateEndIcon ${canvas} ${suite_record} ${datestamp} ${currentTime}
   }
}

# this function process the exp box logic when the root experiment node
# is in end state
proc Overview_processEndStatus { canvas suite_record datestamp {status end} } {
   ::log::log debug "Overview_processEndStatus ${suite_record} ${datestamp} ${status}"

   set expPath [${suite_record} cget -suite_path]
   set startTime [::SuiteNode::getStartTime ${suite_record} ${datestamp}]
   set endTime [::SuiteNode::getEndTime ${suite_record} ${datestamp}]
   set startDateTime [::SuiteNode::getStatusClockValue ${suite_record} ${datestamp} begin]
   set endDateTime [::SuiteNode::getStatusClockValue ${suite_record} ${datestamp} end]

   set statusTime [::SuiteNode::getLastStatusTime ${suite_record} ${datestamp}]
   set refStartTime [Overview_getRefTimings ${expPath} [Utils_getHourFromDatestamp ${datestamp}] start]
   set refEndTime [Overview_getRefTimings ${expPath} [Utils_getHourFromDatestamp ${datestamp}]  end]
   set xoriginDateTime [Overview_GraphGetXOriginDateTime]
   ::log::log debug "Overview_processEndStatus ${suite_record} refStartTime:$refStartTime refEndTime:$refEndTime startTime:$startTime endTime:$endTime startDateTime:$startDateTime endDateTime:$endDateTime"
   set shiftDay false
   if { ${startTime} != "" } {
      set middleBoxTime ${endTime}
      if { [expr ${startDateTime} < ${xoriginDateTime}] &&
            [expr ${endDateTime} > ${xoriginDateTime} ] } {
         # start time is not visible hour but end time is visible... move it 0
         Overview_ExpCreateStartIcon ${canvas} ${suite_record} ${datestamp} [Overview_GraphGetXOriginTime]
         Overview_ExpCreateMiddleBox ${canvas} ${suite_record} ${datestamp} ${middleBoxTime} ${shiftDay}
         Overview_ExpCreateEndIcon ${canvas} ${suite_record} ${datestamp} ${middleBoxTime} ${shiftDay}
      } elseif { [expr ${startDateTime} <= ${xoriginDateTime}] &&
            [expr ${endDateTime} <= ${xoriginDateTime}]  } {
         # start time and end time both prior to origin hour, shit to right end grid
         set shiftDay true
         ::log::log debug "Overview_processEndStatus ${suite_record} ${datestamp} ${status} shiftDay true"
         ::SuiteNode::setLastStatusInfo ${suite_record} ${datestamp} init "" ""
         if { ${refStartTime} != "" } {
            Overview_ExpCreateStartIcon ${canvas} ${suite_record} ${datestamp} ${refStartTime} ${shiftDay}
            set middleBoxTime ${refEndTime}
            Overview_ExpCreateMiddleBox ${canvas} ${suite_record} ${datestamp} ${middleBoxTime} ${shiftDay}
            Overview_ExpCreateEndIcon ${canvas} ${suite_record} ${datestamp} ${middleBoxTime} ${shiftDay}
         } else {
            # put at x origin 
            Overview_ExpCreateStartIcon ${canvas} ${suite_record} ${datestamp} [Overview_GraphGetXOriginTime] ${shiftDay}
         }
         if { ${datestamp} != "" } {
            Overview_cleanExpDatestamp ${expPath} ${datestamp}
         }
      } else {
         Overview_ExpCreateStartIcon ${canvas} ${suite_record} ${datestamp} ${startTime} ${shiftDay}
         Overview_ExpCreateMiddleBox ${canvas} ${suite_record} ${datestamp} ${middleBoxTime} ${shiftDay}
         Overview_ExpCreateEndIcon ${canvas} ${suite_record} ${datestamp} ${middleBoxTime} ${shiftDay}
      }
   } else {
         # Overview_ExpCreateStartIcon ${canvas} ${suite_record} ${datestamp} ${statusTime}
      if { [expr ${endDateTime} <= ${xoriginDateTime}]  } {
         set shiftDay true
         ::SuiteNode::setLastStatusInfo ${suite_record} ${datestamp} init "" ""
         if { ${refStartTime} != "" } {
            Overview_ExpCreateStartIcon ${canvas} ${suite_record} ${datestamp} ${refStartTime} ${shiftDay}
            set middleBoxTime ${refEndTime}
            Overview_ExpCreateMiddleBox ${canvas} ${suite_record} ${datestamp} ${middleBoxTime} ${shiftDay}
            Overview_ExpCreateEndIcon ${canvas} ${suite_record} ${datestamp} ${middleBoxTime} ${shiftDay}
         } else {
            # put at x origin 
            Overview_ExpCreateStartIcon ${canvas} ${suite_record} default [Overview_GraphGetXOriginTime] ${shiftDay}
         }
      } else {
         Overview_ExpCreateStartIcon ${canvas} ${suite_record} ${datestamp} ${statusTime}
      }
   }
}

proc Overview_cleanExpDatestamp { exp_path datestamp } {
   global MSG_CENTER_THREAD_ID
   if { ${MSG_CENTER_THREAD_ID} != "" } {
      puts "Overview_cleanExpDatestamp $exp_path $datestamp"
      catch { thread::send ${MSG_CENTER_THREAD_ID} "MsgCenterThread_removeDatestamp ${exp_path} ${datestamp}" }
   }
}

# this function process the exp box logic when the root experiment node
# is in abort state
proc Overview_processAbortStatus { canvas suite_record datestamp {status abort} } {

   set expPath [${suite_record} cget -suite_path]
   set startTime [::SuiteNode::getStartTime ${suite_record} ${datestamp}]
   set startDateTime [::SuiteNode::getStatusClockValue ${suite_record} ${datestamp} begin]

   set statusTime [::SuiteNode::getLastStatusTime ${suite_record} ${datestamp}]
   set refEndTime [Overview_getRefTimings ${expPath} [Utils_getHourFromDatestamp ${datestamp}]  end]
   set refEndDateTime [clock scan ${refEndTime}]
   set currentDateTime [clock seconds]
   set xoriginDateTime [Overview_GraphGetXOriginDateTime]
   set currentTime [Utils_getCurrentTime]

   if { ${startTime} != "" } {
      if { [expr ${startDateTime} < ${xoriginDateTime}] } {
         # start time is prior to visible hour, move it 0
         Overview_ExpCreateStartIcon ${canvas} ${suite_record} ${datestamp} [Overview_GraphGetXOriginTime]
      } else {
         Overview_ExpCreateStartIcon ${canvas} ${suite_record} ${datestamp} ${startTime}
      }
   } else {
      Overview_ExpCreateStartIcon ${canvas} ${suite_record} ${datestamp} ${statusTime}
   }
   # add middle box up to abort time
   Overview_ExpCreateMiddleBox ${canvas} ${suite_record} ${datestamp} ${statusTime}
   if { ${refEndTime} != "" } {
      if { [Overview_getXCoordTime ${currentTime}] < [Overview_getXCoordTime ${refEndTime}] } {     
         Overview_ExpCreateReferenceBox ${canvas} ${suite_record} ${datestamp} ${statusTime}
         Overview_ExpCreateEndIcon ${canvas} ${suite_record} ${datestamp} ${refEndTime}
      } else {
         set newcoords [Overview_getRunBoxBoundaries  ${canvas} ${suite_record} ${datestamp}]
         Overview_ExpCreateEndIcon ${canvas} ${suite_record} ${datestamp} ${statusTime}
      }
   }
}

# sets a visual indication when an exp is running late with respect
# to reference timings...when the reference end time is passed
proc Overview_setExpLate { canvas suite_record datestamp } {
   set expPath [${suite_record} cget -suite_path]
   ${canvas} itemconfigure ${expPath}.text -fill DarkViolet
}

# this function is called to display the exp node with the right
# color status... usually when the exp thread notifies the overview
# of a new experiment status
proc Overview_refreshBoxStatus { suite_record datestamp {status ""} } {
   set canvas [Overview_getCanvas] 
   if { ${status} == "" } {
      set status [::SuiteNode::getLastStatus ${suite_record} ${datestamp}]
   }
   set expPath [$suite_record cget -suite_path]
   set tagName ${expPath}.${datestamp}
   set colors [::DrawUtils::getStatusColor $status]
   set bgColor [::DrawUtils::getBgStatusColor ${status}]
   set fgColor [::DrawUtils::getFgStatusColor ${status}]
   set outlineColor [::DrawUtils::getOutlineStatusColor ${status}]
   set initBgColor [::DrawUtils::getBgStatusColor init]
   if { [winfo exists $canvas] } {

      if { ${status} == "late" } {
         $canvas itemconfigure ${tagName}.middle -fill DarkViolet
         $canvas itemconfigure ${tagName}.text -fill [::DrawUtils::getFgStatusColor end]
      } else {
         $canvas itemconfigure ${tagName}.start -fill $bgColor -outline ${outlineColor}
         $canvas itemconfigure ${tagName}.middle -outline ${outlineColor}
         $canvas itemconfigure ${tagName}.reference -fill ${initBgColor} -outline ${outlineColor}
         $canvas itemconfigure ${tagName}.end -fill $bgColor -outline ${outlineColor}
      }
      ${canvas} raise ${tagName}.text
   }
}

# this function creates an experiment start icon
#  - It creates a circle with a starting point that represents the timevalue argument
#  - It creates a label with the exp name
#  - The start icon is colored with the status color
#  If the shift_day argument is true, it forces the status to init... This means that
#  the timings of the exp are off the left side grid...
proc Overview_ExpCreateStartIcon { canvas suite_record datestamp timevalue {shift_day false} } {
   global graphStartX expEntryHeight startEndIconSize expBoxOutlineWidth
   ::log::log debug "Overview_ExpCreateStartIcon $suite_record $datestamp $timevalue shift_day:$shift_day"
   # set displayGroup [${suite_record} cget -overview_group_record]
   set expPath [${suite_record} cget -suite_path]
   set displayGroup [SharedData_getExpGroupDisplay ${expPath}]
   set startY [expr [${displayGroup} cget -y] +  $expEntryHeight/2 - (${startEndIconSize}/2)]
   set startX [Overview_getXCoordTime ${timevalue} ${shift_day}]

   set labelX [expr $startX + 10]
   set startX2 [expr $startX + ${startEndIconSize}]
   set startY2 [expr $startY + ${startEndIconSize}]

   set currentStatus [::SuiteNode::getLastStatus ${suite_record} ${datestamp}]

   # delete previous box
   Overview_removeExpBox ${canvas} ${expPath} ${datestamp} ${currentStatus}

   set tailName [file tail ${expPath}]
   set expLabel " ${tailName} "
   set outlineColor [::DrawUtils::getOutlineStatusColor ${currentStatus}]
   # puts "Overview_ExpCreateStartIcon outlineColor:$outlineColor currentStatus:$currentStatus"
   if { ${shift_day} == true || [string match "defaut*" ${datestamp}] } {
      set currentStatus init
      set expBoxTag [Overview_getExpBoxTag ${expPath} ${datestamp} default]
      if { [SharedData_getExpTimings ${expPath}] != "" } {
         set hour [Utils_getHourFromDatestamp ${datestamp}]
         set expLabel " ${tailName}-${hour} "
      }
   } else {
      set expBoxTag [Overview_getExpBoxTag ${expPath} ${datestamp} ${currentStatus}]
      if { [SharedData_getExpTimings ${expPath}] != "" || ${currentStatus} != "init"} {
         set hour [Utils_getHourFromDatestamp ${datestamp}]
         set expLabel " ${tailName}-${hour} "
      }
   }
   set bgColor [::DrawUtils::getBgStatusColor ${currentStatus}]
   ::log::log debug "Overview_ExpCreateStartIcon ${expBoxTag}.start at ${startX} ${startY} ${startX2} ${startY2} outlineColor:${outlineColor} bgColor:${bgColor}"
   # create the left box      
   set startBoxId [$canvas create oval ${startX} ${startY} ${startX2} ${startY2} -width 1.0 \
      -fill ${bgColor} -outline ${outlineColor} -tag "${displayGroup} ${expPath} ${expBoxTag} ${expBoxTag}.start"]

   # create the exp label
   set labelY [expr ${startY} + (${startEndIconSize}/2)]
   set expLabelId [$canvas create text ${labelX} ${labelY} -font [Overview_getBoxLabelFont] \
      -text ${expLabel} -fill black -anchor w -tag "${displayGroup} ${expPath} ${expBoxTag} ${expBoxTag}.text"]
}

# this function creates an experiment end icon
#  - It creates a circle with a starting point that represents the timevalue argument
#  If the shift_day argument is true, it forces the status to init... This means that
#  the timings of the exp are off the left side grid...
proc Overview_ExpCreateEndIcon { canvas suite_record datestamp timevalue {shift_day false} } {
   ::log::log debug "Overview_ExpCreateEndIcon ${suite_record} ${datestamp} ${timevalue} shift_day:$shift_day"
   global graphStartX expEntryHeight startEndIconSize expBoxOutlineWidth
   # set displayGroup [${suite_record} cget -overview_group_record]
   set expPath [${suite_record} cget -suite_path]
   set displayGroup [SharedData_getExpGroupDisplay ${expPath}]
   set currentCoords [Overview_getRunBoxBoundaries  ${canvas} ${suite_record} ${datestamp}]
   # puts "Overview_ExpCreateEndIcon currentCoords:${currentCoords} status:[::SuiteNode::getLastStatus ${suite_record} ${datestamp}]"
   set startX [Overview_getXCoordTime ${timevalue} ${shift_day}]
   set startY [expr [lindex ${currentCoords} 1] +  $expEntryHeight/2 - (${startEndIconSize}/2)]

   set currentStatus [::SuiteNode::getLastStatus ${suite_record} ${datestamp}]
   puts "Overview_ExpCreateEndIcon currentStatus:$currentStatus"
   if { ${shift_day} == true || [string match "defaut*" ${datestamp}] } {
      set currentStatus init
      set expBoxTag [Overview_getExpBoxTag ${expPath} ${datestamp} default]
   } else {
      set expBoxTag [Overview_getExpBoxTag ${expPath} ${datestamp} ${currentStatus}]
   }
   # set expBoxTag [Overview_getExpBoxTag ${expPath} ${datestamp} ${currentStatus}]
   ${canvas} delete ${expBoxTag}.end

   set outlineColor [::DrawUtils::getOutlineStatusColor ${currentStatus}]
   set bgColor [::DrawUtils::getBgStatusColor ${currentStatus}]


   # we create an end icon only if the middle box or the reference box exist
   if { [${canvas} coords ${expBoxTag}.middle] != "" || [${canvas} coords ${expBoxTag}.reference] != ""} {

      set startX2 [expr $startX + ${startEndIconSize}]
      set startY2 [expr $startY + ${startEndIconSize}]
      
      # create the left box
      set endBoxId [${canvas} create oval ${startX} ${startY} ${startX2} ${startY2} -width 1 \
         -fill ${bgColor} -outline ${outlineColor} -tag "${displayGroup} ${expPath} ${expBoxTag} ${expBoxTag}.end"]

      if { [${canvas} coords ${expBoxTag}.reference] != "" } {
         $canvas lower ${expBoxTag}.end ${expBoxTag}.reference
      } else {
         $canvas lower ${expBoxTag}.end ${expBoxTag}.middle
      }
   }
}

# this function creates an experiment reference box.
# The reference box is only created if reference timings are available for an exp.
# The reference box is usually shown when the exp has been submitted and
# the current time is prior to the end reference time.
proc Overview_ExpCreateReferenceBox { canvas suite_record datestamp timevalue {late_reference false} } {
   ::log::log debug "Overview_ExpCreateReferenceBox ${suite_record} ${datestamp} ${timevalue} late_reference:$late_reference"
   global graphStartX expEntryHeight startEndIconSize expBoxOutlineWidth
   set expPath [${suite_record} cget -suite_path]
   # set displayGroup [${suite_record} cget -overview_group_record]
   set displayGroup [SharedData_getExpGroupDisplay ${expPath}]
   set currentCoords [Overview_getRunBoxBoundaries  ${canvas} ${suite_record} ${datestamp}]   
   set currentStatus [::SuiteNode::getLastStatus ${suite_record} ${datestamp}]
   set expBoxTag [Overview_getExpBoxTag ${expPath} ${datestamp} ${currentStatus}]
   set startCoords [${canvas} coords ${expBoxTag}.start]
   ::log::log debug "Overview_ExpCreateReferenceBox ${expPath} startCoords:${startCoords}"
   set refEndTime [Overview_getRefTimings ${expPath} [Utils_getHourFromDatestamp ${datestamp}]  end]
   ::log::log debug "Overview_ExpCreateReferenceBox refEndTime:$refEndTime"
   set startX [Overview_getXCoordTime ${timevalue}]
   set outlineColor [::DrawUtils::getOutlineStatusColor ${currentStatus}]


   if { [${canvas} coords ${expBoxTag}.middle] == "" } {
      set startX [lindex ${startCoords} 2]
   }
   set endX [Overview_getXCoordTime ${refEndTime}]

   if { [${canvas} coords ${expBoxTag}.middle] == "" &&
         [${canvas} coords ${expBoxTag}.reference] == "" } {
      # create the reference from the start icon up to the end reference time
      set startY [expr [lindex ${currentCoords} 1] - ${expEntryHeight}/2 + ${startEndIconSize}/2 ]
      set endY [expr ${startY} + $expEntryHeight/2 + 8 ]
   } else {
      set startY [lindex ${currentCoords} 1]
      set endY [expr $startY + $expEntryHeight/2 + 8]
   }

   # create the ref box
   ${canvas} delete ${expBoxTag}.reference
   if { ${late_reference} == "true" } {
         ${canvas} itemconfigure ${expBoxTag}.text -fill DarkViolet
   } else {
      set refBoxId [${canvas} create rectangle ${startX} ${startY} ${endX} ${endY} -width 1 \
         -dash { 4 3 } -outline ${outlineColor} -tag "${displayGroup} ${expPath} ${expBoxTag} ${expBoxTag}.reference"]

      if { [${canvas} coords ${expBoxTag}.middle] != "" } {
         ${canvas} lower ${expBoxTag}.reference  ${expBoxTag}.middle
      }
   }
}

# create a box from the end of the start icon up to the timevalue
# this middle box is used to show the progression of a running exp
proc Overview_ExpCreateMiddleBox { canvas suite_record datestamp timevalue {shift_day false}  {dummy_box false} } {
   ::log::log debug "Overview_ExpCreateMiddleBox ${suite_record} ${datestamp} ${timevalue} shift_day:${shift_day}"
   global expEntryHeight startEndIconSize expBoxOutlineWidth
   # set displayGroup [${suite_record} cget -overview_group_record]
   set expPath [${suite_record} cget -suite_path]
   set displayGroup [SharedData_getExpGroupDisplay ${expPath}]
   set currentStatus [::SuiteNode::getLastStatus ${suite_record} ${datestamp}]
   set expBoxTag [Overview_getExpBoxTag ${expPath} ${datestamp} ${currentStatus}]
   set startIconCoords [${canvas} coords ${expBoxTag}.start]
   ::log::log debug "Overview_ExpCreateMiddleBox startIconCoords: $startIconCoords"

   $canvas delete ${expBoxTag}.middle
   # middle box starts at end of start box
   set startX [lindex ${startIconCoords} 2]
   set endX [Overview_getXCoordTime ${timevalue} ${shift_day}]

   if { ${shift_day} == true } {
      set currentStatus default
   }
   ::log::log debug "Overview_ExpCreateMiddleBox currentStatus: $currentStatus"

   # delete previous one if exists
   ${canvas} delete ${expBoxTag}.middle

   set outlineColor [::DrawUtils::getOutlineStatusColor ${currentStatus}]

   if { ${dummy_box} && [${canvas} coords ${expBoxTag}.text] != "" } {
      set endX [lindex [${canvas} bbox ${expBoxTag}.text] 2]
   }
   if { [expr ${endX} > ${startX}] } {
      # vertical coords are the same
      set startY [expr [lindex ${startIconCoords} 1] - ${expEntryHeight}/2 + ${startEndIconSize}/2 ]
      set endY [expr ${startY} + $expEntryHeight/2 + 8]
   
      set middleBoxId [$canvas create rectangle ${startX} ${startY} ${endX} ${endY} -width ${expBoxOutlineWidth} \
         -outline ${outlineColor} -fill white -tag "${displayGroup} ${expPath} ${expBoxTag} ${expBoxTag}.middle"]

      $canvas lower ${expBoxTag}.middle ${expBoxTag}.text

      $canvas bind $middleBoxId <Double-Button-1> [list Overview_launchExpFlow ${expPath} ${datestamp} ]
      $canvas bind ${expBoxTag}.text <Double-Button-1> [list Overview_launchExpFlow ${expPath} ${datestamp}]
   }

}

proc Overview_getRefTimings { exp_path hour start_or_end } {
   set refTimings [ExpOptions_getRefTimings ${exp_path} ${hour}]
   
   set foundIndex [lsearch -exact -index 0 ${refTimings} ${hour}]
   if { ${foundIndex} != -1 } {
      set foundRefTimings [lrange [lindex ${refTimings} ${foundIndex}] 1 2]
   }
   set foundTimings ""

   if { ${refTimings} != "" } {
      if { ${start_or_end} == "start" } {
         set foundTimings [lindex ${refTimings} 0]
      } else {
         set foundTimings [lindex ${refTimings} 1]
      }
   }
   # puts "Overview_getRefTimings ${exp_path} ${hour} ${start_or_end} value: ${foundTimings}"
   return ${foundTimings}
}

proc Overview_getExpBoxTag { exp_path datestamp status {full_tag true} } {
   # puts "Overview_getExpBoxTag ${exp_path} $datestamp $status"
   set refTimings [SharedData_getExpTimings ${exp_path}]
   if { [string match "default*" ${datestamp}] } {
      set expBoxTag ${datestamp}
   } else {
      if { ${status} == "default" } {
         if { ${refTimings} == "" } {
            set expBoxTag default
         } else {
            set hour [Utils_getHourFromDatestamp ${datestamp}]
            set expBoxTag default_${hour}
         }
      } else {
         set expBoxTag ${datestamp}
      }
   }
   if { ${full_tag} == true } {
      set expBoxTag ${exp_path}.${expBoxTag}
   }
   #puts "Overview_getExpBoxTag $exp_path $datestamp status value:$expBoxTag"
   return ${expBoxTag}
}

proc Overview_getExpBoxTag__________ { exp_path datestamp status {full_tag true} } {
   puts "Overview_getExpBoxTag ${exp_path} $datestamp $status"
   set refTimings [SharedData_getExpTimings ${exp_path}]
   if { [string match "default*" ${datestamp}] } {
      set expBoxTag ${datestamp}
   } else {
      if { ${status} == "init" } {
         if { ${refTimings} == "" } {
            set expBoxTag default
         } else {
            set hour [Utils_getHourFromDatestamp ${datestamp}]
            set expBoxTag default_${hour}
         }
      } else {
         set expBoxTag ${datestamp}
      }
   }
   if { ${full_tag} == true } {
      set expBoxTag ${exp_path}.${expBoxTag}
   }
   #puts "Overview_getExpBoxTag $exp_path $datestamp status value:$expBoxTag"
   return ${expBoxTag}
}

# return the list of tags in the overview canvas that are used to
# check for box collision.
# The list contains boxes that have a specific datestamp i.e. yyyymmddhh0000
# and default tags for experiment that have reference timings i.e. default_00, default_06, default_12 ....
# and or the default for experiments withouth any reference timings.
proc Overview_getExpBoxTags { canvas exp_path } {
   set suiteRecord [::SuiteNode::formatSuiteRecord ${exp_path}]
   set expBoxTags [::SuiteNode::getDatestamps ${suiteRecord}]
   set refTimings [SharedData_getExpTimings ${exp_path}]
   if { ${refTimings} == "" } {
      if { [${canvas} gettags ${exp_path}.default] != "" } {
         lappend expBoxTags default
      }
   } else {
      foreach refTiming ${refTimings} {
         foreach { hour startTime endTime } ${refTiming} {
            if { [${canvas} gettags ${exp_path}.default_${hour}] != "" } {
               lappend expBoxTags default_${hour}
            }
         }
      }
   }
   set results {}
   foreach expBoxTag ${expBoxTags} {
      if { [${canvas} gettags ${exp_path}.${expBoxTag}] != "" } {
         lappend results ${expBoxTag}
      }
   }
   return ${results}
}

proc Overview_isExpBoxObsolete { canvas exp_path datestamp } {
   # puts "Overview_isExpBoxObsolete $exp_path $datestamp"
   set suiteRecord [::SuiteNode::formatSuiteRecord ${exp_path}]
   set endTime [::SuiteNode::getEndTime ${suiteRecord} ${datestamp}]
   set endDateTime [::SuiteNode::getStatusClockValue ${suiteRecord} ${datestamp} end]
   set xoriginDateTime [Overview_GraphGetXOriginDateTime]
   set currentStatus [::SuiteNode::getLastStatus ${suiteRecord} ${datestamp}]

   set isObsolete false
   if { ${currentStatus} == "end" && [expr ${endDateTime} <= ${xoriginDateTime}] } {
      set isObsolete true
   }
   return ${isObsolete}
}

proc Overview_addExpDefaultBoxes { canvas exp_path } {
   # puts "Overview_addExpDefaultBoxes $exp_path"
   set suiteRecord [::SuiteNode::formatSuiteRecord ${exp_path}]
   set refTimings [SharedData_getExpTimings ${exp_path}]
   if { ${refTimings} == "" } {
      # exp withouth ExpOptions.xml or withouth any ref timings
      Overview_updateExpBox ${canvas} ${suiteRecord} default init
   } else {
      foreach refTiming ${refTimings} {
         foreach { hour startTime endTime } ${refTiming} {
            Overview_updateExpBox ${canvas} ${suiteRecord} default_${hour} init
         }
      }
   }
}

proc Overview_addExpDefaultBox { canvas exp_path datestamp } {
   #puts "Overview_addExpDefaultBox $exp_path $datestamp"
   set refTimings [SharedData_getExpTimings ${exp_path}]
   set suiteRecord [::SuiteNode::formatSuiteRecord ${exp_path}]
   if { ${refTimings} != "" } {
      set hour [Utils_getHourFromDatestamp ${datestamp}]
      set refStartTime [Overview_getRefTimings ${exp_path} ${hour} start]
      set refEndTime [Overview_getRefTimings ${exp_path} ${hour}  end]
      Overview_ExpCreateStartIcon ${canvas} ${suiteRecord} default_${hour} ${refStartTime} true
      Overview_ExpCreateMiddleBox ${canvas} ${suiteRecord} default_${hour} ${refEndTime} true
      Overview_ExpCreateEndIcon ${canvas} ${suiteRecord} default_${hour} ${refEndTime} true
   } else {
      # for default box without ref timings, only add if no other boxes active
      if { [llength [Overview_getExpBoxTags ${canvas} ${exp_path}]] == 0 } {
         set originDateTime [Overview_GraphGetXOriginTime]
         Overview_ExpCreateStartIcon ${canvas} ${suiteRecord} default ${originDateTime} true
      }
   }
}

proc Overview_advanceExpDefaultBox { canvas exp_path } {
   global graphHourX

   set suiteRecord [::SuiteNode::formatSuiteRecord ${exp_path}]
   set refTimings [SharedData_getExpTimings ${exp_path}]

   if { ${refTimings} == "" } {
      if { [${canvas} gettags ${exp_path}.default] != "" } {
         Overview_updateExpBox ${canvas} ${suiteRecord} default init
      }
   } else {
      foreach refTiming ${refTimings} {
         foreach { hour startTime endTime } ${refTiming} {
            Overview_updateExpBox ${canvas} ${suiteRecord} default_${hour} init
         }
      }
   }
}

proc Overview_removeExpBox { canvas exp_path datestamp status } {

   # puts "Overview_removeExpBox $canvas $exp_path datestamp:$datestamp status:$status"
   set expBoxTag [Overview_getExpBoxTag ${exp_path} ${datestamp} ${status}]
   ${canvas} delete ${expBoxTag}.text
   ${canvas} delete ${expBoxTag}.start
   ${canvas} delete ${expBoxTag}.middle
   ${canvas} delete ${expBoxTag}.reference
   ${canvas} delete ${expBoxTag}.end

   if { ! [string match "default*" ${datestamp}] } {
      # try delete default_${hour} tag
      set expBoxTag [Overview_getExpBoxTag ${exp_path} ${datestamp} default]
      # puts "Overview_removeExpBox deleting ${expDefaultTag}"
      ${canvas} delete ${expBoxTag}.text
      ${canvas} delete ${expBoxTag}.start
      ${canvas} delete ${expBoxTag}.middle
      ${canvas} delete ${expBoxTag}.reference
      ${canvas} delete ${expBoxTag}.end
   }
}

proc Overview_isDefaultBoxActive { canvas exp_path datestamp } {
   set refTimings [SharedData_getExpTimings ${exp_path}]
   set isActive false
   set expBoxTag [Overview_getExpBoxTag ${exp_path} ${datestamp} default]
   if { [${canvas} gettags ${expBoxTag}] != "" } {
      set isActive true
   }

   return ${isActive}
}

# if an exp is executing (begin state), this function is called every minute
# to update the exp status
proc Overview_updateExpBox { canvas suite_record datestamp status { timevalue "" } } {
   global startEndIconSize
   set expPath  [${suite_record} cget -suite_path]
   after cancel [SharedData_getExpOverviewUpdateAfterId ${expPath} ${datestamp}]
   set continueStatus ""
   set currentDateTime [clock seconds]
   set currentTime [clock format ${currentDateTime} -format "%H:%M" -gmt 1]

   if { ${timevalue} == "" } {
      set timevalue ${currentTime}
   }

   ::log::log debug "Overview_updateExpBox suite_record:$suite_record datestamp:$datestamp status:$status time:$timevalue updating..."

   array set statusUpdateMap {
      init "Overview_processInitStatus"
      submit "Overview_processSubmitStatus"
      begin "Overview_processBeginStatus continue_begin"
      beginx "Overview_processBeginStatus continue_begin"
      continue_begin "Overview_processBeginStatus continue_begin"
      end "Overview_processEndStatus"
      abort "Overview_processAbortStatus"
      catchup "Overview_processCatchupStatus"
      wait "Overview_processWaitStatus"
   }
   set statusProc ""
   set continueStatus ""
   catch { 
      set statusProcInfo $statusUpdateMap($status)
      set statusProc [lindex ${statusProcInfo} 0]
      set continueStatus [lindex ${statusProcInfo} 1]
   }

   ::log::log debug "Overview_updateExpBox status proc handler: $statusProc"

   if { ${statusProc} != "" } {
      if { [Overview_isExpBoxObsolete ${canvas} ${expPath} ${datestamp}] == true } {
         # the box becomes history, don't need it anymore
         ::SuiteNode::removeStatusDatestamp ${suite_record} ${datestamp}

         Overview_addExpDefaultBox ${canvas} ${expPath} ${datestamp}
         set datestamp [file tail [Overview_getExpBoxTag ${expPath} ${datestamp} default false]]
      } elseif { [string match "default*" ${datestamp}] } {
         Overview_addExpDefaultBox ${canvas} ${expPath} ${datestamp}
      } else {
         ${statusProc} ${canvas} ${suite_record} ${datestamp} ${status}
      }

      set newcoords [Overview_getRunBoxBoundaries ${canvas} ${suite_record} ${datestamp}]
      if { ${newcoords} != "" } {
         set newx1 [lindex ${newcoords} 0]
         set newx2 [lindex ${newcoords} 2]
         set newy1 [lindex ${newcoords} 1]
         set newy2 [lindex ${newcoords} 3]
         # resolve any collision with existings exp boxes
         Overview_resolveLocation ${canvas} ${suite_record} ${datestamp} ${newx1} ${newy1} ${newx2} ${newy2}
      }
      Overview_setExpTooltip ${canvas} ${suite_record} ${datestamp}
   
      $canvas bind ${expPath}.${datestamp} <Button-3> [ list Overview_boxMenu $canvas ${expPath} ${datestamp} %X %Y]
   
      if { ${continueStatus} != "" } {
         set afterId [after 60000 [list Overview_updateExpBox ${canvas} ${suite_record} ${datestamp} ${continueStatus} ]]
         SharedData_setExpOverviewUpdateAfterId ${expPath} ${datestamp} ${afterId}
      }
   }
}

# this function places exp run boxes on the same y slot if there is enough space for it
proc Overview_OptimizeExpBoxes { displayGroup } {
   ::log::log debug "Overview_OptimizeExpBoxes..."

   set canvasW [Overview_getCanvas]

   set expList [$displayGroup cget -exp_list]
   foreach exp $expList {
      # set suiteRecord [::SuiteNode::getSuiteRecordFromPath ${exp}]
      set suiteRecord [::SuiteNode::formatSuiteRecord ${exp}]
      # get the list of datestamps
      set datestamps [::SuiteNode::getDatestamps ${suiteRecord}]

      foreach expDatestamp ${datestamps} {
         # set newcoords [Overview_getExpBoundaries ${canvasW} ${suiteRecord}]
         set newcoords [Overview_getRunBoxBoundaries ${canvasW} ${suiteRecord} ${expDatestamp}]
         if { ${newcoords} != "" } {
            # retrieves the y slot start for the group
            set ySlotStart [DisplayGrp_getNextSlotY ${displayGroup}]
            # retrieves the y slot based on the current position of the exp box
            set yCurrentSlot [DisplayGrp_getCurrentSlotY [lindex ${newcoords} 1]]
            if { ${ySlotStart} != ${yCurrentSlot} } {
               # need to move the exp box to a new location
               set deltaY [expr ${yCurrentSlot} - ${ySlotStart}]
               set done false
               while { ${done} == "false" } {
                  ::log::log debug "Overview_OptimizeExpBoxes $exp ySlotStart:${ySlotStart}"
                  ::log::log debug "Overview_OptimizeExpBoxes $exp yCurrentSlot:${yCurrentSlot} deltaY:$deltaY"
                  set newx1 [lindex ${newcoords} 0]
                  set newx2 [lindex ${newcoords} 2]
                  set newy1 [expr [lindex ${newcoords} 1] - ${deltaY}]
                  set newy2 [expr [lindex ${newcoords} 3] - ${deltaY}]
                  set beforeCoords "$newx1 $newy1 $newx2 $newy2"
                  ::log::log debug "Overview_OptimizeExpBoxes $exp newcoords:${newcoords} beforeCoords:$beforeCoords"
                  set overlapCoords [Overview_resolveOverlap ${canvasW} ${suiteRecord} ${expDatestamp} ${newx1} ${newy1} ${newx2} ${newy2}]
                  ::log::log debug "Overview_OptimizeExpBoxes $exp overlapCoords:${overlapCoords}"
                  if { [Utils_isListEqual ${overlapCoords} ${beforeCoords}] == "true" } {
                     set deltay [expr [lindex $overlapCoords 1] - [lindex ${newcoords} 1]]
                     ::log::log debug "Overview_OptimizeExpBoxes $exp moving to new location 0 ${deltay}"
                     ${canvasW} move ${exp} 0 ${deltay}
                     DisplayGrp_setMaxY ${displayGroup} [lindex $overlapCoords 1]
                     DisplayGrp_processOverlap ${displayGroup}
                     # DisplayGrp_processEmptyRows ${displayGroup}
                     set done true
                  } else {
                     if { [expr ${ySlotStart} == [${displayGroup} cget -maxy]] } {
                        set done true
                     }
                     set ySlotStart [DisplayGrp_getNextSlotY ${displayGroup} ${ySlotStart}]
                  }
                  set deltaY [expr ${yCurrentSlot} - ${ySlotStart}]
               }
            }
         }
      # end for each datestamp
      }
   }
}

# this function finds the right location for an exp box datestamp.
proc Overview_resolveLocation { canvas suite_record datestamp x1 y1 x2 y2 } {
   global expEntryHeight
   ::log::log debug "Overview_resolveLocation suite_record:$suite_record datestamp:$datestamp x1:$x1 y1:$y1 x2:$x2 y2:$y2"
   set expPath [${suite_record} cget -suite_path]
   set currentCoords "${x1} ${y1} ${x2} ${y2}"
   set overlapCoords [Overview_resolveOverlap ${canvas} ${suite_record} ${datestamp} ${x1} ${y1} ${x2} ${y2}]
   ::log::log debug "Overview_resolveLocation overlapCoords ${overlapCoords}"
   # set displayGroup [${suite_record} cget -overview_group_record]
   set displayGroup [SharedData_getExpGroupDisplay ${expPath}]
   if { [Utils_isListEqual ${currentCoords} ${overlapCoords}] == "false" } {
      set deltax [expr [lindex $overlapCoords 0] - ${x1}]
      set deltay [expr [lindex $overlapCoords 1] - ${y1}]
      $canvas move ${expPath}.${datestamp} ${deltax} ${deltay}
      ::log::log debug "Overview_resolveLocation $canvas move ${expPath}.${datestamp} ${deltax} ${deltay}"
      ::log::log debug "Overview_resolveLocation moving ${expPath}.${datestamp} from $x1 $y1 $x2 $y2 to $overlapCoords"
      DisplayGrp_setMaxY ${displayGroup} [lindex $overlapCoords 1]
      DisplayGrp_processOverlap ${displayGroup}
      # the new location is clear within its own group but
      # need to check if the new location overlaps with another display group
      ::log::log debug "Overview_resolveLocation moving ${expPath} from $x1 $y1 $x2 $y2 to $overlapCoords"
   }
   DisplayGrp_processEmptyRows ${displayGroup}
   # sua testing buggy right now
   # Overview_OptimizeExpBoxes ${displayGroup}
}

# this function is used to shift up a row exp boxes within an exp group 
# if the boxes are located below an empty row...
proc Overview_ShiftExpRow { display_group empty_slot_y } {
   global expEntryHeight

   ::log::log debug "Overview_ShiftExpRow $display_group $empty_slot_y"
   set expList [${display_group} cget -exp_list]
   set overviewCanvas [Overview_getCanvas]
   foreach exp ${expList} {
      set suiteRecord [::SuiteNode::formatSuiteRecord ${exp} ]
      set datestamps [::SuiteNode::getDatestamps ${suiteRecord}]
      foreach expDatestamp ${datestamps} {

         foreach {xx1 yy1 xx2 yy2} [Overview_getRunBoxBoundaries ${overviewCanvas} ${suiteRecord} ${expDatestamp}] { break }
            if { ${yy1} != "" && ${yy1} > ${empty_slot_y} } {
               # y of exp is greater than empty box, shift it up
               ::log::log debug "Overview_ShiftExpRow ${display_group} shifting ${exp}.${expDatestamp} up"
               ${overviewCanvas} move ${exp}.${expDatestamp} 0 -${expEntryHeight}
            }
         }
      set suiteRecord [::SuiteNode::getSuiteRecordFromPath ${exp} ]
      set expBoxCoords [Overview_getExpBoundaries ${overviewCanvas} ${suiteRecord}]
      if { [lindex ${expBoxCoords} 1] > ${empty_slot_y} } {
         # y of exp is greater than empty box, shift it up
         ::log::log debug "Overview_ShiftExpRow ${display_group} shifting ${exp} up"
         ${overviewCanvas} move ${exp} 0 -${expEntryHeight}
      }
   }
}

# this function is called to check whether or not the current exp box is
# overlapping another exp from the same experiment group.
# It checks the boundaries of the given exp (x1 y1 x2 y2) against the
# boundaries of every exp in the same group. If there is an overlap, the function
# recursively finds another location. The boundaries coordinates are returned
# as "x1 y1 x2 y2"... It is up to the caller to compare the boundaries and to move
# the exp box to the new location
proc Overview_resolveOverlap { canvas suite_record datestamp x1 y1 x2 y2 } {
   ::log::log debug "Overview_resolveOverlap $suite_record datestamp:$datestamp x1:$x1 y1:$y1 x2:$x2 y2:$y2"
   global expEntryHeight
   # set displayGroup [${suite_record} cget -overview_group_record]
   set expPath [${suite_record} cget -suite_path]
   set displayGroup [SharedData_getExpGroupDisplay ${expPath}]
   set expList [${displayGroup} cget -exp_list]

   set currentExpBoxTag ${datestamp}
   # first check if the current run box collides with other run boxes of the
   # the same experiment
   set expBoxTags [Overview_getExpBoxTags ${canvas} ${expPath}]
   ::log::log debug "Overview_resolveOverlap Overview_resolveOverlap expBoxTags:${expBoxTags}"
   foreach expBoxTag ${expBoxTags} {
      set isOverlap 0
      if { ${expBoxTag} != ${currentExpBoxTag} } {
         ::log::log debug "Overview_resolveOverlap ${expBoxTag} != ${currentExpBoxTag}"
         foreach {xx1 yy1 xx2 yy2} [Overview_getRunBoxBoundaries ${canvas} ${suite_record} ${expBoxTag}] { break }
         if { [info exists xx1] && "${xx1}" != "" } {
            set isOverlap [Utils_isOverlap $x1 $y1 $x2 $y2 $xx1 $yy1 $xx2 $yy2]
         }
      }
      if { ${isOverlap} } {
         # try to display the box in the next row
         set newy1 [expr ${y1} + ${expEntryHeight}]
         set newy2 [expr ${y2} + ${expEntryHeight}]
         ::log::log debug "Overview_resolveOverlap calling recursive Overview_resolveOverlap expBoxTag:${expBoxTag} ${x1} ${newy1} ${x2} ${newy2}"
         set newCoords [Overview_resolveOverlap ${canvas} ${suite_record} ${currentExpBoxTag} ${x1} ${newy1} ${x2} ${newy2}]
         ::log::log debug "Overview_resolveOverlap got new coords Overview_resolveOverlap ${newCoords}"
         return ${newCoords}
      }
   }

   # then check if it does not overlap with the rest of the run boxes of the other exps
   foreach exp $expList {
      set isOverlap 0
      if { ${exp} != ${expPath} } {
         set testedSuiteRecord [::SuiteNode::formatSuiteRecord ${exp}]
         set expBoxTags [Overview_getExpBoxTags ${canvas} ${exp}]
         ::log::log debug "Overview_resolveOverlap ${exp} $testedSuiteRecord Overview_resolveOverlap expBoxTags2:${expBoxTags}"
         foreach expBoxTag ${expBoxTags} {
            set isOverlap 0
            ::log::log debug "Overview_resolveOverlap testing ${expPath} collision with exp:$exp ???"
            set testedExpBox [Overview_getRunBoxBoundaries ${canvas} ${testedSuiteRecord} ${expBoxTag}]
            if { [llength $testedExpBox] != 0 } {
               ::log::log debug "Overview_resolveOverlap exp:$exp testedExpBox:$testedExpBox"
               foreach {xx1 yy1 xx2 yy2} [Overview_getRunBoxBoundaries ${canvas} ${testedSuiteRecord} ${expBoxTag}] { break }
               if { [info exists xx1] && "${xx1}" != "" } {
                  ::log::log debug "Overview_resolveOverlap xx1:$xx1 yy1:$yy1 xx2:$xx2 yy2:$yy2"
                  set isOverlap [Utils_isOverlap $x1 $y1 $x2 $y2 $xx1 $yy1 $xx2 $yy2]
               }
               ::log::log debug "Overview_resolveOverlap FOUND OVERLAP? $isOverlap"
            }
            if { ${isOverlap} } {
               # try to display the box in the next row
               set newy1 [expr ${y1} + ${expEntryHeight}]
               set newy2 [expr ${y2} + ${expEntryHeight}]
               ::log::log debug "Overview_resolveOverlap calling recursive Overview_resolveOverlap ${x1} ${newy1} ${x2} ${newy2}"
               set newCoords [Overview_resolveOverlap ${canvas} ${suite_record} ${currentExpBoxTag} ${x1} ${newy1} ${x2} ${newy2}]
               ::log::log debug "Overview_resolveOverlap got new coords Overview_resolveOverlap ${newCoords}"
               return ${newCoords}
            }
         }
      }
   }

   ::log::log debug "Overview_resolveOverlap $suite_record datestamp:${datestamp}  returning $x1 $y1 $x2 $y2"

   return "$x1 $y1 $x2 $y2"
}

# this function is called to pop-up an exp node menu
proc Overview_boxMenu { canvas exp_path datestamp x y } {
   global env
   ::log::log debug "Overview_boxMenu() exp_path:$exp_path datestamp:${datestamp}"
   if { [string match "default*" ${datestamp}] } {
      set datestamp ""
   }

   set popMenu .popupMenu
   if { [winfo exists $popMenu] } {
      destroy $popMenu
   }
   menu $popMenu
   $popMenu add command -label "History" \
      -command [list Overview_historyCallback $canvas $exp_path ${datestamp} $popMenu]
   $popMenu add command -label "Flow" -command [list Overview_launchExpFlow $exp_path ${datestamp}]
   $popMenu add command -label "Shell" -command [list Utils_launchShell $env(TRUE_HOST) $exp_path $exp_path "SEQ_EXP_HOME=${exp_path}"]
   $popMenu add command -label "Support" -command [list Overview_showSupportCallback $exp_path ${datestamp} [winfo toplevel ${canvas}]]
   tk_popup $popMenu $x $y
   ::tooltip::tooltip $popMenu -index 0 "Show Exp History"
}

proc Overview_showSupportCallback { exp_path datestamp {caller_w .} } {
   ExpOptions_showSupport $exp_path [Utils_getHourFromDatestamp ${datestamp}] [winfo toplevel ${caller_w}]
}

# this function is called to show the history of an experiment
proc Overview_historyCallback { canvas exp_path datestamp caller_menu } {
   ::log::log debug "Overview_historyCallback exp_path:$exp_path"
   set seqExec [SharedData_getMiscData SEQ_UTILS_BIN]/nodehistory
   set suiteRecord [::SuiteNode::formatSuiteRecord ${exp_path}]
   set seqNode [SharedData_getExpRootNode ${exp_path}]
   if { ${datestamp} != "" } {
      # retrieve the last 30 days
      set cmdArgs "-n $seqNode -edate ${datestamp} -history [expr 30*24]"
   } else {
      # retrieve all
      set cmdArgs "-n $seqNode"
   }

   Sequencer_runCommandWithWindow $exp_path ${datestamp} $seqExec "Node History ${exp_path}" bottom ${cmdArgs}
}

proc Overview_ThreadFullEvent { {name1 ""} {name2 ""} {op ""} } {
   global THREAD_FULL_EVENT
   if { ${THREAD_FULL_EVENT} == true } {
      tk_messageBox -title "Warning!" -parent [Overview_getToplevel] -type ok -icon warning \
         -message "Maximum flow windows reached, please close some windows."
      set THREAD_FULL_EVENT false
   }
}

# this function is called to launch an exp window
# It sends the request to the exp thread to care of it.
proc Overview_launchExpFlow { exp_path datestamp } {
   global EXP_LAUNCH_AFTER_ID
   ::log::log debug "Overview_launchExpFlow exp_path:$exp_path datestamp:$datestamp"
   ::log::log notice "Overview_launchExpFlow exp_path:$exp_path datestamp:$datestamp"
   global env ExpThreadList PROGRESS_REPORT_TXT

   xflow_init ${exp_path}

   set progressWidth 25
   set extraMsg ""
   if { ${datestamp} != "" } {
      set progressWidth 40
      set extraMsg "datestamp=[Utils_getVisibleDatestampValue ${datestamp}]"
   }
   set result [ catch {

      set isNewThread false
      set expThreadId [SharedData_getExpThreadId ${exp_path} ${datestamp}]
      if { ${expThreadId} == "" } {
         set expThreadId [ThreadPool_getThread]
         if { ${expThreadId} == "" } {
            tk_messageBox -title "Launch Exp Flow Error" -parent [Overview_getToplevel] -type ok -icon error \
               -message "Maximum flow windows reached, please close some windows and re-launch manually."
            return
         }
         set isNewThread true
      }

      ::log::log notice "Overview_ThreadLaunchFLow launching progess bar..."
      set progressW .pd
      if { ! [winfo exists ${progressW}] } {
         ProgressDlg ${progressW} -title "Launch Exp Flow" -parent [Overview_getToplevel]  -textvariable PROGRESS_REPORT_TXT -width ${progressWidth} -stop stop
      }

      set PROGRESS_REPORT_TXT "Launching [file tail ${exp_path}] ${extraMsg}"
      # for some reason, I need to call the update for the progress dlg to appear properly
      update idletasks

      # retrieve the exp thread based on the exp_path
      set suiteRecord [::SuiteNode::formatSuiteRecord ${exp_path}]

      if { ${isNewThread} == true } {

         # force reread of log file from start
         SharedData_setExpDatestampOffset ${exp_path} ${datestamp} 0

         if { [thread::exists ${expThreadId}] } {
             ::log::log notice "Overview_launchExpFlow new exp thread calling LogReader_startExpLogReader..."
            thread::send ${expThreadId} "LogReader_startExpLogReader ${exp_path} \"${datestamp}\""
         }
      }

      ::log::log debug "Overview_ThreadLaunchFLow ${exp_path} \"${datestamp}\""
      ::log::log notice "Overview_launchExpFlow sending Overview_ThreadLaunchFLow"
      # send the request to the exp thread
      # thread::send ${expThreadId} "Overview_ThreadLaunchFLow ${exp_path} \"${datestamp}\""
      Overview_ThreadLaunchFLow ${exp_path} "${datestamp}"
      ::log::log notice "Overview_launchExpFlow Overview_ThreadLaunchFLow ${exp_path} done"


      destroy ${progressW}

   } message ]

   # any errors, put the cursor back to normal state
   if { ${result} != 0  } {
      ::log::log notice "Overview_launchExpFlow ERROR: ${message}"

      set einfo $::errorInfo
      set ecode $::errorCode
      catch { destroy ${progressW} }

      # report the error with original details
      return -code ${result} \
         -errorcode ${ecode} \
         -errorinfo ${einfo} \
         ${message}
   }
}

# this proc is called before releasing an exp thread to the thread pool
proc Overview_releaseExpThread { exp_thread_id exp_path datestamp } {
   puts "Overview_releaseExpThread exp_thread_id:${exp_thread_id} exp_path:${exp_path} datestamp:${datestamp}"
   SharedData_removeExpThreadId ${exp_path} ${datestamp}
   # thread::send -async ${exp_thread_id} "xflow_quit true"
   ThreadPool_releaseThread ${exp_thread_id}
}

# At application startup, this function is called by each
# exp thread to notify the overview that it is done reading
# the exp log file... At startup, the overview waits for every exp thread
# to finish before proceeding...
proc Overview_childInitDone { exp_path datestamp } {
   global EXP_THREAD_STARTUP_DONE ALL_CHILD_INIT_DONE STARTUP_PROGRESS_VALUE
   global STARTUP_PROGRESS_TXT
   ::log::log debug "Overview_childInitDone datestamp:${datestamp} exp_path:$exp_path"

   catch { unset EXP_THREAD_STARTUP_DONE(${exp_path}_${datestamp}) }
   incr STARTUP_PROGRESS_VALUE
   set STARTUP_PROGRESS_TXT "${exp_path} \n datestamp=${datestamp} loaded."
   if { [array names EXP_THREAD_STARTUP_DONE] != "" } {
      ::log::log debug "Overview_childInitDone note done: [array names EXP_THREAD_STARTUP_DONE]"
   } else {
      set ALL_CHILD_INIT_DONE 1
   }
}

proc Overview_addChildInit { exp_path datestamp } {
   global EXP_THREAD_STARTUP_DONE
   set EXP_THREAD_STARTUP_DONE(${exp_path}_${datestamp}) 0
}

proc Overview_waitChildInitDone {} {
   global EXP_THREAD_STARTUP_DONE
   
   if { [array names EXP_THREAD_STARTUP_DONE] != "" } {
      ::log::log debug "Overview_waitChildInitDone ..."
      vwait ALL_CHILD_INIT_DONE
   }
}

proc Overview_isExpStartupDone { exp_thread_id exp_path datestamp } {
   set isStartupDone [SharedData_getMiscData STARTUP_DONE]
}

# this function is called asynchronously by experiment child threads to
# update the status of an experiment node in the overview panel.
# See LogReader.tcl
proc Overview_updateExp { exp_thread_id exp_path datestamp status timestamp } {
   global AUTO_LAUNCH
   ::log::log debug "Overview_updateExp exp_thread_id:$exp_thread_id $suite_record datestamp:$datestamp status:$status timestamp:$timestamp "
   set suite_record [::SuiteNode::formatSuiteRecord ${exp_path}]
   set colors [::DrawUtils::getStatusColor $status]
   set bgColor [lindex $colors 1]
   set canvas [Overview_getCanvas]
   # retrieve the date & time from the given time stamp
   set dateValue [Utils_getDateFromDatestamp ${timestamp}]
   set timeValue [Utils_getTimeFromDatestamp ${timestamp}]
   set tagName [$suite_record cget -suite_path]
   ::log::log debug "Overview_updateExp setLastStatusInfo $suite_record $datestamp $status $dateValue $timeValue"
   set currentLastStatus [::SuiteNode::getLastStatus ${suite_record} ${datestamp}]

   # store the info for current update
   ::SuiteNode::setLastStatusInfo $suite_record $datestamp $status $dateValue $timeValue
   if { $status == "beginx" } {
      if { ${currentLastStatus} == "end" } {
      }
      # beginx usually means that a task node that has aborted is restarted... we don't want 
      # the exp box to move everytime a task is restarted so we get the begin value and 
      set statusInfo [::SuiteNode::getStatusInfo ${suite_record} ${datestamp} begin]

      set timeValue [lindex ${statusInfo} 1]
      ::log::log debug "Overview_updateExp getStatusInfo $suite_record $datestamp status:begin statusInfo:${statusInfo}"
      ::log::log debug "Overview_updateExp getStatusInfo $suite_record $datestamp status:beginx statusInfo:[::SuiteNode::getStatusInfo ${suite_record} ${datestamp} beginx]"
   }
   if { [winfo exists $canvas] } {

      set isStartupDone [SharedData_getMiscData STARTUP_DONE]
      if { $status == "begin" } {
         # launch the flow if needed... but not when the app is startup up
         if { ${AUTO_LAUNCH} == "true" && ${isStartupDone} == "true"  && [SharedData_getExpStartupDone ${exp_path} ${datestamp}] == true } {
            ::log::log notice "exp begin detected for [${suite_record} cget -suite_path] datestamp:${datestamp} timestamp:${timestamp}"
            ::log::log notice "exp launching xflow window [${suite_record} cget -suite_path] datestamp:${datestamp}"
            Overview_launchExpFlow [$suite_record cget -suite_path] ${datestamp}
         }
      } else {
         # change the exp colors
         Overview_refreshBoxStatus ${suite_record} ${datestamp}
      }
      if { ${isStartupDone} == "true" && [SharedData_getExpStartupDone ${exp_path} ${datestamp}] == true } {
         # check for box overlapping, auto-refresh, etc
         Overview_updateExpBox ${canvas} ${suite_record} ${datestamp} ${status} ${timeValue}
      ::log::log debug "Overview_updateExp Overview_updateExpBox DONE!"
         Overview_checkGridLimit
      ::log::log debug "Overview_updateExp Overview_checkGridLimit DONE!"
      }

   } else {
      ::log::log debug "Overview_updateExp canvas $canvas does not exists!"
   }

}

proc Overview_refreshExpLastStatus { exp_path datestamp } {
   set suiteRecord [::SuiteNode::formatSuiteRecord ${exp_path}]
   set currentStatus [::SuiteNode::getLastStatus ${suiteRecord} ${datestamp}]
   set statusTime [::SuiteNode::getLastStatusTime ${suiteRecord} ${datestamp}]
   if { ${statusTime} != "" } {
      Overview_updateExpBox [Overview_getCanvas] ${suiteRecord} ${datestamp} ${currentStatus} ${statusTime}
   }
}

# checks whether the time grid is too small to hold all exp boxes,
# increase the grid if required
proc Overview_checkGridLimit {} {
   global expEntryHeight graphy
   set displayGroups [ExpXmlReader_getGroups]
   set lastGroup [lindex ${displayGroups} end]
   if { ${lastGroup} != "" } {
      #puts "Overview_checkGridLimit last group y:[${lastGroup} cget -y] maxy:[${lastGroup} cget -maxy]"
      #puts "Overview_checkGridLimit grid maxy: [[Overview_getCanvas] coords grid_max_y]"
      set canvasW [Overview_getCanvas]
      # get the max y from the exp boxes
      set maxExpBoxY [${lastGroup} cget -maxy]
      # get the max y coord of the grid
      set maxGridCoords [${canvasW} coords grid_max_y]
      if { ${maxGridCoords} != "" } {
         set maxGridY [lindex ${maxGridCoords} 1]
         if { ${maxGridY} <= ${maxExpBoxY} } {
            # grid is too small, increase it
            #puts "Overview_checkGridLimit adjust grid from ${maxGridY} to ${maxExpBoxY}"
            # round out the value to the next grid value
            set graphy [expr ${maxExpBoxY} + [expr ${maxExpBoxY} % ${expEntryHeight}]]
            # delete the grid
            ${canvasW} delete grid_item
            Overview_createGraph ${canvasW}
            ${canvasW} lower grid_item
            ${canvasW} lower canvas_bg_image
            Overview_setCurrentTime ${canvasW}
            Overview_setCanvasScrollArea ${canvasW}
         }
      }
   }
}

# sets the scrolll area of the overview grid
proc Overview_setCanvasScrollArea { canvasW } {
   global graphX graphStartX

   set x1 0
   set y1 0
   set x2 [expr ${graphStartX} + ${graphX} + 60]
   set footerCoords [${canvasW} coords grid_footer]
   set y2 [expr [lindex ${footerCoords} 3] + 120]

   # the scroll area is determined by the grid
   # puts "Overview_setCanvasScrollArea -scrollregion $x1 $y1 $x2 $y2"
   ${canvasW} configure -scrollregion [list $x1 $y1 $x2 $y2] -yscrollincrement 5 -xscrollincrement 5
}

# this function is called to add a new experiment to be monitored by the overview
proc Overview_addExp { display_group canvas exp_path } {
   ::log::log debug "Overview_addExp display_group:$display_group exp_path:$exp_path"
   
   set suiteRecord [::SuiteNode::formatSuiteRecord ${exp_path}]
   # creates a dummy suite record
   SuiteInfo ${suiteRecord} -suite_path ${exp_path}
   ::log::log debug "Overview_addExp suiteRecord:$suiteRecord"

   ############################
   # thread part start
   ############################
   set mainid [thread::id]

   # create startup threads to process log datestamps
   # get the list of datestamps visible from the left side of the overview for this exp
   set visibleDatestamps [LogMonitor_getDatestamps ${exp_path} [clock format [clock add [clock seconds] -13 hours]]]
   ::log::log debug "Overview_addExp suiteRecord:$suiteRecord visibleDatestamps:$visibleDatestamps"

   if [ catch { ExpOptions_read ${exp_path} } message ] {
      set errMsg "Error Parsing ExpOptions.xml file ${exp_path}:\n$message"
      puts "${errMsg}"
      tk_messageBox -title "Application Error!" -type ok -icon error \
         -message ${errMsg}
   }
   

   foreach datestamp ${visibleDatestamps} {
      if { [Utils_validateRealDatestamp ${datestamp}] == true } {
         # create a child thread for the exp
         set childId [ThreadPool_getThread true]

         set currentDateTime [clock seconds]
         set currentTime [clock format ${currentDateTime} -format "%H:%M" -gmt 1]
         set dateValue [clock format ${currentDateTime} -format "%Y%m%d" -gmt 1]
         # forces the exp node to be init mode
         # the exp node will be updated later with new entries from the log file
         ::SuiteNode::setLastStatusInfo ${suiteRecord} ${datestamp} init $dateValue ${currentTime}

         # read log and quit
         Overview_addChildInit ${exp_path} ${datestamp}
         # puts "Overview_addExp thread::send -async ${childId} Overview_startExpLogReader ${exp_path} ${suiteRecord} ${datestamp} true"
         thread::send -async ${childId} "LogReader_startExpLogReader ${exp_path} ${datestamp} true"
      }
   }

   # retrieve the exp root node
   #${suiteRecord} configure -overview_group_record ${display_group}
   SharedData_setExpGroupDisplay ${exp_path} ${display_group}
}

# this function is called from the overview main thread to the exp thread
# to start the processing of the exp log file i.e. it is meant to be run in the exp thread.
proc Overview_startExpLogReader { exp_path suite_record datestamp {is_startup false} } {
   # puts "Overview_startExpLogReader exp_path:$exp_path datestamp:$datestamp is_startup:$is_startup"
   global env this_id
   ::log::log debug "Overview_startExpLogReader"

   xflow_initThread

   # tk appname "[file tail ${exp_path}] - ${datestamp}"

   SharedData_setExpThreadId ${exp_path} "${datestamp}" [thread::id]

   ::log::log debug "Overview_startExpLogReader exp_path=${exp_path} datestamp:${datestamp}"
   # puts "Overview_startExpLogReader xflow_readFlowXml"

   if [ catch { xflow_readFlowXml ${exp_path} } message ] {
      set errMsg "Error Parsing flow.xml file ${exp_path}:\n$message"
      puts "${errMsg}"
      tk_messageBox -title "Application Error!" -type ok -icon error \
         -message ${errMsg}
      exit 1
   }

   # puts "Overview_startExpLogReader LogReader_readFile"
   if { ${is_startup} == true } {
      if { [LogMonitor_isLogFileActive ${exp_path} ${datestamp}] == false } {
         # inactive log
         # only send to overview and msg center, don't send to flow
         LogReader_readFile ${suite_record} ${datestamp} no_flow
         # release exp thread
         thread::send -async [SharedData_getMiscData OVERVIEW_THREAD_ID] "Overview_releaseExpThread [thread::id] ${exp_path} ${datestamp}"
      } else {
         # active log, we read the log files, send updates to overview, to msg center and to flow thread as well
         LogReader_readFile ${suite_record} ${datestamp} all
      }
   } else {
      # this is usually called when the user launches a flow from the overview,
      # at that point we don't care about sending updates to overview or msg center cause it's already done
      # just launch the flow
      LogReader_readFile ${suite_record} ${datestamp} refresh_flow
   }
}

# this function is called from the overview main thread to the exp thread
# to display the exp flow either on user's request or because of "Auto Launch"
proc Overview_ThreadLaunchFLow { exp_path datestamp } {
   global this_id
   ::log::log debug "Overview_ThreadLaunchFLow exp_path:${exp_path} datestamp:${datestamp}"
   xflow_displayFlow ${exp_path} ${datestamp}
}


# this function returns a list of 4 coords x1 y1 x2 y2
# that are the boundaries of an exp box in the display.
# the boundaries values are based on the different items displayed
# for an exp box.
proc Overview_getExpBoundaries { canvas suite_record } {
   global expEntryHeight startEndIconSize
   set expPath [${suite_record} cget -suite_path]

   if { [${canvas} coords ${expPath}] == "" } {
      ::log::log debug "Overview_getExpBoundaries no boundaries found for ${expPath}"
      return ""
   }

   set boundaries [${canvas} coords ${expPath}]
   set x1 [lindex ${boundaries} 0]
   set y1 [lindex ${boundaries} 1]
   set x2 [lindex ${boundaries} 2]
   set y2 [lindex ${boundaries} 3]

   if { [${canvas} coords ${expPath}.start] != "" } {
      set boundaries [${canvas} coords ${expPath}.start]
      set x1 [lindex ${boundaries} 0]
      set y1 [lindex ${boundaries} 1]
      set x2 [lindex ${boundaries} 2]
      set y2 [lindex ${boundaries} 3]
   }

   if { [${canvas} coords ${expPath}.text] != "" } {
      set boundaries [${canvas} bbox ${expPath}.text]
      if { [expr [lindex ${boundaries} 0] < ${x1}] } {
         set x1 [lindex ${boundaries} 0]
      }
      if { [expr [lindex ${boundaries} 2] > ${x2}] } {
         set x2 [lindex ${boundaries} 2]
      }
   }

   if { [${canvas} coords ${expPath}.middle] != "" } {
      set boundaries [${canvas} coords ${expPath}.middle]
      set y1 [lindex ${boundaries} 1]
      set x2 [lindex ${boundaries} 2]
      set y2 [lindex ${boundaries} 3]
   }

   if { [${canvas} coords ${expPath}.reference] != "" } {
      set boundaries [${canvas} coords ${expPath}.reference]
      set y1 [lindex ${boundaries} 1]
      set x2 [lindex ${boundaries} 2]
      set y2 [lindex ${boundaries} 3]
   }

   if { [${canvas} coords ${expPath}.end] != "" } {
      set boundaries [${canvas} coords ${expPath}.end]
      set x2 [lindex ${boundaries} 2]
   }

   set boundaries "$x1 $y1 $x2 $y2"
   ::log::log debug "Overview_getExpBoundaries boudaries ${expPath} : ${boundaries}"
   return ${boundaries}
}

proc Overview_getRunBoxBoundaries { canvas suite_record datestamp } {
   set expPath [${suite_record} cget -suite_path]
   set lastStatusTime [::SuiteNode::getLastStatusTime ${suite_record} ${datestamp}]
   set xoriginDateTime [Overview_GraphGetXOriginDateTime]

   set lastStatus [::SuiteNode::getLastStatus ${suite_record} ${datestamp}]
   set expBoxTag [Overview_getExpBoxTag ${expPath} ${datestamp} ${lastStatus}]
      ::log::log debug "Overview_getRunBoxBoundaries expBoxTag ${expBoxTag}"

   if { [${canvas} coords ${expBoxTag}] == "" } {
      ::log::log debug "Overview_getRunBoxBoundaries no boudaries found for ${expPath}.${datestamp}"
      return ""
   }

   foreach {x1 y1 x2 y2} [${canvas} coords ${expBoxTag}] { break }

   if { [${canvas} coords ${expBoxTag}.start] != "" } {
      set boundaries [${canvas} coords ${expBoxTag}.start]
      set x1 [lindex ${boundaries} 0]
      set y1 [lindex ${boundaries} 1]
      set x2 [lindex ${boundaries} 2]
      set y2 [lindex ${boundaries} 3]
   }

   if { [${canvas} coords ${expBoxTag}.middle] != "" } {
      set boundaries [${canvas} coords ${expBoxTag}.middle]
      set y1 [lindex ${boundaries} 1]
      set x2 [lindex ${boundaries} 2]
      set y2 [lindex ${boundaries} 3]
   }

   if { [${canvas} coords ${expBoxTag}.reference] != "" } {
      set boundaries [${canvas} coords ${expBoxTag}.reference]
      set y1 [lindex ${boundaries} 1]
      set x2 [lindex ${boundaries} 2]
      set y2 [lindex ${boundaries} 3]
   }

   if { [${canvas} coords ${expBoxTag}.end] != "" } {
      set boundaries [${canvas} coords ${expBoxTag}.end]
      set x2 [lindex ${boundaries} 2]
   }

   if { [${canvas} coords ${expBoxTag}.text] != "" } {
      set boundaries [${canvas} bbox ${expBoxTag}.text]
      if { [expr [lindex ${boundaries} 0] < ${x1}] } {
         set x1 [lindex ${boundaries} 0]
      }
      if { [expr [lindex ${boundaries} 2] > ${x2}] } {
         set x2 [lindex ${boundaries} 2]
      }
   }


   set boundaries "$x1 $y1 $x2 $y2"
   ::log::log debug "Overview_getRunBoxBoundaries boudaries ${expBoxTag} : ${boundaries}"
   return ${boundaries}
}

proc Overview_getRunBoxBoundaries____________ { canvas suite_record datestamp } {
   set expPath [${suite_record} cget -suite_path]
   set lastStatusTime [::SuiteNode::getLastStatusTime ${suite_record} ${datestamp}]
   set xoriginDateTime [Overview_GraphGetXOriginDateTime]

   if { [${canvas} coords ${expPath}.${datestamp}] == "" } {
      if { [${canvas} coords ${expPath}.] != "" } {
         set datestamp ""
         # puts "Overview_resolveOverlap Overview_getRunBoxBoundaries found empty datestamp boudaries for  ${expPath}.${datestamp}"
      } else {
         ::log::log debug "Overview_getRunBoxBoundaries no boudaries found for ${expPath}.${datestamp}"
         # puts "Overview_resolveOverlap Overview_getRunBoxBoundaries no boudaries found for ${expPath}.${datestamp}"
         return ""
      }
   }

   set boundaries [${canvas} coords ${expPath}.${datestamp}]
   set x1 [lindex ${boundaries} 0]
   set y1 [lindex ${boundaries} 1]
   set x2 [lindex ${boundaries} 2]
   set y2 [lindex ${boundaries} 3]

   if { [${canvas} coords ${expPath}.${datestamp}.start] != "" } {
      set boundaries [${canvas} coords ${expPath}.${datestamp}.start]
      set x1 [lindex ${boundaries} 0]
      set y1 [lindex ${boundaries} 1]
      set x2 [lindex ${boundaries} 2]
      set y2 [lindex ${boundaries} 3]
   }

   if { [${canvas} coords ${expPath}.${datestamp}.middle] != "" } {
      set boundaries [${canvas} coords ${expPath}.${datestamp}.middle]
      set y1 [lindex ${boundaries} 1]
      set x2 [lindex ${boundaries} 2]
      set y2 [lindex ${boundaries} 3]
   }

   if { [${canvas} coords ${expPath}.${datestamp}.reference] != "" } {
      set boundaries [${canvas} coords ${expPath}.${datestamp}.reference]
      set y1 [lindex ${boundaries} 1]
      set x2 [lindex ${boundaries} 2]
      set y2 [lindex ${boundaries} 3]
   }

   if { [${canvas} coords ${expPath}.${datestamp}.end] != "" } {
      set boundaries [${canvas} coords ${expPath}.${datestamp}.end]
      set x2 [lindex ${boundaries} 2]
   }

   if { [${canvas} coords ${expPath}.${datestamp}.text] != "" } {
      set boundaries [${canvas} bbox ${expPath}.${datestamp}.text]
      if { [expr [lindex ${boundaries} 0] < ${x1}] } {
         set x1 [lindex ${boundaries} 0]
      }
      if { [expr [lindex ${boundaries} 2] > ${x2}] } {
         set x2 [lindex ${boundaries} 2]
      }
   }


   set boundaries "$x1 $y1 $x2 $y2"
   ::log::log debug "Overview_getRunBoxBoundaries boudaries ${expPath}.${datestamp} : ${boundaries}"
   return ${boundaries}
}

# returns the boundaries of a DisplayGroup record
# that covers the entire rows that are used by the display group
# the Display Group + every rows used by its exp boxes
proc Overview_getGroupBoundaries { canvas display_group } {
   global graphX graphStartX graphHourX

   set expList [${display_group} cget -exp_list]
   set boundaries [${canvas} bbox ${display_group}]
   set startx ${graphStartX}
   set endX [expr ${startx} + 24 * ${graphHourX}]

   if { ${expList} != "" } {
      set y1 [lindex ${boundaries} 1]
      set y2 [lindex ${boundaries} 3]

      foreach exp ${expList} {
         # set suiteRecord [::SuiteNode::getSuiteRecordFromPath ${exp}]
         set suiteRecord [::SuiteNode::formatSuiteRecord ${exp}]
         if { [record exists instances ${suiteRecord}] } {
            set expBoundaries [Overview_getExpBoundaries ${canvas} ${suiteRecord}]
            set expy1 [lindex ${expBoundaries} 1]
            set expx2 [lindex ${expBoundaries} 2]
            set expy2 [lindex ${expBoundaries} 3]
            if { ${expy1} != "" && ${y1} > ${expy1} } {
               set y1 ${expy1}
            }
            if { ${expy2} != "" && ${y2} < ${expy2} } {
               set y2 ${expy2}
            }
         }
      }
      set boundaries [list ${startx} $y1 ${endX} $y2]
   }

   return ${boundaries}
}

# this function sets the exp box mouse over tooltip information.
# it is updated everytime the exp node root status changes
proc Overview_setExpTooltip { canvas suite_record datestamp } {
   ::log::log debug "Overview_setExpTooltip suite_record:${suite_record} datestamp:${datestamp}"
   set expPath [${suite_record} cget -suite_path]
   set expName [file tail ${expPath}]
   set startTime [::SuiteNode::getStartTime ${suite_record} ${datestamp}]
   set endTime [::SuiteNode::getEndTime ${suite_record} ${datestamp}]
   set refStartTime [Overview_getRefTimings ${expPath} [Utils_getHourFromDatestamp ${datestamp}] start]
   set refEndTime [Overview_getRefTimings ${expPath} [Utils_getHourFromDatestamp ${datestamp}]  end]
   set currentStatus [::SuiteNode::getLastStatus ${suite_record} ${datestamp}]
   set currentStatusTime [::SuiteNode::getLastStatusTime ${suite_record} ${datestamp}]
   # set currentDatestamp [::SuiteNode::getLastStatusDatestamp ${suite_record}]
   set tooltipText "name: ${expName}"
   if { ${refStartTime} != "" } {
      set tooltipText "name: ${expName}-[Utils_getHourFromDatestamp ${datestamp}]"
   }

   if { ${datestamp} != "" && ! [string match "default*" ${datestamp}] } {
      append tooltipText "\ndatestamp: [Utils_getVisibleDatestampValue ${datestamp}]"
   }
   if { ${refStartTime} != "" } {
      append tooltipText "\nref.begin: ${refStartTime}"
      append tooltipText "\nref.end: ${refEndTime}"
   }

   switch ${currentStatus} {
      "init" {
         append tooltipText "\n${currentStatus}: ${currentStatusTime}"
      }
      "abort" {
         append tooltipText "\nbegin: ${startTime}"
         append tooltipText "\n${currentStatus}: ${currentStatusTime}"
      }
      "end" {
         append tooltipText "\nbegin: ${startTime}"
         append tooltipText "\n${currentStatus}: ${currentStatusTime}"
      }
      default {
         append tooltipText "\n${currentStatus}: ${currentStatusTime}"
      }
   }

   # set exptag ${expPath}.${datestamp}
   set expBoxTag [Overview_getExpBoxTag ${expPath} ${datestamp} ${currentStatus}]

   ::tooltip::tooltip $canvas -item ${expBoxTag} ${tooltipText}
}

# this function is used to shuffle group display up or down depending
# on exp boxes overlapping or not
# input: source_group
#        any record that is found after the source_group will also be moved. T
#        herefore, it assumes that the
#        display groups are presented in the list given by the DisplayGroup records
proc Overview_moveGroups { source_group delta_x delta_y } {
   set displayGroups [ExpXmlReader_getGroups]
   set foundIndex [lsearch $displayGroups ${source_group}]
   if { ${foundIndex} != -1 } {
      # get the list of groups to move
      #set groupsToMove [lrange ${displayGroups} [expr ${foundIndex} + 1] end]
      set groupsToMove [lrange ${displayGroups} ${foundIndex} end]
      set overviewCanvas [Overview_getCanvas]
      foreach displayGroup ${groupsToMove} {
         # set the new min and max if group exists
         if { [${overviewCanvas} gettags ${displayGroup}] != "" } {
            set newMin [expr [${displayGroup} cget -y] + ${delta_y}]
            set newMax [expr [${displayGroup} cget -maxy] + ${delta_y}]
            ${displayGroup} configure -y ${newMin}
            ${displayGroup} configure -maxy ${newMax}

            # move the group and exp boxes that belongs to it
            ::log::log debug "Overview_moveGroups ${overviewCanvas} moving ${displayGroup} delta_y:${delta_y}"
            ${overviewCanvas} move ${displayGroup} ${delta_x} ${delta_y}
         }
      }
   }
}

# returns the y position that a group should be displayed based on the
# group already displayed prior to itself. This function should be useful
# at startup when we add the display groups one by one
proc Overview_getGroupDisplayY { group_display } {
   global entryStartY expEntryHeight
   set displayGroups [ExpXmlReader_getGroups]
   set myIndex [lsearch ${displayGroups} ${group_display}]
   if { ${myIndex} == -1 || ${myIndex} == 0 } {
      # not found or first group, return the start y
      return ${entryStartY}
   }

   # get the previous group from the list
   set prevGroup [lindex ${displayGroups} [expr ${myIndex} - 1]]
   set prevGroupBoundaries  [Overview_getGroupBoundaries [Overview_getCanvas] ${prevGroup}]

   set prevGroupY [lindex ${prevGroupBoundaries} 3]
   #set thisGroupY [Overview_GroupNextY ${prevGroupY}]
   set thisGroupY [DisplayGrp_getNextSlotY ${prevGroup} ${prevGroupY}]
   ::log::log debug "Overview_getGroupDisplayY value: ${thisGroupY}"
   return ${thisGroupY}
}

proc Overview_addGroup { canvas displayGroup } {
   global graphX graphy graphStartX graphStartY graphHourX expEntryHeight entryStartX entryStartY
   #puts "Overview_addGroup displayGroup:${displayGroup}"
   set groupName [$displayGroup cget -name]
   set displayName [file tail $groupName]
   set tagName ${displayGroup}
   set groupLevel [$displayGroup cget -level]
   set groupEntryCurrentY [Overview_getGroupDisplayY ${displayGroup}]

   #puts "Overview_addGroups groupLevel:$groupLevel  groupEntryCurrentY:$groupEntryCurrentY"

   # add indentation for each different level
   set expEntryCurrentX [expr $entryStartX + 4 + $groupLevel * 15]

   #puts "Overview_addGroups displayGroup:$displayGroup groupName:$groupName groupEntryCurrentY:$groupEntryCurrentY"
   set groupId [$canvas create text $expEntryCurrentX [expr $groupEntryCurrentY + $expEntryHeight/2]  \
      -text $displayName -justify left -anchor w -fill grey20 -tag "${tagName} displayGroup_${tagName}"]

   # get the font for each level
   set newFont [Overview_getLevelFont $canvas displayGroup_${tagName} $groupLevel]

   $canvas itemconfigure displayGroup_${tagName} -font $newFont
   ::tooltip::tooltip $canvas -item "${groupId}" "more info here for $displayName"

   $displayGroup configure -x [expr $graphStartX + 20]
   DisplayGrp_setSlotY ${displayGroup} ${groupEntryCurrentY}

   set xoriginDateTime [Overview_GraphGetXOriginDateTime]
   # get the exps for each group if exists
   set expList [$displayGroup cget -exp_list]
   foreach exp $expList {
      Overview_addExpDefaultBoxes ${canvas} ${exp}
      set suiteRecord [::SuiteNode::formatSuiteRecord ${exp}]
      set datestamps [::SuiteNode::getDatestamps ${suiteRecord}]
      foreach datestamp ${datestamps} {
         set currentStatus [::SuiteNode::getLastStatus ${suiteRecord} ${datestamp}]
         set statusTime [::SuiteNode::getLastStatusTime ${suiteRecord} ${datestamp}]
         set statusDateTime [::SuiteNode::getStatusClockValue ${suiteRecord} ${datestamp} ${currentStatus}]
         Overview_updateExpBox ${canvas} ${suiteRecord} ${datestamp} ${currentStatus} ${statusTime}
      }
   }

   foreach grp [${displayGroup} cget -grp_list] {
      Overview_addGroup $canvas ${grp}
   }
}

# this function creates the group labels at the left of the graph
# the values of the labels are read from a suites/exp list
proc Overview_addGroups { canvas } {
   global graphX graphy graphStartX graphStartY graphHourX expEntryHeight entryStartX entryStartY
   global STARTUP_PROGRESS_VALUE STARTUP_PROGRESS_TXT
   set displayGroups [ExpXmlReader_getGroups]

   set groupEntryCurrentY $entryStartY
   set expEntryCurrentX $entryStartX
   ::log::log debug "Overview_addGroups groupEntryCurrentY:$groupEntryCurrentY"

   set expNumber 0
   foreach displayGroup $displayGroups {
      set expList [$displayGroup cget -exp_list]
      foreach exp $expList {
         incr expNumber
      }
   }
   # startup progress bar
   set STARTUP_PROGRESS_VALUE 0
   set progressBar [ProgressDlg .overview_progress \
    -title "Xflow_overview - Loading Experiments Data" -maximum ${expNumber} \
    -variable STARTUP_PROGRESS_VALUE -textvariable STARTUP_PROGRESS_TXT]
   wm geometry .overview_progress =600x200

   ${progressBar} configure -foreground blue

   #set currentTime [clock format [clock seconds]]
   set currentTime [clock seconds]

   foreach displayGroup $displayGroups {
      set expList [$displayGroup cget -exp_list]
      foreach exp $expList {
         Overview_addExp $displayGroup $canvas $exp
         SharedData_setSuiteData ${exp} LAST_CHECKED_TIME ${currentTime}
      }
   }

   # wait for all child to be done with their init
   Overview_waitChildInitDone


   # get the root groups and display from there
   set rootGroups [DisplayGrp_getGroupLevel 0]
   foreach rootGroup ${rootGroups} {
      Overview_addGroup ${canvas} ${rootGroup}
   }
   # check if we need to resize the grid based on exp data
   Overview_checkGridLimit

   destroy ${progressBar}
}

# this function is a place holder to add logic to
# display different font for each level
proc Overview_getLevelFont { canvas item_tag level } {
   #puts "Overview_getLevelFont item_tag:$item_tag"
   set searchFont canvas_level_${level}_font
   if { [lsearch [font names] $searchFont] == -1 } {
      set canvasFont [$canvas itemcget "${item_tag}" -font]
      set newFont [font create canvas_level_${level}_font]
      font configure $newFont -family [font actual $canvasFont -family] \
         -size [font actual $canvasFont -size] \
         -weight [font actual $canvasFont -weight] \
         -slant  [font actual $canvasFont -slant ]

      if { $level == 0 } {
         font configure $newFont  -weight bold
      }
   }

   return $searchFont
}

proc Overview_getBoxLabelFont {} {
   set labelFont canvas_exp_box_label_font
   if { [lsearch [font names] ${labelFont}] == -1 } {
      set newFont [font create ${labelFont}]
      set canvasW [Overview_getCanvas]
      font configure ${newFont} -family [font actual ${canvasW} -family] \
         -size [font actual ${canvasW} -size] \
         -weight [font actual ${canvasW} -weight] \
         -slant  [font actual ${canvasW} -slant ]

      font configure ${newFont} -weight bold -size 10
   }

   return ${labelFont}
}

# this function creates the time grid in the
# specified canvas.
proc Overview_createGraph { canvas } {
   global graphX graphy graphStartX graphStartY graphHourX expEntryHeight entryStartX 

   # adds horiz shaded grid
   set x1 $entryStartX
   set x2  [expr $graphStartX + $graphX]
   set y1 $graphStartY
   set fillColor grey90
   set count 0
   while { ${y1} < [expr $graphy + $graphStartY] } {
      # use a different color for each rectangle
      $canvas create rectangle $x1 [expr $y1 ] $x2 [expr $y1 + $expEntryHeight ] -fill $fillColor -outline $fillColor -tag "grid_item"
      set y1 [expr $y1 + $expEntryHeight]
      if { $fillColor == "grey90" } {
         set fillColor grey95
      } else {
         set fillColor grey90
      }
      incr count
   }

   # creates hor lines at bottom & top
   $canvas create line $graphStartX $graphStartY [expr $graphStartX + $graphX] $graphStartY -arrow last -tag "grid_item grid_min_y"
   $canvas create line $graphStartX [expr $graphStartY + $graphy] \
      [expr $graphStartX + $graphX] [expr $graphStartY + $graphy] -arrow last -tags "grid_item grid_footer grid_max_y"

   # x axis title
   $canvas create text [expr ${x2}/2 ] [expr $graphStartY + $graphy + 60] -text "Time (UTC)" -tag "grid_item grid_footer"
   
   # y axe origin
   $canvas create line $graphStartX [expr $graphStartY - 20] $graphStartX [expr $graphStartY + $graphy] -arrow first -tag "grid_item"
   
   # the grid starts at current_hour - 12 and ends at current_hour + 12
   set currentHour [Utils_getNonPaddedValue [clock format [clock seconds] -format "%H" -gmt 1]]
   if { ${currentHour} < 12 } {
      set hourTag [expr 12 + ${currentHour}] 
   } else {
      set hourTag [expr ${currentHour} % 12]
   }
   set count 1
   # adds hour delimiter & ver grid along hour
   while { $count < 25 } {
      Overview_GraphAddHourLine ${canvas} ${count} ${hourTag}
      incr count
      incr hourTag
      if { ${hourTag} == "25" } {
         set hourTag 1
      }
   }
}

# returns the date as an int value of the date and time
# of the time hour displayed at x=0
proc Overview_GraphGetXOriginDateTime {} {
   set origDateTime [clock add [clock seconds] -13 hours]
   set origDateTimeFormat [clock format ${origDateTime} -format {%Y-%m-%d %H}]
   set origDateTimeFormat ${origDateTimeFormat}:00:00
   set value [clock scan ${origDateTimeFormat}]
   return ${value}
}


# returns the hour that sits that
# the x origin
proc Overview_GraphGetXOriginHour {} {
   set originClockTime [clock add [clock seconds] -13 hours]
   set originHour [Utils_getNonPaddedValue [clock format ${originClockTime} -format "%H" -gmt 1]]

   set value "[Utils_getPaddedValue ${originHour}]"
   return ${value}
}

# this function returns the time value as hh:mm for the hour grid at the far-left
# of the time grid
proc Overview_GraphGetXOriginTime {} {
   set originClockTime [Overview_GraphGetXOriginDateTime]
   set originHour [clock format ${originClockTime} -format "%H" -gmt 1]
   set value "[Utils_getPaddedValue ${originHour}]:00"

   return ${value}
}

# this function is called to delete an hour grid at the specified hour value.
proc Overview_GraphDeleteHourLine {canvas hour} {
   # set hour [Utils_getPaddedValue ${hour}]
   set toDeleteTag [Overview_getGridTagHour ${hour}]
   ::log::log debug "Overview_GraphDeleteHourLine deleting tag hour: ${toDeleteTag}"
   ${canvas} delete ${toDeleteTag}
   ::log::log debug "Overview_GraphDeleteHourLine coords ${toDeleteTag}: [$canvas coords ${toDeleteTag}]"
}

# returns the tag that is used to reference each hour in the
# grid
proc Overview_getGridTagHour { hour } {

   if { ${hour} >= "24" } {
      set hour [expr ${hour} % 24]
   }
   set hour [Utils_getPaddedValue ${hour}]
   set hourTag grid_vertical_hour_${hour}

   return ${hourTag}
}

# this function is called to add an hour grid at the specified hour value.
proc Overview_GraphAddHourLine {canvas grid_count hour} {
   global graphX graphy graphStartX graphStartY graphHourX expEntryHeight entryStartX
   set hour [Utils_getPaddedValue ${hour}]
   ::log::log debug "Overview_GraphAddHourLine add tag hour: grid_hour grid_vertical_hour_${hour}"

   if { ${hour} == 24 } {
      set xLabel "00Z"
   } {
      set xLabel "${hour}Z"
   }

   set tagHour [Overview_getGridTagHour ${hour}]
   ::log::log debug "Overview_GraphAddHourLine tag hour: grid_hour tagHour:${tagHour}"


   set x1 [expr ${graphStartX} + ${grid_count} * ${graphHourX}]
   set x2 $x1
   set y1 [expr ${graphStartY} - 4]
   set y2 [expr ${graphStartY} + 4]
   $canvas create line $x1 $y1 $x2 $y2 -tag "grid_item grid_hour ${tagHour}"
   $canvas create line $x1 [expr $y1 + $graphy] $x2 [expr $y2 + $graphy ] -tag "grid_item grid_hour ${tagHour}"
   $canvas create line $x1 [expr $y1 + 5] $x2 [expr $y2 + $graphy - 5 ] -dash 2 -fill grey60 -tag  "grid_item grid_hour ${tagHour}"

   $canvas create text $x2 [expr $y1 - 20 ] -text $xLabel -tag "grid_item grid_hour ${tagHour}"
   $canvas create text $x2 [expr $y2 + $graphy +20 ] -text $xLabel -tag "grid_item grid_hour ${tagHour} grid_footer"

}

proc Overview_init {} {
   global env AUTO_LAUNCH FLOW_SCALE NODE_DISPLAY_PREF
   global graphX graphy graphStartX graphStartY graphHourX expEntryHeight entryStartX entryStartY
   global expBoxLength startEndIconSize expBoxOutlineWidth

   set AUTO_LAUNCH [SharedData_getMiscData AUTO_LAUNCH]
   set NODE_DISPLAY_PREF [SharedData_getMiscData NODE_DISPLAY_PREF]
   set FLOW_SCALE [SharedData_getMiscData FLOW_SCALE]
   SharedData_setMiscData IMAGE_DIR $env(SEQ_XFLOW_BIN)/../etc/images

   Utils_logInit
   ::log::log notice "xflow_overview Application startup user=$env(USER) real user:[SharedData_getMiscData REAL_USER] host:[exec hostname]"

   # hor size of graph
   set graphX 1225
   # vert size of graph
   #set graphy 600
   set graphy 400
   set graphStartX 200
   set graphStartY 50
   # x size of each hour
   set graphHourX 48
   # y size of each entry on the left side of y axis
   set expEntryHeight 20

   set expBoxLength 40
   
   # creates suite entries
   set entryStartY 70
   set entryStartX 20

   #set startEndIconSize 8
   set startEndIconSize 10

   set expBoxOutlineWidth 1.5

   keynav::enableMnemonics .

}

# this function reads an xml configuration file that
# lists the exp to be monitored
proc Overview_readExperiments {} {
   global env
   set suitesFile [SharedData_getMiscData SUITES_FILE]
   set suiteList {}
   if { [file exists $suitesFile] } {
      puts "Overview_readExperiments from file: $suitesFile"
      ExpXmlReader_readExperiments $suitesFile
      set suiteList [ExpXmlReader_getExpList]
      puts "suiteList: $suiteList"
   } else {
      puts "ERROR: file not found ${suitesFile}"
      Utils_fatalError . "Overview Startup Error" "${suitesFile} does not exists! Exiting..."
   }
}

proc Overview_quit {} {
   global TimeAfterId MSG_CENTER_THREAD_ID
   ::log::log debug "Overview_quit"
   if { [info exists TimeAfterId] } {
      after cancel $TimeAfterId
   }

   thread::send ${MSG_CENTER_THREAD_ID} "MsgCenterThread_quit"

   # destroy $top
   exit 0
}

proc Overview_parseCmdOptions {} {
   global argv env 
   global AUTO_MSG_DISPLAY

   if { [info exists argv] } {
      set options {
         {main ""}
         {debug "Turn debug on"}
         {logfile.arg "" "App log file"}
         {noautomsg "No automatic message display"}
         {suites.arg "" "suites definition file"}
         {user.arg "" "real user (before switching -as)"}
         {rc.arg "" "maestrorc preferrence file"}
      }
   
      set usage "\[options] \noptions:"
      if [ catch { array set params [::cmdline::getoptions argv $options $usage] } message ] {
         puts "\n$message"
         exit 1
      }

      if { $params(main) } {
         wm withdraw .
         SharedData_setMiscData OVERVIEW_THREAD_ID [thread::id]
         SharedData_init
         SharedData_setMiscData OVERVIEW_MODE true

         if { $params(logfile) != "" } {
            puts "Overview_parseCmdOptions writing to log file: $params(logfile)"
            SharedData_setMiscData APP_LOG_FILE $params(logfile)
         } 

         SharedData_setMiscData REAL_USER $env(USER)
         if { $params(user) != "" } {
            puts "Overview_parseCmdOptions real user is $params(user)"
            SharedData_setMiscData REAL_USER $params(user)
         } 

         if { $params(noautomsg) } {
            SharedData_setMiscData AUTO_MSG_DISPLAY false
         } 

         if { $params(debug) } {
            puts "Overview_parseCmdOptions DEBUG_TRACE 1"
            SharedData_setMiscData DEBUG_TRACE 1
         } 

         # ::log::log debug "Overview_parseCmdOptions AUTO_MSG_DISPLAY: ${AUTO_MSG_DISPLAY}"
         # ::log::log debug "Overview_parseCmdOptions SUITES_FILE: [SharedData_getMiscData SUITES_FILE]"
         if { ! ($params(rc) == "") } {
            puts "Overview_parseCmdOptions using maestrorc file: $params(rc)"
         }

         SharedData_readProperties $params(rc)

         if { ! ($params(suites) == "") } {
            # command line arguments overwrites maestrorc file
            SharedData_setMiscData SUITES_FILE $params(suites)
         } elseif { [SharedData_getMiscData SUITES_FILE] == "" } {
            # if not defined in maestrorc, used a default one
            SharedData_setMiscData SUITES_FILE $env(HOME)/xflow.suites.xml
         }

         Overview_main
      }

   }
}

proc Overview_addFileMenu { parent } {
   set menuButtonW ${parent}.file_menub
   set menuW $menuButtonW.menu

   menubutton $menuButtonW -text File -underline 0 -menu $menuW
   menu $menuW -tearoff 0 -type normal

   $menuW add command -label "Quit" -underline 0 -command [list Overview_quit]

   pack $menuButtonW -side left -padx 2
}

proc Overview_toFront {} {
   set topW [Overview_getToplevel]
   switch [wm state ${topW}] {
      withdrawn -
      "iconic" {
         wm deiconify ${topW}
      }
   }
   raise ${topW}
}

proc Overview_addPrefMenu { parent } {
   global AUTO_MSG_DISPLAY AUTO_LAUNCH FLOW_SCALE NODE_DISPLAY_PREF
   set menuButtonW ${parent}.pref_menub
   set menuW $menuButtonW.menu
   menubutton $menuButtonW -text Preferences -underline 0 -menu $menuW
   menu $menuW -tearoff 0

   $menuW add checkbutton -label "Auto Launch" -variable AUTO_LAUNCH \
      -onvalue true -offvalue false

   set AUTO_MSG_DISPLAY [SharedData_getMiscData AUTO_MSG_DISPLAY]
   $menuW add checkbutton -label "Auto Message Display" -variable AUTO_MSG_DISPLAY \
      -command [list Overview_setAutoMsgDisplay] \
      -onvalue true -offvalue false
   ::tooltip::tooltip $menuW -index 1 "Automatic launch of flow when experiment starts."
   ::tooltip::tooltip $menuW -index 2 "Automatic message window on new alarm."

   # Node Display submenu
   set displayMenu $menuW.displayMenu
   $menuW add cascade -label "Node Display" -underline 5 -menu ${displayMenu}
   menu ${displayMenu} -tearoff 0
   foreach item "normal catchup cpu machine_queue memory mpi wallclock" {
      set value ${item}
      ${displayMenu} add radiobutton -label ${item} -variable NODE_DISPLAY_PREF -value ${value} \
         -command [list Overview_nodeDisplayCallback]
   }

   # Flow Scale submenu
   set scaleMenu $menuW.scaleMenu
   $menuW add cascade -label "Flow Scale" -underline 5 -menu ${scaleMenu}
   menu ${scaleMenu} -tearoff 0
   ${scaleMenu} add radiobutton -label "scale-normal" -variable FLOW_SCALE -value 1 \
      -command [list Overview_flowScaleCallback]
   ${scaleMenu} add radiobutton -label "scale-2" -variable FLOW_SCALE -value 2 \
      -command [list Overview_flowScaleCallback]

   pack $menuButtonW -side left -padx 2
}

proc Overview_addHelpMenu { parent } {
   set menuButtonW ${parent}.help_menub
   set menuW $menuButtonW.menu

   menubutton $menuButtonW -text Help -underline 0 -menu $menuW
   menu $menuW -tearoff 0

   $menuW add command -label "About" -underline 0 -command "About_show ${parent}"

   pack $menuButtonW -side left -padx 2
}

proc Overview_createMenu { _toplevelW } {
   set topFrame ${_toplevelW}.topframe
   frame ${topFrame} -relief [SharedData_getMiscData MENU_RELIEF]
   grid ${topFrame} -row 0 -column 0 -sticky nsew -padx 2
   Overview_addFileMenu ${topFrame}
   Overview_addPrefMenu ${topFrame}
   Overview_addHelpMenu ${topFrame}
}

# set the global configuration whether or not the msg center
# should be automatically displayed on new messages
proc Overview_setAutoMsgDisplay {} {
   global AUTO_MSG_DISPLAY
   ::log::log notice "Overview change AUTO_MSG_DISPLAY new value: ${AUTO_MSG_DISPLAY}"
   SharedData_setMiscData AUTO_MSG_DISPLAY ${AUTO_MSG_DISPLAY}
}

# this function is mainly called by the msg center thread
# to notify the overview main thread of a new message.
# The overview highlights the msg center icon in the toolbar
proc Overview_newMessageCallback { has_new_msg } {
   ::log::log debug "Overview_newMessageCallback has_new_msg:$has_new_msg"
   set msgCenterWidget .overview_top.toolbar.button_msgcenter
   set noNewMsgImage .overview_top.toolbar.msg_center_img
   set hasNewMsgImage .overview_top.toolbar.msg_center_new_img
   set normalBgColor [option get ${msgCenterWidget} background Button]
   set newMsgBgColor  [SharedData_getColor COLOR_MSG_CENTER_MAIN]
   if { [winfo exists ${msgCenterWidget}] } {
      set currentImage [${msgCenterWidget} cget -image]
      if { ${has_new_msg} == "true" && ${currentImage} != ${hasNewMsgImage} } {
         ${msgCenterWidget} configure -image ${hasNewMsgImage} -bg ${newMsgBgColor}
      } elseif { ${has_new_msg} == "false" && ${currentImage} != ${noNewMsgImage} } {
         ${msgCenterWidget} configure -image ${noNewMsgImage} -bg ${normalBgColor}
      }
   }
}

proc Overview_nodeDisplayCallback {} {
   global NODE_DISPLAY_PREF
   SharedData_setMiscData NODE_DISPLAY_PREF ${NODE_DISPLAY_PREF}
}

proc Overview_flowScaleCallback {} {
   global FLOW_SCALE
   SharedData_setMiscData FLOW_SCALE ${FLOW_SCALE}
}

proc Overview_createToolbar { _toplevelW } {
   global MSG_CENTER_THREAD_ID
   set toolbarW ${_toplevelW}.toolbar
   set mesgCenterW ${toolbarW}.button_msgcenter
   set closeW ${toolbarW}.button_close
   set colorLegendW ${toolbarW}.button_colorlegend
   frame ${toolbarW} -bd 1

   set imageDir [SharedData_getMiscData IMAGE_DIR]

   image create photo ${toolbarW}.msg_center_img -file ${imageDir}/open_mail_sh.gif
   image create photo ${toolbarW}.msg_center_new_img -file ${imageDir}/open_mail_new.gif
   image create photo ${toolbarW}.color_legend_img -file ${imageDir}/color_legend.gif

   button ${mesgCenterW} -image ${toolbarW}.msg_center_img -command {
      thread::send -async ${MSG_CENTER_THREAD_ID} "MsgCenterThread_showWindow"
   } -relief flat

   ::tooltip::tooltip ${mesgCenterW} "Show Message Center."

   image create photo ${toolbarW}.close -file ${imageDir}/cancel.gif
   button ${closeW} -image ${toolbarW}.close -command [list Overview_quit] -relief flat
   ::tooltip::tooltip ${closeW} "Close Application."

   button ${colorLegendW} -image ${toolbarW}.color_legend_img -command [list xflow_showColorLegend ${colorLegendW}] -relief flat
   tooltip::tooltip ${colorLegendW} "Show color legend."

   if { [SharedData_getMiscData OVERVIEW_SHOW_AIX_ICON] == true } { 
      # show aix icon
      image create photo ${toolbarW}.back_end_img -file ${imageDir}/backend.png
      set backEndW [button ${toolbarW}.button_be -image ${toolbarW}.back_end_img -relief flat \
                     -command [list Utils_getBackEndHost [Overview_getToplevel] ] ]
      grid ${mesgCenterW} ${colorLegendW} ${backEndW} ${closeW} -sticky w -padx 2 
   } else {
      grid ${mesgCenterW} ${colorLegendW} ${closeW} -sticky w -padx 2 
   }

   grid ${toolbarW} -row 1 -column 0 -sticky nsew -padx 2
}

proc Overview_createCanvas { _toplevelW } {
   set canvasFrame [frame ${_toplevelW}.canvas_frame]
   set canvasW ${canvasFrame}.canvas

   frame ${canvasFrame}.xframe

   scrollbar ${canvasFrame}.yscroll -command [list ${canvasW} yview ]
   scrollbar ${canvasFrame}.xscroll -orient horizontal -command [list ${canvasW} xview]
   set pad 12
   frame ${canvasFrame}.pad -width $pad -height $pad

   grid ${canvasFrame}.xframe -row 2 -column 0 -columnspan 2 -sticky ewns
   grid ${canvasFrame}.yscroll -row 0 -column 1 -sticky ns

   grid ${canvasFrame}.pad -row 0 -column 1 -in ${canvasFrame}.xframe -sticky es
   grid ${canvasFrame}.xscroll -row 0 -column 0 -sticky ew -in ${canvasFrame}.xframe

   grid columnconfigure ${canvasFrame}.xframe 0 -weight 1
   grid rowconfigure ${canvasFrame}.xframe 1 -weight 1

   # only show the scrollbars if required
   ::autoscroll::autoscroll ${canvasFrame}.yscroll
   ::autoscroll::autoscroll ${canvasFrame}.xscroll

   canvas ${canvasFrame}.canvas -relief raised -bd 2 -bg [SharedData_getColor CANVAS_COLOR] \
      -yscrollcommand [list ${canvasFrame}.yscroll set] -xscrollcommand [list ${canvasFrame}.xscroll set]

   Utils_bindMouseWheel ${canvasW} 5

   grid ${canvasW} -row 0 -column 0 -sticky nsew

   # make the canvas expandable to right & bottom
   grid columnconfigure ${canvasFrame} 0 -weight 1
   grid rowconfigure ${canvasFrame} 0 -weight 1

   grid ${canvasFrame} -row 2 -column 0 -sticky nsew

}

proc Overview_addCanvasImage { canvas } {

   set boxCoords [${canvas} bbox all]
   set imageBg ${canvas}.bg_image
   set tiledImage [image create photo]
   if { [SharedData_getMiscData BACKGROUND_IMAGE] != "" } {
      set imageFile [SharedData_getMiscData BACKGROUND_IMAGE]
   } else {
      set imageDir [SharedData_getMiscData IMAGE_DIR]
      set imageFile [SharedData_getMiscData IMAGE_DIR]/artist-canvas_2.gif
   }

   ${canvas} delete canvas_bg_image
   image create photo ${imageBg} -file ${imageFile}
   #${canvas} create image 0 0 -anchor nw -image ${imageBg} -tags canvas_bg_image
   ${canvas} create image 0 0 -anchor nw -image ${tiledImage} -tags canvas_bg_image
   
    bind $canvas <Configure> [list Overview_tileBgImage ${canvas} ${imageBg} ${tiledImage}]
    Overview_tileBgImage $canvas ${imageBg} ${tiledImage}
   ${canvas} lower canvas_bg_image
}

 proc Overview_tileBgImage { canvas sourceImage tiledImage } {
    set canvasBox [${canvas} bbox all]
    set canvasItemsW [lindex ${canvasBox} 2]
    set canvasItemsH [lindex ${canvasBox} 3]
    set canvasW [winfo width ${canvas}]
    set canvasH [winfo height ${canvas}]
    set usedW ${canvasItemsW}
    if { ${canvasW} > ${canvasItemsW} } {
      set usedW ${canvasW}
    }
    set usedH ${canvasItemsH}
    if { ${canvasH} > ${canvasItemsH} } {
      set usedH ${canvasH}
    }

    $tiledImage copy $sourceImage \
        -to 0 0 [expr ${usedW} + 20] [expr ${usedH} + 20]
 }

proc Overview_setTitle { top_w time_value } {
   global env
   set winTitle "Xflow Overview - User=$env(USER) Host=[exec hostname] Time=${time_value}"
   wm title [winfo toplevel ${top_w}] ${winTitle}
}

proc Overview_getCanvas {} {
   return .overview_top.canvas_frame.canvas
}

proc Overview_getToplevel {} {
   return .overview_top
}

proc Overview_setMainCoords { _topOverview } {
   SharedData_setMiscData OVERVIEW_MAIN_COORDS "[winfo x ${_topOverview}] [winfo y ${_topOverview}]"
}

proc Overview_main {} {
   global MSG_CENTER_THREAD_ID
   global DEBUG_TRACE THREAD_FULL_EVENT
   global TEST_VAR
   set TEST_VAR true
   Overview_setTkOptions

   set DEBUG_TRACE [SharedData_getMiscData DEBUG_TRACE]
   ::DrawUtils::init
   Overview_init
   set MSG_CENTER_THREAD_ID [MsgCenter_getThread]
   set topOverview [Overview_getToplevel]
   set topCanvas [Overview_getCanvas]
   toplevel ${topOverview}
   # keep track of coords
   bind ${topOverview} <Configure> [list Overview_setMainCoords ${topOverview}]
   wm withdraw ${topOverview}

   Overview_readExperiments

   Overview_createMenu ${topOverview}
   Overview_createToolbar ${topOverview}
   Overview_createCanvas ${topOverview}
   #canvas ${topCanvas} -relief raised -bd 2 -bg [SharedData_getColor CANVAS_COLOR]

   # grid ${topCanvas} -row 2 -column 0 -sticky nsew -padx 2
   grid columnconfigure ${topOverview} 0 -weight 1
   grid rowconfigure ${topOverview} 1 -weight 0
   grid rowconfigure ${topOverview} 2 -weight 1

   set sizeGripWidget [ttk::sizegrip ${topOverview}.sizeGrip]
   grid ${sizeGripWidget} -sticky se

   Overview_createGraph ${topCanvas}


   wm protocol ${topOverview} WM_DELETE_WINDOW [list Overview_quit ]

   # create pool of threads to parse and launch exp flows
   ThreadPool_init [SharedData_getMiscData MAX_XFLOW_INSTANCE]
   Overview_addGroups ${topCanvas}
   Overview_setCanvasScrollArea ${topCanvas}
   Overview_setCurrentTime ${topCanvas}
   Overview_addCanvasImage ${topCanvas}
   Overview_GridAdvanceHour

   SharedData_setMiscData STARTUP_DONE true
   thread::send -async ${MSG_CENTER_THREAD_ID} "MsgCenterThread_startupDone"

   # warn users when maximum window reached
   trace add variable THREAD_FULL_EVENT write Overview_ThreadFullEvent

   wm geometry ${topOverview} =1500x600
   wm deiconify ${topOverview}

   # run a periodic monitor to look for new log files to process
   LogMonitor_checkNewLogFiles
}

Overview_parseCmdOptions
