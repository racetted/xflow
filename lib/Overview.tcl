package require struct::record
package require tooltip
package require cmdline
package require Thread
namespace import ::tooltip::tooltip
namespace import ::struct::record::record
package require log
package require img::png
package require autoscroll

global env
if { ! [info exists env(SEQ_XFLOW_BIN) ] } {
   puts "Environment variable SEQ_XFLOW_BIN must be defined!"
   exit
}

set lib_dir $env(SEQ_XFLOW_BIN)/../lib
set auto_path [linsert $auto_path 0 $lib_dir ]

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
   global LIST_TAG

   if [ catch {

      # wake-up in an hour
      set sleepTime 3600000
      set nextHour ""

      set currentClock [clock seconds]

      ::log::log debug "Overview_GridAdvanceHour new_hour:${new_hour} [clock format ${currentClock}]"
      ::log::log notice "Overview_GridAdvanceHour new_hour:${new_hour} [clock format ${currentClock}]"
      set advanceGrid true
      if { ${new_hour} == "" } {
         # first time called, calculate the time to sleep before the hour
         set advanceGrid false
         set new_hour [Utils_getNonPaddedValue [clock format ${currentClock} -format %H -gmt 1]]
         set elapsedMin [Utils_getNonPaddedValue [clock format ${currentClock} -format %M]]
         set elapsedSeconds [Utils_getNonPaddedValue [clock format ${currentClock} -format %S]]
         set elapsedInMilliSec [expr ${elapsedMin} * 60000 + ${elapsedSeconds} * 1000]
         set sleepTime [expr 3600000 - ${elapsedInMilliSec}]
      }

      if { ${new_hour} == "24" } {
         set nextHour 1
      } else {
         set nextHour [expr ${new_hour} + 1]
      }

      ::log::log debug "Overview_GridAdvanceHour sleeping for ${sleepTime} msecs before hour ${nextHour}"

      after ${sleepTime} [list Overview_GridAdvanceHour ${nextHour}]
   } message ] {
      ::log::log notice "ERROR in Overview_GridAdvanceHour(1) message:${message}"
      set errMsg "ERROR in proc Overview_GridAdvanceHour(1) :\n$message"
      tk_messageBox -title "Application Error!" -type ok -icon error \
        -message ${errMsg}
      return
   }  

   if { ${advanceGrid} == false } {
      return
   }

   if [ catch {

   ::log::log debug "Overview_GridAdvanceHour advancing grid hour ${new_hour}"

   set canvasW [Overview_getCanvas]

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

   # set new timeline
   Overview_setCurrentTime ${canvasW}

   # shift all the exp boxes in the canvas
   set displayGroups [ExpXmlReader_getGroups]

   # check if we need to release obsolete data
   OverviewExpStatus_checkObseleteDatestamps

   foreach displayGroup $displayGroups {
      set expList [$displayGroup cget -exp_list]
      foreach exp $expList {
      
         # delete all exp boxes
         Overview_removeAllExpBoxes ${canvasW} ${exp}

         # create default boxes
         Overview_addExpDefaultBoxes ${canvasW} ${exp}

         set datestamps [OverviewExpStatus_getDatestamps ${exp}]

         foreach datestamp ${datestamps} {
            set runBoxCoords [Overview_getRunBoxBoundaries  ${canvasW} ${exp} ${datestamp}]
            set currentX [lindex ${runBoxCoords} 0]
            set lastStatus [OverviewExpStatus_getLastStatus ${exp} ${datestamp}]
            set lastStatusTime [OverviewExpStatus_getLastStatusTime ${exp} ${datestamp}]

            # is the exp thread still needed?
            set expThreadId [SharedData_getExpThreadId ${exp} ${datestamp}]
            if { [OverviewExpStatus_getLastStatus ${exp} ${datestamp}] == "end" 
	         && [LogMonitor_isLogFileActive ${exp} ${datestamp}] == false 
		 && [xflow_isWindowActive ${exp} ${datestamp}] == false } {
               # the exp thread that followed this log is not needed anymore, release it    
               ::log::log notice "Overview_GridAdvanceHour Overview_releaseExpThread releasing exp thread for ${exp} ${datestamp}"
               Overview_releaseExpThread ${expThreadId} ${exp} ${datestamp}
            }

            if { [Overview_isExpBoxObsolete ${exp} ${datestamp}] == true } {
               # the end time happened prior to the x origin time,
               # shift the exp box to the left
               Overview_cleanDatestamp ${exp} ${datestamp}

               # delete current exp box from overview
               Overview_removeExpBox ${canvasW} ${exp} ${datestamp} ${lastStatus}
               
               Overview_addExpDefaultBoxes ${canvasW} ${exp} [Utils_getHourFromDatestamp ${datestamp}]
            } else {
               if { ${lastStatusTime} != "" } {
                  Overview_updateExpBox ${canvasW} ${exp} ${datestamp} ${lastStatus} ${lastStatusTime}
	       }
            }
         }

      }
   }
   # I'm updating the msg center once here instead of updating it every time we remove obsolete messages for every experiment 
   # It was creating flickering in the overview and msgcenter when shifting the grid at every hour
   MsgCenter_refreshActiveMessages [MsgCenter_getTableWidget]
   MsgCenter_ModifText 
   MsgCenter_sendNotification

   Overview_HighLightFindNode ${LIST_TAG}
   Overview_checkGridLimit 
   # Overview_setCurrentTime ${canvasW}
   ::log::log notice "Overview_GridAdvanceHour new_hour:${new_hour} [clock format ${currentClock}] DONE"

  } message ] {
      ::log::log notice "ERROR in Overview_GridAdvanceHour(2) message:${message}"
      set errMsg "ERROR in proc Overview_GridAdvanceHour(2) :\n$message"
      tk_messageBox -title "Application Error!" -type ok -icon error \
         -message ${errMsg}
  }
}

# redraws the overview for an exp
proc Overview_redrawExp { exp_path } {
   set canvasW [Overview_getCanvas]

   # delete all exp boxes
   Overview_removeAllExpBoxes ${canvasW} ${exp_path}

   # create default boxes
   Overview_addExpDefaultBoxes ${canvasW} ${exp_path}

   set datestamps [OverviewExpStatus_getDatestamps ${exp_path}]
   foreach datestamp ${datestamps} {
      set runBoxCoords [Overview_getRunBoxBoundaries  ${canvasW} ${exp_path} ${datestamp}]
      set currentX [lindex ${runBoxCoords} 0]
      set lastStatus [OverviewExpStatus_getLastStatus ${exp_path} ${datestamp}]
      set lastStatusTime [OverviewExpStatus_getLastStatusTime ${exp_path} ${datestamp}]

      if { ${lastStatusTime} != "" } {
         Overview_updateExpBox ${canvasW} ${exp_path} ${datestamp} ${lastStatus} ${lastStatusTime}
      }
   }
}

# sends a notification when an exp/datestamp is in idle state... 
#
# idle state is defined by an experiment where 
# 1) the log file exists (not in default state)
# 2) The log files and has not been modified in over
# a configurable idle threshold value
# 3) the current state is not "end" state
proc Overview_checkExpIdle { { next_check_time 3600000 } } {
   ::log::log debug "Overview_checkExpIdle [exec -ignorestderr date]"
   global CHECK_EXP_IDLE
   set displayGroups [ExpXmlReader_getGroups]

   set dialogTitle "Exp Idle Warning"
   if { ${CHECK_EXP_IDLE} == true } {
      foreach displayGroup $displayGroups {
         set expList [$displayGroup cget -exp_list]

         foreach expPath $expList {
            set datestamps [OverviewExpStatus_getDatestamps ${expPath}]
            set idleThreshold [SharedData_getExpIdleThreshold ${expPath}]
            foreach datestamp ${datestamps} {
               set lastStatus [OverviewExpStatus_getLastStatus ${expPath} ${datestamp}]
	       if { [ExpOptions_getCheckIdle ${expPath}] == true && ! [string match "default*" ${datestamp}] 
	          &&  ${lastStatus} != "end" && [LogMonitor_isLogFileActive ${expPath} ${datestamp} ${idleThreshold}] == false 
	         && [Overview_isExpIdle ${expPath} ${datestamp}] == true } {

                  # raise dialog to warn user exp is idled
                  ::log::log notice "Experiment ${expPath} ${datestamp} IDLE..."
                  set topW .idle_[regsub -all {[\.]} ${expPath}_${datestamp} _]
                  if { [winfo exists ${topW}] == 0 && [SharedData_getExpStopCheckIdle  ${expPath} ${datestamp}] == "0" } {
                     set idleThreshold [SharedData_getExpIdleThreshold ${expPath}]
		     set elapsedTimeMinutes [expr ([clock scan now] - [LogMonitor_getDatestampModTime ${expPath} ${datestamp}])  / 60]
	             set dialogText "Exp Idle Warning:\n\nExp: ${expPath} datestamp:${datestamp}  \
		     has been idle since \"[clock format [LogMonitor_getDatestampModTime ${expPath} ${datestamp}]] (${elapsedTimeMinutes} Minutes)\". \
		     \nIdle Threshold: ${idleThreshold} Minutes\nPlease verify!" 

                     global WARNING_AFTERID_${topW}
                     set dlg [Dialog ${topW} -parent [Overview_getToplevel] -modal none \
                             -separator 1 -title ${dialogTitle} -default 0 -place below -cancel 0]
                     $dlg add -name Ok -text Ok -command [list Overview_warningDlgOkCallback ${expPath} ${datestamp} ${topW} ${dialogTitle}]
                     $dlg add -name Find -text "Find" -width 8  -command [list Overview_findExp ${expPath} ${datestamp}]
                     $dlg add -name Launch -text "Launch Flow" -width 12 -command [list Overview_warningDlgLaunchCallback ${expPath} ${datestamp} ${topW} ${dialogTitle}]
                     $dlg add -name NoShowAgain -text "Do Not Show Again" -width 20 -command [list Overview_idleExpNoShowAgainCallback ${expPath} ${datestamp} ${topW} ${dialogTitle}]

                     # set a timer in 60 seconds to reshow the widget if the user did not ackownledge
                     set WARNING_AFTERID_${topW} [after 60000 [list Overview_showWarningReminder  ${expPath} ${datestamp} ${topW}]]
                     set msg [message [$dlg getframe].msg -aspect 600 -text ${dialogText} -justify left -anchor c  -font [xflow_getWarningFont] ]
                     pack $msg -fill both -expand yes -padx 20 -pady 20 

                     $dlg draw

                     # send message in msg center
	             MsgCenter_processNewMessage ${datestamp} [MsgCenter_getCurrentTime] sysinfo [Overview_getExpRootNodeInfo ${expPath}] "Exp Idle Warning!" ${expPath}
                  } else {
                     puts "Overview_processIdleExp NOT SENDING warning for ${expPath} ${datestamp}"
                  }
               }
            }
         }
      }
   } else {
      ::log::log debug "Overview_checkExpIdle CHECK_EXP_IDLE off!"
   }

   if { [string is integer -strict ${next_check_time}] } {
      after ${next_check_time} [list Overview_checkExpIdle ${next_check_time}]
   }
}

# checks exp submission late every 15 minutes
proc Overview_checkExpSubmitLate { { next_check_time 900000 }} {
   global CHECK_EXP_IDLE

   # puts "Overview_checkExpSubmitLate date:[exec -ignorestderr date]"
   if { ${CHECK_EXP_IDLE} == true } {

      set canvasW [Overview_getCanvas]
      set currentTime [clock seconds]
      foreach displayGroup [ExpXmlReader_getGroups] {
         set expList [$displayGroup cget -exp_list]

         foreach expPath $expList {
	    if { [ExpOptions_getCheckIdle ${expPath}] } {
	       # check submit late for this exp
               set expSubmitLateThreshold [SharedData_getExpSubmitLateThreshold ${expPath}]
               if { [string is integer -strict ${expSubmitLateThreshold}] == 0 || ${expSubmitLateThreshold} <=0 } {
                  ::log::log notice "Overview_checkExpSubmitLate ${expPath} invalid OVERVIEW_SUBMIT_LATE_THRESHOLD value: ${expSubmitLateThreshold}"
                  puts stderr "ERROR: Overview_checkExpSubmitLate ${expPath} invalid OVERVIEW_SUBMIT_LATE_THRESHOLD value: ${expSubmitLateThreshold}"
	          set expSubmitLateThreshold 15
               }

               # get the exp box from the overview
               set checkList [Overview_getExpBoxTags ${canvasW} ${expPath}]
	       # we are looking for boxes that have default_ tag, those are the ones that have not been submitted
	       set checkListIndex [lsearch -all ${checkList} default_*]
	       foreach checkIndex ${checkListIndex} {
	          set checkTag [lindex ${checkList} ${checkIndex}]
                  set refStartTime [Overview_getRefTimings ${expPath} [Utils_getHourFromDatestamp ${checkTag}] start]
                  if { [Overview_isExpStartPassed ${expPath} ${checkTag}] == true && ${refStartTime} != "" } {
                     set hour [Utils_getHourFromDatestamp ${checkTag}]
                     set datestamp [Overview_getScheduledInfo ${expPath} ${hour}]
                     set refTimeStartSeconds [Overview_getScheduledInfo ${expPath} ${hour} ${refStartTime} time]
		     # set dayValue [Utils_getDayClockFromDatestamp ${datestamp}]
		     scan ${refStartTime} %d:%d hourValue minuteValue
                     # set refTimeStartSeconds [clock add ${dayValue} ${hourValue} hour ${minuteValue} minute]
                     set refTimeLateSeconds [clock add ${refTimeStartSeconds} ${expSubmitLateThreshold} minute]

                     # check if exp box is passed current time and that is not within the log span discard
	             if {  [Overview_isExpScheduled ${expPath} ${hour} ${refStartTime}] == true && ${currentTime} > ${refTimeLateSeconds} && ${refTimeStartSeconds} > [SharedData_getMiscData LOG_SPAN_THRESHOLD_TIME] } {
		        # we need to send a warning dialog
                        set shortName [SharedData_getExpShortName ${expPath}]
                        set expLabel "${shortName}-${hour}"

		        set elapsedTimeMinutes [expr ([clock scan now] - ${refTimeStartSeconds})  / 60]
                        ::log::log notice "Experiment ${expPath} ${datestamp} SUBMIT LATE." 
                        set topW .submit_late_[regsub -all {[\.]} ${expPath}_${datestamp} _]
                        if { [winfo exists ${topW}] == 0 && [SharedData_getExpStopCheckSubmitLate ${expPath} ${datestamp}] == "0" } {
	                   # exp is late , send a message dialog warning user
	                   set dialogTitle "Exp Submit Late Warning"
	                   set dialogText "Exp Submit Late Warning:\n\nExp: ${expPath}\n${expLabel} \
			   has been late since \"[clock format ${refTimeStartSeconds}] (${elapsedTimeMinutes} Minutes)\". \
			   \nSubmit Late Threshold: ${expSubmitLateThreshold} Minutes\nPlease verify!" 


                           global WARNING_AFTERID_${topW}
                           Overview_closeWarningDlg  ${expPath} ${datestamp} ${topW} ${dialogTitle}
                           set dlg [Dialog ${topW} -parent . -modal none -geometry 750x300 \
                                -separator 1 -title ${dialogTitle} -default 0 -cancel 0]
                           $dlg add -name Ok -text Ok -command [list Overview_warningDlgOkCallback ${expPath} ${datestamp} ${topW} ${dialogTitle}]
                           $dlg add -name Find -text "Find" -width 8  -command [list Overview_findExp ${expPath} ${datestamp} true]
                           $dlg add -name Launch -text "Launch Flow" -width 12 -command [list Overview_warningDlgLaunchCallback ${expPath} ${datestamp} ${topW} ${dialogTitle}]
                           $dlg add -name NoShowAgain -text "Do Not Show Again" -width 20 -command [list Overview_expLateNoShowAgainCallback ${expPath} ${datestamp} ${topW} ${dialogTitle}]

                           set msg [message [$dlg getframe].msg -aspect 600 -text ${dialogText} -justify left -anchor w  -font [xflow_getWarningFont] ]
                           pack $msg -fill x -expand yes -padx 20 -pady 20 

                           $dlg draw

                           # set a timer in 60 seconds to reshow the widget if the user did not respond
                           set WARNING_AFTERID_${topW} [after 60000 [list Overview_showWarningReminder  ${expPath} ${datestamp} ${topW}]]

	                   # send message in msg center
	                   MsgCenter_processNewMessage ${datestamp} [MsgCenter_getCurrentTime] sysinfo [Overview_getExpRootNodeInfo ${expPath}] "Submission Late Warning!" ${expPath}

                        } else {
                           puts "Overview_checkExpSubmitLate NOT SENDING warning for ${expPath} ${datestamp}"
	                }
                     }
                  }
               }
            }
         }
      }
   }

   if { [string is integer -strict ${next_check_time}] } {
      after ${next_check_time} [list Overview_checkExpSubmitLate ${next_check_time}]
   }
}

# retrieves the scheduled datestamp or the scheduled start time of the run in seconds
# the datestamp_or_time argument is used to know whether the datestamp or the time should be returned
# if datestamp_or_time not given, default is datestamp
# 
# returned datestamp value is full i.e. 20160418160000
# returned time format value is seconds...same as output of [clock seconds]
proc Overview_getScheduledInfo { exp_path datestamp_hour {start_time ""} {datestamp_or_time datestamp}} {
   # ::log::log debug "Overview_getScheduledInfo $exp_path $datestamp_hour start_time:$start_time $datestamp_or_time"
   global graphStartX

   set currentTimeX [Overview_getCurrentTimeX]
   set today00ZX [Overview_getZeroHourX]
   if { [Overview_GraphGetXOriginHour] == "00" } {
      set today00ZX $graphStartX
   }
   set dayValue [Utils_getDayClockFromDatestamp [Utils_getDatestamp 0 0]]
   set myDatestampHourX [Overview_getXCoordTime ${datestamp_hour}:00]
   set deltaDay 0

   if { ${start_time} == "" } {
      set start_time 00:00
      # get from reference times
      set refTimings [SharedData_getExpTimings ${exp_path}]
      foreach refTiming ${refTimings} {
         foreach { myhour myStartTime myEndTime } ${refTiming} {
            if { ${datestamp_hour} == ${myhour} } {
               set start_time ${myStartTime}
            }
         }
      }
   }

   set myStartTimeX [Overview_getXCoordTime ${start_time}]
   scan ${start_time} %d:%d hourValue minuteValue

   ::log::log debug "datestamp_hour:$datestamp_hour hourValue:$hourValue currentTimeX:$currentTimeX myStartTimeX:$myStartTimeX myDatestampHourX:$myDatestampHourX today00ZX:$today00ZX"
   if {  (${datestamp_hour} > ${hourValue} && ${currentTimeX} >= ${myStartTimeX} && ${myDatestampHourX} <= ${today00ZX}) ||
         (${myStartTimeX} <= ${today00ZX} && ${currentTimeX} >= ${today00ZX}) } {
        # if the current time is to the right of the 00Z and the starting time is to the left then its yesterday's datestamp
        # for example, g218 & e218 should land here
	if { ${myStartTimeX}  >= ${today00ZX} } {
           set startReferenceTime [clock add ${dayValue} [expr ${hourValue}] hour ${minuteValue} minute]
	} else {
           set startReferenceTime [clock add ${dayValue} [expr -24 + ${hourValue}] hour ${minuteValue} minute]
	}
	set deltaDay -1
	::log::log debug "Overview_getScheduledInfo here 0 exp_path:$exp_path datestamp_hour:${datestamp_hour} deltaDay:$deltaDay startReferenceTime:$startReferenceTime"
   } elseif { (${datestamp_hour} > ${hourValue} &&  ${myDatestampHourX} > ${today00ZX} && ${currentTimeX} > ${today00ZX}) } {
        set startReferenceTime [clock add ${dayValue} ${hourValue} hour ${minuteValue} minute]
	set deltaDay -1
	::log::log debug "Overview_getScheduledInfo here 1 exp_path:$exp_path datestamp_hour:${datestamp_hour} deltaDay:$deltaDay startReferenceTime:$startReferenceTime"
   } elseif { (${myStartTimeX} > ${today00ZX} && ${currentTimeX} < ${today00ZX}) } {
        # if both start time and datestamp hour is passed the 00Z, then it's for tomorrow
        set startReferenceTime [clock add ${dayValue} [expr 24 + ${hourValue}] hour ${minuteValue} minute]
        if { ${myDatestampHourX} > ${currentTimeX} && ${myDatestampHourX} >= ${today00ZX} } {
	   set deltaDay 1
	}
	::log::log debug "Overview_getScheduledInfo here 2 exp_path:$exp_path datestamp_hour:${datestamp_hour} deltaDay:$deltaDay startReferenceTime:$startReferenceTime"
   } else {
        # default is today
        set startReferenceTime [clock add ${dayValue} ${hourValue} hour ${minuteValue} minute]
	set deltaDay 0
	::log::log debug "Overview_getScheduledInfo here 3 exp_path:$exp_path datestamp_hour:${datestamp_hour} deltaDay:$deltaDay startReferenceTime:$startReferenceTime"
   }

   if { ${datestamp_or_time} == "datestamp" } {
      set value [Utils_getDatestamp ${datestamp_hour} ${deltaDay}]
   } else {
      set value ${startReferenceTime}
   }

   ::log::log debug "Overview_getScheduledInfo here 4 exp_path:$exp_path datestamp_hour:${datestamp_hour} value:$value"
   return ${value}
}

proc Overview_isExpIdle { exp_path datestamp } {
   # puts "Overview_isExpIdle exp_path:$exp_path datestamp:$datestamp"
   set lastStatus [OverviewExpStatus_getLastStatus ${exp_path} ${datestamp}]
   set lastStatusTime [OverviewExpStatus_getLastStatusTime ${exp_path} ${datestamp}]
   set isIdle false
   set idleThreshold [SharedData_getExpIdleThreshold ${exp_path}]
   if { ! [string match "default*" ${datestamp}] && ${lastStatus} != "end" && [LogMonitor_isLogFileActive ${exp_path} ${datestamp} ${idleThreshold}] == false } {
      set isIdle true
   }
   # puts "Overview_isExpIdle exp_path:$exp_path datestamp:$datestamp"
   return ${isIdle}
}

# locates and point to an exp/datestamp box in the overview grid
proc Overview_findExp { exp_path datestamp {isDefault false}} {
   ::log::log debug "Overview_findExp exp_path:${exp_path} datestamp:${datestamp}"
   if { ${isDefault} == true } {
      set currentStatus default
   } else {
      set currentStatus [OverviewExpStatus_getLastStatus ${exp_path} ${datestamp}]
   }

   set expBoxTag [Overview_getExpBoxTag ${exp_path} ${datestamp} ${currentStatus}]
   ::DrawUtils::pointOverviewExp  ${exp_path} ${datestamp} [Overview_getCanvas] ${expBoxTag}
}

proc Overview_warningDlgLaunchCallback { exp_path datestamp callingTopLevelW title } {
   Overview_launchExpFlow ${exp_path} ${datestamp}
   Overview_closeWarningDlg ${exp_path} ${datestamp} ${callingTopLevelW} ${title}
   ::log::log notice "Experiment ${exp_path} ${datestamp} ${title} launch xflow acknowledge." 
}

proc Overview_idleExpNoShowAgainCallback { exp_path datestamp callingTopLevelW title } {
   SharedData_setExpStopCheckIdle ${exp_path} ${datestamp} 1
   Overview_closeWarningDlg ${exp_path} ${datestamp} ${callingTopLevelW} ${title}
   ::log::log notice "Experiment ${exp_path} ${datestamp} ${title} turned OFF." 
}

proc Overview_expLateNoShowAgainCallback { exp_path datestamp callingTopLevelW title } {
   SharedData_setExpStopCheckSubmitLate ${exp_path} ${datestamp} 1
   Overview_closeWarningDlg ${exp_path} ${datestamp} ${callingTopLevelW} ${title}
   ::log::log notice "Experiment ${exp_path} ${datestamp} ${title} turned OFF." 
}

proc Overview_warningDlgOkCallback { exp_path datestamp callingTopLevelW title } {
   Overview_closeWarningDlg ${exp_path} ${datestamp} ${callingTopLevelW} ${title}
   ::log::log notice "Experiment ${exp_path} ${datestamp} ${title} ok acknowledge."
}

proc Overview_closeWarningDlg { exp_path datestamp callingTopLevelW title } {
   global WARNING_AFTERID_${callingTopLevelW}
   catch { after cancel [set WARNING_AFTERID_${callingTopLevelW}] }
   catch { unset WARNING_AFTERID_${callingTopLevelW} }
   destroy ${callingTopLevelW}
}

proc Overview_showWarningReminder { exp_path datestamp callingTopLevelW } {
   global WARNING_AFTERID_${callingTopLevelW}
   # puts "Overview_showWarningReminder exp_path:${exp_path} datestamp:${datestamp}"
   if { [winfo exists ${callingTopLevelW}] } {
      wm withdraw ${callingTopLevelW}; wm deiconify ${callingTopLevelW} ; raise ${callingTopLevelW}
      set WARNING_AFTERID_${callingTopLevelW} [after 60000 [list Overview_showWarningReminder  ${exp_path} ${datestamp} ${callingTopLevelW}]]
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

   set timeHour [Utils_getPaddedValue [Utils_getHourFromTime ${timevalue}]]
   set timeMinute [Utils_getMinuteFromTime ${timevalue}]

   # puts "Overview_getXCoordTime timevalue:$timevalue graphStartX:$graphStartX"
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
   global LIST_TAG SHOW_MSGBAR

   ::log::log debug "setCurrentTime canvas:$canvas current_time:${current_time}"
   $canvas delete current_timeline

   if { [info exists TimeAfterId] } {
      after cancel ${TimeAfterId}
   }

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
   set x1 ${currentTimeCoordx}
   set x2 ${currentTimeCoordx}
   set y1 [expr $graphStartY - 4]
   set y2 [expr $graphStartY + 4]
   set lineId [$canvas create line $x1 [expr $y1 - 25] $x2 [expr $y2 + $graphy + 25] -tag "grid_time current_timeline" -fill DarkGreen]
   ::tooltip::tooltip $canvas -item "${lineId}" "Current Time:${current_time}Z\nUpdated every 30 seconds"

   if { [$canvas gettags current_timetext] == "" } {
      $canvas create text [expr $x1 +2] [expr $y2 + $graphy + 25] -fill DarkGreen -anchor w -justify left -tag "grid_item current_timetext"
   }

   $canvas itemconfigure current_timetext -text "Current Time: ${current_time}Z"

   # set overview title at the same time
   Overview_setTitle [winfo toplevel ${canvas}] ${current_time}

   # reset hightlight node
   if { ${SHOW_MSGBAR} == "true" } {
      Overview_HighLightFindNode ${LIST_TAG}
   }

   set TimeAfterId [after ${sleepTime} [list Overview_setCurrentTime $canvas]]
}

# returns the x coordinate of the current timeline
proc Overview_getCurrentTimeX {} {
   set canvas [Overview_getCanvas]
   set coords [${canvas} coords current_timeline]
   set currentTimex [lindex ${coords} 0]
   return ${currentTimex}
}

# returns the x coordinate of the 00Z time grid
proc Overview_getZeroHourX {} {
   set canvas [Overview_getCanvas]
   set hourTag [Overview_getGridTagHour 00 ]
   set coords [${canvas} coords ${hourTag}]
   set zeroHourX [lindex ${coords} 0]
   return ${zeroHourX}
}

#
#
# this function process the exp box logic when the root experiment node
# is in init state
proc Overview_processInitStatus { canvas exp_path datestamp {status init} } {
   ::log::log debug "Overview_processInitStatus ${exp_path} ${datestamp} ${status}"
   set statusTime [OverviewExpStatus_getLastStatusTime ${exp_path} ${datestamp}]
   set statusDateTime [OverviewExpStatus_getStatusClockValue ${exp_path} ${datestamp} init]
   set xoriginDateTime [Overview_GraphGetXOriginDateTime]
   set refEndTime [Overview_getRefTimings ${exp_path} [Utils_getHourFromDatestamp ${datestamp}]  end]
   set currentTime [Utils_getCurrentTime]

   if { ${statusTime} != "" && ${statusDateTime} != "" } {
      if { [expr ${statusDateTime} < ${xoriginDateTime}] } {
         # start time is prior to visible hour, move it 0
         Overview_ExpCreateStartIcon ${canvas} ${exp_path} ${datestamp} [Overview_GraphGetXOriginTime]
      } else {
         Overview_ExpCreateStartIcon ${canvas} ${exp_path} ${datestamp} ${statusTime}
      }

      if { ${refEndTime} != "" } {
         if { [Overview_getXCoordTime ${currentTime}] < [Overview_getXCoordTime ${refEndTime}] } {
            # the reference end is still coming
            Overview_ExpCreateReferenceBox ${canvas} ${exp_path} ${datestamp} ${currentTime}
            Overview_ExpCreateEndIcon ${canvas} ${exp_path} ${datestamp} ${refEndTime}
         }
      } else {
         # the reference end time is still ahead
         Overview_ExpCreateMiddleBox ${canvas} ${exp_path} ${datestamp} ${currentTime} false true
         set newcoords [Overview_getRunBoxBoundaries  ${canvas} ${exp_path} ${datestamp}]
         set endTime [Overview_getTimeFromCoord [lindex ${newcoords} 2]]
         Overview_ExpCreateEndIcon ${canvas} ${exp_path} ${datestamp} ${endTime}
      }
   }
}

# this function process the exp box logic when the root experiment node
# is in wait state
proc Overview_processWaitStatus { canvas exp_path datestamp {status wait} } {
   ::log::log debug "Overview_processWaitStatus ${exp_path} ${datestamp} ${status}"
   set statusTime [OverviewExpStatus_getLastStatusTime ${exp_path} ${datestamp}]
   set statusDateTime [OverviewExpStatus_getStatusClockValue ${exp_path} ${datestamp} wait]
   set xoriginDateTime [Overview_GraphGetXOriginDateTime]
   set currentTime [Utils_getCurrentTime]
   set refEndTime [Overview_getRefTimings ${exp_path} [Utils_getHourFromDatestamp ${datestamp}]  end]

   if { ${status} == "wait" } {
      if { [expr ${statusDateTime} < ${xoriginDateTime}] } {
         # start time is prior to visible hour, move it 0
         Overview_ExpCreateStartIcon ${canvas} ${exp_path} ${datestamp} [Overview_GraphGetXOriginTime]
      } else {
         Overview_ExpCreateStartIcon ${canvas} ${exp_path} ${datestamp} ${statusTime}
      }
   }
   # add middle box up to current time
   Overview_ExpCreateMiddleBox ${canvas} ${exp_path} ${datestamp} ${currentTime}

   # add reference
   if { ${refEndTime} != "" } {
      if { [Overview_getXCoordTime ${currentTime}] > [Overview_getXCoordTime ${refEndTime}] } {
         # we are late
         Overview_ExpCreateEndIcon ${canvas} ${exp_path} ${datestamp} ${currentTime}
         Overview_setExpLate ${canvas} ${exp_path} ${datestamp}
      } else {
         Overview_ExpCreateReferenceBox ${canvas} ${exp_path} ${datestamp} ${currentTime}
         Overview_ExpCreateEndIcon ${canvas} ${exp_path} ${datestamp} ${refEndTime}
      }
   } else {
         Overview_ExpCreateEndIcon ${canvas} ${exp_path} ${datestamp} ${currentTime}
   }
}

# this function process the exp box logic when the root experiment node
# is in catchup state
proc Overview_processCatchupStatus { canvas exp_path datestamp {status catchup} } {
   ::log::log debug "Overview_processCatchupStatus ${exp_path} ${datestamp} ${status}"
   set statusTime      [OverviewExpStatus_getLastStatusTime ${exp_path} ${datestamp}]
   set statusDateTime  [OverviewExpStatus_getStatusClockValue ${exp_path} ${datestamp} catchup]
   set currentTime     [Utils_getCurrentTime]
   set refStartTime    [Overview_getRefTimings ${exp_path} [Utils_getHourFromDatestamp ${datestamp}] start]
   set refEndTime      [Overview_getRefTimings ${exp_path} [Utils_getHourFromDatestamp ${datestamp}]  end]
   set xoriginDateTime [Overview_GraphGetXOriginDateTime]

   # I only care if the catchup time is visible
   if { [expr ${statusDateTime} > ${xoriginDateTime}] } {
      Overview_ExpCreateStartIcon ${canvas} ${exp_path} ${datestamp} ${statusTime}
      Overview_ExpCreateMiddleBox ${canvas} ${exp_path} ${datestamp} ${currentTime} false true
      set newcoords [Overview_getRunBoxBoundaries  ${canvas} ${exp_path} ${datestamp}]
      set endTime [Overview_getTimeFromCoord [lindex ${newcoords} 2]]
      Overview_ExpCreateEndIcon ${canvas} ${exp_path} ${datestamp}  ${endTime}
   } elseif { ${refStartTime} != "" } {
      Overview_ExpCreateStartIcon ${canvas} ${exp_path} ${datestamp} ${refStartTime} true
      Overview_ExpCreateMiddleBox ${canvas} ${exp_path} ${datestamp} ${refEndTime} true
      Overview_ExpCreateEndIcon ${canvas} ${exp_path} ${datestamp} ${refEndTime} true
   }
}

# this function process the exp box logic when the root experiment node
# is in submit state
proc Overview_processSubmitStatus { canvas exp_path datestamp {status submit} } {
   ::log::log debug "Overview_processSubmitStatus ${exp_path} ${datestamp} ${status}"
   set statusTime      [OverviewExpStatus_getLastStatusTime ${exp_path} ${datestamp}]
   set statusDateTime  [OverviewExpStatus_getStatusClockValue ${exp_path} ${datestamp} submit]
   set currentTime     [Utils_getCurrentTime]
   set refEndTime      [Overview_getRefTimings ${exp_path} [Utils_getHourFromDatestamp ${datestamp}]  end]
   set refEndDateTime  [clock scan ${refEndTime}]
   set currentDateTime [clock seconds]
   set xoriginDateTime [Overview_GraphGetXOriginDateTime]

   if { [expr ${statusDateTime} <= ${xoriginDateTime}] } {
      # submit time is prior to visible hour, move it 0
      Overview_ExpCreateStartIcon ${canvas} ${exp_path} ${datestamp} [Overview_GraphGetXOriginTime]
   } else {
      Overview_ExpCreateStartIcon ${canvas} ${exp_path} ${datestamp} ${statusTime}
   }
   if { ${refEndTime} != "" } {
      if { [expr ${currentDateTime} > ${refEndDateTime}] } {
         # we are late
         Overview_setExpLate ${canvas} ${exp_path} ${datestamp}
         Overview_ExpCreateMiddleBox ${canvas} ${exp_path} ${datestamp} ${currentTime} false true
         set newcoords [Overview_getRunBoxBoundaries  ${canvas} ${exp_path} ${datestamp}]
         set endTime [Overview_getTimeFromCoord [lindex ${newcoords} 2]]
         Overview_ExpCreateEndIcon ${canvas} ${exp_path} ${datestamp} ${endTime}
      } else {
         Overview_ExpCreateReferenceBox ${canvas} ${exp_path} ${datestamp} ${currentTime}
         Overview_ExpCreateEndIcon ${canvas} ${exp_path} ${datestamp} ${refEndTime}
      }
   } else {
      Overview_ExpCreateMiddleBox ${canvas} ${exp_path} ${datestamp} ${currentTime} false true
      set newcoords [Overview_getRunBoxBoundaries  ${canvas} ${exp_path} ${datestamp}]
      set endTime [Overview_getTimeFromCoord [lindex ${newcoords} 2]]
      Overview_ExpCreateEndIcon ${canvas} ${exp_path} ${datestamp} ${endTime}
   }

}

# this function process the exp box logic when the root experiment node
# is in begin state
proc Overview_processBeginStatus { canvas exp_path datestamp {status begin} } {
    ::log::log debug "Overview_processBeginStatus ${exp_path} ${datestamp} ${status}"
   set startTime       [OverviewExpStatus_getStartTime ${exp_path} ${datestamp}]
   set xoriginDateTime [Overview_GraphGetXOriginDateTime]
   set currentTime     [Utils_getCurrentTime]
   set refEndTime      [Overview_getRefTimings ${exp_path} [Utils_getHourFromDatestamp ${datestamp}]  end]
   set startDateTime   [OverviewExpStatus_getStatusClockValue ${exp_path} ${datestamp} begin]

   if { ${status} == "beginx" && [${canvas} coords ${exp_path}.${datestamp}.start] == "" } {
      set status begin
   }

   if { ${status} == "begin" } {
      if { [expr ${startDateTime} < ${xoriginDateTime}] } {
         # start time is prior to visible hour, move it 0
         Overview_ExpCreateStartIcon ${canvas} ${exp_path} ${datestamp} [Overview_GraphGetXOriginTime]
      } else {
         Overview_ExpCreateStartIcon ${canvas} ${exp_path} ${datestamp} ${startTime}
      }
   }
   # add middle box up to current time
   Overview_ExpCreateMiddleBox ${canvas} ${exp_path} ${datestamp} ${currentTime}

   # add reference
   if { ${refEndTime} != "" } {
      if { [Overview_getXCoordTime ${currentTime}] > [Overview_getXCoordTime ${refEndTime}] } {
         # we are late
         Overview_ExpCreateEndIcon ${canvas} ${exp_path} ${datestamp} ${currentTime}
         Overview_setExpLate ${canvas} ${exp_path} ${datestamp}
      } else {
         Overview_ExpCreateReferenceBox ${canvas} ${exp_path} ${datestamp} ${currentTime}
         Overview_ExpCreateEndIcon ${canvas} ${exp_path} ${datestamp} ${refEndTime}
      }
   } else {
      Overview_ExpCreateEndIcon ${canvas} ${exp_path} ${datestamp} ${currentTime}
   }
}

# this function process the exp box logic when the root experiment node
# is in end state
proc Overview_processEndStatus { canvas exp_path datestamp {status end} } {
   ::log::log debug "Overview_processEndStatus ${exp_path} ${datestamp} ${status}"

   set startTime       [OverviewExpStatus_getStartTime ${exp_path} ${datestamp}]
   set endTime         [OverviewExpStatus_getEndTime  ${exp_path} ${datestamp}]
   set startDateTime   [OverviewExpStatus_getStatusClockValue ${exp_path} ${datestamp} begin]
   set endDateTime     [OverviewExpStatus_getStatusClockValue ${exp_path} ${datestamp} end]
   set statusTime      [OverviewExpStatus_getLastStatusTime ${exp_path} ${datestamp}]
   set refStartTime    [Overview_getRefTimings ${exp_path} [Utils_getHourFromDatestamp ${datestamp}] start]
   set refEndTime      [Overview_getRefTimings ${exp_path} [Utils_getHourFromDatestamp ${datestamp}]  end]
   set xoriginDateTime [Overview_GraphGetXOriginDateTime]
   ::log::log debug "Overview_processEndStatus ${exp_path} refStartTime:$refStartTime refEndTime:$refEndTime startTime:$startTime endTime:$endTime startDateTime:$startDateTime endDateTime:$endDateTime"
   set shiftDay false
   if { ${startTime} != "" } {
      set currentTime [Utils_getCurrentTime]
      set middleBoxTime ${endTime}
      if { [expr ${startDateTime} < ${xoriginDateTime}] &&
            [expr ${endDateTime} > ${xoriginDateTime} ] } {

         # start time is not visible hour but end time is visible... move it 0
         Overview_ExpCreateStartIcon ${canvas} ${exp_path} ${datestamp} [Overview_GraphGetXOriginTime]
         Overview_ExpCreateMiddleBox ${canvas} ${exp_path} ${datestamp} ${middleBoxTime} ${shiftDay}
         Overview_ExpCreateEndIcon ${canvas} ${exp_path} ${datestamp} ${middleBoxTime} ${shiftDay}
         if { ${refEndTime} != "" && [Overview_getXCoordTime ${endTime}] > [Overview_getXCoordTime ${refEndTime}] } {
            # we are late
            Overview_setExpLate ${canvas} ${exp_path} ${datestamp}
         }
      } elseif { [expr ${startDateTime} <= ${xoriginDateTime}] &&
            [expr ${endDateTime} <= ${xoriginDateTime}]  } {
         # start time and end time both prior to origin hour, shit to right end grid
         set shiftDay true
         ::log::log debug "Overview_processEndStatus ${exp_path} ${datestamp} ${status} shiftDay true"
         OverviewExpStatus_setLastStatusInfo ${exp_path} ${datestamp} init "" ""
         if { ${refStartTime} != "" } {
            Overview_ExpCreateStartIcon ${canvas} ${exp_path} ${datestamp} ${refStartTime} ${shiftDay}
            set middleBoxTime ${refEndTime}
            Overview_ExpCreateMiddleBox ${canvas} ${exp_path} ${datestamp} ${middleBoxTime} ${shiftDay}
            Overview_ExpCreateEndIcon ${canvas} ${exp_path} ${datestamp} ${middleBoxTime} ${shiftDay}
         } else {
            # put at x origin 
            Overview_ExpCreateStartIcon ${canvas} ${exp_path} ${datestamp} [Overview_GraphGetXOriginTime] ${shiftDay}
         }
         if { ${datestamp} != "" } {
            Overview_cleanExpMsgDatestamp ${exp_path} ${datestamp}
         }
      } else {
         Overview_ExpCreateStartIcon ${canvas} ${exp_path} ${datestamp} ${startTime} ${shiftDay}
         Overview_ExpCreateMiddleBox ${canvas} ${exp_path} ${datestamp} ${middleBoxTime} ${shiftDay}
         Overview_ExpCreateEndIcon ${canvas} ${exp_path} ${datestamp} ${middleBoxTime} ${shiftDay}
         if { ${refEndTime} != "" && [Overview_getXCoordTime ${endTime}] > [Overview_getXCoordTime ${refEndTime}] } {
            # we are late
            Overview_setExpLate ${canvas} ${exp_path} ${datestamp}
         }
      }
   } else {
         # Overview_ExpCreateStartIcon ${canvas} ${exp_path} ${datestamp} ${statusTime}
      if { [expr ${endDateTime} <= ${xoriginDateTime}]  } {
         set shiftDay true
         OverviewExpStatus_setLastStatusInfo ${exp_path} ${datestamp} init "" ""
         if { ${refStartTime} != "" } {
            Overview_ExpCreateStartIcon ${canvas} ${exp_path} ${datestamp} ${refStartTime} ${shiftDay}
            set middleBoxTime ${refEndTime}
            Overview_ExpCreateMiddleBox ${canvas} ${exp_path} ${datestamp} ${middleBoxTime} ${shiftDay}
            Overview_ExpCreateEndIcon ${canvas} ${exp_path} ${datestamp} ${middleBoxTime} ${shiftDay}
         } else {
            # put at x origin 
            Overview_ExpCreateStartIcon ${canvas} ${exp_path} default [Overview_GraphGetXOriginTime] ${shiftDay}
         }
      } else {
         Overview_ExpCreateStartIcon ${canvas} ${exp_path} ${datestamp} ${statusTime}
      }
   }
}

proc Overview_cleanExpMsgDatestamp { exp_path datestamp {refresh_msg_center true}} {
   MsgCenter_removeMessages ${exp_path} ${datestamp} ${refresh_msg_center}
}

# this function process the exp box logic when the root experiment node
# is in abort state
proc Overview_processAbortStatus { canvas exp_path datestamp {status abort} } {

   set startTime       [OverviewExpStatus_getStartTime ${exp_path} ${datestamp}]
   set startDateTime   [OverviewExpStatus_getStatusClockValue ${exp_path} ${datestamp} begin]
   set statusTime      [OverviewExpStatus_getLastStatusTime ${exp_path} ${datestamp}]
   set refEndTime      [Overview_getRefTimings ${exp_path} [Utils_getHourFromDatestamp ${datestamp}]  end]
   set refEndDateTime  [clock scan ${refEndTime}]
   set currentDateTime [clock seconds]
   set xoriginDateTime [Overview_GraphGetXOriginDateTime]
   set currentTime     [Utils_getCurrentTime]

   if { ${startTime} != "" } {
      if { [expr ${startDateTime} < ${xoriginDateTime}] } {
         # start time is prior to visible hour, move it 0
         Overview_ExpCreateStartIcon ${canvas} ${exp_path} ${datestamp} [Overview_GraphGetXOriginTime]
      } else {
         Overview_ExpCreateStartIcon ${canvas} ${exp_path} ${datestamp} ${startTime}
      }
   } else {
      Overview_ExpCreateStartIcon ${canvas} ${exp_path} ${datestamp} ${statusTime}
   }
   # add middle box up to abort time
   Overview_ExpCreateMiddleBox ${canvas} ${exp_path} ${datestamp} ${statusTime}
   if { ${refEndTime} != "" } {
      if { [Overview_getXCoordTime ${currentTime}] < [Overview_getXCoordTime ${refEndTime}] } {     
         Overview_ExpCreateReferenceBox ${canvas} ${exp_path} ${datestamp} ${statusTime}
         Overview_ExpCreateEndIcon ${canvas} ${exp_path} ${datestamp} ${refEndTime}
      } else {
         set newcoords [Overview_getRunBoxBoundaries  ${canvas} ${exp_path} ${datestamp}]
         Overview_ExpCreateEndIcon ${canvas} ${exp_path} ${datestamp} ${statusTime}
      }
   }
}

# sets a visual indication when an exp is running late with respect
# to reference timings...when the reference end time is passed
proc Overview_setExpLate { canvas exp_path datestamp } {
   set displayGroup [SharedData_getExpGroupDisplay ${exp_path}]
   set status [OverviewExpStatus_getLastStatus ${exp_path} ${datestamp}]
   set refEndTime [Overview_getRefTimings ${exp_path} [Utils_getHourFromDatestamp ${datestamp}]  end]

   # puts "Overview_setExpLate  $exp_path $datestamp status:$status refEndTime:${refEndTime}" 
   set expBoxTag [Overview_getExpBoxTag ${exp_path} ${datestamp} ${status}]
   set expGroupBoxTag [DisplayGrp_getGroupExpBoxTagName ${displayGroup}]
   ${canvas} itemconfigure ${expBoxTag}.text -fill DarkViolet

   set middleBoxCoords [${canvas} coords ${expBoxTag}.middle]
   if { ${refEndTime} != "" && ${middleBoxCoords} != "" } {
      set refEndTimeX [Overview_getXCoordTime ${refEndTime}]
      if { ${refEndTimeX} < [lindex ${middleBoxCoords} 0] } {
         set refEndTimeX [lindex ${middleBoxCoords} 0]
      }
      set startY [lindex ${middleBoxCoords} 1]
      set endY [lindex ${middleBoxCoords} 3]
      # ${canvas} create line ${refEndTimeX} ${startY} ${refEndTimeX} ${endY} -width 4 -fill [::DrawUtils::getOutlineStatusColor end]
      ${canvas} create line ${refEndTimeX} ${startY} ${refEndTimeX} ${endY} -width 4 -fill DarkViolet -tags "${expGroupBoxTag} ${exp_path} ${expBoxTag} ${expBoxTag}.late_line"
   }
}

# this function is called to display the exp node with the right
# color status... usually when the exp thread notifies the overview
# of a new experiment status
proc Overview_refreshBoxStatus { exp_path datestamp {status ""} } {
   set canvas [Overview_getCanvas] 
   if { ${status} == "" } {
      set status [OverviewExpStatus_getLastStatus ${exp_path} ${datestamp}]
   }
   set expBoxTag [Overview_getExpBoxTag ${exp_path} ${datestamp} ${status}]

   set bgColor [::DrawUtils::getBgStatusColor ${status}]
   set outlineColor [::DrawUtils::getOutlineStatusColor ${status}]
   set initBgColor [::DrawUtils::getBgStatusColor init]
   if { [winfo exists $canvas] } {

      $canvas itemconfigure ${expBoxTag}.start -fill $bgColor -outline ${outlineColor}
      $canvas itemconfigure ${expBoxTag}.middle -outline ${outlineColor}
      $canvas itemconfigure ${expBoxTag}.reference -fill ${initBgColor} -outline ${outlineColor}
      $canvas itemconfigure ${expBoxTag}.end -fill $bgColor -outline ${outlineColor}
      ${canvas} raise ${expBoxTag}.text
   }
}

# this function creates an experiment start icon
#  - It creates a circle with a starting point that represents the timevalue argument
#  - It creates a label with the exp name
#  - The start icon is colored with the status color
#  If the shift_day argument is true, it forces the status to init... This means that
#  the timings of the exp are off the left side grid...
proc Overview_ExpCreateStartIcon { canvas exp_path datestamp timevalue {shift_day false} } {
   global graphStartX expEntryHeight startEndIconSize
    ::log::log debug "Overview_ExpCreateStartIcon $exp_path $datestamp $timevalue shift_day:$shift_day"
   set displayGroup   [SharedData_getExpGroupDisplay ${exp_path}]
   set expGroupBoxTag [DisplayGrp_getGroupExpBoxTagName ${displayGroup}]
   
   set startY  [expr [${displayGroup} cget -y] +  $expEntryHeight/2 - (${startEndIconSize}/2)]
   set startX  [Overview_getXCoordTime ${timevalue} ${shift_day}]
   set labelX  [expr $startX + 10]
   set startX2 [expr $startX + ${startEndIconSize}]
   set startY2 [expr $startY + ${startEndIconSize}]

   # puts "Overview_ExpCreateStartIcon $exp_path $datestamp $timevalue startX:$startX"
   set currentStatus [OverviewExpStatus_getLastStatus ${exp_path} ${datestamp}]

   # delete previous box
   Overview_removeExpBox ${canvas} ${exp_path} ${datestamp} ${currentStatus}

   set datestampRange [SharedData_getMiscData OVERVIEW_DATESTAMP_RANGE]
   set shortName [SharedData_getExpShortName ${exp_path}]
   set expLabel " ${shortName} "
   set outlineColor [::DrawUtils::getOutlineStatusColor ${currentStatus}]
   # puts "Overview_ExpCreateStartIcon outlineColor:$outlineColor currentStatus:$currentStatus"
   if { ${shift_day} == true || [string match "defaut*" ${datestamp}] } {
      set currentStatus init
      set expBoxTag [Overview_getExpBoxTag ${exp_path} ${datestamp} default]
      if { [SharedData_getExpTimings ${exp_path}] != "" } {
         set labelDatestamp [Utils_getHourFromDatestamp ${datestamp}]
         set expLabel " ${shortName}-${labelDatestamp} "
      }
   } else {
      set expBoxTag [Overview_getExpBoxTag ${exp_path} ${datestamp} ${currentStatus}]
      if { [SharedData_getExpTimings ${exp_path}] != "" || ${currentStatus} != "init"} {
         set labelDatestamp [string range ${datestamp} [lindex ${datestampRange} 0] [lindex ${datestampRange} 1]]
         set expLabel " ${shortName}-${labelDatestamp} "
      }
   }
   set bgColor [::DrawUtils::getBgStatusColor ${currentStatus}]
   ::log::log debug "Overview_ExpCreateStartIcon ${expBoxTag}.start at ${startX} ${startY} ${startX2} ${startY2} outlineColor:${outlineColor} bgColor:${bgColor}"
   # create the left box      
   set startBoxId [$canvas create oval ${startX} ${startY} ${startX2} ${startY2} -width 1.0 \
      -fill ${bgColor} -outline ${outlineColor} -tags "${expGroupBoxTag} ${exp_path} ${expBoxTag} ${expBoxTag}.start"]

   # create the exp label
   set labelY [expr ${startY} + (${startEndIconSize}/2)]
   set expLabelId [$canvas create text ${labelX} ${labelY} -font [Overview_getBoxLabelFont] \
      -text ${expLabel} -fill black -anchor w -tags "${expGroupBoxTag} ${exp_path} ${expBoxTag} ${expBoxTag}.text"]
}

# this function creates an experiment end icon
#  - It creates a circle with a starting point that represents the timevalue argument
#  If the shift_day argument is true, it forces the status to init... This means that
#  the timings of the exp are off the left side grid...
proc Overview_ExpCreateEndIcon { canvas exp_path datestamp timevalue {shift_day false} } {
   ::log::log debug "Overview_ExpCreateEndIcon ${exp_path} ${datestamp} ${timevalue} shift_day:$shift_day"
   global graphStartX expEntryHeight startEndIconSize
   set displayGroup   [SharedData_getExpGroupDisplay ${exp_path}]
   set expGroupBoxTag [DisplayGrp_getGroupExpBoxTagName ${displayGroup}]
   set currentCoords  [Overview_getRunBoxBoundaries  ${canvas} ${exp_path} ${datestamp}]
   set startX         [Overview_getXCoordTime ${timevalue} ${shift_day}]
   set currentY       [DisplayGrp_getCurrentSlotY [lindex ${currentCoords} 1]]
   set startY         [expr ${currentY} +  $expEntryHeight/2 - (${startEndIconSize}/2)]

   set currentStatus [OverviewExpStatus_getLastStatus ${exp_path} ${datestamp}]
   # puts "Overview_ExpCreateEndIcon currentStatus:$currentStatus"
   if { ${shift_day} == true || [string match "defaut*" ${datestamp}] } {
      set currentStatus init
      set expBoxTag [Overview_getExpBoxTag ${exp_path} ${datestamp} default]
   } else {
      set expBoxTag [Overview_getExpBoxTag ${exp_path} ${datestamp} ${currentStatus}]
   }
   ${canvas} delete ${expBoxTag}.end

   set outlineColor [::DrawUtils::getOutlineStatusColor ${currentStatus}]
   set bgColor [::DrawUtils::getBgStatusColor ${currentStatus}]


   # we create an end icon only if the middle box or the reference box exist
   if { [${canvas} coords ${expBoxTag}.middle] != "" || [${canvas} coords ${expBoxTag}.reference] != ""} {

      set startX2 [expr $startX + ${startEndIconSize}]
      set startY2 [expr $startY + ${startEndIconSize}]

      # create the left box
      set endBoxId [${canvas} create oval ${startX} ${startY} ${startX2} ${startY2} -width 1 \
         -fill ${bgColor} -outline ${outlineColor} -tags "${expGroupBoxTag} ${exp_path} ${expBoxTag} ${expBoxTag}.end"]

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
proc Overview_ExpCreateReferenceBox { canvas exp_path datestamp timevalue {late_reference false} } {
   ::log::log debug "Overview_ExpCreateReferenceBox ${exp_path} ${datestamp} ${timevalue} late_reference:$late_reference"
   global graphStartX expEntryHeight startEndIconSize
   set displayGroup [SharedData_getExpGroupDisplay ${exp_path}]
   set expGroupBoxTag [DisplayGrp_getGroupExpBoxTagName ${displayGroup}]
   
   set currentCoords [Overview_getRunBoxBoundaries  ${canvas} ${exp_path} ${datestamp}]   
   set currentStatus [OverviewExpStatus_getLastStatus ${exp_path} ${datestamp}]
   set expBoxTag [Overview_getExpBoxTag ${exp_path} ${datestamp} ${currentStatus}]
   set startCoords [${canvas} coords ${expBoxTag}.start]
   ::log::log debug "Overview_ExpCreateReferenceBox ${exp_path} startCoords:${startCoords}"
   set refEndTime [Overview_getRefTimings ${exp_path} [Utils_getHourFromDatestamp ${datestamp}]  end]
   ::log::log debug "Overview_ExpCreateReferenceBox refEndTime:$refEndTime"
   set startX [Overview_getXCoordTime ${timevalue}]
   set outlineColor [::DrawUtils::getOutlineStatusColor ${currentStatus}]


   if { [${canvas} coords ${expBoxTag}.middle] == "" } {
      set startX [lindex ${startCoords} 2]
   }
   set endX [Overview_getXCoordTime ${refEndTime}]

   set startY [expr [DisplayGrp_getCurrentSlotY [lindex ${startCoords} 1]] + 2 ]
   set endY [expr ${startY} + ${expEntryHeight} - 3 ]

   # create the ref box
   ${canvas} delete ${expBoxTag}.reference
   if { ${late_reference} == "true" } {
         ${canvas} itemconfigure ${expBoxTag}.text -fill DarkViolet
   } else {
      set refBoxId [${canvas} create rectangle ${startX} ${startY} ${endX} ${endY} -width 1 \
         -dash { 4 3 } -outline ${outlineColor} -tags "${expGroupBoxTag} ${exp_path} ${expBoxTag} ${expBoxTag}.reference"]

      if { [${canvas} coords ${expBoxTag}.middle] != "" } {
         ${canvas} lower ${expBoxTag}.reference  ${expBoxTag}.middle
      }
   }
}

# create a box from the end of the start icon up to the timevalue
# this middle box is used to show the progression of a running exp
proc Overview_ExpCreateMiddleBox { canvas exp_path datestamp timevalue {shift_day false}  {dummy_box false} } {
   ::log::log debug "Overview_ExpCreateMiddleBox ${exp_path} ${datestamp} ${timevalue} shift_day:${shift_day}"
   global expEntryHeight startEndIconSize expBoxOutlineWidth
   set displayGroup [SharedData_getExpGroupDisplay ${exp_path}]
   set expGroupBoxTag [DisplayGrp_getGroupExpBoxTagName ${displayGroup}]
   set currentStatus [OverviewExpStatus_getLastStatus ${exp_path} ${datestamp}]
   set expBoxTag [Overview_getExpBoxTag ${exp_path} ${datestamp} ${currentStatus}]
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
      set startY [expr [DisplayGrp_getCurrentSlotY [lindex ${startIconCoords} 1]] + 2 ]
      set endY [expr ${startY} + ${expEntryHeight} - 3 ]
   
      set middleBoxId [$canvas create rectangle ${startX} ${startY} ${endX} ${endY} -width ${expBoxOutlineWidth} \
         -outline ${outlineColor} -fill white -tags "${expGroupBoxTag} ${exp_path} ${expBoxTag} ${expBoxTag}.middle"]

      set datestampHour [Utils_getHourFromDatestamp ${datestamp}]
      $canvas lower ${expBoxTag}.middle ${expBoxTag}.text
      set list_tag [list $canvas ${expBoxTag} ${exp_path} ${datestamp}]

      $canvas bind $middleBoxId      <Button-1>        [list Overview_togglemsgbarCallback ${exp_path} ${datestamp} true ${list_tag}]
      $canvas bind ${expBoxTag}.text <Button-1>        [list Overview_togglemsgbarCallback ${exp_path} ${datestamp} true ${list_tag}]
      $canvas bind canvas_bg_image   <ButtonPress-1>   [list Overview_togglemsgbarCallback ${exp_path} ${datestamp} false ${list_tag}]
      $canvas bind grid_item         <ButtonPress-1>   [list Overview_togglemsgbarCallback ${exp_path} ${datestamp} false ${list_tag}]
   }
}

proc Overview_expDoubleClickCallback { exp_path datestamp datestamp_hour } {
   global EXP_BOX_SELECT_AFTER_ID EXP_BOX_LAUNCH_AFTER_ID
   # cancel exp selection on mouse click 
   catch { after cancel ${EXP_BOX_SELECT_AFTER_ID} }
   catch { after cancel ${EXP_BOX_LAUNCH_AFTER_ID} }
   set EXP_BOX_LAUNCH_AFTER_ID [ after 100 [list Overview_launchExpFlow ${exp_path} ${datestamp} ${datestamp_hour}]]
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

# return the list of tags in the overview canvas that are used to
# check for box collision.
# The list contains boxes that have a specific datestamp i.e. yyyymmddhh0000
# and default tags for experiment that have reference timings i.e. default_00, default_06, default_12 ....
# and or the default for experiments withouth any reference timings.
proc Overview_getExpBoxTags { canvas exp_path } {
   set expBoxTags [OverviewExpStatus_getDatestamps ${exp_path}]
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

proc Overview_isExpBoxObsolete { exp_path datestamp } {
   ::log::log debug "Overview_isExpBoxObsolete $exp_path $datestamp"
   if { ${datestamp} == "default" } {
      # puts "Overview_isExpBoxObsolete exp_path:${exp_path} datestamp:${datestamp}"
      return false
   }

   set endTime [OverviewExpStatus_getEndTime  ${exp_path} ${datestamp}]
   # puts "Overview_isExpBoxObsolete $exp_path endTime:$endTime"
   set xoriginDateTime [Overview_GraphGetXOriginDateTime]
   set currentStatus [OverviewExpStatus_getLastStatus ${exp_path} ${datestamp}]

   set isObsolete false
   ::log::log debug "Overview_isExpBoxObsolete $exp_path $datestamp currentStatus:${currentStatus}"
   if { ${currentStatus} == "end" } {
      set endDateTime [OverviewExpStatus_getStatusClockValue ${exp_path} ${datestamp} end]
      ::log::log debug "Overview_isExpBoxObsolete $exp_path $datestamp endDateTime:${endDateTime} xoriginDateTime:${xoriginDateTime}"
      if { [expr ${endDateTime} <= ${xoriginDateTime}] } {
         set isObsolete true
      }
   } else {
      if { [LogMonitor_isLogFileObsolete  ${exp_path} ${datestamp}] == true } {
         # log file has not been modified since 12 hours... This is mainly to care of exp like
	 # preop where there might not be any status at all for the top node...
	 # they still need to be cleared at some point...
         set isObsolete true
      }
   }

   ::log::log debug "Overview_isExpBoxObsolete $exp_path $datestamp isObsolete:$isObsolete"
   return ${isObsolete}
}

proc Overview_addExpDefaultBoxes { canvas exp_path {myhour ""} } {
   # puts "Overview_addExpDefaultBoxes $exp_path"
   if { [SharedData_getExpShowExp ${exp_path}] == false } {
      # this is a configuration from ExpOptions.xml
      # user decided that this suite not be shown in overview i.e. mainly used for default suite
      # puts "Overview_addExpDefaultBoxes skipping ${exp_path}"
      return
   }

   set refTimings [SharedData_getExpTimings ${exp_path}]
   if { ${refTimings} == "" } {
      # exp withouth ExpOptions.xml or withouth any ref timings
      Overview_updateExpBox ${canvas} ${exp_path} default init
   } else {
      foreach refTiming ${refTimings} {
         foreach { hour startTime endTime } ${refTiming} {
	    set scheduledDatestamp [Overview_getScheduledInfo ${exp_path} ${hour} ${startTime} datestamp]
	    set isExpBoxActive [Overview_isExpBoxActive ${canvas} ${exp_path} ${scheduledDatestamp}]
	    # if there is already a box active for the datestamp, no need for a default box
	    if { ${isExpBoxActive} == false } {
	       if { ${myhour} != "" } {
	          if { ${hour} == ${myhour} && [Overview_isExpScheduled ${exp_path} ${hour} ${startTime}] == true } {
                     Overview_updateExpBox ${canvas} ${exp_path} default_${hour} init
	          }
               } else {
	           if { [Overview_isExpScheduled ${exp_path} ${hour} ${startTime}] == true } {
		      # puts "Overview_updateExpBox ${canvas} ${exp_path} default_${hour} init"
                      Overview_updateExpBox ${canvas} ${exp_path} default_${hour} init
                   }
	       }
	    }
         }
      }
   }
}

# check if the exp box should be displayed in the overview
proc Overview_isExpScheduled { exp_path hour start_time } {
   global DayOfWeekMapping 

   # by default it runs
   set isScheduled true
   
   if [ catch {

   if { ! [info exists DayOfWeekMapping] } {
      set DayOfWeekMapping { Sun 0 Mon 1 Tue 2 Wed 3 Thu 4 Fri 5 Sat 6 }
   }
   ::log::log debug "Overview_isExpScheduled exp_path:$exp_path hour:${hour} start_time:${start_time} scheduledDatestamp:?"
   set scheduledDatestamp [Overview_getScheduledInfo ${exp_path} ${hour} ${start_time} datestamp]
   ::log::log debug "Overview_isExpScheduled exp_path:$exp_path hour:${hour} scheduledDatestamp:$scheduledDatestamp"
   if { ${scheduledDatestamp} != "" } {
     # get day of week schedule for the exp
     set scheduleType [SharedData_getExpScheduleType ${exp_path}]
     set scheduleInfo [SharedData_getExpScheduleValue ${exp_path}]
     if { ${scheduleInfo} != "" && ${scheduleType} != "" } {
        set isScheduled false
        if { ${scheduleType} == "DAY_OF_WEEK" } {
           # get day of week for datestamp
           # value is like Mon, Tue, Wed... Sun
           set dayOfWeekString [clock format [clock scan ${scheduledDatestamp} -format "%Y%m%d%H0000"] -format %a]
           set dayOfWeekInt [string map ${DayOfWeekMapping} ${dayOfWeekString}]
	   if { [lsearch ${scheduleInfo} ${dayOfWeekInt}] != -1 } {
	      set isScheduled true
	   }
	}
	::log::log debug "Overview_isExpScheduled exp_path:$exp_path hour:${hour} scheduleType:$scheduleType scheduleInfo;$scheduleInfo isScheduled:$isScheduled"
     }
   }

   } message ] {
      puts stderr "Overview_isExpScheduled ERROR: exp_path:$exp_path hour:$hour message:$message"
      ::log::log debug "Overview_isExpScheduled exp_path:$exp_path hour:$hour"
   }

   return ${isScheduled}
}

proc Overview_addExpDefaultBox { canvas exp_path datestamp } {
   # puts "Overview_addExpDefaultBox $exp_path $datestamp"
   set refTimings [SharedData_getExpTimings ${exp_path}]
   if { ${refTimings} != "" } {
      set hour         [Utils_getHourFromDatestamp ${datestamp}]
      set refStartTime [Overview_getRefTimings ${exp_path} ${hour} start]
      set refEndTime   [Overview_getRefTimings ${exp_path} ${hour}  end]
      if { ${refStartTime} != "" && ${refEndTime} != "" } {
         Overview_ExpCreateStartIcon ${canvas} ${exp_path} default_${hour} ${refStartTime} true
         Overview_ExpCreateMiddleBox ${canvas} ${exp_path} default_${hour} ${refEndTime} true
         Overview_ExpCreateEndIcon ${canvas} ${exp_path} default_${hour} ${refEndTime} true
      }
   } else {
      # for default box without ref timings, only add if no other boxes active
      if { [llength [Overview_getExpBoxTags ${canvas} ${exp_path}]] == 0 } {
         set originDateTime [Overview_GraphGetXOriginTime]
         Overview_ExpCreateStartIcon ${canvas} ${exp_path} default ${originDateTime} true
      }
   }
}

proc Overview_removeExpBox { canvas exp_path datestamp status } {
   # ::log::log notice "Overview_removeExpBox ${exp_path} ${datestamp} ${status}"

   # puts "Overview_removeExpBox $canvas $exp_path datestamp:$datestamp status:$status"
   set expBoxTag [Overview_getExpBoxTag ${exp_path} ${datestamp} ${status}]
   ${canvas} delete ${expBoxTag}.text
   ${canvas} delete ${expBoxTag}.start
   ${canvas} delete ${expBoxTag}.middle
   ${canvas} delete ${expBoxTag}.reference
   ${canvas} delete ${expBoxTag}.end
   ${canvas} delete ${expBoxTag}.late_line

   # do we need to delete the default box?
   if { ! [string match "default*" ${datestamp}] } {
      set hour [Utils_getHourFromDatestamp ${datestamp}]
      set schedDatestamp [Overview_getScheduledInfo ${exp_path} ${hour}]
      # ::log::log notice "Overview_removeExpBox ${exp_path} datestamp:${datestamp} schedDatestamp:$schedDatestamp"
      # delete the default box only if the datestamp matches the one that should be launched
      # for instance if I resubmit a run from yesterday's datestamp, the default one for today
      # should be untouched
      # The default box is also deleted if the exp does not use daily datestamp i.e. for exps
      # like geps reforecast & reforecast_stat
      if { ${datestamp} == ${schedDatestamp} || [SharedData_getExpIsDailyDatestamp ${exp_path}] == false } {
         # ::log::log notice "Overview_removeExpBox ${exp_path} datestamp:${datestamp} schedDatestamp:$schedDatestamp deleting default"
         # try delete default_${hour} tag
         set expBoxTag [Overview_getExpBoxTag ${exp_path} ${datestamp} default]
         # puts "Overview_removeExpBox deleting ${expDefaultTag}"
         ${canvas} delete ${expBoxTag}.text
         ${canvas} delete ${expBoxTag}.start
         ${canvas} delete ${expBoxTag}.middle
         ${canvas} delete ${expBoxTag}.reference
         ${canvas} delete ${expBoxTag}.end
         ${canvas} delete ${expBoxTag}.late_line
      }
   }

}

proc Overview_removeAllExpBoxes { canvas exp_path } {
   ${canvas} delete ${exp_path}
}

# locates and point to an exp/datestamp box in the overview grid
proc Overview_isExpBoxActive { canvas_w exp_path datestamp {isDefault false}} {
   ::log::log debug "Overview_isExpBoxActive exp_path:${exp_path} datestamp:${datestamp}"
   set isActive false
   if { ${isDefault} == true } {
      set currentStatus default
   } else {
      set currentStatus [OverviewExpStatus_getLastStatus ${exp_path} ${datestamp}]
   }

   set expBoxTag [Overview_getExpBoxTag ${exp_path} ${datestamp} ${currentStatus}]
   if { [${canvas_w} gettags ${expBoxTag}] != "" } {
      set isActive true
   }
   return ${isActive}
}

# if an exp is executing (begin state), this function is called every minute
# to update the exp status
proc Overview_updateExpBox { canvas exp_path datestamp status { timevalue "" } } {
   ::log::log debug "Overview_updateExpBox exp_path:$exp_path datestamp:$datestamp status:$status time:$timevalue"
   global startEndIconSize
   after cancel [SharedData_getExpOverviewUpdateAfterId ${exp_path} ${datestamp}]
   set continueStatus ""
   set currentDateTime [clock seconds]
   set currentTime [clock format ${currentDateTime} -format "%H:%M" -gmt 1]

   if { ${timevalue} == "" } {
      set timevalue ${currentTime}
   }

   ::log::log debug "Overview_updateExpBox exp_path:$exp_path datestamp:$datestamp status:$status time:$timevalue updating..."

   array set statusUpdateMap {
      init "Overview_processInitStatus"
      submit "Overview_processSubmitStatus"
      begin "Overview_processBeginStatus continue_begin"
      beginx "Overview_processBeginStatus continue_begin"
      continue_begin "Overview_processBeginStatus continue_begin"
      continue_wait "Overview_processWaitStatus continue_wait"
      end "Overview_processEndStatus"
      abort "Overview_processAbortStatus"
      catchup "Overview_processCatchupStatus"
      wait "Overview_processWaitStatus continue_wait"
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
      if { [string match "default*" ${datestamp}] } {
         Overview_addExpDefaultBox ${canvas} ${exp_path} ${datestamp}
      } elseif { [Overview_isExpBoxObsolete ${exp_path} ${datestamp}] == true } {
         # the box becomes history, don't need it anymore
	 ::log::log notice "Overview_updateExpBox() OverviewExpStatus_addObsoleteDatestamp ${exp_path} ${datestamp}"
	 OverviewExpStatus_addObsoleteDatestamp ${exp_path} ${datestamp}
         set datestamp [file tail [Overview_getExpBoxTag ${exp_path} ${datestamp} default false]]

	 set continueStatus ""
      } else {
         ${statusProc} ${canvas} ${exp_path} ${datestamp} ${status}
      }

      set newcoords [Overview_getRunBoxBoundaries ${canvas} ${exp_path} ${datestamp}]
      if { ${newcoords} != "" } {
         set newx1 [lindex ${newcoords} 0]
         set newx2 [lindex ${newcoords} 2]
         set newy1 [lindex ${newcoords} 1]
         set newy2 [lindex ${newcoords} 3]
         # resolve any collision with existings exp boxes
         Overview_resolveLocation ${canvas} ${exp_path} ${datestamp} ${newx1} ${newy1} ${newx2} ${newy2}
      }
      Overview_setExpTooltip ${canvas} ${exp_path} ${datestamp}
      set currentStatus [OverviewExpStatus_getLastStatus ${exp_path} ${datestamp}]
      set expBoxTag     [Overview_getExpBoxTag ${exp_path} ${datestamp} ${currentStatus}]
      set list_tag      [list $canvas ${expBoxTag} ${exp_path} ${datestamp}]

      set datestampHour [Utils_getHourFromDatestamp ${datestamp}]
      if { [string match "default*" ${datestamp}] } {
         $canvas bind ${expBoxTag}      <Double-Button-1> [list Overview_expDoubleClickCallback ${exp_path} "" ${datestampHour}]
         $canvas bind ${expBoxTag}.text <Double-Button-1> [list Overview_expDoubleClickCallback ${exp_path} "" ${datestampHour}]
      } else {
         $canvas bind ${expBoxTag}      <Double-Button-1> [list Overview_expDoubleClickCallback ${exp_path} ${datestamp} ""]
         $canvas bind ${expBoxTag}.text <Double-Button-1> [list Overview_expDoubleClickCallback ${exp_path} ${datestamp} ""]
      }
      $canvas bind ${exp_path}.${datestamp} <Button-1>        [ list Overview_togglemsgbarCallback ${exp_path} ${datestamp} true ${list_tag}]
      $canvas bind ${exp_path}.${datestamp} <Button-3>        [ list Overview_boxMenuCallback $canvas ${exp_path} ${datestamp} %X %Y]
   
      if { ${continueStatus} != "" } {
         set afterId [after 60000 [list Overview_updateExpBox ${canvas} ${exp_path} ${datestamp} ${continueStatus} ]]
         SharedData_setExpOverviewUpdateAfterId ${exp_path} ${datestamp} ${afterId}
      }
   }
   ::log::log debug "Overview_updateExpBox exp_path:$exp_path datestamp:$datestamp status:$status time:$timevalue DONE"
}

# this function places exp run boxes on the same y slot if there is enough space for it
# NOTE: not used right now
proc Overview_OptimizeExpBoxes { displayGroup } {
   ::log::log debug "Overview_OptimizeExpBoxes..."

   set canvasW [Overview_getCanvas]

   set expList [$displayGroup cget -exp_list]
   foreach exp $expList {
      # get the list of datestamps
      set datestamps [OverviewExpStatus_getDatestamps ${exp}]

      foreach expDatestamp ${datestamps} {
         set newcoords [Overview_getRunBoxBoundaries ${canvasW} ${exp} ${expDatestamp}]
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
                  set overlapCoords [Overview_resolveOverlap ${canvasW} ${exp} ${expDatestamp} ${newx1} ${newy1} ${newx2} ${newy2}]
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
                     if { [expr ${ySlotStart} == [${displayGroup} cget -max_y]] } {
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
proc Overview_resolveLocation { canvas exp_path datestamp x1 y1 x2 y2 } {
   global expEntryHeight
   ::log::log debug "Overview_resolveLocation exp_path:$exp_path datestamp:$datestamp x1:$x1 y1:$y1 x2:$x2 y2:$y2"
   set currentCoords "${x1} ${y1} ${x2} ${y2}"
   set displayGroup [SharedData_getExpGroupDisplay ${exp_path}]
   set overlapCoords [Overview_resolveOverlap ${canvas} ${exp_path} ${datestamp} ${x1} ${y1} ${x2} ${y2}]
   if { [Utils_isListEqual ${currentCoords} ${overlapCoords}] == "false" } {
      ::log::log debug "Overview_resolveLocation exp_path:$exp_path currentCoords: ${currentCoords} overlapCoords:${overlapCoords} datestamp:${datestamp}"

      set deltax [expr [lindex $overlapCoords 0] - ${x1}]
      set deltay [expr [lindex $overlapCoords 1] - ${y1}]
      $canvas move ${exp_path}.${datestamp} ${deltax} ${deltay}
      ::log::log debug "Overview_resolveLocation $canvas move ${exp_path}.${datestamp} ${deltax} ${deltay}"
      ::log::log debug "Overview_resolveLocation moving ${exp_path}.${datestamp} from $x1 $y1 $x2 $y2 to $overlapCoords"
      ::log::log debug "Overview_resolveLocation DisplayGrp_setMaxY  ${displayGroup} [lindex $overlapCoords 1]"
      DisplayGrp_setMaxY ${displayGroup} [lindex $overlapCoords 1]
      DisplayGrp_processOverlap ${displayGroup}
      # the new location is clear within its own group but
      # need to check if the new location overlaps with another display group
   }
   DisplayGrp_processEmptyRows ${displayGroup}
}

# this function is used to shift up a row exp boxes within an exp group 
# if the boxes are located below an empty row...
proc Overview_ShiftExpRow { display_group empty_slot_y } {
   global expEntryHeight

   ::log::log debug "Overview_ShiftExpRow $display_group $empty_slot_y"
   set expList [${display_group} cget -exp_list]
   set overviewCanvas [Overview_getCanvas]
   foreach exp ${expList} {
      set datestamps [OverviewExpStatus_getDatestamps ${exp}]
      foreach expDatestamp ${datestamps} {

         foreach {xx1 yy1 xx2 yy2} [Overview_getRunBoxBoundaries ${overviewCanvas} ${exp} ${expDatestamp}] { break }
         if { [info exists yy1] && ${yy1} != "" && ${yy1} > ${empty_slot_y} } {
            # y of exp is greater than empty box, shift it up
            ::log::log debug "Overview_ShiftExpRow ${display_group} shifting ${exp}.${expDatestamp} up"
            ${overviewCanvas} move ${exp}.${expDatestamp} 0 -${expEntryHeight}
         }
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
proc Overview_resolveOverlap { canvas exp_path datestamp x1 y1 x2 y2 } {
   ::log::log debug "Overview_resolveOverlap $exp_path datestamp:$datestamp x1:$x1 y1:$y1 x2:$x2 y2:$y2"
   global expEntryHeight
   set displayGroup [SharedData_getExpGroupDisplay ${exp_path}]
   set expList [${displayGroup} cget -exp_list]

   set currentExpBoxTag ${datestamp}
   # first check if the current run box collides with other run boxes of the
   # the same experiment
   set expBoxTags [Overview_getExpBoxTags ${canvas} ${exp_path}]
   ::log::log debug "Overview_resolveOverlap Overview_resolveOverlap expBoxTags:${expBoxTags}"
   foreach expBoxTag ${expBoxTags} {
      set isOverlap 0
      if { ${expBoxTag} != ${currentExpBoxTag} } {
         ::log::log debug "Overview_resolveOverlap ${expBoxTag} != ${currentExpBoxTag}"
         foreach {xx1 yy1 xx2 yy2} [Overview_getRunBoxBoundaries ${canvas} ${exp_path} ${expBoxTag}] { break }
         if { [info exists xx1] && "${xx1}" != "" } {
            set isOverlap [Utils_isOverlap $x1 $y1 $x2 $y2 $xx1 $yy1 $xx2 $yy2]
         }
      }
         ::log::log debug "Overview_resolveOverlap boundaries for $exp_path ${expBoxTag} [Overview_getRunBoxBoundaries ${canvas} ${exp_path} ${expBoxTag}]" 
      if { ${isOverlap} } {
         ::log::log debug "Overview_resolveOverlap FOUND OVERLAP? YES expBoxTag:$expBoxTag currentExpBoxTag:$currentExpBoxTag exp_path:$exp_path  $x1 $y1 $x2 $y2 $xx1 $yy1 $xx2 $yy2"
         # try to display the box in the next row
         set newy1 [expr ${y1} + ${expEntryHeight}]
         set newy2 [expr ${y2} + ${expEntryHeight}]
         ::log::log debug "Overview_resolveOverlap calling recursive Overview_resolveOverlap expBoxTag:${expBoxTag} ${x1} ${newy1} ${x2} ${newy2}"
         set newCoords [Overview_resolveOverlap ${canvas} ${exp_path} ${currentExpBoxTag} ${x1} ${newy1} ${x2} ${newy2}]
         ::log::log debug "Overview_resolveOverlap got new coords Overview_resolveOverlap ${newCoords}"
         return ${newCoords}
      }
   }

   # then check if it does not overlap with the rest of the run boxes of the other exps
   foreach exp $expList {
      set isOverlap 0
      if { ${exp} != ${exp_path} } {
         set expBoxTags [Overview_getExpBoxTags ${canvas} ${exp}]
         ::log::log debug "Overview_resolveOverlap ${exp} Overview_resolveOverlap expBoxTags2:${expBoxTags}"
         foreach expBoxTag ${expBoxTags} {
            set isOverlap 0
            ::log::log debug "Overview_resolveOverlap testing ${exp_path} collision with exp:$exp ???"
            set testedExpBox [Overview_getRunBoxBoundaries ${canvas} ${exp} ${expBoxTag}]
            if { [llength $testedExpBox] != 0 } {
               ::log::log debug "Overview_resolveOverlap exp:$exp testedExpBox:$testedExpBox"
               foreach {xx1 yy1 xx2 yy2} [Overview_getRunBoxBoundaries ${canvas} ${exp} ${expBoxTag}] { break }
               if { [info exists xx1] && "${xx1}" != "" } {
                  ::log::log debug "Overview_resolveOverlap xx1:$xx1 yy1:$yy1 xx2:$xx2 yy2:$yy2"
                  set isOverlap [Utils_isOverlap $x1 $y1 $x2 $y2 $xx1 $yy1 $xx2 $yy2]
               }
               ::log::log debug "Overview_resolveOverlap FOUND OVERLAP? $isOverlap"
            }
            if { ${isOverlap} } {
               ::log::log debug "Overview_resolveOverlap FOUND OVERLAP? YES exp:$exp testedExpBox:$testedExpBox with $exp_path"
               # try to display the box in the next row
               set newy1 [expr ${y1} + ${expEntryHeight}]
               set newy2 [expr ${y2} + ${expEntryHeight}]
               ::log::log debug "Overview_resolveOverlap calling recursive Overview_resolveOverlap ${x1} ${newy1} ${x2} ${newy2}"
               set newCoords [Overview_resolveOverlap ${canvas} ${exp_path} ${currentExpBoxTag} ${x1} ${newy1} ${x2} ${newy2}]
               ::log::log debug "Overview_resolveOverlap got new coords Overview_resolveOverlap ${newCoords}"
               return ${newCoords}
            }
         }
      }
   }

   ::log::log debug "Overview_resolveOverlap $exp_path datestamp:${datestamp}  returning $x1 $y1 $x2 $y2"

   return "$x1 $y1 $x2 $y2"
}

proc Overview_boxMenuCallback { canvas exp_path datestamp x y } {
   Overview_boxMenu ${canvas} ${exp_path} ${datestamp} $x $y
}

# this function is called to pop-up an exp node menu
proc Overview_boxMenu { canvas exp_path datestamp x y } {
   global env

   ::log::log debug "Overview_boxMenu() exp_path:$exp_path datestamp:${datestamp}"
   set currentStatus [OverviewExpStatus_getLastStatus ${exp_path} ${datestamp}]
   set expBoxTag [Overview_getExpBoxTag ${exp_path} ${datestamp} ${currentStatus}]
   set list_tag [list $canvas ${expBoxTag} ${exp_path} ${datestamp}]
   set datestampHour [Utils_getHourFromDatestamp ${datestamp}]
   if { [string match "default*" ${datestamp}] } {
      set datestamp ""
   }

   set popMenu .popupMenu
   if { [winfo exists $popMenu] } {
      destroy $popMenu
   }
   menu $popMenu -title [file tail ${exp_path}]  -tearoffcommand [list xflow_nodeMenuTearoffCallback]

   $popMenu add command -label "History" \
      -command [list Overview_historyCallback $canvas $exp_path ${datestamp} $popMenu]
   $popMenu add command -label "xflow" -command [list Overview_launchExpFlow $exp_path ${datestamp} ${datestampHour}]
   $popMenu add command -label "Open shell" -command [list Utils_launchShell $env(TRUE_HOST) $exp_path $exp_path "SEQ_EXP_HOME=${exp_path}"]
   $popMenu add command -label "Support" -command [list ExpOptions_showSupportCallback ${exp_path} ${datestamp} [Overview_getToplevel]]
   $popMenu add command -label "Reload Options" -command [list Overview_xmlOptionsCallback ${exp_path}]
   $popMenu add separator
   Overview_showPluginMenu ${popMenu} ${exp_path} ${datestamp}

    tk_popup $popMenu $x $y
   ::tooltip::tooltip $popMenu -index 0 "Show Exp History"
   # Overview_addMsgCenterWidget ${exp_path} ${datestamp} ${list_tag}
}

proc Overview_xmlOptionsCallback { exp_path } {
   ExpOptions_read ${exp_path} 
   Overview_redrawExp ${exp_path}
}

# this function loads the plugin menu items
proc Overview_showPluginMenu { parentMenu exp_path datestamp } {
    Utils_showPluginMenu "overview" ${parentMenu} ${exp_path} ${datestamp} ""
}

proc Overview_showSupportCallback { exp_path datestamp {caller_w .} } {
   ExpOptions_showSupport $exp_path [Utils_getHourFromDatestamp ${datestamp}] [winfo toplevel ${caller_w}]
}

# this function is called to show the history of an experiment
proc Overview_historyCallback { canvas exp_path datestamp caller_menu } {
   ::log::log debug "Overview_historyCallback exp_path:$exp_path datestamp:${datestamp}"
   set seqExec nodehistory
   if { ${datestamp} != "" } {
      # retrieve the last 30 days
      set seqNode [SharedData_getExpRootNode ${exp_path} ${datestamp}]
      set cmdArgs "-n $seqNode -edate ${datestamp} -history [expr 30*24]"
   } else {
      # retrieve all
      set seqNode [Overview_getExpRootNodeInfo ${exp_path}]
      set cmdArgs "-n $seqNode"
   }

   Sequencer_runCommandWithWindow $exp_path ${datestamp} [Overview_getToplevel] $seqExec "Node History ${exp_path}" bottom 0 ${cmdArgs}
}

# this function is called to launch an exp window
# It sends the request to the exp thread to care of it.
proc Overview_launchExpFlow { exp_path datestamp {datestamp_hour ""} } {
   global LIST_EXP

   ::log::log debug "Overview_launchExpFlow exp_path:$exp_path datestamp:$datestamp"
   ::log::log notice "Overview_launchExpFlow exp_path:$exp_path datestamp:$datestamp"
   puts "Overview_launchExpFlow exp_path:${exp_path} datestamp:${datestamp} "
   
   global PROGRESS_REPORT_TXT LAUNCH_XFLOW_MUTEX OVERVIEW_LAUNCH_EXP_AFTER_ID

   # lock execution of this proc... seems like this proc could be executed in multiple
   # instances at the same time even though it is only send/invoked within the main thread...
   # Since it is using global vars need to make sure the block below is ecxcuted in serial

   if { ! [info exists LAUNCH_XFLOW_MUTEX] } {
      set LAUNCH_XFLOW_MUTEX [thread::mutex create]
     ::log::log notice "Overview_launchExpFlow creating LAUNCH_XFLOW_MUTEX"
   }

   if [ catch { thread::mutex lock ${LAUNCH_XFLOW_MUTEX} } message ] {
      puts stderr "Overview_launchExpFlow ERROR locking mutex... trying again later" 
      after 500 Overview_launchExpFlow ${exp_path} ${datestamp}
      return
   }

   puts "Overview_launchExpFlow LOCKED exp_path:${exp_path} datestamp:${datestamp} "

   # make sure overview is visible
   wm deiconify [Overview_getToplevel]


   if { ${datestamp} == "" && ${datestamp_hour} != "" } {
      # user launched a flow without datestamp but with reference hour
      # We need to calculate the reference datestamp based on the
      # current date & time and the reference time of the run
      set datestamp [Overview_getScheduledInfo ${exp_path} ${datestamp_hour}]
      ::log::log debug "Overview_launchExpFlow got reference datestamp:${datestamp}"
   }

   xflow_init ${exp_path}

   set progressWidth 25
   set extraMsg ""
   if { ${datestamp} != "" } {
      set progressWidth 40
      set extraMsg "datestamp=[Utils_getVisibleDatestampValue ${datestamp} [SharedData_getMiscData DATESTAMP_VISIBLE_LEN]]"
   }
   set result [ catch {

      set isNewThread false
      set expThreadId [SharedData_getExpThreadId ${exp_path} ${datestamp}]
      if { ${expThreadId} == "" } {
         puts "Overview_launchExpFlow ThreadPool_getNextThread...  exp_path:${exp_path} datestamp:${datestamp}"
	 set expThreadId [ThreadPool_getNextThread]
         set isNewThread true
         puts "Overview_launchExpFlow SharedData_setExpThreadId exp_path:${exp_path} datestamp:${datestamp} threadid:${expThreadId}"
         SharedData_setExpThreadId ${exp_path} "${datestamp}" ${expThreadId}
      } else {
         puts "Overview_launchExpFlow got existing thread.. exp_path:${exp_path} datestamp:${datestamp}."
      }

      ::log::log notice "Overview_launchExpFlow launching progress bar..."
      set progressW  ${exp_path}_${datestamp}
      set progressW  [regsub -all {[\.]} ${progressW} _]
      set progressW .pd_${progressW}
      # set a 60 seconds timeout to kill the dialog in case it fails to grab the focus
      set OVERVIEW_LAUNCH_EXP_AFTER_ID [after 60000 [list Overview_launchExpTimeout ${exp_path} ${datestamp} ${datestamp_hour} ${isNewThread} ${progressW}]]

      if { [winfo exists ${progressW}] } {
         # this should not happen but keep note of it
         ::log::log notice "WARNING: Overview_launchExpFlow killing existing progress bar."
	 destroy ${progressW}
      }

      if { ! [winfo exists ${progressW}] } {
         ProgressDlg ${progressW} -title "Launch Exp Flow" -parent [Overview_getToplevel]  -textvariable PROGRESS_REPORT_TXT \
	    -width ${progressWidth} -stop cancel -command [list Overview_cancelLaunchExp ${exp_path} ${datestamp} ${isNewThread} ${progressW}]
         update idletasks
      }

      ::log::log notice "Overview_launchExpFlow launching progress bar DONE"
      catch { after cancel ${OVERVIEW_LAUNCH_EXP_AFTER_ID} }
      set PROGRESS_REPORT_TXT "Launching [file tail ${exp_path}] ${extraMsg}"
      # for some reason, I need to call the update for the progress dlg to appear properly
      update idletasks

      if { [thread::exists ${expThreadId}] } {
         # first time, reads the full data
	 # second time, it checks if data is cached i.e. read log starting from last read
	 set useLogCache [SharedData_getExpNodeLogCache ${exp_path} ${datestamp}] 
	 set readType refresh_flow
	 if { ${useLogCache} == true } {
	    set readType all
	 }
         ::log::log notice "Overview_launchExpFlow new exp thread: ${expThreadId}  calling LogReader_startExpLogReader... ${exp_path} ${datestamp} refresh_flow false ${useLogCache}"
         # thread::send -async ${expThreadId} "LogReader_startExpLogReader ${exp_path} \"${datestamp}\" refresh_flow false ${useLogCache}" LogReaderDone
         thread::send -async ${expThreadId} "LogReader_startExpLogReader ${exp_path} \"${datestamp}\" ${readType} false ${useLogCache}" LogReaderDone
         vwait LogReaderDone
	 # tell next read to use cache
	 SharedData_setExpNodeLogCache ${exp_path} ${datestamp} true
      }

      # launch flow only if user has not cancelled
      if { [winfo exists ${progressW}] } {
         if { [xflow_isWindowActive ${exp_path} ${datestamp}] == true } {
            ::log::log debug "Overview_launchExpFlow flow window already exists exp_path:${exp_path} datestamp: ${datestamp}"
            xflow_toFront [xflow_getToplevel ${exp_path} ${datestamp}]
         } else {
            ::log::log debug "Overview_launchExpFlow calling xflow_displayFlow exp_path:${exp_path} datestamp: ${datestamp}"
            xflow_displayFlow ${exp_path} ${datestamp} true
            ::log::log notice "Overview_launchExpFlow xflow_displayFlow exp_path:${exp_path} datestamp: ${datestamp} done"
         }
      }

      catch { 
         destroy ${progressW}
	 update idletasks
      }

   } message ]

   # any errors, put the cursor back to normal state
   if { ${result} != 0  } {
      ::log::log notice "Overview_launchExpFlow ERROR: ${message}"

      set einfo $::errorInfo
      set ecode $::errorCode
      catch { destroy ${progressW} }

      catch { thread::mutex unlock ${LAUNCH_XFLOW_MUTEX} }

      # report the error with original details
      return -code ${result} \
         -errorcode ${ecode} \
         -errorinfo ${einfo} \
         ${message}
   }
   catch { thread::mutex unlock ${LAUNCH_XFLOW_MUTEX} }
   puts "Overview_launchExpFlow UNLOCKED exp_path:${exp_path} datestamp:${datestamp} "
   puts "Overview_launchExpFlow exp_path:${exp_path} datestamp:${datestamp} DONE"
   lappend LIST_EXP [list ${exp_path} ${datestamp}]
}

proc Overview_launchExpTimeout { exp_path datestamp datestamp_hour is_new_thread progress_w} {

   ::log::log notice "Overview_launchExpTimeout exp_path:${exp_path} datestamp: ${datestamp}"

   Overview_cancelLaunchExp ${exp_path} ${datestamp} ${is_new_thread} ${progress_w}
   ::log::log notice "Overview_launchExpTimeout exp_path:${exp_path} datestamp: ${datestamp} DONE"
}

proc Overview_cancelLaunchExp { exp_path datestamp is_new_thread progress_w } {
   global OVERVIEW_LAUNCH_EXP_AFTER_ID
   global LAUNCH_XFLOW_MUTEX
   ::log::log notice "Overview_cancelLaunchExp exp_path:${exp_path} datestamp:${datestamp}"

   catch { after cancel ${OVERVIEW_LAUNCH_EXP_AFTER_ID} }
   catch { thread::mutex unlock ${LAUNCH_XFLOW_MUTEX} }
   catch { grab release ${progress_w} }
   catch { destroy  ${progress_w} }
   if { ${is_new_thread} == true } {
       set expThreadId [SharedData_getExpThreadId ${exp_path} ${datestamp}]
       Overview_releaseExpThread ${expThreadId} ${exp_path} ${datestamp}
   }
}

# the end time happened prior to the x origin time,
proc Overview_cleanDatestamp { exp_path datestamp } {
   ::log::log notice "Overview_cleanDatestamp exp_path:${exp_path} datestamp:${datestamp}"
   # register the datestamp for data cleanup
   OverviewExpStatus_addObsoleteDatestamp ${exp_path} ${datestamp}

   # remove msg center data
   set refreshMsgCenter false
   Overview_cleanExpMsgDatestamp ${exp_path} ${datestamp} ${refreshMsgCenter}

   ::log::log notice "Overview_cleanDatestamp exp_path:${exp_path} datestamp:${datestamp} DONE"
}

# this proc is called before releasing an exp thread to the thread pool
# it also cleans up flow related data
proc Overview_releaseExpThread { exp_thread_id exp_path datestamp } {
   ::log::log notice "Overview_releaseExpThread exp_thread_id:${exp_thread_id} exp_path:${exp_path} datestamp:${datestamp}"
   if { ${exp_thread_id} != "" } {
      xflow_quit ${exp_path} ${datestamp} true
      Overview_releaseLoggerThread ${exp_thread_id} ${exp_path} ${datestamp}
   }
}

# stops monitoring the datestamp log
proc Overview_releaseLoggerThread { exp_thread_id exp_path datestamp } {
   if { ${exp_thread_id} != "" } {
      ::log::log notice "Overview_releaseLoggerThread releasing inactive log exp=${exp_path} datestamp=${datestamp}"
      # ::thread::send -async ${exp_thread_id} "LogReader_removeMonitorDatestamp ${exp_path} ${datestamp}"
      # remove monitoring from the thread
      ::thread::send ${exp_thread_id} "LogReader_removeMonitorDatestamp ${exp_path} \"${datestamp}\""

      # remove heartbeat monitoring
      # Overview_removeHeartbeatDatestamp ${exp_thread_id} ${exp_path} ${datestamp}
      if { [SharedData_getMiscData STARTUP_DONE] == false } {
         ThreadPool_releaseThread ${exp_thread_id} ${exp_path} "${datestamp}"
      }
      SharedData_removeExpThreadId ${exp_path} ${datestamp}
      ::log::log notice "Overview_releaseLoggerThread releasing inactive log exp=${exp_path} datestamp=${datestamp} DONE"
   }
}

# At application startup, this function is called by each
# exp thread to notify the overview that it is done reading
# the exp log file... At startup, the overview waits for every exp thread
# to finish before proceeding...
proc Overview_childInitDone { exp_thread_id exp_path datestamp } {
   global EXP_THREAD_STARTUP_DONE ALL_CHILD_INIT_DONE STARTUP_PROGRESS_VALUE
   global STARTUP_PROGRESS_TXT
   ::log::log debug "Overview_childInitDone datestamp:${datestamp} exp_path:$exp_path"

   catch { unset EXP_THREAD_STARTUP_DONE(${exp_path}_${datestamp}) }
   incr STARTUP_PROGRESS_VALUE
   set STARTUP_PROGRESS_TXT "${exp_path} \n datestamp=${datestamp} loaded."

   # free up the thread to process another log at startup
   ThreadPool_releaseThread ${exp_thread_id}

   ::log::log debug "Overview_childInitDone ThreadPool_releaseThread ${exp_thread_id} DONE"

   # if log has not been modified for a while, we don't monitor it
   if { [LogMonitor_isLogFileActive ${exp_path} ${datestamp}] == false } {
      ::log::log debug "Overview_childInitDone Overview_releaseLoggerThread ${exp_thread_id} ${exp_path} ${datestamp}"
      Overview_releaseLoggerThread ${exp_thread_id} ${exp_path} ${datestamp}
   } else {
      # Overview_addHeartbeatDatestamp ${exp_path} ${datestamp}
   }

   # check if all startup threads are done reading
   if { [array names EXP_THREAD_STARTUP_DONE] != "" } {
      ::log::log debug "Overview_childInitDone not done: [array names EXP_THREAD_STARTUP_DONE]"
   } else {
      set ALL_CHILD_INIT_DONE 1
   }
}

proc Overview_getStartupNofDatestamps {} {
   global EXP_THREAD_STARTUP_DONE
   if { [array names EXP_THREAD_STARTUP_DONE] != "" } {
      return [array size EXP_THREAD_STARTUP_DONE]
   }
   return 0
}

proc Overview_addStartupDatestamp { exp_path datestamp } {
   global EXP_THREAD_STARTUP_DONE
   set EXP_THREAD_STARTUP_DONE(${exp_path}_${datestamp}) "${exp_path} ${datestamp}"
}

proc Overview_waitStartupDatestamps {} {
   global EXP_THREAD_STARTUP_DONE
   
   if { [array names EXP_THREAD_STARTUP_DONE] != "" } {
      ::log::log debug "Overview_waitStartupDatestamps ..."
      vwait ALL_CHILD_INIT_DONE
   }
}

# this function is called asynchronously by experiment child threads to
# update the status of an experiment node in the overview panel.
# See LogReader.tcl
proc Overview_updateExp { exp_thread_id exp_path datestamp status timestamp } {
   # puts "Overview_updateExp $exp_thread_id $exp_path $datestamp $status $timestamp"

   global AUTO_LAUNCH LIST_TAG
   ::log::log debug "Overview_updateExp exp_thread_id:$exp_thread_id ${exp_path} datestamp:$datestamp status:$status timestamp:$timestamp "
   # ::log::log debug "Overview_updateExp exp_thread_id:$exp_thread_id ${exp_path} datestamp:$datestamp status:$status timestamp:$timestamp "
   ::log::log notice "Overview_updateExp exp_thread_id:$exp_thread_id ${exp_path} datestamp:$datestamp status:$status timestamp:$timestamp "
   set canvas [Overview_getCanvas]
   # retrieve the date & time from the given time stamp
   set dateValue [Utils_getDateFromDatestamp ${timestamp}]
   set timeValue [Utils_getTimeFromDatestamp ${timestamp}]
   ::log::log debug "Overview_updateExp setLastStatusInfo $exp_path $datestamp $status $dateValue $timeValue"

   # store the info for current update
   OverviewExpStatus_setLastStatusInfo $exp_path $datestamp $status $dateValue $timeValue
   if { $status == "beginx" } {
      # beginx usually means that a task node that has aborted is restarted... we don't want 
      # the exp box to move everytime a task is restarted so we get the begin value and 
      set statusInfo [OverviewExpStatus_getStatusInfo ${exp_path} ${datestamp} begin]

      set timeValue [lindex ${statusInfo} 1]
      ::log::log debug "Overview_updateExp getStatusInfo $exp_path $datestamp status:begin statusInfo:${statusInfo}"
      ::log::log debug "Overview_updateExp getStatusInfo $exp_path $datestamp status:beginx statusInfo:[OverviewExpStatus_getStatusInfo ${exp_path} ${datestamp} beginx]"
   }

   if { [OverviewExpStatus_getLastStatusDateTime ${exp_path} ${datestamp}] >  [Overview_GraphGetXOriginDateTime] ||
        ( $status == "beginx" && [clock scan "${dateValue} ${timeValue}"] > [Overview_GraphGetXOriginDateTime] ) } {
      if { [winfo exists $canvas] } {
         set isStartupDone [SharedData_getMiscData STARTUP_DONE]
         # update exp box status
         if { ${isStartupDone} == "true" } {
            # check for box overlapping, auto-refresh, etc
            Overview_updateExpBox ${canvas} ${exp_path} ${datestamp} ${status} ${timeValue}
            ::log::log debug "Overview_updateExp Overview_updateExpBox DONE!"
            Overview_checkGridLimit
            ::log::log debug "Overview_updateExp Overview_checkGridLimit DONE!"
         }
         # launch the flow if needed... but not when the app is startup up
         if { $status == "begin" } {
            if { [SharedData_getExpAutoLaunch ${exp_path}] == true && ${AUTO_LAUNCH} == "true" \
	         && ${isStartupDone} == "true" } {
               ::log::log notice "exp begin detected for ${exp_path} datestamp:${datestamp} timestamp:${timestamp}"
               ::log::log notice "exp launching xflow window ${exp_path} datestamp:${datestamp}"
               Overview_launchExpFlow ${exp_path} ${datestamp}
            }
         } else {
            # change the exp colors
            Overview_refreshBoxStatus ${exp_path} ${datestamp}
         }
      } else {
         ::log::log debug "Overview_updateExp canvas $canvas does not exists!"
      }
   }
   Overview_HighLightFindNode ${LIST_TAG}
   ::log::log notice "Overview_updateExp exp_thread_id:$exp_thread_id ${exp_path} datestamp:$datestamp status:$status timestamp:$timestamp DONE"
   ::log::log debug "Overview_updateExp exp_thread_id:$exp_thread_id ${exp_path} datestamp:$datestamp status:$status timestamp:$timestamp DONE"
}

proc Overview_refreshExpLastStatus { exp_path datestamp } {
   set currentStatus [OverviewExpStatus_getLastStatus ${exp_path} ${datestamp}]
   set statusTime [OverviewExpStatus_getLastStatusTime ${exp_path} ${datestamp}]
   if { ${statusTime} != "" } {
      Overview_updateExpBox [Overview_getCanvas] ${exp_path} ${datestamp} ${currentStatus} ${statusTime}
   }
}

# checks whether the time grid is too small to hold all exp boxes,
# increase the grid if required
proc Overview_checkGridLimit {} {
   global expEntryHeight graphy defaultGraphY
   set displayGroups [ExpXmlReader_getGroups]
   set lastGroup [lindex ${displayGroups} end]
   if { ${lastGroup} != "" } {
      #puts "Overview_checkGridLimit last group y:[${lastGroup} cget -y] max_y:[${lastGroup} cget -max_y]"
      #puts "Overview_checkGridLimit grid max_y: [[Overview_getCanvas] coords grid_max_y]"
      set canvasW [Overview_getCanvas]
      # get the max y from the exp boxes
      set maxExpBoxY [${lastGroup} cget -max_y]
      # get the max y coord of the grid
      set maxGridCoords [${canvasW} coords grid_max_y]
      if { ${maxGridCoords} != "" } {
         set maxGridY [lindex ${maxGridCoords} 1]
         if { ${maxGridY} <= [expr ${maxExpBoxY} + ${expEntryHeight}] } {
            # grid is too small, increase it
            #puts "Overview_checkGridLimit adjust grid from ${maxGridY} to ${maxExpBoxY}"
            set graphy [expr ${maxExpBoxY} + ${expEntryHeight}/2]
            ::log::log debug "Overview_checkGridLimit expanding grid to graphy:$graphy"
            Overview_redrawGrid
         } elseif { ${graphy} > ${defaultGraphY} && ${graphy} >  [expr ${maxExpBoxY} + ${expEntryHeight}] } {
	    # shring the grid to default value
            ::log::log debug "Overview_checkGridLimit reducing grid to graphy:$graphy"
	    set graphy [expr ${maxExpBoxY} + ${expEntryHeight}/2]
            Overview_redrawGrid
	 }
      }
   }
}

proc Overview_redrawGrid {} {
   global expEntryHeight graphy defaultGraphY
   set canvasW [Overview_getCanvas]
   set groupCanvasW [Overview_getGroupDisplayCanvas]
   ${canvasW} delete grid_item
   ${groupCanvasW} delete grid_item

   Overview_createGraph
   ${canvasW} lower grid_item
   ${canvasW} lower canvas_bg_image
   Overview_setCurrentTime ${canvasW}
   Overview_setCanvasScrollArea
}

# sets the scrolll area of the overview grid
proc Overview_setCanvasScrollArea {} {
   global graphX graphStartX

   set canvasW [Overview_getCanvas]
   set groupCanvasW [Overview_getGroupDisplayCanvas]

   # set canvasBox [${canvasW} bbox canvas_bg_image]
   set canvasBox [${canvasW} bbox grid_item ]
   set groupCanvasBox [${groupCanvasW} bbox all]

   # puts "Overview_setCanvasScrollArea canvasBox:$canvasBox groupCanvasBox:$groupCanvasBox"
   set canvasX2 [lindex ${canvasBox} 2]
   set canvasY2 [lindex ${canvasBox} 3]
   set groupCanvasX2 [expr [lindex ${groupCanvasBox} 2] - 2]

   # setting the vertical scroll the same between the two canvas so that the scrolling is smooth between the two
   ${canvasW} configure -scrollregion [list 0 0 ${canvasX2} ${canvasY2}] -yscrollincrement 2 -xscrollincrement 5
   ${groupCanvasW} configure -scrollregion [list 0 0 [expr ${groupCanvasX2}] ${canvasY2}] -yscrollincrement 2 -xscrollincrement 5
}


# this function is called to add a new experiment to be monitored by the overview
proc Overview_addExp { display_group canvas exp_path } {
   ::log::log debug "Overview_addExp display_group:$display_group exp_path:$exp_path"
 
   set key [regsub -all " " ${exp_path} _]
   set key [regsub -all "/" ${key} _]
   set key [regsub -all {[\.]} ${key} _]
   SharedData_setExpData ${exp_path} EXP_PATH_KEY ${key}

   # create startup threads to process log datestamps
   # get the list of datestamps visible from the left side of the overview for this exp
   set visibleDatestamps [LogMonitor_getDatestamps ${exp_path} [expr -[SharedData_getMiscData LOG_SPAN_IN_HOURS]*60] ]

   ::log::log debug "Overview_addExp exp_path:$exp_path visibleDatestamps:$visibleDatestamps"

   if [ catch { ExpOptions_read ${exp_path} } message ] {
      set errMsg "Error Parsing ExpOptions.xml file ${exp_path}:\n$message"
      puts "${errMsg}"
      tk_messageBox -title "Application Error!" -type ok -icon error \
         -message ${errMsg}
      return
   }

   # build the list of valid datestamps
   foreach datestamp ${visibleDatestamps} {
      if { [Utils_validateRealDatestamp ${datestamp}] == true } {
         Overview_addStartupDatestamp ${exp_path} ${datestamp}
      }
   }

   # retrieve the exp root node
   SharedData_setExpGroupDisplay ${exp_path} ${display_group}
}

# reads all the datestamps at application startup time
proc Overview_readExpLogs {} {
   global EXP_THREAD_STARTUP_DONE
   set keyList [array names EXP_THREAD_STARTUP_DONE]
   foreach key ${keyList} {
      foreach {exp_path datestamp} [split $EXP_THREAD_STARTUP_DONE($key)] {}
      ::log::log debug "Overview_readExpLogs value:[split $EXP_THREAD_STARTUP_DONE($key)] exp_path:${exp_path} datestamp:${datestamp}"
      if { [Utils_validateRealDatestamp ${datestamp}] == true } {
         # get a thread from the pool... at startup the call waits if all threads are busy
	 # processing other logs
         set expThreadId [ThreadPool_getThread true]
         SharedData_setExpThreadId ${exp_path} "${datestamp}" ${expThreadId}
         OverviewExpStatus_addStatusDatestamp ${exp_path} ${datestamp}

         ::log::log debug "Overview_readExpLogs  thread::send -async ${expThreadId} \"LogReader_startExpLogReader ${exp_path} ${datestamp} all true\""
         thread::send -async ${expThreadId} "LogReader_startExpLogReader ${exp_path} ${datestamp} all true"
      }
   }
}

# this function returns a list of 4 coords x1 y1 x2 y2
# that are the boundaries of an exp box in the display.
# the boundaries values are based on the different items displayed
# for an exp datestamp box.
proc Overview_getRunBoxBoundaries { canvas exp_path datestamp } {

   set lastStatus default

   if { ! [string match "default*" ${datestamp}] } {
      set lastStatusTime [OverviewExpStatus_getLastStatusTime ${exp_path} ${datestamp}]
      set xoriginDateTime [Overview_GraphGetXOriginDateTime]

      set lastStatus [OverviewExpStatus_getLastStatus ${exp_path} ${datestamp}]
   }
   set expBoxTag [Overview_getExpBoxTag ${exp_path} ${datestamp} ${lastStatus}]
      ::log::log debug "Overview_getRunBoxBoundaries expBoxTag ${expBoxTag}"

   if { [${canvas} coords ${expBoxTag}] == "" } {
      ::log::log debug "Overview_getRunBoxBoundaries no boudaries found for ${exp_path}.${datestamp}"
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


# this function sets the exp box mouse over tooltip information.
# it is updated everytime the exp node root status changes
proc Overview_setExpTooltip { canvas exp_path datestamp } {
   ::log::log debug "Overview_setExpTooltip exp_path:${exp_path} datestamp:${datestamp}"
   # puts "Overview_setExpTooltip exp_path:${exp_path} datestamp:${datestamp}"

   # set expName [file tail ${exp_path}]
   set expName [SharedData_getExpShortName ${exp_path}]
   if { [string match "default*" ${datestamp}] } {
      set currentStatus default
      set currentStatusTime ""
   } else {
      set startTime [OverviewExpStatus_getStartTime ${exp_path} ${datestamp}]
      set endTime [OverviewExpStatus_getEndTime  ${exp_path} ${datestamp}]
      set currentStatus [OverviewExpStatus_getLastStatus ${exp_path} ${datestamp}]
      set currentStatusTime [OverviewExpStatus_getLastStatusTime ${exp_path} ${datestamp}]
   }

   set refStartTime [Overview_getRefTimings ${exp_path} [Utils_getHourFromDatestamp ${datestamp}] start]
   set refEndTime [Overview_getRefTimings ${exp_path} [Utils_getHourFromDatestamp ${datestamp}]  end]
   set tooltipText "name: ${expName}"
   if { ${refStartTime} != "" } {
      set tooltipText "name: ${expName}-[Utils_getHourFromDatestamp ${datestamp}]"
   }

   if { ${datestamp} != "" && ! [string match "default*" ${datestamp}] } {
      append tooltipText "\ndatestamp: [Utils_getVisibleDatestampValue ${datestamp} [SharedData_getMiscData DATESTAMP_VISIBLE_LEN]]"
   } else {
      if { ${datestamp} != "default" } {
      set schedDatestamp [Overview_getScheduledInfo ${exp_path} [Utils_getHourFromDatestamp ${datestamp}]]
      append tooltipText "\ndatestamp: [Utils_getVisibleDatestampValue ${schedDatestamp} [SharedData_getMiscData DATESTAMP_VISIBLE_LEN]]"
      }
   }
   if { ${refStartTime} != "" } {
      append tooltipText "\nref.begin: ${refStartTime}"
      append tooltipText "\nref.end: ${refEndTime}"
   }

   switch ${currentStatus} {
      "abort" {
         append tooltipText "\nbegin: ${startTime}"
         append tooltipText "\n${currentStatus}: ${currentStatusTime}"
      }
      "end" {
         append tooltipText "\nbegin: ${startTime}"
         append tooltipText "\n${currentStatus}: ${currentStatusTime}"
      }
      default {
         if { ! [string match "default*" ${currentStatus}] } {
            append tooltipText "\n${currentStatus}: ${currentStatusTime}"
         }
      }
   }
   set Abort  [Utils_getMsgCenter_Info ${exp_path} abort ${datestamp}]
   if { ${Abort} != "" } {
      append tooltipText "\nAbort: ${Abort}"
   }
   set Event  [Utils_getMsgCenter_Info ${exp_path} event ${datestamp}]
   if { ${Event} != "" } {
      append tooltipText "\nEvent: ${Event}"
   }
   set Info   [Utils_getMsgCenter_Info ${exp_path} info ${datestamp}]
   if { ${Info} != "" } {
      append tooltipText "\nInfo: ${Info}"
   }
   set Sysinfo  [Utils_getMsgCenter_Info ${exp_path} sysinfo ${datestamp}]
   if { ${Sysinfo} != "" } {
      append tooltipText "\nSysinfo: ${Sysinfo}"
   }
   set expBoxTag [Overview_getExpBoxTag ${exp_path} ${datestamp} ${currentStatus}]
   ::log::log debug "Overview_setExpTooltip exp_path:${exp_path} datestamp:${datestamp} currentStatus:${currentStatus} currentStatusTime:${currentStatusTime} expBoxTag:${expBoxTag}"

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
      set groupsToMove [lrange ${displayGroups} ${foundIndex} end]
      set canvasW [Overview_getCanvas]
      set groupCanvasW [Overview_getGroupDisplayCanvas]
      foreach displayGroup ${groupsToMove} {
         set groupTagName [DisplayGrp_getTagName ${displayGroup}]
	 set expBoxGroupTagName [DisplayGrp_getGroupExpBoxTagName ${displayGroup}]
         # set the new min and max if group exists
         if { [${groupCanvasW} gettags ${groupTagName}] != "" } {
            set newMin [expr [${displayGroup} cget -y] + ${delta_y}]
            set newMax [expr [${displayGroup} cget -max_y] + ${delta_y}]
            ${displayGroup} configure -y ${newMin}
            ${displayGroup} configure -max_y ${newMax}

            # move the group and exp boxes that belongs to it
            ::log::log debug "Overview_moveGroups ${canvasW} moving ${displayGroup} delta_y:${delta_y}"
            ${groupCanvasW} move ${groupTagName} ${delta_x} ${delta_y}
            ${canvasW} move ${expBoxGroupTagName} ${delta_x} ${delta_y}
         }
      }
   }
}

# lay out the group 
proc Overview_addGroup { canvas displayGroup } {
   global expEntryHeight

   # puts "Overview_addGroup displayGroup:${displayGroup}"
   set groupName [$displayGroup cget -name]

   # the tagName is used to refer the group in the canvas
   set tagName [DisplayGrp_getTagName ${displayGroup}]
   set groupLevel [$displayGroup cget -level]
   set groupEntryCurrentY [DisplayGrp_getGroupDisplayY ${displayGroup}]

   set deltaName ""
   if { [${displayGroup} cget -parent] != "" } {
      set deltaName "-"
   }

   set expEntryCurrentX [DisplayGrp_getGroupDisplayX ${displayGroup}]

   ::log::log debug "Overview_addGroup creating group:$groupName at location x:$expEntryCurrentX y:[expr $groupEntryCurrentY + $expEntryHeight/2]"
   $canvas create text $expEntryCurrentX [expr $groupEntryCurrentY + $expEntryHeight/2]  \
      -text "${deltaName}${groupName}" -justify left -anchor w -fill grey20 -tag "DisplayGroup ${tagName}"

   # get the font for each level
   set newFont [Overview_getLevelFont $canvas ${tagName} $groupLevel]

   $canvas itemconfigure ${tagName} -font $newFont

   DisplayGrp_setMaxX ${displayGroup}
   DisplayGrp_setSlotY ${displayGroup} ${groupEntryCurrentY}

   foreach grp [${displayGroup} cget -grp_list] {
      Overview_addGroup $canvas ${grp}
   }
}

proc Overview_addGroupExps { canvas } {
   global STARTUP_PROGRESS_VALUE STARTUP_PROGRESS_TXT

   set currentTime [clock seconds]
   set displayGroups [ExpXmlReader_getGroups]

   # lay out the exps on the grid
   foreach displayGroup $displayGroups {
      set expList [$displayGroup cget -exp_list]
      foreach exp $expList {
         Overview_addExp $displayGroup $canvas $exp
         Overview_addExpDefaultBoxes ${canvas} ${exp}
         LogMonitor_setLastCheckTime ${exp} ${currentTime}
      }
   }

   # nof datestamp log files to be loaded
   set progressMax [Overview_getStartupNofDatestamps]

   if { ${progressMax} > 0 } {
      # puts "Overview_addGroupExps: nof log files to be loaded: [array size EXP_THREAD_STARTUP_DONE]"
      # startup progress bar
      set STARTUP_PROGRESS_VALUE 0
      set progressBar [ProgressDlg .overview_progress \
       -title "Xflow_overview - Loading Experiments Data" -maximum ${progressMax} \
       -variable STARTUP_PROGRESS_VALUE -textvariable STARTUP_PROGRESS_TXT]
      wm geometry .overview_progress =600x200

      ${progressBar} configure -foreground blue

      # read all valid datestamp logs 
      Overview_readExpLogs

      # wait for all child to be done with their reads
      Overview_waitStartupDatestamps

      Overview_checkStartupError

      foreach displayGroup $displayGroups {
         set expList [$displayGroup cget -exp_list]
         foreach exp $expList {
            set datestamps [OverviewExpStatus_getDatestamps ${exp}]
            foreach datestamp ${datestamps} {
               set currentStatus [OverviewExpStatus_getLastStatus ${exp} ${datestamp}]
               set statusTime [OverviewExpStatus_getLastStatusTime ${exp} ${datestamp}]
	       if { ${statusTime} != "" } {
                  Overview_updateExpBox ${canvas} ${exp} ${datestamp} ${currentStatus} ${statusTime}
               }
	    }
         }
      }
      Overview_checkGridLimit
      destroy ${progressBar}
   }
}

# this procedure is called by exp threads when an error is detected
proc Overview_threadErrorCallback { threadId errorInfo } {
   global ALL_CHILD_INIT_DONE STARTUP_ERROR_MSG
   if { [SharedData_getMiscData STARTUP_DONE] == false } {
      set ALL_CHILD_INIT_DONE 1
      set STARTUP_ERROR_MSG ${errorInfo}
   }
}

# verify if any errors raised by exp threads at startup
proc Overview_checkStartupError {} {
   global STARTUP_ERROR_MSG
   if { [info exists STARTUP_ERROR_MSG] && ${STARTUP_ERROR_MSG} != "" } {
      tk_messageBox -title "Application Startup Error!" -type ok -icon error -parent [Overview_getToplevel] \
         -message "Application will exit!\n\n${STARTUP_ERROR_MSG}"
      exit
   }
}

# this function is a place holder to add logic to
# display different font for each level
proc Overview_getLevelFont { canvas item_tag level } {
    global LIST_FONT_LEVEL
    #puts "Overview_getLevelFont item_tag:$item_tag Lavel:$level"
   lappend LIST_FONT_LEVEL [list $canvas $item_tag $level ]
   set searchFont canvas_level_${level}_font
   if { [lsearch [font names] $searchFont] == -1 } {
      set canvasFont [$canvas itemcget "${item_tag}" -font]
      set newFont [font create canvas_level_${level}_font]
      font configure $newFont -family [font actual $canvasFont -family] \
         -size   [font actual $canvasFont -size] \
         -weight [font actual $canvasFont -weight] \
         -slant  [font actual $canvasFont -slant ]

      if { $level == 0 } {
         font configure $newFont  -weight bold
      }
   } else {
      font configure ${searchFont} -family [SharedData_getMiscData FONT_TASK] \
            -size   [SharedData_getMiscData FONT_TASK_SIZE] \
            -slant  [SharedData_getMiscData FONT_TASK_SLANT] \
            -underline [SharedData_getMiscData FONT_TASK_UNDERL]
   }

   return $searchFont
}

proc Overview_getBoxLabelFont {} {
   set labelFont canvas_exp_box_label_font
   if { [lsearch [font names] ${labelFont}] == -1 } {
      set newFont [font create ${labelFont}]
      set canvasW [Overview_getCanvas]
      font configure ${newFont} -family [font actual ${canvasW} -family] \
         -size   [font actual ${canvasW} -size] \
         -weight [font actual ${canvasW} -weight] \
         -slant  [font actual ${canvasW} -slant ]

      font configure ${newFont} -weight bold -size 10
   } else {
      font configure ${labelFont} -family [SharedData_getMiscData FONT_TASK] \
            -size   [SharedData_getMiscData FONT_TASK_SIZE] \
            -weight [SharedData_getMiscData FONT_TASK_STYLE] \
            -slant  [SharedData_getMiscData FONT_TASK_SLANT] \
            -underline [SharedData_getMiscData FONT_TASK_UNDERL]
   }

   return ${labelFont}
}

# this function creates the time grid in the
# specified canvas.
proc Overview_createGraph { } {
   global graphX graphy graphStartX graphStartY graphHourX expEntryHeight entryStartX

   set canvasW [Overview_getCanvas]
   set groupCanvasW [Overview_getGroupDisplayCanvas]

   # get the max x of the exp groupings to know where to position the grid, the y axe is created at the extreme end of the group canvas
   set groupDisplayMaxX [DisplayGrp_getAllGroupMaxX [Overview_getGroupDisplayCanvas]]

   # adds horiz shaded grid
   set x1 $entryStartX
   set x2  [expr $graphStartX + $graphX]
   set y1 $graphStartY
   set fillColor grey90
   set count 0
   set groupMaxX [expr ${groupDisplayMaxX} + 5]
   while { ${y1} < [expr $graphy + $graphStartY] } {
      # use a different color for each rectangle
      ${canvasW} create rectangle $x1 [expr $y1 ] $x2 [expr $y1 + $expEntryHeight ] -fill $fillColor -outline $fillColor -tag "grid_item"
      $groupCanvasW create rectangle $x1 [expr $y1 ] ${groupMaxX} [expr $y1 + $expEntryHeight ] -fill $fillColor -outline $fillColor -tag "grid_item"
      set y1 [expr $y1 + $expEntryHeight]
      if { $fillColor == "grey90" } {
         set fillColor grey95
      } else {
         set fillColor grey90
      }
      incr count
   }

   # creates hor lines at bottom & top
   ${canvasW} create line $graphStartX $graphStartY [expr $graphStartX + $graphX] $graphStartY -arrow last -tag "grid_item grid_min_y"
   ${canvasW} create line $graphStartX [expr $graphStartY + $graphy] \
      [expr $graphStartX + $graphX] [expr $graphStartY + $graphy] -arrow last -tags "grid_item grid_footer grid_max_y"

   # x axis title
   ${canvasW} create text [expr ${x2}/2 ] [expr $graphStartY + $graphy + 40] -text "Time (UTC)" -tag "grid_item grid_footer"
  
   # y axe origin
   # this is now created on the group canvas instead of the grid 
   # 
   set origX [expr ${groupDisplayMaxX} + 2]
   ${groupCanvasW} create line $origX [expr $graphStartY - 20] $origX [expr $graphStartY + $graphy] -arrow first -tag "grid_item grid_x_origin"
   ${groupCanvasW} create line $origX  [expr $graphStartY + $graphy] [expr $origX + 3] [expr $graphStartY + $graphy] -tag "grid_item grid_x_origin"
   
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
      Overview_GraphAddHourLine ${canvasW} ${count} ${hourTag}
      incr count
      incr hourTag
      if { ${hourTag} == "25" } {
         set hourTag 1
      }
   }

   # put the groups on top of the grid
   ${canvasW} lower grid_item DisplayGroup
   ${groupCanvasW} lower grid_item DisplayGroup
}

proc Overview_createSideToolbarIcons { parent_frame } {
   set imageDir [SharedData_getMiscData IMAGE_DIR]
   image create photo ${parent_frame}.msg_center_img -file ${imageDir}/open_mail_sh_16x16.png
   image create photo ${parent_frame}.msg_center_new_img -file ${imageDir}/open_mail_new_16x16.png
   image create photo ${parent_frame}.toggle_expand_top_img -file ${imageDir}/toggle_expand.png
   image create photo ${parent_frame}.toggle_top_img -file ${imageDir}/toggle.png

   set normMsgB [button ${parent_frame}.msg_center_b -image ${parent_frame}.msg_center_img -command [list MsgCenter_show true] -relief flat ]
   set newMsgB [button ${parent_frame}.msg_center_new_b -image ${parent_frame}.msg_center_new_img -command [list MsgCenter_show true] -relief flat ]
   set toggleTopB [button ${parent_frame}.toggle_top_b -image ${parent_frame}.toggle_top_img -command [list Overview_toggleToolbarCallback] -relief flat]
   set toggleExpandTopB [button ${parent_frame}.toggle_expand_top_b -image ${parent_frame}.toggle_expand_top_img -command [list Overview_toggleToolbarCallback] -relief flat]

   ::tooltip::tooltip ${normMsgB} "Show Message Center"
   ::tooltip::tooltip ${newMsgB} "Show Message Center"
   ::tooltip::tooltip ${toggleTopB} "Hide Toolbar & Menus"
   ::tooltip::tooltip ${toggleExpandTopB} "Show Toolbar & Menus"
}

proc Overview_toggleToolbarCallback {} {
   global SHOW_TOOLBAR
   if { ${SHOW_TOOLBAR} == true } {
      set SHOW_TOOLBAR false
   } else {
      set SHOW_TOOLBAR true
   }
   Overview_showToolbarCallback
}

proc Overview_toggleMessageIcons { parent_frame } {
   global OVERVIEW_HAS_NEW_MSG SHOW_TOOLBAR
   ::log::log debug "Overview_toggleMessageIcons SHOW_TOOLBAR:$SHOW_TOOLBAR OVERVIEW_HAS_NEW_MSG:$OVERVIEW_HAS_NEW_MSG"

   set normMsgB  ${parent_frame}.msg_center_b
   set newMsgB  ${parent_frame}.msg_center_new_b
   set toggleTopB  ${parent_frame}.toggle_top_b 
   set toggleExpandTopB ${parent_frame}.toggle_expand_top_b 

   # first hide them all
   grid forget ${normMsgB} ${newMsgB} ${toggleTopB} ${toggleExpandTopB}

   # then show the appropriate
   if { ${SHOW_TOOLBAR} == false } {
      # hide toolbar so show both icons
      grid ${toggleExpandTopB} -column 0 -row 0 -pady 1
      if { ${OVERVIEW_HAS_NEW_MSG} } {
         # show new msg icon
         grid ${newMsgB} -column 0 -row 1 -pady 1
      } else {
         grid ${normMsgB} -column 0 -row 1 -pady 1
      }
   } else {
      # toolbar is on so don't show msg center icon
      grid ${toggleTopB} -column 0 -row 0 -pady 1
   }
}

# checks if the starting point of an exp box in the overview
# has passed (to the left side of) the current timeline
proc Overview_isExpStartPassed { exp_path datestamp } {
   set isPassed false
   set canvasW [Overview_getCanvas]
   set coords [Overview_getRunBoxBoundaries  ${canvasW} ${exp_path} ${datestamp}]
   set timelineX [Overview_getCurrentTimeX]
   if { ${coords} != "" } {
      set coordX [lindex ${coords} 0]
      if { ${coordX} <= ${timelineX} } {
         set isPassed true
      }
   }
   return ${isPassed}
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

# returns the date as an init value of the date and time
# of the time hour displayed at x=end
proc Overview_GraphGetXEndDateTime {} {
   set endDateTime [clock add [clock seconds] +11 hours]
   set endDateTimeFormat [clock format ${endDateTime} -format {%Y-%m-%d %H}]
   set endDateTimeFormat ${endDateTimeFormat}:00:00
   set value [clock scan ${endDateTimeFormat}]
   return ${value}
}

# returns value of current day at 00Z
proc Overview_GraphGetCurrentDayTime {} {
   set currentTime [clock seconds]
   set currentDay00Z [clock format ${currentTime} -format {%Y-%m-%d}]
   set currentDay00Z "${currentDay00Z} 00:00:00"
   set value [clock scan ${currentDay00Z}]
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
   } else {
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

   # $canvas create text $x2 [expr $y1 - 20 ] -text $xLabel -tag "grid_item grid_hour ${tagHour}"
   # $canvas create text $x2 [expr $y2 + $graphy +20 ] -text $xLabel -tag "grid_item grid_hour ${tagHour} grid_footer"
   $canvas create text $x2 [expr $y1 - 8 ] -text $xLabel -tag "grid_item grid_hour ${tagHour}"
   $canvas create text $x2 [expr $y2 + $graphy +8 ] -text $xLabel -tag "grid_item grid_hour ${tagHour} grid_footer"

}

proc Overview_init {} {
   global env AUTO_LAUNCH FLOW_SCALE NODE_DISPLAY_PREF CHECK_EXP_IDLE SHOW_TOOLBAR OVERVIEW_HAS_NEW_MSG COLLAPSE_DISABLED_NODES
   global graphX graphy graphStartX graphStartY graphHourX expEntryHeight entryStartX entryStartY defaultGraphY
   global expBoxLength startEndIconSize expBoxOutlineWidth SHOW_MSGBAR LIST_TAG

   set SHOW_TOOLBAR [SharedData_getMiscData OVERVIEW_SHOW_TOOLBAR]
   puts "Overview_init SHOW_TOOLBAR:$SHOW_TOOLBAR"

   set OVERVIEW_HAS_NEW_MSG false
   set AUTO_LAUNCH [SharedData_getMiscData AUTO_LAUNCH]
   set CHECK_EXP_IDLE [SharedData_getMiscData OVERVIEW_CHECK_EXP_IDLE]
   set NODE_DISPLAY_PREF [SharedData_getMiscData NODE_DISPLAY_PREF]
   set FLOW_SCALE [SharedData_getMiscData FLOW_SCALE]
   set COLLAPSE_DISABLED_NODES [SharedData_getMiscData COLLAPSE_DISABLED_NODES]
   SharedData_setMiscData IMAGE_DIR $env(SEQ_XFLOW_BIN)/../etc/images

   set SHOW_MSGBAR false
   set LIST_TAG    ""

   puts "Overview_init Utils_logInit"
   Utils_logInit
   Utils_createTmpDir
   ::DrawUtils::initStatusImages


   # hor size of graph
   set graphX 1225
   # vert size of graph
   set graphy 400
   set defaultGraphY ${graphy}
   set graphStartX 0
   # set graphStartY 50
   set graphStartY 30
   # x size of each hour
   set graphHourX 48

   # y size of each entry on the left side of y axis
   set expEntryHeight 20

   set expBoxLength 40
   
   # creates suite entries
   set entryStartY ${graphStartY}
   set entryStartX 0

   set startEndIconSize 10

   set expBoxOutlineWidth 1.5
}

# this function reads an xml configuration file that
# lists the exp to be monitored
proc Overview_readExperiments {} {
   global env
   set suitesFile [SharedData_getMiscData SUITES_FILE]
   set suiteList {}
   if { [file exists $suitesFile] } {
      puts "Overview_readExperiments from file: $suitesFile"
      ::log::log debug "Overview_readExperiments date: [exec -ignorestderr date]"
      ExpXmlReader_readExperiments $suitesFile
      set suiteList [ExpXmlReader_getExpList]
      ::log::log debug "suiteList: $suiteList"
      ::log::log debug "Overview_readExperiments DONE date: [exec -ignorestderr -ignorestderr date]"
   } else {
      puts stderr "ERROR: file not found ${suitesFile}"
      Utils_fatalError . "Overview Startup Error" "${suitesFile} does not exists! Exiting..."
   }
}

proc Overview_quit {} {
   global TimeAfterId SESSION_TMPDIR
   ::log::log debug "Overview_quit"
   if { [info exists TimeAfterId] } {
      after cancel $TimeAfterId
   }

   set displayGroups [ExpXmlReader_getGroups]
   foreach displayGroup $displayGroups {
      set expList [$displayGroup cget -exp_list]
      foreach exp $expList {
      
         set datestamps [OverviewExpStatus_getDatestamps ${exp}]

         foreach datestamp ${datestamps} {
            set expThreadId [SharedData_getExpThreadId ${exp} ${datestamp}]
            Overview_releaseExpThread ${expThreadId} ${exp} ${datestamp}
         }
      }
   }
   ThreadPool_quit

   catch { 
      exec -ignorestderr rm -fr ${SESSION_TMPDIR}
      puts "exec rm -fr ${SESSION_TMPDIR}"
   }
   
   ::log::log notice "xflow_overview exited normally..."
   # destroy $top
   exit 0
}

proc Overview_parseCmdOptions {} {
   global argv env startupExp DISPLAY_GROUPS
   global AUTO_MSG_DISPLAY

   set startupExp ""
   if { [info exists argv] } {
      set options {
         {main ""}
         {debug "Turn debug on"}
         {exp.arg "" "experiment path"}
         {logfile.arg "" "App log file"}
         {noautomsg.arg "" "No automatic message display"}
         {suites.arg "" "suites definition file"}
         {user.arg "" "real user (before switching -as)"}
         {rc.arg "" "maestrorc preferrence file"}
         {logspan.arg "" "read the past ARGUMENT hours of logs, default is 14"}
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

         if { ! ($params(rc) == "") } {
            puts "Overview_parseCmdOptions using maestrorc file: $params(rc)"
         }

         SharedData_readProperties $params(rc)

         SharedData_setMiscData REAL_USER $env(USER)
         if { $params(user) != "" } {
            puts "Overview_parseCmdOptions real user is $params(user)"
            SharedData_setMiscData REAL_USER $params(user)
         } 

         if { $params(noautomsg) != "" } {
            puts "Overview_parseCmdOptions noautomsg argument is $params(noautomsg)"
	    if { $params(noautomsg) == 1 } {
               SharedData_setMiscData AUTO_MSG_DISPLAY false
            }
	 }


         if { $params(logspan) != "" } {
            SharedData_setMiscData LOG_SPAN_IN_HOURS $params(logspan)
	    # set the log span time threshold (useful for when to start checking submit late for an exp)
	    SharedData_setMiscData LOG_SPAN_THRESHOLD_TIME [clock add [clock seconds] -$params(logspan) hours]
         } else { 
            SharedData_setMiscData LOG_SPAN_IN_HOURS 14
	    SharedData_setMiscData LOG_SPAN_THRESHOLD_TIME [clock add [clock seconds] -14 hours]
         } 

         if { $params(debug) } {
            puts "Overview_parseCmdOptions DEBUG_TRACE 1"
            SharedData_setMiscData DEBUG_TRACE 1
         } 

	 SharedData_setDerivedColors
	 SharedData_setPlugins "overview"

	 set logDir [SharedData_getMiscData APP_LOG_DIR]
         if { $params(logfile) == "" && ${logDir} != "" } {
	    if { ! [file writable ${logDir}] } {
	       puts stderr "ERROR: cannot create application log file in directory ${logDir}!"
	       puts stderr "   Check the APP_LOG_DIR entry from your maestrorc file."
	       exit 0
	    }
	    # log in given log directory
            SharedData_setMiscData APP_LOG_FILE [SharedData_getMiscData APP_LOG_DIR]/xflow_overview_log.[exec -ignorestderr hostname].[pid]
         } else {
            SharedData_setMiscData APP_LOG_FILE $params(logfile)
	 }

         if { ! ($params(suites) == "") } {
            # command line arguments overwrites maestrorc file
            SharedData_setMiscData SUITES_FILE $params(suites)
         } elseif { [SharedData_getMiscData SUITES_FILE] == "" } {
            # if not defined in maestrorc, used a default one
            SharedData_setMiscData SUITES_FILE $env(HOME)/xflow.suites.xml
         }

         if { ! ($params(exp) == "") && $params(suites) == "" } {
	    set startupExp $params(exp)
	    xflow_validateExp ${startupExp}
	    DisplayGrp_createDefaultGroup ${startupExp}
            SharedData_setMiscData SUITES_FILE ""
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
   # force remove and redisplay of overview
   # Need to do this cause when the overview is in another virtual
   # desktop, it is the only way for it to redisplay in the
   # current desktop
   wm withdraw ${topW}
   wm deiconify ${topW}
   raise ${topW}
}

proc Overview_changeSettings { varName {name1 ""} {name2 ""} {op ""} } {
   global ${varName}
   ::log::log notice "${varName} change to [set ${varName}]"
}

proc Overview_addPrefMenu { parent } {
   global AUTO_MSG_DISPLAY AUTO_LAUNCH FLOW_SCALE NODE_DISPLAY_PREF CHECK_EXP_IDLE SUBMIT_POPUP COLLAPSE_DISABLED_NODES
   set menuButtonW ${parent}.pref_menub
   set menuW $menuButtonW.menu
   menubutton $menuButtonW -text Preferences -underline 0 -menu $menuW
   menu $menuW -tearoff 0

   set AUTO_LAUNCH [SharedData_getMiscData AUTO_LAUNCH]

   $menuW add checkbutton -label "Auto Launch" -variable AUTO_LAUNCH \
      -onvalue true -offvalue false
   trace add variable AUTO_LAUNCH write [list Overview_changeSettings AUTO_LAUNCH]

   set SUBMIT_POPUP [SharedData_getMiscData SUBMIT_POPUP]

   $menuW add checkbutton -label "Submit Popup" -variable SUBMIT_POPUP \
      -command [list xflow_setSubmitPopup] \
      -onvalue true -offvalue false

   set AUTO_MSG_DISPLAY [SharedData_getMiscData AUTO_MSG_DISPLAY]
   $menuW add checkbutton -label "Auto Message Display" -variable AUTO_MSG_DISPLAY \
      -command [list Overview_setAutoMsgDisplay] \
      -onvalue true -offvalue false
   trace add variable AUTO_MSG_DISPLAY write [list Overview_changeSettings AUTO_MSG_DISPLAY]
   ::tooltip::tooltip $menuW -index 1 "Automatic launch of flow when experiment starts"
   ::tooltip::tooltip $menuW -index 2 "Automatic message window on new alarm"


   $menuW add checkbutton -label "Check Exp Idle" -variable CHECK_EXP_IDLE \
      -onvalue true -offvalue false
   trace add variable CHECK_EXP_IDLE write [list Overview_changeSettings CHECK_EXP_IDLE]

   $menuW add checkbutton -label "Show Toolbar" -variable SHOW_TOOLBAR \
      -onvalue true -offvalue false -command [list Overview_showToolbarCallback]

   $menuW add checkbutton -label "Collapse Catchup State Nodes" -variable COLLAPSE_DISABLED_NODES \
      -onvalue true -offvalue false

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

proc Overview_showToolbarCallback {} {
   global SHOW_TOOLBAR

   set topOverview [Overview_getToplevel]
   set topFrame ${topOverview}.topframe
   set toolbarW ${topOverview}.toolbar
   if { ${SHOW_TOOLBAR} == true } {
       grid ${topFrame} -row 0 -column 1 -sticky nsew -padx 2
       grid ${toolbarW} -row 1 -column 1 -sticky nsew -padx 0
   } else {
      grid forget ${topFrame}
      grid forget ${toolbarW}
   }
   Overview_toggleMessageIcons [Overview_getVerticalToolbarFrame]
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
   # grid ${topFrame} -row 0 -column 0 -sticky nsew -padx 2
   # grid ${topFrame} -row 0 -column 1 -sticky nsew -padx 2
   grid ${topFrame} -row 0 -column 1 -sticky ew -padx 2
   Overview_addFileMenu ${topFrame}
   Overview_addPrefMenu ${topFrame}
   Overview_addHelpMenu ${topFrame}
   # Overview_createLabel ${topFrame}
}

# display is to right of menu as bold text
# NOT USED
proc Overview_createLabel { parentWidget } {
   set labelFrame [frame ${parentWidget}.label_frame]
   set labelW [label ${labelFrame}.label -font [xflow_getExpLabelFont] -text [DisplayGrp_getWindowsLabel]]
   # grid ${labelW} -sticky nesw
   grid ${labelW} -sticky ew 
   pack ${labelFrame} -side left -padx {20 0}
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
   global OVERVIEW_HAS_NEW_MSG

   ::log::log debug "Overview_newMessageCallback has_new_msg:$has_new_msg"
   set OVERVIEW_HAS_NEW_MSG ${has_new_msg}
   set msgCenterWidget .overview_top.toolbar.label.core.button_msgcenter
   set noNewMsgImage .overview_top.toolbar.label.core.msg_center_img
   set hasNewMsgImage .overview_top.toolbar.label.core.msg_center_new_img
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
   Overview_toggleMessageIcons [Overview_getVerticalToolbarFrame]
}

proc Overview_nodeDisplayCallback {} {
   global NODE_DISPLAY_PREF
   SharedData_setMiscData NODE_DISPLAY_PREF ${NODE_DISPLAY_PREF}
}

proc Overview_flowScaleCallback {} {
   global FLOW_SCALE
   SharedData_setMiscData FLOW_SCALE ${FLOW_SCALE}
}
# highlights a node that is selected with the find functionality
# by drawing a yellow rectangle around the node
proc Overview_HighLightFindNode { ll } {
   global LIST_TAG expBoxOutlineWidth expEntryHeight

   if { [llength ${ll}] > 0} {
     set selectColor        [SharedData_getColor FLOW_FIND_SELECT]
     set canvas             [lindex $ll 0]
     set expBoxTag          [lindex $ll 1]
     set exp_path           [lindex $ll 2]
     set datestamp          [lindex $ll 3]
     $canvas delete ${canvas}.find_select

     set boundaries [Overview_getRunBoxBoundaries ${canvas} ${exp_path} ${datestamp}] 
   # create a rectangle around the node
     set findBoxDelta 2
     set x1 [expr [lindex ${boundaries} 0] - ${findBoxDelta}]
     set y1 [DisplayGrp_getCurrentSlotY [lindex ${boundaries} 1]]
     set x2 [expr [lindex ${boundaries} 2] + ${findBoxDelta}]
     # set y2 [expr [lindex ${boundaries} 3] + ${findBoxDelta}]
     set y2 [expr ${y1} + ${expEntryHeight}]
   
     set selectTag ${canvas}.find_select
     # ${canvas} create rectangle ${x1} ${y1} ${x2} ${y2} -width  ${expBoxOutlineWidth} -fill ${selectColor} -tag ${selectTag}
     ${canvas} create rectangle ${x1} ${y1} ${x2} ${y2} -width 1 -fill ${selectColor} -tag ${selectTag} -outline grey
     ${canvas} lower ${selectTag} ${expBoxTag}
   }
   set LIST_TAG $ll
}

proc Overview_togglemsgbarCallback {exp_path datestamp show_msgbar ll} {
   global SHOW_MSGBAR EXP_BOX_SELECT_AFTER_ID

   # setting the exp box selection to be done only after 250 ms so that the double click can cancel the selection
   # otherwise, a double click will always select an exp box too
   catch { after cancel ${EXP_BOX_SELECT_AFTER_ID} }
   set EXP_BOX_SELECT_AFTER_ID [after 250 [list Overview_selectExpBox ${exp_path} ${datestamp} ${show_msgbar} ${ll}]]
}

proc Overview_selectExpBox { exp_path datestamp show_msgbar ll } {
   global SHOW_MSGBAR
   set topOverview [Overview_getToplevel]
   set toolbarW ${topOverview}.toolbar.msg_frame
   set SHOW_MSGBAR ${show_msgbar}
  
   if { ${SHOW_MSGBAR} == true } {
      Overview_addMsgCenterWidget ${exp_path} ${datestamp} ${ll}
      Overview_HighLightFindNode ${ll}
   } elseif { [winfo exists $toolbarW]} {
      set canvas    [lindex ${ll} 0]
      $canvas delete ${canvas}.find_select
      grid forget ${toolbarW}  
   }
}

# this function creates the widgets that allows
# the user to set/query the current datestamp
proc Overview_addMsgCenterWidget { exp_path datestamp ll} {
   ::log::log debug "Overview_addMsgCenterWidget $exp_path $datestamp"
   global datestamp_msgframe exp_path_frame

   set exp_path_frame      ${exp_path}
   set datestamp_msgframe  ${datestamp}
   set canvas    [lindex ${ll} 0]

   set expName [SharedData_getExpShortName ${exp_path}]
   set refStartTime [Overview_getRefTimings ${exp_path} [Utils_getHourFromDatestamp ${datestamp}] start]
  
   if { ${expName} != "" && ${refStartTime} != "" } {
     set labeltext "${expName}-[Utils_getHourFromDatestamp ${datestamp}]"
   } elseif {${expName} == "" && ${refStartTime} != ""} {
     set expName [SharedData_getExpDisplayName ${exp_path}]
     set labeltext "${expName}-[Utils_getHourFromDatestamp ${datestamp}]"
   } else {
     set labeltext "${expName}"
   }
  
   set topOverview [Overview_getToplevel]
   set msgFrame ${topOverview}.toolbar.msg_frame
   set labelFrame ${msgFrame}.msg_frame_label
   set labelCloseB ${labelFrame}.label_close_button
   set labelCloseImg  ${labelFrame}.label_close_image]
   set label_abortW ${labelFrame}.abort
   set label_eventW ${labelFrame}.event
   set label_infoW ${labelFrame}.info
   set label_sysinfoW ${labelFrame}.sysinfo

   if { ! [winfo exists ${msgFrame}] } {
      labelframe ${msgFrame}
      frame ${labelFrame}
      set imageDir [SharedData_getMiscData IMAGE_DIR]
      image create photo ${labelCloseImg} -file ${imageDir}/[xflow_getImageFile find_close_image_file]
      Button ${labelCloseB} -image ${labelCloseImg} -relief flat -command [list Overview_togglemsgbarCallback ${exp_path} ${datestamp} false $ll]
      tooltip::tooltip ${labelCloseB} "Close Message Center Info"

      foreach widget [list $label_abortW $label_eventW $label_infoW $label_sysinfoW] {
         label ${widget}
      }
   }
   ${msgFrame} configure -text "${labeltext} active message count"
   tooltip::tooltip ${msgFrame} "${labeltext} selected experiment has the following active (unacknowledged) messages"

   ${labelCloseB} configure -command [list Overview_togglemsgbarCallback ${exp_path} ${datestamp} false $ll]

   set newMsgColor [SharedData_getColor COLOR_MSG_CENTER_MAIN]
   set normalBgColor [option get ${label_abortW} background Label]
   set normalFgColor [option get ${label_abortW} foreground Label]

   set Abort  [Utils_getMsgCenter_Info ${exp_path} abort ${datestamp}]
   if { ${Abort} != "" } {
      set infoText  "Abort: ${Abort}"
      ${label_abortW} configure -justify center -text ${infoText} -bg $newMsgColor -fg white
   } else {
      set infoText  "Abort: 0"
      ${label_abortW} configure -justify center -text ${infoText} -bg ${normalBgColor} -fg ${normalFgColor}
   }

   set Event  [Utils_getMsgCenter_Info ${exp_path} event ${datestamp}]
   if { ${Event} != "" } {
      set infoText " Event: ${Event}"
      ${label_eventW} configure -justify center -text ${infoText} -bg $newMsgColor -fg white
   } else {
      set infoText " Event: 0"
      ${label_eventW} configure -justify center -text ${infoText} -bg ${normalBgColor} -fg ${normalFgColor}
   }
   set Info   [Utils_getMsgCenter_Info ${exp_path} info ${datestamp}]
   if { ${Info} != "" } {
      set infoText " Info: ${Info}"
      ${label_infoW} configure -justify center -text ${infoText} -bg $newMsgColor -fg white
   } else {
      set infoText " Info: 0"
      ${label_infoW} configure -justify center -text ${infoText} -bg ${normalBgColor} -fg ${normalFgColor}
   }
   set Sysinfo  [Utils_getMsgCenter_Info ${exp_path} sysinfo ${datestamp}]
   if { ${Sysinfo} != "" } {
      set infoText  " Sysinfo: ${Sysinfo}"
      ${label_sysinfoW} configure -justify center -text ${infoText} -bg $newMsgColor -fg white
   } else {
      set infoText " Sysinfo: 0"
      ${label_sysinfoW} configure -justify center -text ${infoText} -bg ${normalBgColor} -fg ${normalFgColor}
   }

   eval grid ${labelCloseB} $label_abortW ${label_eventW} ${label_infoW} ${label_sysinfoW} -sticky w -padx \[list 2 0\] 
   pack ${labelFrame} -pady 2 -side left
   grid ${msgFrame}  -row 0 -column 4 -sticky nsew -padx 2
}

proc Overview_createMsgCenterbar { _toplevelW } {
   # puts "Overview_createMsgCenterbar"
   variable infoText

   set nb_all     [OverviewExpMsgCenter_getactiveInfo all]
   set nb_abort   [OverviewExpMsgCenter_getactiveInfo abort]
   set nb_event   [OverviewExpMsgCenter_getactiveInfo event]
   set nb_info    [OverviewExpMsgCenter_getactiveInfo info]   
   set nb_sysinfo [OverviewExpMsgCenter_getactiveInfo sysinfo]
   set tt_all     [OverviewExpMsgCenter_gettotalInfo all]
   set tt_abort   [OverviewExpMsgCenter_gettotalInfo abort]
   set tt_event   [OverviewExpMsgCenter_gettotalInfo event]
   set tt_info    [OverviewExpMsgCenter_gettotalInfo info]   
   set tt_sysinfo [OverviewExpMsgCenter_gettotalInfo sysinfo]
   # create the frame to hold the core icons and plugin icons
   set msgbarFrame ${_toplevelW}.toolbar.msgbar
   # core icons is childe of main toolbar frame
   set labelFrame ${msgbarFrame}.msgbar_frame_label
   set label_totalW ${labelFrame}.total 
   set label_abortW ${labelFrame}.abort
   set label_eventW ${labelFrame}.event
   set label_infoW ${labelFrame}.info
   set label_sysinfoW ${labelFrame}.sysinfo

   # reuse widgets if already there, no need to recreate
   if { ! [winfo exists $msgbarFrame] } {
      labelframe ${msgbarFrame} -text "Message Center Overview"
      # create frame main toolbar
      frame ${labelFrame} -bd 1

      foreach widget [list $label_totalW $label_abortW $label_eventW $label_infoW $label_sysinfoW] {
         label ${widget}
      }

      # if the option is not set, set it; it is used below
      # on most wm, it is there but it was not on mobaxterm so we set it here if not available
      if { [option get ${label_abortW} background Label] == "" } {
         option add *Label.background [${label_abortW} cget -bg]
      }
      if { [option get ${label_abortW} foreground Label] == "" } {
         option add *Label.foreground [${label_abortW} cget -fg]
      }
      
      ::tooltip::tooltip ${labelFrame} "Number of unacknowledged / (total) messages"
   }

   set newMsgColor [SharedData_getColor COLOR_MSG_CENTER_MAIN]
   set normalBgColor [option get ${label_abortW} background Label]
   set normalFgColor [option get ${label_abortW} foreground Label]

   if { ${nb_all} != "0" && ${tt_all} != "0"} {
      set infoText "All : $nb_all/($tt_all) "
      ${label_totalW} configure -justify center -text ${infoText} -bg $newMsgColor -fg white
   } elseif { ${nb_all} == "0" && ${tt_all} != "0"} {
      set infoText "All : 0/($tt_all) "
      ${label_totalW} configure -justify center -text ${infoText} -bg ${normalBgColor} -fg ${normalFgColor}
   } else {
      set infoText "All : 0 "
      ${label_totalW} configure -justify center -text ${infoText} -bg ${normalBgColor} -fg ${normalFgColor}
   }

   if { ${nb_abort} != "0" && ${tt_abort} != "0"} {
      set infoText " Abort : ${nb_abort}/($tt_abort) "
      ${label_abortW} configure -justify center -text ${infoText} -bg $newMsgColor -fg white
   } elseif { ${nb_abort} == "0" && ${tt_abort} != "0"} {
      set infoText " Abort : 0/($tt_abort) "
      ${label_abortW} configure -justify center -text ${infoText} -bg ${normalBgColor} -fg ${normalFgColor}
   } else {
      set infoText " Abort : 0 "
      ${label_abortW} configure -justify center -text ${infoText} -bg ${normalBgColor} -fg ${normalFgColor}
   }

   if { ${nb_event} != "0" && ${tt_event} != "0"} {
      set infoText " Event : ${nb_event}/($tt_event) "
      ${label_eventW} configure -justify center -text ${infoText} -bg $newMsgColor -fg white
   } elseif { ${nb_event} == "0" && ${tt_event} != "0"} {
      set infoText " Event : 0/($tt_event) "
      ${label_eventW} configure -justify center -text ${infoText} -bg ${normalBgColor} -fg ${normalFgColor}
   } else {
      set infoText " Event : 0 "
      ${label_eventW} configure -justify center -text ${infoText} -bg ${normalBgColor} -fg ${normalFgColor}
   }
   if { ${nb_info} != "0" && ${tt_info} != "0"} {
      set infoText " Info : ${nb_info}/($tt_info) "
      ${label_infoW} configure -justify center -text ${infoText} -bg $newMsgColor -fg white
   } elseif { ${nb_info} == "0" && ${tt_info} != "0"} {
      set infoText " Info : 0/($tt_info) "
      ${label_infoW} configure -justify center -text ${infoText} -bg ${normalBgColor} -fg ${normalFgColor}
   } else {
      set infoText " Info : 0 "
      ${label_infoW} configure -justify center -text ${infoText} -bg ${normalBgColor} -fg ${normalFgColor}
   }
   if { ${nb_sysinfo} != "0" && ${tt_sysinfo} != "0"} {
      set infoText " Sysinfo : $nb_sysinfo/($tt_sysinfo)"
      ${label_sysinfoW} configure -justify center -text ${infoText} -bg $newMsgColor -fg white
   } elseif { ${nb_sysinfo} == "0" && ${tt_sysinfo} != "0"} {
      set infoText " Sysinfo : 0/($tt_sysinfo) "
      ${label_sysinfoW} configure -justify center -text ${infoText} -bg ${normalBgColor} -fg ${normalFgColor}
   } else {
      set infoText " Sysinfo : 0 "
      ${label_sysinfoW} configure -justify center -text ${infoText} -bg ${normalBgColor} -fg ${normalFgColor}
   }
   eval grid ${label_totalW} ${label_abortW} ${label_eventW} ${label_infoW} ${label_sysinfoW} -sticky w -padx \[list 2 0\] 
   pack ${labelFrame} -pady 2 -side left
   grid ${msgbarFrame} -row 0 -column 2 -sticky nsew -padx 2
}

proc Overview_createToolbar { _toplevelW } {
    # create the frame to hold the core icons and plugin icons
   set ToolbarW ${_toplevelW}.toolbar
   frame ${ToolbarW} -relief [SharedData_getMiscData MENU_RELIEF]
   # create the frame to hold the core icons and plugin icons
   set mainToolbarW ${ToolbarW}.label
   
   # core icons is childe of main toolbar frame
   set toolbarW ${mainToolbarW}.core

   set mesgCenterW ${toolbarW}.button_msgcenter
   set closeW ${toolbarW}.button_close
   set colorLegendW ${toolbarW}.button_colorlegend
   set fontW ${toolbarW}.button_font
   # create frame main toolbar
   # frame ${mainToolbarW} -bd 1
   labelframe ${mainToolbarW} -text Toolbar

   # create frame core toolbar
   frame ${toolbarW} -bd 1

   set imageDir [SharedData_getMiscData IMAGE_DIR]

   image create photo ${toolbarW}.msg_center_img -file ${imageDir}/open_mail_sh.gif
   image create photo ${toolbarW}.msg_center_new_img -file ${imageDir}/open_mail_new.gif
   image create photo ${toolbarW}.color_legend_img -file ${imageDir}/color_legend.gif
   image create photo ${toolbarW}.font_img -file ${imageDir}/font.gif

   button ${mesgCenterW} -image ${toolbarW}.msg_center_img -command [list MsgCenter_show true] -relief flat

   ::tooltip::tooltip ${mesgCenterW} "Show Message Center"

   image create photo ${toolbarW}.close -file ${imageDir}/cancel.gif
   button ${closeW} -image ${toolbarW}.close -command [list Overview_quit] -relief flat
   ::tooltip::tooltip ${closeW} "Close Application"

   button ${colorLegendW} -image ${toolbarW}.color_legend_img -command [list xflow_showColorLegend ${colorLegendW}] -relief flat
   tooltip::tooltip ${colorLegendW} "Show color legend"

   set testBellW ""
   if { [SharedData_getMiscData OVERVIEW_SHOW_TEST_BELL_ICON] == true } { 
      # mainly for a&p allow them to test if the application alarm bell is working
      image create photo ${toolbarW}.test_bell_img -file ${imageDir}/bell_test.png
      set testBellW [button ${toolbarW}.button_test_bell -image ${toolbarW}.test_bell_img -relief flat \
                     -command [list Overview_testBellCallback ${toolbarW}.button_test_bell] ]
      tooltip::tooltip ${testBellW} "Test Bell"
   }
   button ${fontW} -image ${toolbarW}.font_img -command DkfFont_init -relief flat
   tooltip::tooltip ${fontW} "Select font"
   
   eval grid ${mesgCenterW} ${colorLegendW} ${testBellW} ${closeW} ${fontW} -sticky w -padx \[list 2 0\] 

   # core toolbar stis on column 0 
   grid ${toolbarW} -row 0 -column 0 -sticky ew
   # place the main toolbar frame on the grid
   grid ${mainToolbarW} -row 0 -column 0 -sticky nsew -padx 0
   grid ${ToolbarW} -row 1 -column 1 -sticky nsew -padx 0
}


proc Overview_createCanvas { _toplevelW } {
   # set canvasFrame [frame ${_toplevelW}.canvas_frame]
   set canvasPanedW [panedwindow ${_toplevelW}.canvas_pane -showhandle 1 -orient horizontal -handlesize 2 -sashwidth 2]
   set canvasFrame [frame ${canvasPanedW}.canvas_frame]
   set groupCanvasFrame [frame ${canvasPanedW}.group_canvas_frame]

   ${canvasPanedW} add ${groupCanvasFrame} ${canvasFrame}

   set groupCanvasW [Overview_getGroupDisplayCanvas]
   set group_xScrollW [scrollbar ${groupCanvasFrame}.group_xscroll]
   # autoscroll messes up the two canvas when scrolling to the end of the canvas... disable for now
   # ::autoscroll::autoscroll ${group_xScrollW}
   canvas ${groupCanvasW} -relief flat -bd 0 -highlightthickness 0 -xscrollcommand [list ${group_xScrollW} set]
   ${group_xScrollW} configure -orient horizontal -command [list ${groupCanvasW} xview]
   grid ${groupCanvasW} -row 0 -column 0 -sticky nsew
   grid ${group_xScrollW} -row 1 -column 0 -sticky ew 
   grid rowconfigure ${groupCanvasFrame} 0 -weight 1
   grid columnconfigure ${groupCanvasFrame} 0 -weight 1

   set canvasW ${canvasFrame}.canvas

   frame ${canvasFrame}.xframe

   set yScrollW [scrollbar ${canvasFrame}.yscroll -command [list Overview_yScrollCommandCallback ${canvasW} ${groupCanvasW}]]
   set xScrollW [scrollbar ${canvasFrame}.xscroll -orient horizontal -command [list ${canvasW} xview]]

   set pad 12
   frame ${canvasFrame}.pad -width $pad -height $pad -bd 0 -relief flat

   grid ${canvasFrame}.xframe -row 2 -column 0 -columnspan 2 -sticky ewns
   grid ${yScrollW} -row 0 -column 1 -sticky ns

   grid ${canvasFrame}.pad -row 0 -column 1 -in ${canvasFrame}.xframe -sticky es
   grid ${xScrollW} -row 0 -column 0 -sticky ew -in ${canvasFrame}.xframe

   grid columnconfigure ${canvasFrame}.xframe 0 -weight 1
   grid rowconfigure ${canvasFrame}.xframe 1 -weight 1

   # only show the scrollbars if required
   ::autoscroll::autoscroll ${yScrollW}
   # ::autoscroll::autoscroll ${xScrollW}

   canvas ${canvasW} -relief flat -bd 0 -bg [SharedData_getColor CANVAS_COLOR]  -highlightthickness 0 \
      -yscrollcommand [list ${yScrollW} set] -xscrollcommand [list ${xScrollW} set]

   bind ${canvasW} <Configure> [list Overview_canvasConfigureCallback %w %h %b %D]

   grid ${canvasW} -row 0 -column 0 -sticky nsew

   # make the canvas expandable to right & bottom
   grid rowconfigure ${canvasFrame} 0 -weight 1
   grid columnconfigure ${canvasFrame} 0 -weight 1
   # grid columnconfigure ${canvasFrame} 0 -weight 1

   grid ${canvasPanedW} -row 2 -column 1 -sticky nsew -rowspan 2
   
   bind ${canvasPanedW} <ButtonRelease-1> [list Overview_PaneHandleEvent %W %x %y]
}

proc Overview_PaneHandleEvent { widget x y } {
   global HANDLE_INIT_POSITION
   # puts "Overview_PaneHandleMotionEvent $widget x:$x y:$y"
   set canvasPane [Overview_getCanvasPane]
   foreach {posX posY} [${canvasPane} sash coord 0] {}

   # prevent user from dragging to the right... does not really make sense
   if { [info exists HANDLE_INIT_POSITION] } {
      if { ${posX} > ${HANDLE_INIT_POSITION} } {
         ${canvasPane} sash place 0 ${HANDLE_INIT_POSITION} 1
      }
   }
}

proc Overview_savePaneInitialState {} {
   global HANDLE_INIT_POSITION
   set canvasPane [Overview_getCanvasPane]
   foreach {posX posY} [${canvasPane} sash coord 0] {}

   set HANDLE_INIT_POSITION ${posX}
}

# args parameter has variable number of arguments 
# in this case args can be "moveto value" or "scroll number what"
# the args parameter contains arguments to the "yview" command of the canvas
proc Overview_yScrollCommandCallback { canvas group_canvas args } {
   ::log::log debug "Overview_yScrollCommandCallback args:$args"

   # synchronize the two canvas vertical scrolling
   eval ${canvas} yview ${args}
   eval ${group_canvas} yview ${args}

   Overview_mouseWheelCheck
}

# prohibits y scrolling when limits are reached
proc Overview_mouseWheelCheck {} {
   set canvasW [Overview_getCanvas]
   set groupCanvasW [Overview_getGroupDisplayCanvas]

   foreach { yviewLow yviewHigh } [${canvasW} yview] {}
   if { ${yviewLow} == "0.0" } {
      # reached the lower limit don't allow scrolling
      bind ${canvasW} <4> ""
      bind ${groupCanvasW} <4> ""
   } else {
      bind ${canvasW} <4> [list Overview_yScrollCommandCallback ${canvasW} ${groupCanvasW} scroll -5 units]
      bind ${groupCanvasW} <4> [list Overview_yScrollCommandCallback ${canvasW} ${groupCanvasW} scroll -5 units]
   }
   if { ${yviewHigh} == "1.0" } {
      # reached the upper limit don't allow scrolling
      bind ${canvasW} <5> ""
      bind ${groupCanvasW} <5> ""
   } else {
      bind ${canvasW} <5> [list Overview_yScrollCommandCallback ${canvasW} ${groupCanvasW} scroll +5 units]
      bind ${groupCanvasW} <5> [list Overview_yScrollCommandCallback ${canvasW} ${groupCanvasW} scroll +5 units]
   }
}

# this is called when a configure event is triggered on a widget to resize, iconified a window.
# I need to redraw the bg image everytime the window is resized... however, this proc can 
# be called about 10-15 times when the user drags the mouse to resize; I don't want
# to redraw the bg 15 times... So let's put a delay and every call cancels the previous one unless the 
# delay is passed; only the last one will live to execute the image redraw.
proc Overview_canvasConfigureCallback { event_width event_height event_button_number event_delta } {
   global RESIZE_AFTERID
   # cancel the previous event
   catch { after cancel [set RESIZE_AFTERID] }
   # set the event to draw bg
   set RESIZE_AFTERID [after 100 [list Overview_resizeWindowEvent ${event_width} ${event_height}]]
}

proc Overview_resizeWindowEvent { width height } {
  Overview_addCanvasImage ${width} ${height}
  Overview_setCanvasScrollArea
  Overview_mouseWheelCheck
}

# adds a bg image for both group and exp canvas
proc Overview_addCanvasImage { width height } {
   global FLOW_BG_SOURCE_IMG OVERVIEW_TILED_IMG GROUP_OVERVIEW_TILED_IMG

   if { [SharedData_getMiscData BACKGROUND_IMAGE] != "" } {
      set imageFile [SharedData_getMiscData BACKGROUND_IMAGE]
   } else {
      set imageDir [SharedData_getMiscData IMAGE_DIR]
      set imageFile [SharedData_getMiscData IMAGE_DIR]/artist-canvas_2.gif
   }

   if { ! [info exists FLOW_BG_SOURCE_IMG] } {
      set FLOW_BG_SOURCE_IMG [image create photo -file ${imageFile}]
   }

   set canvasW [Overview_getCanvas]
   set groupCanvas [Overview_getGroupDisplayCanvas]

   # delete previous 
   if { [${canvasW} gettags canvas_bg_image] != "" } {
      image delete ${OVERVIEW_TILED_IMG}
      image delete ${GROUP_OVERVIEW_TILED_IMG}
      ${canvasW} delete canvas_bg_image
      ${groupCanvas} delete canvas_bg_image
   }
   # build the image
   set OVERVIEW_TILED_IMG [image create photo]
   set GROUP_OVERVIEW_TILED_IMG [image create photo]
   ${canvasW} create image 0 0 -anchor nw -image ${OVERVIEW_TILED_IMG} -tags canvas_bg_image
   ${groupCanvas} create image 0 0 -anchor nw -image ${GROUP_OVERVIEW_TILED_IMG} -tags canvas_bg_image
  
   # adjust size
   set canvasBox [${canvasW} bbox all]
   set canvasItemsW [lindex ${canvasBox} 2]
   set canvasItemsH [lindex ${canvasBox} 3]
   set usedW ${canvasItemsW}
   if { ${width} > ${canvasItemsW} } {
      set usedW [expr ${width} + 50]
   }
   set usedH ${canvasItemsH}
   if { ${height} > ${canvasItemsH} } {
      set usedH [expr ${height} + 25]
   }

   set groupCanvasWidth [lindex [${groupCanvas} bbox DisplayGroup] 2]
   # tile the image
   ${OVERVIEW_TILED_IMG} copy ${FLOW_BG_SOURCE_IMG} -to 0 0 ${usedW} ${usedH}
   ${GROUP_OVERVIEW_TILED_IMG} copy ${FLOW_BG_SOURCE_IMG} -to 0 0 ${groupCanvasWidth} ${usedH}

   # put the img below the grid
   ${canvasW} lower canvas_bg_image
   ${groupCanvas} lower canvas_bg_image
}

proc Overview_setTitle { top_w time_value } {
   global env
   set winTitle "Xflow Overview - User=$env(USER) Host=[exec -ignorestderr hostname] Time=${time_value}"
   wm title [winfo toplevel ${top_w}] ${winTitle}
}

proc Overview_getVerticalToolbarFrame {} {
   return .overview_top.side_frame.vertical_toolbar_frame
}

proc Overview_getCanvasPane {} {
   return .overview_top.canvas_pane
}

proc Overview_getCanvas {} {
   return .overview_top.canvas_pane.canvas_frame.canvas
}

proc Overview_getGroupDisplayCanvas {} {
   return .overview_top.canvas_pane.group_canvas_frame.group_canvas
}

proc Overview_getToplevel {} {
   return .overview_top
}

proc Overview_setMainCoords { _topOverview } {
   SharedData_setMiscData OVERVIEW_MAIN_COORDS "[winfo x ${_topOverview}] [winfo y ${_topOverview}]"
}

proc Overview_getExpRootNodeInfo { exp_path } {
   set rootNode ""
   if [ catch { set rootNode [Sequencer_getExpRootNodeInfo ${exp_path}] } message ] {
      set errMsg "Error calling nodeinfo:\n$message"
      tk_messageBox -title "Application Error!" -type ok -icon error \
         -message ${errMsg}
      return ""
   }
   return ${rootNode}
}

proc Overview_testBellCallback { source_w } {
   global TEST_BELL_VAR
   set TEST_BELL_VAR 1
   Overview_soundbell
   tk_messageBox -title "Bell Testing" -message "You should hear the bell every 2 seconds. Click on the ok button to stop!" -type ok -parent ${source_w}
   set TEST_BELL_VAR 0
}

proc Overview_soundbell {} {
   global TEST_BELL_VAR
   if { [info exists TEST_BELL_VAR] && $TEST_BELL_VAR == "1" } {
      puts "sounding bell..."
      bell
      after 2000 { Overview_soundbell }
   }
}

proc Overview_addHeartbeatDatestamp { exp_path datestamp } {
   global HeartbeatDatestamps
   ::log::log notice "Overview_addHeartbeatDatestamp() ${exp_path} ${datestamp} called."
   if { ${exp_path} != "" && ${datestamp} != "" } {
      set key ${exp_path}_${datestamp}
      set HeartbeatDatestamps($key) "${exp_path} ${datestamp}"
   }
   ::log::log notice "Overview_addHeartbeatDatestamp() ${exp_path} ${datestamp} DONE."
}

# keeps track of which thread is monitoring what run datestamp
# stores the current time that this proc is invoked and also the
# current file offset of the datestamp log file
proc Overview_heartbeatDatestamp { thread_id exp_path datestamp offset } {
   ::log::log debug "Overview_heartbeatDatestamp $thread_id $exp_path $datestamp $offset"
   global HeartbeatDatestamps
   if { ${exp_path} != "" && ${datestamp} != "" } {
      set key ${exp_path}_${datestamp}
      set HeartbeatDatestamps($key) "${exp_path} ${datestamp} ${thread_id} [clock seconds] ${offset}"
   }
   ::log::log debug "Overview_heartbeatDatestamp $thread_id $exp_path $datestamp $offset DONE"
}

# drops a run datestamp from the monitored list
proc Overview_removeHeartbeatDatestamp { thread_id exp_path datestamp } {
   global HeartbeatDatestamps

   ::log::log notice "Overview_removeHeartbeatDatestamp() ${exp_path} ${datestamp} called."
   set key ${exp_path}_${datestamp}
   array unset HeartbeatDatestamps $key
   ::log::log notice "Overview_removeHeartbeatDatestamp() ${exp_path} ${datestamp} done."
}

proc Overview_checkDatestampHeartbeats {} {
   ::log::log debug "[exec -ignorestderr date] Overview_checkDatestampHeartbeats..."
   global HeartbeatDatestamps
   set currentTime [clock seconds]
   foreach { key data } [array get HeartbeatDatestamps] {
      set expPath [lindex ${data} 0]
      set datestamp [lindex ${data} 1]
      set heartbeatData [SharedData_getExpHeartbeat ${expPath} ${datestamp}]
      set lastHeartbeat [lindex ${heartbeatData} 1]
      if { ${lastHeartbeat} == "" } {
         ::log::log notice "Overview_checkDatestampHeartbeats $expPath $datestamp NO DATA"
	 continue
      }
      set elapsed [expr ${currentTime} - ${lastHeartbeat}]
      # puts "Overview_checkDatestampHeartbeats key:${key} current time:${currentTime} last heatbeat: ${lastHeartbeat}"
      # puts "Overview_checkDatestampHeartbeats key:${key} elapsed: [expr ${currentTime} - ${lastHeartbeat}]"
      if { ${elapsed} > 60 } {
         # no heartbeat received for the last 60 seconds...
	 set threadId [lindex ${heartbeatData} 0]
         # puts "Overview_checkDatestampHeartbeats key:${key} threadId:${threadId} SOMETHINGS WRONG!"
         ::log::log notice "Thread Hearbeat: heartbeat not received from thread ${threadId} exp:${expPath} datestamp:${datestamp} for more than 60 seconds... destroying thread..."
	 # we consider the tread unreachable and we need to destroy it
         Overview_processDeadThread ${threadId}
	 break
      }
   }
   # execute every minute
   after 60000 Overview_checkDatestampHeartbeats

   ::log::log debug "[exec -ignorestderr date] Overview_checkDatestampHeartbeats DONE"
}

# get rid of an unreachable thread
# 1) get info about every datestamp that the thread is monitoring
# 2) kill the problematic thread
# 3) create a new thread to replace it in the pool
# 4) re-assign all datestamps that the thread was monitoring to other threads
proc Overview_processDeadThread { thread_id } {
   global HeartbeatDatestamps
   # puts "Overview_processDeadThread thread_id:$thread_id"
   ::log::log notice "Thread Heartbeat: preparing to dropt thread ${thread_id}"
   set affectedOnes {}
   # get info about every datestamp that the thread is monitoring
   foreach { key data } [array get HeartbeatDatestamps] {
      set expPath [lindex ${data} 0]
      set datestamp [lindex ${data} 1]
      set heartbeatData [SharedData_getExpHeartbeat ${expPath} ${datestamp}]
      set checkThreadId [lindex ${heartbeatData} 0]
      if { ${checkThreadId} == ${thread_id} } {
	 lappend affectedOnes "${expPath} ${datestamp}"
      }
   }

   ::log::log notice "Thread Heartbeat: exps affected by thread ${thread_id} : ${affectedOnes}"

   # kill the problematic thread
   ::log::log notice "Thread Heartbeat: dropping thread: ${thread_id} ... "
   ThreadPool_dropThread ${thread_id}
   
   # create a new thread to replace it in the pool
   ::log::log notice "Heartbeat: creating new thread to replace ${thread_id} in pool"
   ThreadPool_addNewThread

   # re-assign all datestamps that the thread was monitoring to other threads
   foreach affectedOne ${affectedOnes} {
      set expPath [lindex ${affectedOne} 0]
      set datestamp [lindex ${affectedOne} 1]
      set heartbeatData [SharedData_getExpHeartbeat ${expPath} ${datestamp}]
      set offset [lindex ${heartbeatData} 2]
      # remove the thread currently assigned to the datestamp
      SharedData_removeExpThreadId ${expPath} ${datestamp} 

      # set the datestamp file offset to the last heartbeat received
      SharedData_setExpDatestampOffset ${expPath} ${datestamp} ${offset}

      # get a new thread for the datestamp
      set expThreadId [ThreadPool_getNextThread]
      ::log::log notice "Heartbeat: re-affecting expPath:${expPath} datestamp:${datestamp}... to new thread: ${expThreadId}"
      SharedData_setExpThreadId ${expPath} ${datestamp} ${expThreadId}

      # thread should now monitor new datestamp
      thread::send -async ${expThreadId} "LogReader_addMonitorDatestamp ${expPath} ${datestamp}"
      thread::send -async ${expThreadId} "LogReader_readMonitorDatestamps"
   }
   ::log::log notice "Thread Heartbeat: dropping thread ${thread_id} DONE"
}

# set window as topmost,
# need callback for widgets like MessageDialog
proc Overview_setTopMost { widget } {
   catch {
      wm attributes $widget -topmost 1
   }
}

# this function loads the plugin menu items
proc Overview_createPluginToolbar { parentToolbar } {
    set SEQ_SUITES_XML [SharedData_getMiscData SUITES_FILE]
    set pluginEnv "export SEQ_SUITES_XML=${SEQ_SUITES_XML}"
    Utils_createPluginToolbar "overview" ${parentToolbar} ${pluginEnv}
}

proc Overview_main {} {
   global env startupExp SHOW_TOOLBAR LIST_FONT_LEVEL
   global DEBUG_TRACE FileLoggerCreated
   global SHOW_MSGBAR LIST_TAG LIST_EXP
   Overview_setTkOptions

   set SHOW_MSGBAR false
   set LIST_TAG    {}
   set LIST_EXP    {}
   set LIST_FONT_LEVEL {}

   set DEBUG_TRACE [SharedData_getMiscData DEBUG_TRACE]
   ::DrawUtils::init
   Overview_init

   set appLogFile [SharedData_getMiscData APP_LOG_FILE]
   if { ${appLogFile} != "" } {
      puts "Using application log file: ${appLogFile}"
      set loggerThreadId [FileLogger_createThread ${appLogFile}]
      SharedData_setMiscData FILE_LOGGER_THREAD ${loggerThreadId}
      puts "waiting for FileLoggerCreated..."
      vwait FileLoggerCreated

      puts "xflow_overview loggerThreadId:${loggerThreadId}"
      ::log::log notice "xflow_overview Application startup user=$env(USER) real user:[SharedData_getMiscData REAL_USER] host:[exec -ignorestderr hostname]"
   }

   MsgCenter_init

   set topOverview [Overview_getToplevel]
   set topCanvas [Overview_getCanvas]
   toplevel ${topOverview}

   # keep track of coords
   bind ${topOverview} <Configure> [list Overview_setMainCoords ${topOverview}]

   wm withdraw ${topOverview}
   # wm iconify ${topOverview}

   if { [SharedData_getMiscData SUITES_FILE] != "" } {
      Overview_readExperiments
   }

   # create frame on left side of window to hold msg center and toolbar hide icons
   set sideFrame [labelframe ${topOverview}.side_frame]
   grid ${sideFrame} -column 0 -row 0 -sticky ns -rowspan 3

   set sideToolbarFrame [frame ${sideFrame}.vertical_toolbar_frame]
   grid ${sideToolbarFrame} -column 0 -row 0 -sticky n -pady 2

   # create label on left side of window
   set labelValue [DisplayGrp_getWindowsLabel]
   if { ${labelValue} != "" } {
      set labelBgColor [SharedData_getMiscData WINDOWS_LABEL_BG]
      if { ${labelBgColor} != "" } {
         set labelW [label ${sideFrame}.exp_label -justify center -text [DisplayGrp_getWindowsLabel] -wraplength 1 -font [xflow_getExpLabelFont] -bg [SharedData_getMiscData WINDOWS_LABEL_BG]]
      } else {
         set labelW [label ${sideFrame}.exp_label -justify center -text [DisplayGrp_getWindowsLabel] -wraplength 1 -font [xflow_getExpLabelFont]]
      }
      grid ${labelW} -column 0 -row 1 -sticky ns
   }
   grid rowconfigure ${sideFrame} 0 -weight 0
   grid rowconfigure ${sideFrame} 1 -weight 10

   Overview_createMenu ${topOverview}
   Overview_createToolbar ${topOverview}

   set plugin_toolbar [Overview_createPluginToolbar ${topOverview}.toolbar]
   grid ${plugin_toolbar} -row 0 -column 1 -sticky nsew

   Overview_createCanvas ${topOverview}

   grid columnconfigure ${topOverview} 0 -weight 0 -uniform b 
   grid columnconfigure ${topOverview} 1 -weight 75 -uniform b 
   grid rowconfigure ${topOverview} 0 -weight 0
   grid rowconfigure ${topOverview} 1 -weight 0
   grid rowconfigure ${topOverview} 2 -weight 15 -uniform a

   # set sizeGripWidget [ttk::sizegrip ${topOverview}.sizeGrip]
   # grid ${sizeGripWidget} -sticky se

   # trap windows kill to gracefully exit
   wm protocol ${topOverview} WM_DELETE_WINDOW [list Overview_quit ]

   # create pool of threads to parse and launch exp flows
   ThreadPool_init [SharedData_getMiscData OVERVIEW_NUM_THREADS]

   # set thread error handler for async calls
   thread::errorproc Overview_threadErrorCallback

   # lay out the groups
   set groupCanvasW [Overview_getGroupDisplayCanvas]
   set rootGroups [DisplayGrp_getGroupLevel 0]
   foreach rootGroup ${rootGroups} {
      Overview_addGroup ${groupCanvasW} ${rootGroup}
   }

   # set the max width of the group canvas display based on the groups max length
   set groupDisplayMaxX [DisplayGrp_getAllGroupMaxX ${groupCanvasW}]
   ${groupCanvasW} configure -width [expr ${groupDisplayMaxX} + 5]

   # check if we need to release obsolete data every hour
   after 60000 OverviewExpStatus_checkObseleteDatestamps

   # create the grid
   Overview_createGraph

   # create icons to open/close toolbar
   Overview_createSideToolbarIcons ${sideToolbarFrame}

   Overview_setCurrentTime ${topCanvas}

   # add the exps on the grid and load the log files
   Overview_addGroupExps ${topCanvas}

   Overview_createMsgCenterbar ${topOverview}

   Overview_GridAdvanceHour

   SharedData_setMiscData STARTUP_DONE true
   MsgCenter_startupDone

   wm geometry ${topOverview} =1500x600
   # wm withdraw ${topOverview} ; wm deiconify ${topOverview}
   wm deiconify ${topOverview}
   # wm geometry ${topOverview}  +0+0

   Overview_savePaneInitialState

   # check if mouse wheel is allowed
   Overview_mouseWheelCheck

   # start the reader for currently active logs
   # ::thread::broadcast "LogReader_readMonitorDatestamps true"
   # delay each log thread by 1 sec apart
   global PoolId
   set count 1

   foreach thread [array names PoolId] {
       set delayValue [expr ${count} * 1000]
       ::thread::send -async ${thread} "LogReader_readMonitorDatestamps ${delayValue}"
       incr count
   }

   Overview_checkStartupOptions
   Overview_showToolbarCallback

   # periodic idle check interval in minutes
   set expIdleInterval [SharedData_getMiscData OVERVIEW_EXP_IDLE_INTERVAL]
   
   ::log::log notice "Check Exp Idle Interval: ${expIdleInterval} minutes"
   Overview_checkExpIdle [expr ${expIdleInterval} * 60000]

   # periodic submit late check interval in minutes
   set expSubmitLateInterval [SharedData_getMiscData OVERVIEW_EXP_SUBMIT_LATE_INTERVAL]

   # start a periodic check for late submission (every 15 minutes)
   ::log::log notice "Check Exp Submit Late Interval: ${expSubmitLateInterval} minutes"
   Overview_checkExpSubmitLate [expr ${expSubmitLateInterval} * 60000]

   # run a periodic monitor to look for new log files to process
   LogMonitor_checkNewLogFiles

}

# validate required options
proc Overview_checkStartupOptions {} {
   # periodic idle check interval in minutes
   set expIdleInterval [SharedData_getMiscData OVERVIEW_EXP_IDLE_INTERVAL]
   if { ! [string is integer -strict ${expIdleInterval}] || ${expIdleInterval} <=0 } {
      puts stderr "ERROR: INVALID OVERVIEW_EXP_IDLE_INTERVAL value: ${expIdleInterval} using default 60 minutes"
      SharedData_setMiscData OVERVIEW_EXP_IDLE_INTERVAL 60
      ::log::log notice "ERROR: INVALID OVERVIEW_EXP_IDLE_INTERVAL value: ${expIdleInterval} using default 60 minutes"
   }

   # periodic idle check interval in minutes
   set expSubmitLateInterval [SharedData_getMiscData OVERVIEW_EXP_SUBMIT_LATE_INTERVAL]
   if { ! [string is integer -strict ${expSubmitLateInterval}] || ${expSubmitLateInterval} <=0 } {
      puts stderr "ERROR: INVALID OVERVIEW_EXP_SUBMIT_LATE_INTERVAL value: ${expSubmitLateInterval} using default 15 minutes"
      SharedData_setMiscData OVERVIEW_EXP_SUBMIT_LATE_INTERVAL 15
      ::log::log notice "Invalid Exp Submit Late Interval: ${expSubmitLateInterval} using default 15 minutes"
   }
}

set tcl_traceExec 1

Overview_parseCmdOptions

proc out {} {
# for testing only
# intercep clock commands to allow
# testing with different time values
global env
source $env(SEQ_XFLOW_BIN)/../lib/ClockWrapper.tcl
package require ClockWrapper
interp alias {} ::clock {} ::ClockWrapper
::ClockWrapper::setDelta "4 hour"
# ::ClockWrapper::setDelta "-1 hour"
# ::ClockWrapper::setDelta "0 second"
# Overview_GridAdvanceHour 5
# Overview_redrawGrid
set canvasW [Overview_getCanvas]
set displayGroups [ExpXmlReader_getGroups]
 foreach displayGroup $displayGroups {
    set expList [$displayGroup cget -exp_list]
    foreach exp $expList {
     # delete all exp boxes
       Overview_removeAllExpBoxes ${canvasW} ${exp}
      # create default boxes
       Overview_addExpDefaultBoxes ${canvasW} ${exp}
    }
 }
}
