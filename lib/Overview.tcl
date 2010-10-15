#!/home/binops/afsi/ssm/sw/linux26-i686/bin/tclsh8.4
package require struct::record
package require tooltip
package require cmdline
package require Thread
namespace import ::tooltip::tooltip
namespace import ::struct::record::record

global env
if { ! [info exists env(SEQ_XFLOW_BIN) ] } {
   puts "Environment variable SEQ_XFLOW_BIN must be defined!"
   exit
}
puts "SEQ_XFLOW_BIN=$env(SEQ_XFLOW_BIN)"

set lib_dir $env(SEQ_XFLOW_BIN)/../lib
puts "lib_dir=$lib_dir"
set auto_path [linsert $auto_path 0 $lib_dir ]

package require SuiteNode

# the first time this function is called
# the current_hour should be empty.
# the function wil calculate the time remaining until 
# the next hour switch and then wake up every hour
proc Overview_GridAdvanceHour { {new_hour ""} } {
   global graphHourX graphX graphStartX graphStartY

   set currentClock [clock seconds]
   DEBUG "Overview_GridAdvanceHour new_hour:${new_hour} [clock format ${currentClock}]" 5
   set advanceGrid true
   if { ${new_hour} == "" } {
      set advanceGrid false
      set new_hour [clock format ${currentClock} -format %H -gmt 1]
      set elapsedMin [Utils_getNonPaddedValue [clock format ${currentClock} -format %M]]
      set elapsedSeconds [Utils_getNonPaddedValue [clock format ${currentClock} -format %S]]
      set elapsedInMilliSec [expr ${elapsedMin} * 60000 + ${elapsedSeconds} * 1000]
      set sleepTime [expr 3600000 - ${elapsedInMilliSec}]
   } else {
      # wake-up in an hour
      set sleepTime 3600000
   }
   if { ${new_hour} == "24" } {
      set nextHour 0
   } else {
      set nextHour [expr ${new_hour} + 1]
   }

   DEBUG "Overview_GridAdvanceHour sleeping for ${sleepTime} msecs before hour ${nextHour}" 5
   after ${sleepTime} [list Overview_GridAdvanceHour ${nextHour}]

   if { ${advanceGrid} == false } {
      return
   }
   DEBUG "Overview_GridAdvanceHour advancing grid hour ${new_hour}" 5

   set canvasW [Overview_getCanvas]

   # refresh current Time 
   set timeHour [Utils_getHourFromTime "${new_hour}:00"]
   set currenTime "${timeHour}:00"
   Overview_setCurrentTime ${canvasW} ${currenTime}

   # delete first hour tag
   set mostLeftHour [expr ${new_hour} % 12]
   if { [expr ${new_hour} < 12] } {
      set mostLeftHour [expr ${mostLeftHour} + 12]
   } elseif { ${new_hour} == "12" } {
      set mostLeftHour 24
   } elseif { ${new_hour} == "24" } {
      set mostLeftHour 12
   }

   DEBUG "Overview_GridAdvanceHour deleting hour ${mostLeftHour}" 5
   Overview_GraphDeleteHourLine ${canvasW} ${mostLeftHour}

   # shift the grid by 1 hour
   set gridTag grid_hour
   ${canvasW} move grid_hour -${graphHourX} 0

   DEBUG "Overview_GridAdvanceHour inserting hour ${mostLeftHour}" 5
   # insert new hour at the other end
   Overview_GraphAddHourLine ${canvasW} 24 ${mostLeftHour}

   # shift all the suite boxes in the canvas
   set displayGroups [record show instances DisplayGroup]
   foreach displayGroup $displayGroups {
      set expList [$displayGroup cget -exp_list]
      foreach exp $expList {
         set suiteRecord [::SuiteNode::getSuiteRecordFromPath ${exp}]
         set deltax ${graphHourX}
         set expAdvanceHour true
         set currentExpCoords [Overview_getExpBoundaries ${canvasW} ${suiteRecord}]
         set adjustMiddleBoxCmd ""
         if { [${canvasW} coords ${exp}] != "" } {
            set currentExpEndBoxCoords [${canvasW} coords ${exp}]
         }
         set currentX [lindex ${currentExpCoords} 0]
         set currentEndX [lindex ${currentExpCoords} 2]
         # not moving exps that that are at x origin and needs to be there
         set lastStatus [::SuiteNode::getLastStatus ${suiteRecord}]
         set lastStatusTime [::SuiteNode::getLastStatusTime ${suiteRecord}]
         if { [expr ${currentX} == ${graphStartX}] } {
            if { [::SuiteNode::isHomeless ${suiteRecord}] } {
               set expAdvanceHour false
               DEBUG "Overview_GridAdvanceHour not advancing homeless ${exp}" 5
            } elseif { ${lastStatus} == "begin" || ${lastStatus} == "abort" || ${lastStatus} == "abort" } {
               # begin state siting at 0 must not be shifted
               set expAdvanceHour false
               DEBUG "Overview_GridAdvanceHour not advancing [::SuiteNode::getLastStatus ${suiteRecord}] ${exp}" 5
               if { [::SuiteNode::getLastStatus ${suiteRecord}] == "end" } {
                  set adjustMiddleBoxCmd "Overview_updateExpBox ${canvasW} ${suiteRecord} ${lastStatus} ${lastStatusTime}"
               }
            } elseif { ${lastStatus} == "init" } {
                  Overview_ExpInitiateBox ${canvas} ${suite_record}
            }
         } elseif { [expr ${currentX} < (${graphStartX} + ${graphHourX})] && 
                     [expr ${currentEndX} > ${graphStartX}] } {
            # anything starting in the first 1 hour box but finishing outside must be moved
            # to 0
            DEBUG "Overview_GridAdvanceHour advancing to 0 ${exp}" 5
            set deltax [expr ${currentX} - ${graphStartX}]
            # also need to readjust middle box ending time
            set adjustMiddleBoxCmd "Overview_updateExpBox ${canvasW} ${suiteRecord} ${lastStatus} ${lastStatusTime}"
         }

         if { ${expAdvanceHour} } {
            ${canvasW} move ${exp} -${deltax} 0
         }
         eval ${adjustMiddleBoxCmd}
         # reupdate with current timeline if needed
         set afterCallback [${suiteRecord} cget -overview_after_id]
         if { ${afterCallback} != "" } {
            catch {
               set afterInfo [after info ${afterCallback}]
               set invokeCallback [lindex ${afterInfo} 0]
               DEBUG "Overview_GridAdvanceHour ${exp} invoking callback ${invokeCallback}" 5
               eval ${invokeCallback}
            }
         }
      }
   }
}

proc Overview_getCanvas {} {
   return .overview_top.canvas
}

# returns the overview timeline x coordinate given a time value
# in the hh:mm format
# note that the return value takes into account the start of the
# x axis that is changing every hour
proc Overview_getXCoordTime { timevalue {shift_day false} } {
   global graphHourX graphStartX

   set currentHour [Utils_getNonPaddedValue [clock format [clock seconds] -format "%H" -gmt 1]]
   set timeHour [Utils_getHourFromTime ${timevalue}]
   set timeMinute [Utils_getMinuteFromTime ${timevalue}]

   set hourGrid [expr ${currentHour} % 12]
   set hourDelta [expr ${hourGrid} * ${graphHourX}]
   set xcoordHour [ expr ${graphStartX} + ${timeHour} * ${graphHourX} - ${hourDelta} ]
   set xcoordMin [ expr ${timeMinute} * ${graphHourX} / 60 ]
   set xcoord [ expr ${xcoordHour} + ${xcoordMin} ]

   # if the current hour is before the x origin hour, I'm adding 24 hours
   # this is only used for init status for now when I need to insert runs that
   # appears at the rightmost of the grid
   if { [expr [clock scan ${timevalue}] < [Overview_GraphGetXOriginDateTime]] && ${shift_day} == "true" } {
      set xcoord [expr ${xcoord} + 24 * ${graphHourX}]
   }
   return $xcoord
}

# refresh the current time line every 30 seconds
proc Overview_setCurrentTime { canvas { current_time "" } } {
   global graphStartX graphStartY graphHourX graphy TimeAfterId
   DEBUG "setCurrentTime canvas:$canvas current_time:${current_time}" 5
   $canvas delete current_timeline

   # setting current time
   if { ${current_time} == "" } {
      set current_time [clock format [clock seconds] -format "%H:%M" -gmt 1]
      set currentSeconds [clock format [clock seconds] -format "%S"]
      # set the first sleep time the closest to the minute update
      set sleepTime [expr (30 - [Utils_getNonPaddedValue ${currentSeconds}] % 30) * 1000]
   } else {
      set sleepTime 30000
   }
   set currentTimeCoordx [Overview_getXCoordTime ${current_time}]
   set x1 ${currentTimeCoordx}
   set x2 ${currentTimeCoordx}
   set y1 [expr $graphStartY - 4]
   set y2 [expr $graphStartY + 4]
   set lineId [$canvas create line $x1 [expr $y1 - 40] $x2 [expr $y2 + $graphy + 40 ] -tag current_timeline -fill DarkGreen]
   ::tooltip::tooltip $canvas -item "${lineId}" "Current Time:${current_time}Z\nUpdated every 30 seconds"

   if { [$canvas gettags current_timetext] == "" } {
      $canvas create text $x1 [expr $y2 + $graphy + 45] -fill DarkGreen -anchor w -justify left -tag current_timetext
   }

   $canvas itemconfigure current_timetext -text "Current Time: ${current_time}Z"

   set TimeAfterId [after ${sleepTime} [list Overview_setCurrentTime $canvas]]
}

proc Overview_addExpBox { group_record canvas suite_record } {
   global graphStartX graphHourX expEntryHeight expBoxLength

   DEBUG "Overview_addExpBox group_record:$group_record canvas:$canvas suite_record:$suite_record "
   set exp_path [$suite_record cget -suite_path]

   #
   # if the exp has a start time, create the start box at the start time location
   set startTime [::SuiteNode::getStartTime ${suite_record}]
   set endTime [::SuiteNode::getEndTime ${suite_record}]
   if { ${startTime} != "" } {
      set startX [Overview_getXCoordTime ${startTime}]
   } else {
      # if not create the box at the reference start time if exists
      set refStartTime [${suite_record} cget -ref_start]
      if { ${refStartTime} != "" } {
         set startX [Overview_getXCoordTime ${refStartTime}]
         set refEndTime [${suite_record} cget -ref_end]
         if { ${refEndTime} != "" } {
            set endTime ${refEndTime}
         }
      } else {
         set startX ${graphStartX}
      }
   }
   set labelX [expr $startX + 8]
   set startX2 [expr $startX + 5]
   set startY [${group_record} cget -y]
   set startY2 [expr $startY + $expEntryHeight/2 + 8]

   # create the left box
   set startBoxId [$canvas create rectangle ${startX} ${startY} ${startX2} ${startY2} \
      -fill bisque4 -outline bisque4 -tag "${exp_path} ${exp_path}.start"]

   # create the middle box
   set middleX1 ${startX2}
   set middleY1 ${startY}
   set middleY2 ${startY2}
   if { ${endTime} != "" } {
      set middleX2 [Overview_getXCoordTime ${endTime}]
   } else {
      set middleX2 [expr ${startX2} + 1]
   }

   DEBUG "Overview_addExpBox group_record:$group_record startX:$startX exp_path:[$suite_record cget -suite_path]"
   set middleBoxId [$canvas create rectangle ${middleX1} ${middleY1} \
      ${middleX2} ${middleY2} -outline bisque4 -fill white -tag "${exp_path} ${exp_path}.middle"]

   # create the exp label
   set tailName [file tail ${exp_path}]
   set expLabel " ${tailName} "
   set expY [${group_record} cget -y]
   set labelY [expr $expY + $expEntryHeight/2]
   set expLabelId [$canvas create text ${labelX} ${labelY} \
      -text ${expLabel} -fill grey20 -anchor w -tag "${exp_path} ${exp_path}.text"]

   # set newx for next item, only used when ref timings not used
   set thisExpBox [$canvas bbox ${exp_path}]
   set nextX [lindex ${thisExpBox} 2]
   ${group_record} configure -x [expr $nextX + 10]
   $canvas bind $middleBoxId <Double-Button-1> [list Overview_launchExpFlow $canvas $exp_path ]
   $canvas bind ${exp_path} <Button-3> [ list Overview_boxMenu $canvas $exp_path %X %Y]
}

proc Overview_isOffTimeGrid { suite_record } {
   set lastStatus [::SuiteNode::getLastStatus ${suite_record} ]
   set startDateTime [::SuiteNode::getStatusClockValue ${suite_record} begin]
   set endDateTime [::SuiteNode::getStatusClockValue ${suite_record} end]
   set abortDateTime [::SuiteNode::getStatusClockValue ${suite_record} abort]
   set xoriginDateTime [Overview_GraphGetXOriginDateTime]
   set offGrid false
   if { ${startDateTime} != "" && ${endDateTime} != "" } {
      # if the suite has a start time & end time that is prior to the first hour displayed in the grid
      # it is off the grid.
      if { [expr ${endDateTime} < ${xoriginDateTime}]} {
         set offGrid true
      }
   } elseif { ${startDateTime} != "" && ${abortDateTime} != "" } {
      # if the suite has a start time & abort time that is prior to the first hour displayed in the grid
      # it is off the grid.
      if { [expr ${abortDateTime} < ${xoriginDateTime}]} {
         set offGrid true
      }
   }

   DEBUG "Overview_isOffTimeGrid suite_record:${suite_record} returned value: $offGrid" 5
   return ${offGrid}
}

proc Overview_ExpInitiateBox { canvas suite_record } {
   set exp_path [$suite_record cget -suite_path]
   set group_record [$suite_record cget -overview_group_record]
   set refStartTime [${suite_record} cget -ref_start]
   set refEndTime [${suite_record} cget -ref_end]
   set refDateTime [clock scan ${refEndTime}]
   set currentDateTime [clock seconds]
   set currentTime [clock format ${currentDateTime} -format "%H:%M" -gmt 1]
   set xoriginDateTime [Overview_GraphGetXOriginDateTime]
   DEBUG "Overview_ExpInitiateBox group_record:$group_record canvas:$canvas suite_record:$suite_record " 5


   set startTime [::SuiteNode::getStartTime ${suite_record}]
   set endTime [::SuiteNode::getEndTime ${suite_record}]
   set startDateTime [::SuiteNode::getLastStatusDateTime ${suite_record}]

   set currentStatus [::SuiteNode::getLastStatus ${suite_record}]
   set statusTime [::SuiteNode::getLastStatusTime ${suite_record}]
   set shiftDay false
   if { ${currentStatus} == "init" || [Overview_isOffTimeGrid ${suite_record}] } {
      if { ${refStartTime} != "" } {
         set relativeStartTime [::SuiteNode::getStartRelativeClockValue ${refStartTime} ${refEndTime}]
         if { [expr ${relativeStartTime} < ${xoriginDateTime}] &&
              [expr [clock scan ${refEndTime}]  > ${xoriginDateTime}]  } {
            # start time is prior to visible hour but end ref time is visible, move it 0
            Overview_ExpCreateStartIcon ${canvas} ${suite_record} [Overview_GraphGetXOriginTime]
         } elseif { [expr ${relativeStartTime} < ${xoriginDateTime}] &&
              [expr ${relativeStartTime} < ${xoriginDateTime}]  } {
            set shiftDay true
            Overview_ExpCreateStartIcon ${canvas} ${suite_record} ${refStartTime} ${shiftDay}
         } else {
            Overview_ExpCreateStartIcon ${canvas} ${suite_record} ${refStartTime}
         }
         Overview_ExpCreateMiddleBox ${canvas} ${suite_record} ${refEndTime} ${shiftDay}
         Overview_ExpCreateEndIcon ${canvas} ${suite_record} ${refEndTime} ${shiftDay}
      } else {
         # put it at beginning of graph whereever it fits
         set currentHour [clock format [clock seconds] -format "%H" -gmt 1]
         set zeroHour [expr [Utils_getNonPaddedValue ${currentHour}] % 12 ]
         set zeroHour "[Utils_getPaddedValue ${zeroHour}]:00"
         Overview_ExpCreateStartIcon ${canvas} ${suite_record} ${zeroHour}  
      }
   } elseif { ${currentStatus} == "begin" } {
      if { [expr [clock scan ${startDateTime}] > ${xoriginDateTime}] } {
         # start time is prior to visible hour, move it 0
         Overview_ExpCreateStartIcon ${canvas} ${suite_record} [Overview_GraphGetXOriginTime]
      } else {
         Overview_ExpCreateStartIcon ${canvas} ${suite_record} ${startTime}
      }
      # add middle box up to current time
      Overview_ExpCreateMiddleBox ${canvas} ${suite_record} ${currentTime}

      # add reference
      if { ${refEndTime} != "" } {
         Overview_ExpCreateReferenceBox ${canvas} ${suite_record} ${currentTime}
         Overview_ExpCreateEndIcon ${canvas} ${suite_record} ${refEndTime}
      }
   } elseif { ${currentStatus} == "end" } {
      if { ${startTime} != "" } {
         if { [expr [clock scan ${startDateTime}] > ${xoriginDateTime}] } {
            # start time is prior to visible hour, move it 0
            Overview_ExpCreateStartIcon ${canvas} ${suite_record} [Overview_GraphGetXOriginTime]
         } else {
            Overview_ExpCreateStartIcon ${canvas} ${suite_record} ${startTime}
         }
         Overview_ExpCreateMiddleBox ${canvas} ${suite_record} ${endTime}
         Overview_ExpCreateEndIcon ${canvas} ${suite_record} ${endTime}
      } else {
         Overview_ExpCreateStartIcon ${canvas} ${suite_record} ${statusTime}
      }
      # add middle box up to end time
      #if { ${refEndTime} != "" } {
      #   Overview_ExpCreateReferenceBox ${canvas} ${suite_record} ${endTime}
      #   Overview_ExpCreateEndIcon ${canvas} ${suite_record} ${refEndTime}
      #}
   } elseif { ${currentStatus} == "abort" } {
      if { ${startTime} != "" } {
         if { [expr [clock scan ${startDateTime}] > ${xoriginDateTime}] } {
            # start time is prior to visible hour, move it 0
            Overview_ExpCreateStartIcon ${canvas} ${suite_record} [Overview_GraphGetXOriginTime]
         } else {
            Overview_ExpCreateStartIcon ${canvas} ${suite_record} ${startTime}
         }
      } else {
         Overview_ExpCreateStartIcon ${canvas} ${suite_record} ${statusTime}
      }
      # add middle box up to abort time
      Overview_ExpCreateMiddleBox ${canvas} ${suite_record} ${currentTime}
      if { ${refEndTime} != "" } {
            if { ${currentDateTime} < ${refDateTime} } {     
               set referenceBoxTime ${timevalue}
               set endBoxTime ${refTime}
               Overview_ExpCreateReferenceBox ${canvas} ${suite_record} ${currentTime}
               Overview_ExpCreateEndIcon ${canvas} ${suite_record} ${refEndTime}
            }
            #Overview_ExpCreateReferenceBox ${canvas} ${suite_record} ${currentTime}
            #Overview_ExpCreateEndIcon ${canvas} ${suite_record} ${refEndTime}
      }
   }
   set newcoords [Overview_getExpBoundaries ${canvas} ${suite_record}]
   set newx1 [lindex ${newcoords} 0]
   set newx2 [lindex ${newcoords} 2]
   set newy1 [lindex ${newcoords} 1]
   set newy2 [lindex ${newcoords} 3]
   # resolve any collision with existings exp boxes
   Overview_resolveLocation ${canvas} ${suite_record} ${newx1} ${newy1} ${newx2} ${newy2}

   Overview_setExpTooltip ${canvas} ${suite_record}
   #set currentCoords [Overview_getExpBoundaries ${canvas} ${suite_record}]
   #Overview_GroupSetY ${group_record} [lindex ${currentCoords} 1]
   #set thisExpBox [$canvas bbox ${exp_path}]
   #set nextX [lindex ${thisExpBox} 2]
   #${group_record} configure -x [expr $nextX + 10]
   $canvas bind ${exp_path} <Button-3> [ list Overview_boxMenu $canvas $exp_path %X %Y]
}

proc Overview_refreshBoxStatus { suite_record {status ""} } {
   set canvas [Overview_getCanvas] 
   if { ${status} == "" } {
      set status [::SuiteNode::getLastStatus ${suite_record}]
   }
   set tagName [$suite_record cget -suite_path]
   set colors [::DrawUtils::getStatusColor $status]
   set bgColor [lindex $colors 1]
   set fgColor [lindex $colors 0]
   if { [winfo exists $canvas] } {

      if { ${status} == "late" } {
         $canvas itemconfigure ${tagName}.middle -fill DarkViolet
         $canvas itemconfigure ${tagName}.text -fill [::DrawUtils::getFgStatusColor end]
      } else {
         $canvas itemconfigure ${tagName}.start -fill $bgColor -outline $bgColor
         $canvas itemconfigure ${tagName}.middle -outline $bgColor
         $canvas itemconfigure ${tagName}.reference -outline $bgColor
         $canvas itemconfigure ${tagName}.end -fill $bgColor -outline $bgColor
      }
      #$canvas itemconfigure ${tagName}.text -fill ${fgColor}

   }
}

proc Overview_ExpCreateStartIcon { canvas suite_record timevalue {shift_day false} } {
   global graphStartX expEntryHeight startEndIconSize
   DEBUG "Overview_ExpCreateStartIcon $suite_record $timevalue shift_day:$shift_day" 5
   set groupRecord [${suite_record} cget -overview_group_record]
   set expPath [${suite_record} cget -suite_path]
   DEBUG "Overview_ExpCreateStartIcon y value [${groupRecord} cget -y]" 5
   set startY [expr [${groupRecord} cget -y] +  $expEntryHeight/2 - (${startEndIconSize}/2)]

   set startX [Overview_getXCoordTime ${timevalue} ${shift_day}]

   set labelX [expr $startX + 10]
   set startX2 [expr $startX + ${startEndIconSize}]
   set startY2 [expr $startY + ${startEndIconSize}]

   ${canvas} delete ${expPath}.start
   ${canvas} delete ${expPath}.middle
   ${canvas} delete ${expPath}.reference
   ${canvas} delete ${expPath}.end
   ${canvas} delete ${expPath}.text
   DEBUG "Overview_ExpCreateStartIcon ${expPath}.start at ${startX} ${startY} ${startX2} ${startY2}" 5
   # create the left box      
   set startBoxId [$canvas create oval ${startX} ${startY} ${startX2} ${startY2} \
      -fill bisque4 -outline bisque4 -tag "${expPath} ${expPath}.start"]

   # create the exp label
   set tailName [file tail ${expPath}]
   set expLabel " ${tailName} "
   set labelY [expr ${startY} + (${startEndIconSize}/2)]
   set expLabelId [$canvas create text ${labelX} ${labelY} \
      -text ${expLabel} -fill grey20 -anchor w -tag "${expPath} ${expPath}.text"]
}

proc Overview_ExpCreateEndIcon { canvas suite_record timevalue {shift_day false} } {
   DEBUG "Overview_ExpCreateEndIcon ${suite_record} ${timevalue} shift_day:$shift_day" 5
   global graphStartX expEntryHeight startEndIconSize
   set groupRecord [${suite_record} cget -overview_group_record]
   set expPath [${suite_record} cget -suite_path]
   set currentCoords [Overview_getExpBoundaries ${canvas} ${suite_record}]
   set startX [Overview_getXCoordTime ${timevalue} ${shift_day}]
   set startY [expr [lindex ${currentCoords} 1] +  $expEntryHeight/2 - (${startEndIconSize}/2)]

   # get the x coord for the given time

   set startX2 [expr $startX + ${startEndIconSize}]
   set startY2 [expr $startY + ${startEndIconSize}]
   
   ${canvas} delete ${expPath}.end
   # create the left box
   set endBoxId [${canvas} create oval ${startX} ${startY} ${startX2} ${startY2} \
      -fill bisque4 -outline bisque4 -tag "${expPath} ${expPath}.end"]
}

proc Overview_ExpCreateReferenceBox { canvas suite_record timevalue {late_reference false} } {
   DEBUG "Overview_ExpCreateReferenceBox ${suite_record} ${timevalue} late_reference:$late_reference" 5
   global graphStartX expEntryHeight startEndIconSize
   set expPath [${suite_record} cget -suite_path]
   set currentCoords [Overview_getExpBoundaries ${canvas} ${suite_record}]
   set startCoords [${canvas} coords ${expPath}.start]
   DEBUG "Overview_ExpCreateReferenceBox ${expPath} startCoords:${startCoords}"
   set referenceTime [${suite_record} cget -ref_end]
   set startTime [::SuiteNode::getStartTime ${suite_record}]
   DEBUG "Overview_ExpCreateReferenceBox referenceTime:$referenceTime"
      set startX [Overview_getXCoordTime ${timevalue}]

   if { [${canvas} coords ${expPath}.middle] == "" } {
      set startX [lindex ${startCoords} 2]
   }
   set endX [Overview_getXCoordTime ${referenceTime}]
      if { [${canvas} coords ${expPath}.middle] == "" &&
           [${canvas} coords ${expPath}.reference] == "" } {
         # create the reference from the start icon up to the end reference time
         set startY [expr [lindex ${currentCoords} 1] - ${expEntryHeight}/2 + ${startEndIconSize}/2 ]
         set endY [expr ${startY} + $expEntryHeight/2 + 8]
      } else {
         set startY [lindex ${currentCoords} 1]
         set endY [expr $startY + $expEntryHeight/2 + 8]
      }

      # create the ref box
      ${canvas} delete ${expPath}.reference
      if { ${late_reference} } {
         if { [expr ${endX} < ${startX}] } {
            # for some reason the whole run has started before the reference end time
            # make the full box late instead of having a reference outside the box
            #${canvas} itemconfigure ${expPath}.middle -fill DarkViolet
            ${canvas} itemconfigure ${expPath}.text -fill DarkViolet
         } else {
            set startX [expr ${endX} - 4]
            set refBoxId [${canvas} create rectangle ${startX} ${startY} ${endX} ${endY} \
               -fill DarkViolet -outline bisque4 -tag "${expPath} ${expPath}.reference"]
         }
      } else {
         set refBoxId [${canvas} create rectangle ${startX} ${startY} ${endX} ${endY} \
            -dash { 4 3 } -outline bisque4 -tag "${expPath} ${expPath}.reference"]
      }
      if { [${canvas} coords ${expPath}.middle] != "" } {
         ${canvas} raise ${expPath}.reference  ${expPath}.middle
      }
}

# create a box from the end of the start icon up to the timevalue
proc Overview_ExpCreateMiddleBox { canvas suite_record timevalue {shift_day false} } {
   DEBUG "Overview_ExpCreateMiddleBox ${suite_record} ${timevalue} shift_day:${shift_day}" 5
   global graphStartX expEntryHeight startEndIconSize
   set groupRecord [${suite_record} cget -overview_group_record]
   set expPath [${suite_record} cget -suite_path]
   set startIconCoords [${canvas} coords ${expPath}.start]
   DEBUG "Overview_ExpCreateMiddleBox startIconCoords: $startIconCoords"

   $canvas delete ${expPath}.middle
   # middle box starts at end of start box
   set startX [lindex ${startIconCoords} 2]
   set endX [Overview_getXCoordTime ${timevalue} ${shift_day}]
   if { [expr ${endX} > ${startX}] } {
      # vertical coords are the same
      set startY [expr [lindex ${startIconCoords} 1] - ${expEntryHeight}/2 + ${startEndIconSize}/2 ]
      set endY [expr ${startY} + $expEntryHeight/2 + 8]
   
      # delete previous one if exists
      ${canvas} delete ${expPath}.middle

      set middleBoxId [$canvas create rectangle ${startX} ${startY} ${endX} ${endY} \
         -outline bisque4 -fill white -tag "${expPath} ${expPath}.middle"]

      $canvas lower ${expPath}.middle ${expPath}.text

      $canvas bind $middleBoxId <Double-Button-1> [list Overview_launchExpFlow $canvas ${expPath} ]
   }

}

# if a run is executing, this procedure is called every minute
# to update the status
proc Overview_updateExpBox { canvas suite_record status { timevalue "" } } {
   global startEndIconSize
   after cancel [${suite_record} cget -overview_after_id]

   set currentDateTime [clock seconds]
   set currentTime [clock format ${currentDateTime} -format "%H:%M" -gmt 1]
   set xoriginDateTime [Overview_GraphGetXOriginDateTime]
   if { ${timevalue} == "" } {
      set timevalue ${currentTime}
   }
   set timeValueDate [clock scan ${timevalue}]
   DEBUG "Overview_updateExpBox suite_record:$suite_record status:$status time:$timevalue updating..." 5

   set expPath [${suite_record} cget -suite_path]
   set xcoord [Overview_getXCoordTime ${timevalue}]
   set currentCoords [${canvas} coords ${expPath}]

   set middleBoxTime ${currentTime}
   set referenceBoxTime ""
   set endBoxTime ""
   set startTime [::SuiteNode::getStartTime ${suite_record}]
   set refTime [${suite_record} cget -ref_end]
   set refDateTime [clock scan ${refTime}]
   set lateReference false

   switch ${status} {
      "init" {
         Overview_ExpInitiateBox  $canvas $suite_record
      }
      "continue_begin" {
         set middleBoxTime ${currentTime}
         if { ${refTime} != "" } {
            if { ${currentDateTime} > ${refDateTime} } {
               # we are late
               set referenceBoxTime ${currentTime}
               set endBoxTime ${currentTime}
               set lateReference true
            } else {
               # we're still on time
               set referenceBoxTime ${currentTime}
               set endBoxTime ${refTime}
            }
         }
      }
      "begin" {
         # move the current box to the start time location
         set startDateTime [::SuiteNode::getStatusClockValue ${suite_record} begin]
            DEBUG "Overview_updateExpBox startDateTime:$startDateTime" 5
         if { [expr ${startDateTime} < ${xoriginDateTime}]} {
            # start date & time is previous to origin hour so move to 0
            DEBUG "Overview_updateExpBox moving to x origin" 5
            set xcoord [Overview_getXCoordTime [Overview_GraphGetXOriginTime]]
         }
         set deltax [expr ${xcoord} - [lindex ${currentCoords} 0]]
         DEBUG "Overview_updateExpBox suite_record:$suite_record --- $canvas move $expPath ${deltax} 0 ---" 5$canvas
         $canvas move $expPath ${deltax} 0
   
         set middleBoxTime ${currentTime}
         if { ${refTime} != "" } {
            if { ${currentDateTime} > ${refDateTime} } {
               # we are late
               set referenceBoxTime ${currentTime}
               set endBoxTime ${currentTime}
               set lateReference true
            } else {
               # we're still on time
               set referenceBoxTime ${currentTime}
               set endBoxTime ${refTime}
            }
         }
      }
      "end" {
         set middleBoxTime ${timevalue}
         ${canvas} delete ${expPath}.reference
         if { ${refTime} != "" } {
            if { ${timeValueDate} > ${refDateTime} } {
               # ended late
               set startDateTime [::SuiteNode::getStatusClockValue ${suite_record} begin]
               set referenceBoxTime ${currentTime}
               set endBoxTime ${timevalue}
               set lateReference true
            } else {
               if { ${startTime} != "" } {
                  # no startime, so no end time box
                  set endBoxTime ${timevalue}
               }
            }
         }
      }
      "abort" {
         set middleBoxTime ${timevalue}
         #set middleBoxTime ${currentTime}
         if { ${refTime} != "" } {
            if { ${currentDateTime} < ${refDateTime} } {     
               set referenceBoxTime ${timevalue}
               set endBoxTime ${refTime}
            } else {
               if { ${startTime} != "" } {
                  # no startime, so no end time box
                  set endBoxTime ${timevalue}
               }
            }
         }
      }
      default {
      }
   }

   if { ${status} != "init" } {
      Overview_ExpCreateMiddleBox ${canvas} ${suite_record} ${middleBoxTime}
      if { ${referenceBoxTime} != "" } {
         Overview_ExpCreateReferenceBox ${canvas} ${suite_record} ${referenceBoxTime} ${lateReference}
      }
      if { ${endBoxTime} != "" } {
         Overview_ExpCreateEndIcon ${canvas} ${suite_record} ${endBoxTime}
      }
   }

   set newcoords [Overview_getExpBoundaries ${canvas} ${suite_record}]
   set newx1 [lindex ${newcoords} 0]
   set newx2 [lindex ${newcoords} 2]
   set newy1 [lindex ${newcoords} 1]
   set newy2 [lindex ${newcoords} 3]
   # resolve any collision with existings exp boxes
   Overview_resolveLocation ${canvas} ${suite_record} ${newx1} ${newy1} ${newx2} ${newy2}
   Overview_refreshBoxStatus ${suite_record}
   Overview_setExpTooltip ${canvas} ${suite_record}

   if { ${status} == "begin" || ${status} == "continue_begin" } {
      # update every minute
      # continue_begin is used to update the status of an executing run
      # every minute
      ${suite_record} configure -overview_after_id \
         [ after 60000 [list Overview_updateExpBox ${canvas} ${suite_record} "continue_begin"] ]
   }

}

# places the exp boxes on the same line if there is room for it
proc Overview_shuffleExpBoxes {} {
   global graphX graphStartX expEntryHeight
   DEBUG "Overview_shuffleExpBoxes..." 5

   set displayGroups [record show instances DisplayGroup]
   set canvasW [Overview_getCanvas]
   foreach displayGroup $displayGroups {
      set expList [$displayGroup cget -exp_list]
      foreach exp $expList {
         set suiteRecord [::SuiteNode::getSuiteRecordFromPath ${exp}]
         set newcoords [Overview_getExpBoundaries ${canvasW} ${suiteRecord}]
         if { ${newcoords} != "" } {
            set ySlotStart [Overview_GroupGetNextSlotY ${displayGroup}]
            set yCurrentSlot [Overview_GroupGetCurrentSlotY ${displayGroup} [lindex ${newcoords} 1]]
            if { ${ySlotStart} != ${yCurrentSlot} } {
               set deltaY [expr ${yCurrentSlot} - ${ySlotStart}]
               set done false
               while { ${done} == "false" } {
                  DEBUG "Overview_shuffleExpBoxes $exp ySlotStart:${ySlotStart}" 5
                  DEBUG "Overview_shuffleExpBoxes $exp yCurrentSlot:${yCurrentSlot} deltaY:$deltaY" 5
                  set newx1 [lindex ${newcoords} 0]
                  set newx2 [lindex ${newcoords} 2]
                  set newy1 [expr [lindex ${newcoords} 1] - ${deltaY}]
                  set newy2 [expr [lindex ${newcoords} 3] - ${deltaY}]
                  set beforeCoords "$newx1 $newy1 $newx2 $newy2"
                  DEBUG "Overview_shuffleExpBoxes $exp newcoords:${newcoords} beforeCoords:$beforeCoords" 5
                  set overlapCoords [Overview_resolveOverlap ${canvasW} ${suiteRecord} ${newx1} ${newy1} ${newx2} ${newy2}]
                  DEBUG "Overview_shuffleExpBoxes $exp overlapCoords:${overlapCoords}"
                  if { [Utils_isListEqual ${overlapCoords} ${beforeCoords}] == "true" } {
                     set deltay [expr [lindex $overlapCoords 1] - [lindex ${newcoords} 1]]
                     DEBUG "Overview_shuffleExpBoxes $exp moving to new location 0 ${deltay}" 5
                     ${canvasW} move ${exp} 0 ${deltay}
                     set done true
                  } else {
                     if { [expr ${ySlotStart} == [${displayGroup} cget -maxy]] } {
                        set done true
                     }
                     set ySlotStart [Overview_GroupGetNextSlotY ${displayGroup} ${ySlotStart}]
                  }
                  set deltaY [expr ${yCurrentSlot} - ${ySlotStart}]
               }
            }
         }
      }
      # see if we can free some vertical space from the Group Display
      if { ${expList} != "" } {
         set ymin [${displayGroup} cget -miny]
         set y [${displayGroup} cget -maxy]
         while { [expr $y > ${ymin}] } {
            DEBUG "Overview_shuffleExpBoxes ${displayGroup} y:$y ymin:${ymin}" 5
            if { [${canvasW} find enclosed ${graphStartX} ${y} [expr ${graphStartX} + ${graphX}] [expr ${y} + ${expEntryHeight}]] == "" } {
               DEBUG  "Overview_shuffleExpBoxes ${displayGroup} set max to ${y}" 5
               ${displayGroup} configure -maxy ${y}
            }
            set y [expr ${y} - ${expEntryHeight}]
         }
      }
   }
}

proc Overview_resolveLocation { canvas suite_record x1 y1 x2 y2 } {
   global expEntryHeight
   DEBUG "Overview_resolveLocation x1:$x1 y1:$y1 x2:$x2 y2:$y2" 5
   set expPath [${suite_record} cget -suite_path]
   set currentCoords "${x1} ${y1} ${x2} ${y2}"
   set overlapCoords [Overview_resolveOverlap ${canvas} ${suite_record} ${x1} ${y1} ${x2} ${y2}]
   DEBUG "Overview_resolveLocation overlapCoords ${overlapCoords}" 5
   if { [Utils_isListEqual ${currentCoords} ${overlapCoords}] == "false" } {
      set deltax [expr [lindex $overlapCoords 0] - ${x1}]
      set deltay [expr [lindex $overlapCoords 1] - ${y1}]
      $canvas move ${expPath} ${deltax} ${deltay}
      set groupRecord [${suite_record} cget -overview_group_record]
      set newY [expr [lindex $overlapCoords 1] + ${expEntryHeight}]
      #${groupRecord} configure -y ${newY}
      #DEBUG "Overview_resolveLocation newY ${newY}" 5
      Overview_GroupSetY ${groupRecord} ${newY}
      DEBUG "Overview_resolveLocation moving ${expPath} from $x1 $y1 $x2 $y2 to $overlapCoords" 5
   }
}

proc Overview_resolveOverlap { canvas suite_record x1 y1 x2 y2 } {
   DEBUG "Overview_resolveOverlap $suite_record x1:$x1 y1:$y1 x2:$x2 y2:$y2" 5
   global expEntryHeight
   set groupRecord [${suite_record} cget -overview_group_record]
   set expPath [${suite_record} cget -suite_path]
   set expList [${groupRecord} cget -exp_list]

   foreach exp $expList {
      set isOverlap 0
      if { ${exp} != ${expPath} } {
         DEBUG "Overview_resolveOverlap testing ${expPath} collision with exp:$exp ???" 5
         set testedSuiteRecord [::SuiteNode::getSuiteRecordFromPath ${exp} ]
         set testedExpBox [Overview_getExpBoundaries ${canvas} ${testedSuiteRecord}]
         if { [llength $testedExpBox] != 0 } {
            DEBUG "Overview_resolveOverlap exp:$exp testedExpBox:$testedExpBox" 5
            set xx1 [lindex ${testedExpBox} 0]
            set yy1 [lindex ${testedExpBox} 1]
            set xx2 [lindex ${testedExpBox} 2]
            set yy2 [lindex ${testedExpBox} 3]
            DEBUG "Overview_resolveOverlap xx1:$xx1 yy1:$yy1 xx2:$xx2 yy2:$yy2" 5
            set isOverlap [Utils_isOverlap $x1 $y1 $x2 $y2 $xx1 $yy1 $xx2 $yy2]
            DEBUG "Overview_resolveOverlap FOUND OVERLAP? $isOverlap" 5
         }
      }
      if { ${isOverlap}  } {
         DEBUG "Overview_resolveOverlap $expPath we have and overlap" 5
         break
      }
   }
   if { ${isOverlap} } {
      # try to display the box in the next row
      set newy1 [expr ${y1} + ${expEntryHeight}]
      set newy2 [expr ${y2} + ${expEntryHeight}]
      DEBUG "Overview_resolveOverlap calling recursive Overview_resolveOverlap ${x1} ${newy1} ${x2} ${newy2}" 5
      set newCoords [Overview_resolveOverlap ${canvas} ${suite_record} ${x1} ${newy1} ${x2} ${newy2}]
      DEBUG "Overview_resolveOverlap got new coords Overview_resolveOverlap ${newCoords}" 5
      return ${newCoords}
   }

   DEBUG "Overview_resolveOverlap returing $x1 $y1 $x2 $y2" 5

   return "$x1 $y1 $x2 $y2"
}

proc Overview_boxMenu { canvas exp_path x y } {
   DEBUG "Overview_boxMenu() exp_path:$exp_path" 5
   set popMenu .popupMenu
   if { [winfo exists $popMenu] } {
      destroy $popMenu
   }
   menu $popMenu
   $popMenu add command -label "History" \
      -command [list Overview_historyCallback $canvas $exp_path $popMenu]
   $popMenu add command -label "Display Flow" -command [list Overview_launchExpFlow $canvas $exp_path]
   tk_popup $popMenu $x $y
}

proc Overview_historyCallback { canvas exp_path caller_menu } {
   DEBUG "Overview_historyCallback exp_path:$exp_path" 5
   set seqExec [getGlobalValue SEQ_UTILS_BIN]/nodehistory

   set seqNode [SharedData_getSuiteData ${exp_path} ROOT_NODE]
   Sequencer_runCommand $exp_path $seqExec "Node History ${exp_path}" -n $seqNode
}

proc Overview_launchExpFlow { calling_w exp_path } {
   global env ExpThreadList
   set xflowCmd $env(SEQ_XFLOW_BIN)/xflow

   set mainid [thread::id]
   set formatName [::SuiteNode::formatName ${exp_path}]
   set suiteRecord [::SuiteNode::getSuiteRecordFromPath ${exp_path}]

   set threadId [SharedData_getSuiteData ${exp_path} THREAD_ID]

   thread::send ${threadId} "thread_launchFLow ${mainid} ${threadId} ${suiteRecord}"
}

proc Overview_childQuit { suite_record thread_id } {
   puts "Overview_childQuit suite_record:$suite_record thread: $thread_id"
}

proc Overview_childInitDone { suite_path thread_id } {
   global TEST_VAR ALL_CHILD_INIT_DONE
   DEBUG "Overview_childInitDone suite_path:$suite_path thread: $thread_id" 5
   set TEST_VAR(${suite_path}) 1

   set displayGroups [record show instances DisplayGroup]
   set childNotDone false
   foreach displayGroup $displayGroups {
      set expList [$displayGroup cget -exp_list]
      foreach expPath ${expList} {
         if { ! [info exists TEST_VAR(${expPath})] || $TEST_VAR(${expPath}) == 0 } {
            set childNotDone true
            DEBUG "Overview_childInitDone note done: ${expPath}" 5

            break
         }
      }
      if { ${childNotDone} == true } {
         break
      }
   }

   if { ${childNotDone} == false } {
      set ALL_CHILD_INIT_DONE 1
   }
}

# this function is called asynchronously by experiment child threads to
# update the status of an experiment node in the overview panel.
# See LogReader.tcl
proc Overview_updateExp { suite_record datestamp status timestamp {is_startup 0} } {
   global IS_STARTUP AUTO_LAUNCH
   DEBUG "Overview_updateExp $suite_record status:$status timestamp:$timestamp is_startup:$is_startup IS_STARTUP:$IS_STARTUP" 5
   set colors [::DrawUtils::getStatusColor $status]
   set bgColor [lindex $colors 1]
   set canvas .overview_top.canvas
   # start synchronizing this block, get an exclusive lock

   set mutex [thread::mutex create]
   thread::mutex lock $mutex

   set dateValue [Utils_getDateFromDatestamp ${timestamp}]
   set timeValue [Utils_getTimeFromDatestamp ${timestamp}]
   set tagName [$suite_record cget -suite_path]
   DEBUG "Overview_updateExp setLastStatusInfo $suite_record $status $datestamp $dateValue $timeValue" 5
   ::SuiteNode::setLastStatusInfo $suite_record $status $datestamp $dateValue $timeValue

   if { [winfo exists $canvas] } {
      Overview_refreshBoxStatus ${suite_record}

      if { $status == "begin" } {
         # launch the flow if needed
         if { ${AUTO_LAUNCH} && ! ${is_startup} } {
            # Overview_launchExpFlow $canvas [$suite_record cget -suite_path]
         }
      }
      if { $status == "begin" || $status == "end" || $status == "abort" || $status == "init" } {
         if { ${is_startup} == 0 } {
            Overview_updateExpBox ${canvas} ${suite_record} ${status} ${timeValue}
         }
      }
   
   } else {
      DEBUG "Overview_updateExp canvas $canvas does not exists!" 5
   }

   # unlock and destroy the lock
   thread::mutex unlock $mutex
   thread::mutex destroy $mutex
}


proc Overview_addExp { group_record canvas exp_path } {
   DEBUG "Overview_addExp group_record:$group_record exp_path:$exp_path" 5
   
   set suiteRecord [::SuiteNode::formatSuiteRecord ${exp_path}]
   SuiteInfo ${suiteRecord} -suite_path ${exp_path}

   DEBUG "Overview_addExp suiteRecord:$suiteRecord" 5

   ############################
   # thread part start
   ############################
   set mainid [thread::id]

   # create a child thread for the exp
   set childId [Overview_createThread]

   # run the child thread
   thread::send ${childId} "readMasterfile ${exp_path}/EntryModule/flow.xml ${exp_path} \"\" \"\" "

   ${suiteRecord} configure -root_node [SharedData_getSuiteData ${exp_path} ROOT_NODE] -overview_group_record ${group_record}

   thread::send ${childId} "thread_startLogReader ${mainid} ${suiteRecord}"

   # remove the dummy default tk window
   thread::send ${childId} "wm withdraw ."

   # add the new thread to the list
   SharedData_setSuiteData ${exp_path} THREAD_ID ${childId}

   ############################3
   # thread part ends
   ############################3
}

proc Overview_createThread {} {
   set threadID [thread::create {
      global env
      set lib_dir $env(SEQ_XFLOW_BIN)/../lib
      set auto_path [linsert $auto_path 0 $lib_dir ]

      package require SuiteNode
      package require Tk

      #
      # From here to the 'thread::wait' statement, define the procedure(s)
      # that will be called from your main program
      #
      # The 'thread::wait' is required to keep this thread alive indefinitely.
      #
      global this_id
      set this_id [thread::id]

      proc thread_startLogReader { parent_id suite_record } {
         global this_id
         set isStartup 1
         set isOverview 1
         DEBUG "thread_startLogReader parent_id:$parent_id"

         LogReader_readFile ${suite_record} ${isOverview} ${parent_id} ${isStartup}
      }

      proc thread_launchFLow { parent_id thread_id suite_record } {
         global this_id env
         set env(SEQ_EXP_HOME) [${suite_record} cget -suite_path]
         DEBUG "thread_launchFLow thread_id:$thread_id" 5
         launchXflow ${parent_id} 1
      }

      proc thread_pointNode { exp_path node } {
         DEBUG "thread_pointNode exp_path:${exp_path} node:${node}" 5
      }

      DEBUG "child thread ${this_id} waiting..." 5
      # enter event loop
      thread::wait
   }]
   return ${threadID}
}

proc Overview_getExpBoundaries { canvas suite_record } {
   global expEntryHeight startEndIconSize
   set expPath [${suite_record} cget -suite_path]

   if { [${canvas} coords ${expPath}] == "" } {
      DEBUG "Overview_getExpBoundaries no boudaries found for ${expPath}" 5
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

   set boundaries "$x1 $y1 $x2 $y2"
   DEBUG "Overview_getExpBoundaries boudaries ${expPath} : ${boundaries}" 5
   return ${boundaries}
}

proc Overview_setExpTooltip { canvas suite_record } {
   set tooltipText ""

   set startTime [::SuiteNode::getStartTime ${suite_record}]
   set endTime [::SuiteNode::getEndTime ${suite_record}]
   set refStartTime [${suite_record} cget -ref_start]
   set refEndTime [${suite_record} cget -ref_end]
   set currentStatus [::SuiteNode::getLastStatus ${suite_record}]
   set currentStatusTime [::SuiteNode::getLastStatusTime ${suite_record}]

   set exptag [${suite_record} cget -suite_path]
   if { [${suite_record} cget -ref_start] != "" } {
      append tooltipText "Ref.Start: ${refStartTime}"
      append tooltipText "\nRef.End: ${refEndTime}"
   }

   switch ${currentStatus} {
      "init" {
      }
      "begin" {
         append tooltipText "\nStart: ${startTime}"
      }
      "abort" {
         append tooltipText "\nStart: ${startTime}"
         append tooltipText "\nAbort: ${currentStatusTime}"
      }
      "end" {
         append tooltipText "\nStart: ${startTime}"
         append tooltipText "\nEnd: ${endTime}"
      }
      default {
      }
   }

   ::tooltip::tooltip $canvas -item ${exptag} ${tooltipText}
}

proc Overview_getExpTimings { suite_record } {
   set exp_path [${suite_record} cget -suite_path]
   # get exp timings if exists
   set timingsFile ${exp_path}/ExpTimings
   if { [file exists $timingsFile] } {
      if [catch {open "$timingsFile" "r"} fileId] {
         puts stderr "Cannot open $timingsFile: $timingsFile"
         return 0
      } else {
         while {[gets $fileId line] >= 0} {
            set modif_line [regsub -all "=" ${line} " " ]
            eval "set ${modif_line}"
         }
         catch {
            $suite_record configure -ref_start ${ref_start} -ref_end ${ref_end}
         }
      }
   }
}

# the miny and maxy are timeslots start values
# this function will return the starting y values for an
# experiment box
proc Overview_GroupGetStartY { group_record {y_value ""} } {
   global expEntryHeight startEndIconSize
   if { ${y_value} == "" } {
      set value [${group_record} cget -miny]
   } else {
      set value [expr ${y_value} + ${expEntryHeight}]
      if { [expr ${value} > [${group_record} cget -maxy]] } {
         set value [${group_record} cget -maxy]
      }
   }

   set startY [expr ${value} +  ${expEntryHeight}/2 - (${startEndIconSize}/2)]
   return ${startY}
}

proc Overview_GroupGetNextSlotY { group_record {y_value ""} } {
   global graphStartY expEntryHeight
   if { ${y_value} == "" } {
      set value [${group_record} cget -miny]
   } else {
      set tmpValue [expr ${y_value} - ${graphStartY}]
      set tmpValue [::tcl::mathop::/ ${tmpValue} ${expEntryHeight}]
      set intValue [::tcl::mathfunc::entier ${tmpValue}]
      set slotValue [expr ${graphStartY} + ${intValue} * ${expEntryHeight}]
      set value [expr ${slotValue} + ${expEntryHeight}]
      if { [expr ${value} > [${group_record} cget -maxy]] } {
         set value [${group_record} cget -maxy]
      }
   }
   return ${value}
}

proc Overview_GroupGetCurrentSlotY { group_record {y_value ""} } {
   global graphStartY expEntryHeight
   if { ${y_value} == "" } {
      set value [${group_record} cget -miny]
   } else {
      set tmpValue [expr ${y_value} - ${graphStartY}]
      set tmpValue [::tcl::mathop::/ ${tmpValue} ${expEntryHeight}]
      set intValue [::tcl::mathfunc::entier ${tmpValue}]
      set slotValue [expr ${graphStartY} + ${intValue} * ${expEntryHeight}]
      set value ${slotValue}
      if { [expr ${value} > [${group_record} cget -maxy]] } {
         set value [${group_record} cget -maxy]
      }
   }
   return ${value}
}

# sets the current y timeslots value
# the y_value is converted to the beginning of the 
# timeslot y value
proc Overview_GroupSetY { group_record y_value } {
   global graphStartY expEntryHeight
   puts "Overview_GroupSetY y_value:$y_value"

   set tmpValue [expr ${y_value} - ${graphStartY}]
   set tmpValue [::tcl::mathop::/ ${tmpValue} ${expEntryHeight}]
   set intValue [::tcl::mathfunc::entier ${tmpValue}]
   set slotValue [expr ${graphStartY} + ${intValue} * ${expEntryHeight}]
   puts "Overview_GroupSetY slotValue:$slotValue"
   set currentMinY [${group_record} cget -miny]
   set currentMaxY [${group_record} cget -maxy]
   if { [expr ${currentMinY} == 0] && [expr ${currentMaxY} == 0] } {
      ${group_record} configure -miny ${slotValue}
      ${group_record} configure -maxy ${slotValue}
   } else {
      if { [expr ${slotValue} > ${currentMaxY}] } {
         ${group_record} configure -maxy ${slotValue}
      }
      if { [expr ${slotValue} < ${currentMinY}] } {
         ${group_record} configure -miny ${slotValue}
      }
   }
   puts "Overview_GroupSetY currentMinY:[${group_record} cget -miny] currentMaxY:[${group_record} cget -maxy]"
}

# this function creates the group labels at the left of the graph
# the values of the labels are read from a suites/exp list
proc Overview_addGroups { canvas } {
   global graphX graphy graphStartX graphStartY graphHourX expEntryHeight entryStartX entryStartY
   global IS_STARTUP ALL_CHILD_INIT_DONE
   set displayGroups [record show instances DisplayGroup]
   set groupEntryCurrentY $entryStartY
   set expEntryCurrentX $entryStartX

   # this step is to create an thread for each experiment/suite and
   # then have each thread read the suite's log file once and then
   # then the main thread will continue...
   # it will give us status box information
   foreach displayGroup $displayGroups {
      set expList [$displayGroup cget -exp_list]
      foreach exp $expList {
         Overview_addExp $displayGroup $canvas $exp
      }
   }
   # wait for all child to be done with their init
   vwait ALL_CHILD_INIT_DONE

   # here we will display the boxes
   foreach displayGroup $displayGroups {
      set groupName [$displayGroup cget -name]
      set displayName [file tail $groupName]
      # replace / and spaces with _
      # canvas tag does not like it with spaces
      set tagName [regsub -all "/" ${displayName} _]
      set tagName [regsub -all " " ${tagName} _ ]
      set tagName ${tagName}.label
      #puts "Overview_addGroups groupName:$groupName"
      set groupLevel [$displayGroup cget -level]

      # add indentation for each different level
      set expEntryCurrentX [expr $entryStartX + 4 + $groupLevel * 15]

      puts "Overview_addGroups groupName:$groupName entryStartX:$entryStartX"
      set groupId [$canvas create text $expEntryCurrentX [expr $groupEntryCurrentY + $expEntryHeight/2]  \
         -text $displayName -justify left -anchor w -fill grey20 -tag ${tagName} ]

      # get the font for each level
      set newFont [Overview_getLevelFont $canvas ${tagName} $groupLevel]

      $canvas itemconfigure ${tagName} -font $newFont
      ::tooltip::tooltip $canvas -item "${groupId}" "more info here for $displayName"

      # get the exps for each group if exists
      set expList [$displayGroup cget -exp_list]
      puts "Overview_addGroups groupName:$groupName groupEntryCurrentY:$groupEntryCurrentY"
      $displayGroup configure -x [expr $graphStartX + 20] -y $groupEntryCurrentY
      Overview_GroupSetY ${displayGroup} ${groupEntryCurrentY}

      foreach exp $expList {
         set suiteRecord [::SuiteNode::getSuiteRecordFromPath ${exp}]
         Overview_getExpTimings $suiteRecord
         Overview_ExpInitiateBox  $canvas $suiteRecord
         if { [Overview_isOffTimeGrid ${suiteRecord}] == "false" } {

            set currentStatus [::SuiteNode::getLastStatus ${suiteRecord}]
            set statusTime [::SuiteNode::getLastStatusTime ${suiteRecord}]
            puts "Overview_addGroups exp:${exp} currentStatus:${currentStatus}"
            if { ${currentStatus} == "end" || ${currentStatus} == "abort" } {
               # need to move the start box at the right location
               set startTime [::SuiteNode::getStartTime ${suiteRecord}]
               if { ${startTime} != "" } {
                  Overview_updateExpBox ${canvas} ${suiteRecord} begin ${startTime}
               }
            }
            if { ${currentStatus} == "begin" || ${currentStatus} == "end" || 
                 ${currentStatus} == "abort" || ${currentStatus} == "init" } {
               Overview_updateExpBox ${canvas} ${suiteRecord} ${currentStatus} ${statusTime}
            }
         } else {
            puts "Overview_addGroups exp:${exp} is off time grid"
         }
      }
      Overview_shuffleExpBoxes

      set groupEntryCurrentY [$displayGroup cget -maxy]
      proc out {} {
      if { ${expList} == "" } {
         puts "Overview_addGroups groupName:$groupName set group_y to :[expr $groupEntryCurrentY + $expEntryHeight]"
         $displayGroup configure -group_y [expr $groupEntryCurrentY + $expEntryHeight]
      } else {
         puts "Overview_addGroups groupName:$groupName set group_y to groupEntryCurrentY:$groupEntryCurrentY"
         $displayGroup configure -group_y ${groupEntryCurrentY}
      }
      }
      set groupEntryCurrentY [$displayGroup cget -maxy]
      $displayGroup configure -group_y [expr $groupEntryCurrentY + $expEntryHeight]
      set groupEntryCurrentY [$displayGroup cget -group_y]
   }
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

proc Overview_createGraph { canvas } {
   global graphX graphy graphStartX graphStartY graphHourX expEntryHeight entryStartX 

   # adds horiz shaded grid
   set x1 $entryStartX
   set x2  [expr $graphStartX + $graphX]
   set y1 $graphStartY
   set fillColor grey90
   while { $y1 < [expr $graphy + $graphStartY] } {
      $canvas create rectangle $x1 [expr $y1 ] $x2 [expr $y1 + $expEntryHeight ] -fill $fillColor -outline $fillColor
      set y1 [expr $y1 + $expEntryHeight]
      if { $fillColor == "grey90" } {
         set fillColor grey95
      } else {
         set fillColor grey90
      }
   }

   # creates hor lines at bottom & top
   $canvas create line $graphStartX $graphStartY [expr $graphStartX + $graphX] $graphStartY -arrow last
   $canvas create line $graphStartX [expr $graphStartY + $graphy] \
      [expr $graphStartX + $graphX] [expr $graphStartY + $graphy] -arrow last
   # x axis title
   $canvas create text [expr ${x2}/2 ] [expr $graphStartY + $graphy + 60] -text "Time (UTC)"
   
   # y axe origin
   $canvas create line $graphStartX [expr $graphStartY - 20] $graphStartX [expr $graphStartY + $graphy] -arrow first
   
   # the grid starts at current_hour - 12 and ends at current_hour + 12
   set currentHour [Utils_getNonPaddedValue [clock format [clock seconds] -format "%H" -gmt 1]]
   set hourTag [expr ${currentHour} % 12 + 1]
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

# return the date as an int value of the date and time
# of the time hour displayed at x=0
proc Overview_GraphGetXOriginDateTime {} {
   set origDateTime [clock add [clock seconds] -12 hours]
   set origDateTimeFormat [clock format ${origDateTime} -format {%Y-%m-%d %H}]
   set origDateTimeFormat ${origDateTimeFormat}:00:00
   set value [clock scan ${origDateTimeFormat}]
   return ${value}
}

proc Overview_GraphGetXOriginTime {} {
   set currentHour [Utils_getNonPaddedValue [clock format [clock seconds] -format "%H" -gmt 1]]
   set originHour [expr ${currentHour} % 12]
   set value "[Utils_getPaddedValue ${originHour}]:00"
   return ${value}
}

proc Overview_GraphDeleteHourLine {canvas hour} {
   set toDeleteTag grid_vertical_hour_${hour}   
   puts "Overview_GridAdvanceHour deleting tag hour: $hour"
   ${canvas} delete ${toDeleteTag}   
}

proc Overview_GraphAddHourLine {canvas grid_count hour} {
   global graphX graphy graphStartX graphStartY graphHourX expEntryHeight entryStartX 
   if { ${hour} < 10 } {
      set xLabel "0${hour}Z"
   } elseif { ${hour} == 24 } {
      set xLabel "00Z"
   } {
      set xLabel "${hour}Z"
   }
   

   set x1 [expr ${graphStartX} + ${grid_count} * ${graphHourX}]
   set x2 $x1
   set y1 [expr ${graphStartY} - 4]
   set y2 [expr ${graphStartY} + 4]
   $canvas create line $x1 $y1 $x2 $y2 -tag "grid_hour grid_vertical_hour_${hour}"
   $canvas create line $x1 [expr $y1 + $graphy] $x2 [expr $y2 + $graphy ] -tag "grid_hour  grid_vertical_hour_${hour}"
   $canvas create line $x1 [expr $y1 + 5] $x2 [expr $y2 + $graphy - 5 ] -dash 2 -fill grey60 -tag  "grid_hour  grid_vertical_hour_${hour}"

   $canvas create text $x2 [expr $y1 - 20 ] -text $xLabel -tag "grid_hour  grid_vertical_hour_${hour}"
   $canvas create text $x2 [expr $y2 + $graphy +20 ] -text $xLabel -tag "grid_hour grid_vertical_hour_${hour}"
}

proc Overview_init {} {
   global AUTO_LAUNCH
   global graphX graphy graphStartX graphStartY graphHourX expEntryHeight entryStartX entryStartY
   global expBoxLength startEndIconSize

   set AUTO_LAUNCH 1

   # hor size of graph
   set graphX 1225
   # vert size of graph
   set graphy 600
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

   set startEndIconSize 8

}

proc Overview_readExperiments {} {
   global env
   set suitesFile [getGlobalValue SUITES_FILE]
   set suiteList {}
   if { [file exists $suitesFile] } {
      puts "Overview_readExperiments from file: $suitesFile"
      ExpXmlReader_readExperiments $suitesFile
      set suiteList [ExpXmlReader_getExpList]
      puts "suiteList: $suiteList"
   } else {
      FatalError . "Overview Startup Error" "${suitesFile} does not exists! Exiting..."
   }
}

proc Overview_quit {} {
   global TimeAfterId
   if { [info exists TimeAfterId] } {
      after cancel $TimeAfterId
   }

   # destroy $top
   exit 0
}

proc Overview_parseCmdOptions {} {
   global argv env 
   if { [info exists argv] } {
      set options {
         {main ""}
         {suites.arg "" "suites definition file"}
      }
   
      puts "parseCmdlineOptions arguments list: $argv"
   
      set usage "\[options] \noptions:"
      if [ catch { array set params [::cmdline::getoptions argv $options $usage] } message ] {
         puts "\n$message"
         exit 1
      }
      if { $params(main) } {
         setGlobalValue MAIN 1
      } else {
         setGlobalValue MAIN 0
      }
      if { ! ($params(suites) == "") } {
         DEBUG "parseCmdlineOptions using suites definition file :$params(suites)" 5
         setGlobalValue SUITES_FILE $params(suites)
      } else {
         setGlobalValue SUITES_FILE $env(HOME)/.suites/.xflow.suites.xml
      }
   } else {
      setGlobalValue MAIN 0
   }
}

proc Overview_addFileMenu { parent } {
   set menuButtonW ${parent}.file_menub
   set menuW $menuButtonW.menu

   menubutton $menuButtonW -text File -underline 0 -menu $menuW
   menu $menuW -tearoff 0

   $menuW add command -label "Quit" -underline 0 -command "Overview_quit $parent" 

   pack $menuButtonW -side left -padx 2
}

proc Overview_addPrefMenu { parent } {
   set menuButtonW ${parent}.pref_menub
   set menuW $menuButtonW.menu

   menubutton $menuButtonW -text Preferences -underline 0 -menu $menuW
   menu $menuW -tearoff 0

   $menuW add checkbutton -label "Auto Launch" -variable AUTO_LAUNCH \
      -onvalue 1 -offvalue 0

   tooltip $menuW -index 0 "Automatic launch of flow when experiment starts"
   pack $menuButtonW -side left -padx 2
}

proc Overview_addHelpMenu { parent } {
   set menuButtonW ${parent}.help_menub
   set menuW $menuButtonW.menu

   menubutton $menuButtonW -text Help -underline 0 -menu $menuW
   menu $menuW -tearoff 0

   pack $menuButtonW -side right -padx 2
}

proc Overview_createMenu { toplevel_ } {
   set topFrame ${toplevel_}.topframe
   ttk::frame ${topFrame} -relief [SharedData_getMiscData MENU_RELIEF]
   grid ${topFrame} -row 0 -column 0 -sticky nsew -padx 2
   Overview_addFileMenu ${topFrame}
   Overview_addPrefMenu ${topFrame}
   Overview_addHelpMenu ${topFrame}
}

proc Overview_createToolbar { toplevel_ } {
   global MSG_CENTER_THREAD_ID
   set toolbarW ${toplevel_}.toolbar
   set mesgCenterW ${toolbarW}.button_msgcenter
   set closeW ${toolbarW}.button_close
   frame ${toolbarW} -bd 1

   set imageDir [SharedData_getMiscData IMAGE_DIR]

   image create photo ${toolbarW}.msg_center -file ${imageDir}/open_mail_sh.ppm
   button ${mesgCenterW} -image ${toolbarW}.msg_center -command {
      thread::send -async ${MSG_CENTER_THREAD_ID} "MsgCenterThread_showWindow"
   }

   ::tooltip::tooltip ${mesgCenterW} "Show Message Center."


   image create photo ${toolbarW}.close -file ${imageDir}/cancel.ppm
   button ${closeW} -image ${toolbarW}.close -command [list Overview_quit]
   ::tooltip::tooltip ${closeW} "Close Application."

   grid ${mesgCenterW} ${closeW} -sticky w -padx 2
   grid ${toolbarW} -row 1 -column 0 -sticky nsew -padx 2
}

global IS_STARTUP MSG_CENTER_THREAD_ID
wm withdraw .
SharedData_init

setGlobalValue DEBUG_TRACE 1
Overview_parseCmdOptions
set IS_STARTUP 1
if { [getGlobalValue MAIN] == 1 } {
   ::DrawUtils::init
   set MSG_CENTER_THREAD_ID [MsgCenter_getThread]
   set topOverview .overview_top
   set topCanvas ${topOverview}.canvas
   toplevel ${topOverview}
   wm title ${topOverview} "Xflow Overview Panel"
   Overview_readExperiments
   Overview_init

   Overview_createMenu ${topOverview}
   Overview_createToolbar ${topOverview}
   canvas ${topCanvas} -relief raised -bd 2 -bg cornsilk3
   grid ${topCanvas} -row 2 -column 0 -sticky nsew -padx 2
   grid columnconfigure ${topOverview} 0 -weight 1
   grid rowconfigure ${topOverview} 1 -weight 0
   grid rowconfigure ${topOverview} 2 -weight 1

   Overview_createGraph ${topCanvas}
   Overview_addGroups ${topCanvas}
   Overview_setCurrentTime ${topCanvas}
   Overview_GridAdvanceHour

   wm protocol ${topOverview} WM_DELETE_WINDOW [list Overview_quit ]
   wm geometry ${topOverview} =1500x800
}
set IS_STARTUP 0
