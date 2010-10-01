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
         set deltax ${graphHourX}
         set expAdvanceHour true
         set currentExpCoords [${canvasW} coords ${exp}]
         set adjustMiddleBoxCmd ""
         if { [${canvasW} coords ${exp}] != "" } {
            set currentExpEndBoxCoords [${canvasW} coords ${exp}]
         }
         set suiteRecord [::SuiteNode::getSuiteRecordFromPath ${exp}]
            set currentX [lindex ${currentExpCoords} 0]
            set currentEndX [lindex ${currentExpCoords} 2]
            # not moving exps that that are at x origin and needs to be there
            if { [expr ${currentX} == ${graphStartX}] } {
               set startTime [::SuiteNode::getStartTime ${suiteRecord}]
               if { [::SuiteNode::isHomeless ${suiteRecord}] } {
                  set expAdvanceHour false
                  DEBUG "Overview_GridAdvanceHour not advancing homeless ${exp}" 5
               } elseif { [::SuiteNode::getLastStatus ${suiteRecord}] == "begin" || 
                          [::SuiteNode::getLastStatus ${suiteRecord}] == "end" } {
                  # begin state siting at 0 must not be shifted
                  set expAdvanceHour false
                  DEBUG "Overview_GridAdvanceHour not advancing [::SuiteNode::getLastStatus ${suiteRecord}] ${exp}" 5
               }
            } elseif { [expr ${currentX} < (${graphStartX} + ${graphHourX})] && 
                       [expr ${currentEndX} > ${graphStartX}] } {
               # anything starting in the first 1 hour box but finishing outside must be moved
               # to 0
               set deltax [expr ${currentX} - ${graphStartX}]
               # also need to readjust middle box ending time
               set lastStatus [::SuiteNode::getLastStatus ${suiteRecord}]
               set lastStatusTime [::SuiteNode::getLastStatusTime ${suiteRecord}]
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
proc Overview_getXCoordTime { timevalue } {
   global graphHourX graphStartX

   set currentHour [Utils_getNonPaddedValue [clock format [clock seconds] -format "%H" -gmt 1]]
   set timeHour [Utils_getHourFromTime ${timevalue}]
   set timeMinute [Utils_getMinuteFromTime ${timevalue}]

   set hourGrid [expr ${currentHour} % 12]
   set hourDelta [expr ${hourGrid} * ${graphHourX}]
   set xcoordHour [ expr ${graphStartX} + ${timeHour} * ${graphHourX} - ${hourDelta} ]
   set xcoordMin [ expr ${timeMinute} * ${graphHourX} / 60 ]
   set xcoord [ expr ${xcoordHour} + ${xcoordMin} ]

   return $xcoord
}

proc Overview_addFileMenu { parent } {
   set menuButtonW ${parent}.file_menub
   set menuW $menuButtonW.menu

   menubutton $menuButtonW -text File -underline 0 -menu $menuW -relief raised
   menu $menuW -tearoff 0

   $menuW add command -label "Quit" -underline 0 -command "Overview_quit $parent" 

   pack $menuButtonW -side left -pady 2 -padx 2
}

proc Overview_addPrefMenu { parent } {
   set menuButtonW ${parent}.pref_menub
   set menuW $menuButtonW.menu

   menubutton $menuButtonW -text Preferences -underline 0 -menu $menuW -relief raised
   menu $menuW -tearoff 0

   $menuW add checkbutton -label "Auto Launch" -variable AUTO_LAUNCH \
      -onvalue 1 -offvalue 0

   tooltip $menuW -index 0 "Automatic launch of flow when experiment starts"
   pack $menuButtonW -side left -pady 2 -padx 2
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

proc Overview_ExpInitialBox_ { canvas suite_record } {
   global graphStartX graphHourX expEntryHeight expBoxLength

   set exp_path [$suite_record cget -suite_path]
   set group_record [$suite_record cget -overview_group_record]
   set refStartTime [${suite_record} cget -ref_start]
   set refEndTime [${suite_record} cget -ref_end]
   set currentDateTime [clock seconds]
   set currentTime [clock format ${currentDateTime} -format "%H:%M" -gmt 1]
   set xoriginDateTime [Overview_GraphGetXOriginDateTime]
      DEBUG "Overview_ExpInitialBox_ group_record:$group_record canvas:$canvas suite_record:$suite_record " 5


   set startTime [::SuiteNode::getStartTime ${suite_record}]
   set endTime [::SuiteNode::getEndTime ${suite_record}]
   set startDateTime [::SuiteNode::getLastStatusDateTime ${suite_record}]

   # if the exp has a start time, create the start box at the start time location
   if { ${startTime} != "" } {
      if { [expr [clock scan ${startDateTime}] > ${xoriginDateTime}] } {
         # start time is prior to visible hour, but date is smaller move it 0
         DEBUG "Overview_ExpInitialBox_ Overview_ExpCreateStartBox ${canvas} ${suite_record} ${startTime}"
         Overview_ExpCreateStartBox ${canvas} ${suite_record} [Overview_GraphGetXOriginTime]
      } else {
         DEBUG "Overview_ExpInitialBox_ Overview_ExpCreateStartBox ${canvas} ${suite_record} ${startTime}"
         Overview_ExpCreateStartBox ${canvas} ${suite_record} ${startTime}
      }
      if { ${endTime} != "" } {
         DEBUG "Overview_ExpInitialBox_ ${canvas} ${suite_record} ${endTime}"
         Overview_ExpCreateMiddleBox ${canvas} ${suite_record} ${endTime}
      } else {
         # if no endtime but has ref end time, use ref end time if greater than start time
         if { ${refEndTime} != "" && [::tcl::mathop::> ${refEndTime} ${startTime}] } {
            DEBUG "Overview_ExpInitialBox_ ${canvas} ${suite_record} ${refEndTime}"
            Overview_ExpCreateMiddleBox ${canvas} ${suite_record} ${refEndTime}
         } else {
            puts "Need to create dummy end time!"
         }
      }
   } elseif { ${refStartTime} != "" } {
      # create start box to reference start time
      Overview_ExpCreateStartBox ${canvas} ${suite_record} ${refStartTime}
      DEBUG "Overview_ExpInitialBox_ ${canvas} ${suite_record} ref start: ${refStartTime} ref end: ${refEndTime}"
      if { ${refEndTime} != "" && [::tcl::mathop::> ${refEndTime} ${refStartTime}] } {
         Overview_ExpCreateMiddleBox ${canvas} ${suite_record} ${refEndTime}
      }
   } else {
      # put it at beginning of graph whereever it fits
      set currentHour [clock format [clock seconds] -format "%H" -gmt 1]
      set zeroHour [expr [Utils_getNonPaddedValue ${currentHour}] % 12 ]
      set zeroHour "[Utils_getPaddedValue ${zeroHour}]:00"
      Overview_ExpCreateStartBox ${canvas} ${suite_record} ${zeroHour} 
   }

   # set newx for next item, only used when ref timings not used
   set thisExpBox [$canvas bbox ${exp_path}]
   set nextX [lindex ${thisExpBox} 2]
   ${group_record} configure -x [expr $nextX + 10]

   $canvas bind ${exp_path} <Button-3> [ list Overview_boxMenu $canvas $exp_path %X %Y]
}

proc Overview_refreshBoxStatus { suite_record } {
   set canvas [Overview_getCanvas]
   set status [::SuiteNode::getLastStatus ${suite_record}]
   set tagName [$suite_record cget -suite_path]
   set colors [::DrawUtils::getStatusColor $status]
   set bgColor [lindex $colors 1]
   if { [winfo exists $canvas] } {

      $canvas itemconfigure ${tagName}.start -fill $bgColor -outline $bgColor
      $canvas itemconfigure ${tagName}.middle -outline $bgColor
   }
}

proc Overview_ExpCreateStartIcon { canvas suite_record timevalue } {
   global graphStartX expEntryHeight
   set iconSize 8
   set groupRecord [${suite_record} cget -overview_group_record]
   set expPath [${suite_record} cget -suite_path]
   set startY [expr [${groupRecord} cget -y] +  $expEntryHeight/2 - (${iconSize}/2)]

   # get the x coord for the given time
   set startX [expr [Overview_getXCoordTime ${timevalue}] - ${iconSize}]

   # if { [${canvas} coords ${expPath}] == "" } {
      set labelX [expr $startX + 10]
      set startX2 [expr $startX + 8]
      set startY2 [expr $startY + 8]
   
      ${canvas} delete ${expPath}.start
      ${canvas} delete ${expPath}.text
      # create the left box      
      set startBoxId [$canvas create oval ${startX} ${startY} ${startX2} ${startY2} \
         -fill bisque4 -outline bisque4 -tag "${expPath} ${expPath}.start"]

      # create the exp label
      set tailName [file tail ${expPath}]
      set expLabel " ${tailName} "
      #set labelY [expr ${startY} + $expEntryHeight/2]
      set labelY [expr ${startY} + ($iconSize/2)]
      set expLabelId [$canvas create text ${labelX} ${labelY} \
         -text ${expLabel} -fill grey20 -anchor w -tag "${expPath} ${expPath}.text"]
  #}
}

# 1) moves the box to the timevalue if exists
# 2) if timevalue empty, moves the box to the reference start date if exists
# if 1) and 2) fails moves the box at current time
proc Overview_ExpCreateStartBox { canvas suite_record timevalue } {
   global graphStartX expEntryHeight
   set groupRecord [${suite_record} cget -overview_group_record]
   set expPath [${suite_record} cget -suite_path]
   set startY [${groupRecord} cget -y]

   # get the x coord for the given time
   set startX [Overview_getXCoordTime ${timevalue}]

   if { [${canvas} coords ${expPath}] == "" } {
      set labelX [expr $startX + 8]
      set startX2 [expr $startX + 5]
      set startY2 [expr $startY + $expEntryHeight/2 + 8]
   
      ${canvas} delete ${expPath}.start
      ${canvas} delete ${expPath}.text
      # create the left box      
      set startBoxId [$canvas create rectangle ${startX} ${startY} ${startX2} ${startY2} \
         -fill bisque4 -outline bisque4 -tag "${expPath} ${expPath}.start"]

      # create the exp label
      set tailName [file tail ${expPath}]
      set expLabel " ${tailName} "
      set labelY [expr ${startY} + $expEntryHeight/2]
      set expLabelId [$canvas create text ${labelX} ${labelY} \
         -text ${expLabel} -fill grey20 -anchor w -tag "${expPath} ${expPath}.text"]
   }
}

# 1) assumes the start box exists
# 2) will delete the existing middle box
# 3) will create a middle box from the end of the start box
# up to the given timevalue
proc Overview_ExpCreateMiddleBox { canvas suite_record timevalue } {
   global graphStartX expEntryHeight
   set groupRecord [${suite_record} cget -overview_group_record]
   set expPath [${suite_record} cget -suite_path]
   set startBoxCoords [${canvas} coords ${expPath}.start]

   # middle box starts at end of start box
   set startX [lindex ${startBoxCoords} 2]
   set endX [Overview_getXCoordTime ${timevalue}]

   # vertical coords are the same
   set startY [lindex ${startBoxCoords} 1]
   set endY [lindex ${startBoxCoords} 3]

   # delete previous one if exists
   ${canvas} delete ${expPath}.middle

   set middleBoxId [$canvas create rectangle ${startX} ${startY} ${endX} ${endY} \
      -outline bisque4 -fill white -tag "${expPath} ${expPath}.middle"]

   $canvas lower ${expPath}.middle ${expPath}.text

   $canvas bind $middleBoxId <Double-Button-1> [list Overview_launchExpFlow $canvas ${expPath} ]
}

# This is called to add a box until the reference end date
# the box outline will have dotted lines
proc Overview_ExpAddReferenceBox { canvas suite_record timevalue } {
   global graphStartX expEntryHeight
   set groupRecord [${suite_record} cget -overview_group_record]
   set expPath [${suite_record} cget -suite_path]
   set startBoxCoords [${canvas} coords ${expPath}.start]

   # middle box starts at end of start box
   set startX [lindex ${startBoxCoords} 2]
   set endX [Overview_getXCoordTime ${timevalue}]

   # vertical coords are the same
   set startY [lindex ${startBoxCoords} 1]
   set endY [lindex ${startBoxCoords} 3]

   # delete previous one if exists
   ${canvas} delete ${expPath}.middle

   set middleBoxId [$canvas create rectangle ${startX} ${startY} ${endX} ${endY} \
      -outline bisque4 -fill white -tag "${expPath} ${expPath}.middle"]

   $canvas lower ${expPath}.middle ${expPath}.text

   $canvas bind $middleBoxId <Double-Button-1> [list Overview_launchExpFlow $canvas ${expPath} ]
}

# if a run is executing, this procedure is called
# to extend a continuing box
proc Overview_updateExpBox { canvas suite_record status { timevalue "" } } {
   global graphX graphy graphStartX graphStartY graphHourX expEntryHeight entryStartX entryStartY
   after cancel [${suite_record} cget -overview_after_id]

   set currentDateTime [clock seconds]
   set currentTime [clock format ${currentDateTime} -format "%H:%M" -gmt 1]
   set xoriginDateTime [Overview_GraphGetXOriginDateTime]
   if { ${timevalue} == "" } {
      set timevalue ${currentTime}
   }
   DEBUG "Overview_updateExpBox suite_record:$suite_record status:$status time:$timevalue updating..." 5

   set expPath [${suite_record} cget -suite_path]
   set xcoord [Overview_getXCoordTime ${timevalue}]
   set currentCoords [${canvas} coords ${expPath}]

   set middleBoxTime ${currentTime}
   if { ${status} == "begin" } {
      # move the current box to the start time location
      set startTime [::SuiteNode::getStartTime ${suite_record}]

      set startDateTime [::SuiteNode::getStatusClockValue ${suite_record} begin]
      if { [expr ${startDateTime} < ${xoriginDateTime}]} {
         # start date & time is previous to origin hour so move to 0
         DEBUG "Overview_updateExpBox moving to x origin" 5
         set xcoord [Overview_getXCoordTime [Overview_GraphGetXOriginTime]]
      }
      set deltax [expr ${xcoord} - [lindex ${currentCoords} 0]]
      DEBUG "Overview_updateExpBox suite_record:$suite_record --- $canvas move $expPath ${deltax} 0 ---" 5
      $canvas move $expPath ${deltax} 0

      set middleBoxTime ${currentTime}
   } elseif { ${status} == "end" || ${status} == "abort" } {
      set middleBoxTime ${timevalue}
   }

   if { ${status} == "init" } {
      Overview_ExpInitialBox_  $canvas $suite_record
   } else {
      Overview_ExpCreateMiddleBox ${canvas} ${suite_record} ${middleBoxTime}
   }

   set newx1 [lindex [$canvas coords ${expPath}.start] 0]
   if { [$canvas coords ${expPath}.middle] != "" } {
      set newx2 [lindex [$canvas coords ${expPath}.middle] 2]
   } else {
      set newx2 [lindex [$canvas coords ${expPath}.start] 2]
   }
   set newy1 [lindex [$canvas coords ${expPath}.start] 1]
   set newy2 [lindex [$canvas coords ${expPath}.start] 3]
   set newcoords [${canvas} bbox ${expPath}]
   Overview_resolveLocation  ${canvas} ${suite_record} ${newx1} ${newy1} ${newx2} ${newy2}
   Overview_refreshBoxStatus ${suite_record}

   if { ${status} == "begin" || ${status} == "continue_begin" } {
      # update every minute
      ${suite_record} configure -overview_after_id \
         [ after 60000 [list Overview_updateExpBox ${canvas} ${suite_record} "continue_begin"] ]
   }

}

proc Overview_resolveLocation { canvas suite_record x1 y1 x2 y2 } {
   global expEntryHeight
   DEBUG "Overview_resolveLocation x1:$x1 y1:$y1 x2:$x2 y2:$y2" 5
   set expPath [${suite_record} cget -suite_path]
   set overlapCoords [Overview_resolveOverlap ${canvas} ${suite_record} ${x1} ${y1} ${x2} ${y2}]
   set deltax [expr [lindex $overlapCoords 0] - ${x1}]
   set deltay [expr [lindex $overlapCoords 1] - ${y1}]
   $canvas move ${expPath} ${deltax} ${deltay}
   set groupRecord [${suite_record} cget -overview_group_record]
   set newY [expr [lindex $overlapCoords 1] + ${expEntryHeight} ]
   if { [::tcl::mathop::> ${newY} [${groupRecord} cget -y]] } {
      ${groupRecord} configure -y ${newY}
   }
   DEBUG "Overview_resolveLocation moving ${expPath} from $x1 $y1 $x2 $y2 to $overlapCoords" 5
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
         set testedSuiteRecord [::SuiteNode::getSuiteRecordFromPath ${exp} ]
         #set testedExpBox [::SuiteNode::getOverviewInfo ${testedSuiteRecord}]
         #set testedExpBox [${canvas} coords ${exp}]
         set testedExpBox [${canvas} bbox ${exp}]
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
      if { [::SuiteNode::getStartTime ${suite_record}] != "" } {
         # try to display the box in the next row
         set newy1 [expr ${y1} + ${expEntryHeight}]
         set newy2 [expr ${y2} + ${expEntryHeight}]
         DEBUG "calling recursive Overview_resolveOverlap ${x1} ${newy1} ${x2} ${newy2}" 5
         set newCoords [Overview_resolveOverlap ${canvas} ${suite_record} ${x1} ${newy1} ${x2} ${newy2}]
         DEBUG "got new coords Overview_resolveOverlap ${newCoords}" 5
         return ${newCoords}
      } elseif { [${suite_record} cget -ref_start] == "" } {
         # for user experiments that have no start & time defined, align them horiz
         #$canvas move $expPath [expr ${xx2} + 10] 0
         # $canvas move $expPath ${xx2} 0
         DEBUG "Overview_resolveOverlap moving $expPath x to: ${xx2}" 5
         set newX  [expr ${xx2} + 0]
      }
   }

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

   set seqNode [SharedData_getRootNode ${exp_path}]
   Sequencer_runCommand $exp_path $seqExec "Node History ${exp_path}" -n $seqNode
}

proc Overview_launchExpFlow { calling_w exp_path } {
   global env ExpThreadList
   set xflowCmd $env(SEQ_XFLOW_BIN)/xflow

   set mainid [thread::id]
   set formatName [::SuiteNode::formatName ${exp_path}]
   set suiteRecord [::SuiteNode::getSuiteRecordFromPath ${exp_path}]

   set threadId [Overview_getExpThread ${exp_path}]
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
            Overview_launchExpFlow $canvas [$suite_record cget -suite_path]
         }
      }
      if { $status == "begin" || $status == "end" || $status == "abort" || $status == "init" } {
         if { ${is_startup} == 0 } {
            Overview_updateExpBox ${canvas} ${suite_record} ${status} ${timeValue}
         }
      }
   
      # has the run started or ended late?
      proc out {} {
         if { $status == "end" || $status == "begin" } {
            set refEndTime [${suite_record} cget -ref_end]
            if { ${refEndTime} != "" } {
               set endTime [string range ${timestamp} 19 23]
               if { $endTime > $refEndTime } {
                  $canvas itemconfigure ${tagName}.end -fill DarkViolet -outline DarkViolet
               }
            }
         }
      }
   } else {
      DEBUG "Overview_updateExp canvas $canvas does not exists!" 5
   }

   # unlock and destroy the lock
   thread::mutex unlock $mutex
   thread::mutex destroy $mutex
}


proc Overview_addExpThread { exp_path thread_id } {
   global ExpThreadList

   set ExpThreadList(${exp_path}) $thread_id
}

proc Overview_getExpThread { exp_path } {
   global ExpThreadList

   if { [info exists ExpThreadList(${exp_path})] } {
      return $ExpThreadList(${exp_path})
   }
   return ""
}

proc Overview_addExp { group_record canvas exp_path } {
   DEBUG "Overview_addExp group_record:$group_record exp_path:$exp_path" 5
   
   set tagName [regsub -all "/" ${exp_path} _]
   set tagName [regsub -all " " ${tagName} _ ]
   set tailName [file tail ${exp_path}]
   set expX [expr [${group_record} cget -x] + 10]
   DEBUG "Overview_addExp expX:$expX" 5
   set expY [${group_record} cget -y]

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

   ${suiteRecord} configure -root_node [SharedData_getRootNode ${exp_path}] -overview_group_record ${group_record}

   #thread::send -async ${childId} "thread_startLogReader ${mainid} ${suiteRecord}"
   thread::send ${childId} "thread_startLogReader ${mainid} ${suiteRecord}"

   # remove the dummy default tk window
   thread::send ${childId} "wm withdraw ."

   # add the new thread to the list
   Overview_addExpThread ${exp_path} ${childId}

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

      #proc sendHeartbeat { parent_id exp_path } {
      #   global this_id
      #   thread::send -async ${parent_id} "threadHeartbeat ${this_id} ${exp_path}"
      #   after 30000 [list sendHeartbeat $parent_id $exp_path]
      #}

      proc thread_cp_record { exp_path read_interval } {
         set formatName [::SuiteNode::formatName ${exp_path}]
         # set suiteRecord SuiteInfo.${formatName}
         set suiteRecord [::SuiteNode::formatSuiteRecord ${exp_path}]
         SuiteInfo $suiteRecord -type "user" -suite_name [file tail $exp_path] \
            -suite_path $exp_path -read_interval ${read_interval}
      }

      proc thread_startLogReader { parent_id suite_record } {
         global this_id
         #sendHeartbeat $parent_id $exp_path
         #readLog $parent_id $exp_path
         set isStartup 1
         set isOverview 1
         DEBUG "thread_startLogReader parent_id:$parent_id"

         LogReader_readFile ${suite_record} ${isOverview} ${parent_id} ${isStartup}
      }

      proc thread_launchFLow { parent_id thread_id suite_record } {
         global this_id env
         set env(SEQ_EXP_HOME) [${suite_record} cget -suite_path]
         puts "thread_launchFLow thread_id:$thread_id"
         launchXflow ${parent_id} 1
      }

      DEBUG "child thread ${this_id} waiting..."
      # enter event loop
      thread::wait
   }]
   return ${threadID}
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

# this function creates the group labels at the left of the graph
# the values of the labels are read from a suites/exp list
proc Overview_addGroups { canvas } {
   global graphX graphy graphStartX graphStartY graphHourX expEntryHeight entryStartX entryStartY
   global IS_STARTUP ALL_CHILD_INIT_DONE
   set displayGroups [record show instances DisplayGroup]
   set expEntryCurrentY $entryStartY
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

      #puts "Overview_addGroups groupName:$groupName entryStartX:$entryStartX"
      set groupId [$canvas create text $expEntryCurrentX [expr $expEntryCurrentY + $expEntryHeight/2]  \
         -text $displayName -justify left -anchor w -fill grey20 -tag ${tagName} ]

      # get the font for each level
      set newFont [Overview_getLevelFont $canvas ${tagName} $groupLevel]

      $canvas itemconfigure ${tagName} -font $newFont
      ::tooltip::tooltip $canvas -item "${groupId}" "more info here for $displayName"

      # get the exps for each group if exists
      set expList [$displayGroup cget -exp_list]
      $displayGroup configure -x [expr $graphStartX + 20] -y $expEntryCurrentY
      foreach exp $expList {
         set suiteRecord [::SuiteNode::getSuiteRecordFromPath ${exp}]
         Overview_getExpTimings $suiteRecord
         if { [Overview_isOffTimeGrid ${suiteRecord}] == "false" } {

            Overview_ExpInitialBox_  $canvas $suiteRecord
            set currentStatus [::SuiteNode::getLastStatus ${suiteRecord}]
            set statusTime [::SuiteNode::getLastStatusTime ${suiteRecord}]            
            if { ${currentStatus} == "end" || ${currentStatus} == "abort" } {
               # need to move the start box at the right location
               set startTime [::SuiteNode::getStartTime ${suiteRecord}]
               Overview_updateExpBox ${canvas} ${suiteRecord} begin ${startTime}
            }
            if { ${currentStatus} != "init" } {
               Overview_updateExpBox ${canvas} ${suiteRecord} ${currentStatus} ${statusTime}
            }
         }
      }

      set expEntryCurrentY [$displayGroup cget -y]
      $displayGroup configure -y [expr $expEntryCurrentY + $expEntryHeight]
      set expEntryCurrentY [$displayGroup cget -y]
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
   } else {
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
   global expBoxLength

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

proc Overview_quit { top } {
   global TimeAfterId
   if { [info exists TimeAfterId] } {
      after cancel $TimeAfterId
   }

   destroy $top
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

global IS_STARTUP
wm withdraw .

setGlobalValue DEBUG_TRACE 1
Overview_parseCmdOptions
set IS_STARTUP 1
if { [getGlobalValue MAIN] == 1 } {
   ::DrawUtils::init
   set topOverview .overview_top
   toplevel $topOverview
   #wm iconify $topOverview
   wm title $topOverview "Xflow Overview Panel"
   Overview_readExperiments
   Overview_init

   set topFrame $topOverview.topframe
   set topCanvas $topOverview.canvas
   ttk::frame $topFrame -relief raised
   grid $topFrame -row 0 -column 0 -sticky nw -padx 2 -pady 2
   Overview_addFileMenu $topFrame
   Overview_addPrefMenu $topFrame

   canvas $topCanvas -relief raised -bd 2 -bg cornsilk3
   grid $topCanvas -row 1 -column 0 -sticky nsew -padx 2 -pady 2
   grid columnconfigure $topOverview 0 -weight 1
   grid rowconfigure $topOverview 1 -weight 1

   Overview_createGraph $topCanvas
   Overview_addGroups $topCanvas
   Overview_setCurrentTime $topCanvas
   Overview_GridAdvanceHour

   wm protocol $topOverview WM_DELETE_WINDOW [ list Overview_quit $topOverview ]
   wm geometry $topOverview =1500x800
   #wm deiconify $topOverview
}
set IS_STARTUP 0
