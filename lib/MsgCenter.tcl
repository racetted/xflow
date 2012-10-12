#!/home/binops/afsi/ssm/domain2/tcl-tk_8.5.7_linux26-i686/bin/tclsh8.5
package require Tk
#package require Tktable
package require tablelist
package require autoscroll
package require tooltip
package require log

global env
set lib_dir $env(SEQ_XFLOW_BIN)/../lib
#puts "lib_dir=$lib_dir"
set auto_path [linsert $auto_path 0 $lib_dir ]

proc MsgCenter_setTkOptions {} {
   option add *activeBackground [SharedData_getColor ACTIVE_BG]
   option add *selectBackground [SharedData_getColor SELECT_BG]
   catch { option add *troughColor [::tk::Darken [option get . background Scrollbar] 85] }

   #ttk::style configure Xflow.Menu -background cornsilk4
}

proc MsgCenter_createMenus {} {
   global MsgCenterMainGridRowMap
   set topFrame .topframe
   frame ${topFrame} -relief [SharedData_getMiscData MENU_RELIEF]
   MsgCenter_addFileMenu ${topFrame}
   MsgCenter_addPrefMenu ${topFrame}
   MsgCenter_addHelpMenu ${topFrame}
   grid ${topFrame} -row $MsgCenterMainGridRowMap(Menu) -column 0 -sticky ew -padx 2
}

proc MsgCenter_addFileMenu { parent } {
   set menuButtonW ${parent}.file_menub
   set menuW $menuButtonW.menu

   menubutton $menuButtonW -text File -underline 0 -menu $menuW
   menu $menuW -tearoff 0

   $menuW add command -label "Close" -underline 0 -command [list MsgCenter_close]

   pack $menuButtonW -side left -padx 2
}

proc MsgCenter_addPrefMenu { parent } {
   set menuButtonW ${parent}.pref_menub
   set menuW $menuButtonW.menu

   menubutton $menuButtonW -text Preferences -underline 0 -menu $menuW
   menu $menuW -tearoff 0

   set msgTypeMenuW $menuW.msgtypemenu
   $menuW add cascade -label "Message Type" -underline 0 -menu $msgTypeMenuW

   menu $msgTypeMenuW -tearoff 0
   $msgTypeMenuW add checkbutton -label "Abort" -variable SHOW_ABORT_TYPE \
      -onvalue true -offvalue false -command [list MsgCenter_refreshActiveMessages [MsgCenter_getTableWidget]]
   $msgTypeMenuW add checkbutton -label "Event" -variable SHOW_EVENT_TYPE \
      -onvalue true -offvalue false -command [list MsgCenter_refreshActiveMessages [MsgCenter_getTableWidget]]
   $msgTypeMenuW add checkbutton -label "Info" -variable SHOW_INFO_TYPE \
      -onvalue true -offvalue false -command [list MsgCenter_refreshActiveMessages [MsgCenter_getTableWidget]]

   pack $menuButtonW -side left -padx 2
}

proc MsgCenter_addHelpMenu { parent } {
   set menuButtonW ${parent}.help_menub
   set menuW $menuButtonW.menu

   menubutton $menuButtonW -text Help -underline 0 -menu $menuW
   menu $menuW -tearoff 0

   pack $menuButtonW -side right -padx 2
}

proc MsgCenter_createToolbar { table_w_ } {
   global MsgCenterMainGridRowMap
   set toolbarW .toolbar
   set bellW ${toolbarW}.button_bell
   set ackW ${toolbarW}.button_ack
   set clearW ${toolbarW}.button_clear
   set closeW ${toolbarW}.button_close
   frame ${toolbarW}

   set imageDir [SharedData_getMiscData IMAGE_DIR]
   image create photo ${toolbarW}.stop_bell -file ${imageDir}/bell_cross.gif
   button ${bellW} -image ${toolbarW}.stop_bell -relief flat -command [list MsgCenter_stopBell ${table_w_}]
   ::tooltip::tooltip ${bellW} "Stop ringing bell."

   image create photo ${toolbarW}.ack_msg -file ${imageDir}/message_ack.gif
   button ${ackW} -image ${toolbarW}.ack_msg -relief flat -command [list MsgCenter_ackMessages ${table_w_}]
   ::tooltip::tooltip ${ackW} "Acknowledge new messages."

   image create photo ${toolbarW}.clear_msg -file ${imageDir}/message_clear.gif
   button ${clearW} -image ${toolbarW}.clear_msg -relief flat -command [list MsgCenter_clearMessages ${clearW} ${table_w_}]
   ::tooltip::tooltip ${clearW} "Clear all messages."

   image create photo ${toolbarW}.close -file ${imageDir}/cancel.gif
   button ${closeW} -image ${toolbarW}.close -relief flat -command [list MsgCenter_close]
   ::tooltip::tooltip ${closeW} "Close Message Center."

   if { [SharedData_getMiscData OVERVIEW_MODE] == "true" } {
      set overviewW ${toolbarW}.button_overview
      image create photo ${toolbarW}.overview -file ${imageDir}/calendar_clock.gif
      button ${overviewW} -image ${toolbarW}.overview -relief flat -command {
         set overviewThreadId [SharedData_getMiscData OVERVIEW_THREAD_ID]
         thread::send -async ${overviewThreadId} "Overview_toFront"
      }
      ::tooltip::tooltip ${overviewW} "Show Overview Window."
      grid ${bellW} ${ackW} ${clearW} ${overviewW} ${closeW} -padx 2 -sticky w
   } else {
      grid ${bellW} ${ackW} ${clearW} ${closeW} -padx 2 -sticky w
   }

   grid ${toolbarW} -row $MsgCenterMainGridRowMap(Toolbar) -column 0 -sticky ew -padx 2 -pady 2
   grid columnconfigure ${toolbarW} ${closeW} -weight 1
}

proc MsgCenter_createWidgets {} {
   global MSG_ACTIVE_TABLE 
   global MsgCenterMainGridRowMap MsgTableColMap

   set tableW .table
   if { ! [winfo exists ${tableW}] } {
      MsgCenter_createMenus
      MsgCenter_createToolbar ${tableW}

      array set MsgTableColMap {
         TimestampColNumber 0
         DatestampColNumber 1
         TypeColNumber 2
         NodeColNumber 3
         MessageColNumber 4
         SuiteColNumber 5
         UnackColNumber 6
      }

      set yscrollW .sy
      set xscrollW .sx
      set rowFgColor [SharedData_getColor COLOR_MSG_CENTER_MAIN]
      set tableBgColor [SharedData_getColor DEFAULT_BG]
      set headerBgColor [SharedData_getColor COLOR_MSG_CENTER_MAIN]
      set headerFgColor [SharedData_getColor DEFAULT_HEADER_FG]
      set stripeBgColor [SharedData_getColor MSG_CENTER_STRIPE_BG]
      set normalBgColor [SharedData_getColor MSG_CENTER_NORMAL_BG]
      set defaultAlign center
      set columns [list 0 Timestamp ${defaultAlign} \
                        0 Datestamp ${defaultAlign} \
                        0 Type ${defaultAlign} \
                        0 Node ${defaultAlign} \
                        0 Message ${defaultAlign} \
                        0 Suite ${defaultAlign} \
                        0 Unack ${defaultAlign}]

      tablelist::tablelist ${tableW} -columns ${columns} \
         -arrowcolor white -spacing 1 -resizablecolumns 1 \
         -stretch all -relief flat -labelrelief flat -showseparators 0 -borderwidth 0 -listvariable  MSG_ACTIVE_TABLE \
         -bg ${normalBgColor} -fg ${rowFgColor} \
         -labelcommand tablelist::sortByColumn -labelbg ${headerBgColor} \
         -labelfg ${headerFgColor} -labelpady 5 \
         -labelfont TkHeadingFont -labelbd 1 -labelrelief raised \
         -stripebg ${stripeBgColor} \
         -yscrollcommand [list ${yscrollW} set] -xscrollcommand [list ${xscrollW} set]

      ${tableW} columnconfigure $MsgTableColMap(TimestampColNumber) -resizable false
      ${tableW} columnconfigure $MsgTableColMap(DatestampColNumber) -resizable false
      ${tableW} columnconfigure $MsgTableColMap(TypeColNumber) -resizable false -align left
      ${tableW} columnconfigure $MsgTableColMap(NodeColNumber) -align left
      ${tableW} columnconfigure $MsgTableColMap(MessageColNumber) -align left -wrap 1 -maxwidth 35
      ${tableW} columnconfigure $MsgTableColMap(SuiteColNumber) -align left
      ${tableW} columnconfigure $MsgTableColMap(UnackColNumber) -hide 1

      if { [SharedData_getMiscData OVERVIEW_MODE] == "false" } { ${tableW} columnconfigure $MsgTableColMap(SuiteColNumber) -hide 1 }

      # creating scrollbars
      scrollbar ${yscrollW} -command [list ${tableW} yview]
      scrollbar ${xscrollW} -command [list ${tableW} xview] -orient horizontal
      ::autoscroll::autoscroll ${yscrollW}
      ::autoscroll::autoscroll ${xscrollW}

      grid ${tableW} -row $MsgCenterMainGridRowMap(MsgTable) -column 0 -sticky nsew -padx 2 -pady 2
      grid ${yscrollW} -row $MsgCenterMainGridRowMap(MsgTable) -column 1 -sticky nsew -padx 2 -pady 2
      grid ${xscrollW} -sticky ew
   }
}

# at application startup, we sort the log entries by
# their timestamp values.
proc MsgCenter_initialSort { _tableW } {
   global MsgTableColMap
   ${_tableW} sortbycolumn $MsgTableColMap(TimestampColNumber) -increasing
}

proc MsgCenter_getTableWidget {} {
   return .table
}

proc MsgCenter_getToplevel {} {
   return .
}

# sets the color of the table headers.
# When a new messsage comes in,
# we flash the table headers so this function is called
# might be called multiple times
proc MsgCenter_setHeaderStatus { table_w_ status_ } {
   set alarmBgColor [SharedData_getColor COLOR_MSG_CENTER_MAIN]
   set normalFgColor [SharedData_getColor DEFAULT_HEADER_FG]
   set normalBgColor [SharedData_getColor COLOR_MSG_CENTER_MAIN]
   set alarmAltBgColor [SharedData_getColor COLOR_MSG_CENTER_ALT]

   set currentBgColor [${table_w_} cget -labelbg]
   if { ${status_} == "normal" } {
      ${table_w_} configure -labelbg ${normalBgColor} -labelfg ${normalFgColor}
   } elseif { ${status_} == "alarm_bg" } {
      ${table_w_} configure -labelbg  ${alarmBgColor} -labelfg ${normalFgColor}
   } else {
      # alarm state
      if { ${currentBgColor} == ${alarmBgColor} } {
         ${table_w_} configure -labelbg ${alarmAltBgColor}
      } else {
         ${table_w_} configure -labelbg ${alarmBgColor}
      }
   }
}

# this function is called when a new message comes in
# 
proc MsgCenter_newMessage { table_w_ datestamp_ timestamp_ type_ node_ msg_ exp_ } {
   global MSG_TABLE MSG_COUNTER MSG_ACTIVE_COUNTER
   incr MSG_COUNTER
   ::log::log debug "MsgCenter_newMessage node_:$node_ type_:$type_ msg_:$msg_"
   lappend MSG_TABLE [list ${timestamp_} ${datestamp_} ${type_} ${node_} ${msg_} ${exp_}]

   set isMsgActive [MsgCenter_addActiveMessage ${datestamp_} ${timestamp_} ${type_} ${node_} ${msg_} ${exp_}]

   #MsgCenter_sendNotification
   if { ${isMsgActive} == "true" } {
      ${table_w_} see ${MSG_ACTIVE_COUNTER}
      MsgCengter_processAlarm ${table_w_}
   }
}

proc MsgCenter_getFieldFromLastMessage { field_index } {
   global MSG_ACTIVE_TABLE MSG_ACTIVE_COUNTER
   set value ""
   catch {
      set messageEntry [lindex ${MSG_ACTIVE_TABLE} [expr ${MSG_ACTIVE_COUNTER} - 1]]
      set value [lindex ${messageEntry} ${field_index}]
   }
   return ${value}
}

# see if we need to send notification to xflow or xflow-overview
# for new messages
proc MsgCenter_sendNotification {} {
   global MSG_ACTIVE_COUNTER MsgTableColMap
   set isStartupDone [SharedData_getMiscData STARTUP_DONE]
   if { ${isStartupDone} == "true" && [expr ${MSG_ACTIVE_COUNTER} > 0] } {
      set isOverviewMode [SharedData_getMiscData OVERVIEW_MODE]
      if { ${isOverviewMode} == "true" } {
         set overviewThreadId [SharedData_getMiscData OVERVIEW_THREAD_ID]
         thread::send ${overviewThreadId} "Overview_newMessageCallback true"
      } else {
         set xflowThreadId [SharedData_getMiscData XFLOW_THREAD_ID]
         set exp [MsgCenter_getFieldFromLastMessage $MsgTableColMap(SuiteColNumber)]
         set datestamp [MsgCenter_getFieldFromLastMessage $MsgTableColMap(DatestampColNumber)]
         # puts "MsgCenter_sendNotification exp=$exp datestamp=${datestamp}"
         thread::send ${xflowThreadId} "xflow_newMessageCallback ${exp} ${datestamp} true"
      }
   }
}

proc MsgCenter_addActiveMessage { datestamp_ timestamp_ type_ node_ msg_ exp_ } {
   global SHOW_ABORT_TYPE SHOW_INFO_TYPE SHOW_EVENT_TYPE
   global MSG_ACTIVE_TABLE MSG_ACTIVE_COUNTER

   set isMsgActive false
   switch ${type_} {
      abort {
         if { ${SHOW_ABORT_TYPE} == "true" } {
            set isMsgActive true
         }
      }
      info {
         if { ${SHOW_INFO_TYPE} == "true" } {
            set isMsgActive true
         }
      }
      event {
         if { ${SHOW_EVENT_TYPE} == "true" } {
            set isMsgActive true
         }
      }
   }

   if { ${isMsgActive} == "true" } {
      ::log::log debug "MsgCenter_addActiveMessage adding ${datestamp_} ${timestamp_} ${type_} ${node_} ${msg_} ${exp_}"
      set displayedNodeText [SharedFlowNode_convertToDisplayFormat ${node_}]
      # add 2 spaces between date and time
      set displayedTimestamp [join [split ${timestamp_} .] "  "]
      # show only first 10 digits of datestamp
      set displayedDatestamp [string range ${datestamp_} 0 9]
      incr MSG_ACTIVE_COUNTER
      lappend MSG_ACTIVE_TABLE [list ${displayedTimestamp} ${displayedDatestamp} ${type_} ${displayedNodeText} ${msg_} ${exp_} 1]
   }

   return ${isMsgActive}
}

# refresh shown messages based on user message type filters
# this function is called when the user changes the "Message Type" settings
# under the Preferences menu
proc MsgCenter_refreshActiveMessages { table_w_ } {
   global MSG_TABLE MSG_COUNTER
   # reset active messages
   MsgCenter_initActiveMessages
   set counter 0
   # reprocess all received messages
   while { ${counter} < ${MSG_COUNTER} } {
      foreach {timestamp datestamp type node msg exp} [lindex ${MSG_TABLE} ${counter}] {break}
      ::log::log debug "MsgCenter_refreshActiveMessages coun:$counter type:$type node:$node msg:$msg exp:$exp"
      MsgCenter_addActiveMessage ${datestamp} ${timestamp} ${type} ${node} ${msg} ${exp}
      incr counter
   }
   MsgCenter_ackMessages ${table_w_}
   MsgCenter_initialSort ${table_w_}
}

proc MsgCenter_initActiveMessages {} {
   global MSG_ACTIVE_TABLE MSG_ACTIVE_COUNTER
   set MSG_ACTIVE_TABLE {}
   set MSG_ACTIVE_COUNTER 0
}

proc MsgCenter_ackMessages { table_w_ } {
   global MsgTableColMap
   #wm attributes . -topmost 0
   MsgCenter_stopBell ${table_w_}
   # look for rows that have unack state
   set normalFg [SharedData_getColor MSG_CENTER_NORMAL_FG]
   foreach row [${table_w_} searchcolumn $MsgTableColMap(UnackColNumber) 1 -exact -all] {
         ${table_w_} rowconfigure ${row} -fg ${normalFg}
   }
   MsgCenter_setHeaderStatus ${table_w_} normal
   set isOverviewMode [SharedData_getMiscData OVERVIEW_MODE]
   if { ${isOverviewMode} == "true" } {
      set overviewThreadId [SharedData_getMiscData OVERVIEW_THREAD_ID]
      thread::send ${overviewThreadId} "Overview_newMessageCallback false"
   } else {
      set xflowThreadId [SharedData_getMiscData XFLOW_THREAD_ID]
      set exp [MsgCenter_getFieldFromLastMessage $MsgTableColMap(SuiteColNumber)]
      set datestamp [MsgCenter_getFieldFromLastMessage $MsgTableColMap(DatestampColNumber)]
      # puts "MsgCenter_sendNotification exp=$exp datestamp=${datestamp}"
      thread::send ${xflowThreadId} "xflow_newMessageCallback ${exp} ${datestamp} false"
   }
}

proc MsgCenter_clearMessages { source_w table_w_ } {
   global MSG_ACTIVE_COUNTER
   if { ${MSG_ACTIVE_COUNTER} > 0 } {
      set answer [tk_messageBox -parent ${source_w} -type okcancel \
         -title "Message Center" -icon warning -message \
         "Are you sure you want to clear all messages?"]

      if { $answer == "cancel" } {
         return
      }
      MsgCenter_ackMessages ${table_w_}
      MsgCenter_initActiveMessages

   }
}

# removes msg from the MSG_TABLE when not used anymore...
# datestamp is obsolete from xflow_overview
proc MsgCenter_removeMessages { table_w_ exp datestamp } {
   global MSG_TABLE MsgTableColMap
   ::log::log notice "MsgCenter_removeMessages for exp:${exp} datestamp:${datestamp}"
   # get exp messages
   set foundIndexes [lsearch -exact -all -index $MsgTableColMap(SuiteColNumber) $MSG_TABLE ${exp}]
   set deleteIndexes {}
   foreach foundIndex ${foundIndexes} {
      set msg [lindex ${MSG_TABLE} ${foundIndex}]
      if { [lindex ${msg} $MsgTableColMap(DatestampColNumber)] == ${datestamp} } { 
         lappend deleteIndexes ${foundIndex}
      }
   }
   # delete the indexes in reverse order, else it complains about indexes missing
   set deleteIndexes [lreverse ${deleteIndexes}]
   foreach deleteIndex ${deleteIndexes} {
      set MSG_TABLE [lreplace ${MSG_TABLE} ${deleteIndex} ${deleteIndex}]
   }
}

proc MsgCengter_processAlarm { table_w_ {repeat_alarm false} } {
   global MSG_ALARM_ON MSG_ALARM_ID MSG_BELL_TRIGGER
   global MSG_ALARM_COUNTER MSG_CENTER_USE_BELL

   set autoMsgDisplay [SharedData_getMiscData AUTO_MSG_DISPLAY]

   # flash
   set alarmBgColor [SharedData_getColor COLOR_MSG_CENTER_MAIN]
   set normalFgColor [SharedData_getColor DEFAULT_HEADER_FG]
   set raiseAlarm false

   # I don't start the alarm counter until the gui is up
   if  { [SharedData_getMiscData STARTUP_DONE] == "true" } {
      incr MSG_ALARM_COUNTER
   }

   ::log::log debug "MsgCenter_processAlarm MSG_ALARM_COUNTER:${MSG_ALARM_COUNTER} MSG_BELL_TRIGGER:${MSG_BELL_TRIGGER}"
   # only raise alarm if no other alarm already exists
   if { ${MSG_ALARM_ON} == "true" } {
      if { ${repeat_alarm} == "true" } {
         set raiseAlarm true
      }
   } else {
      set MSG_ALARM_ON true
      set raiseAlarm true
      # put the window on top of the rest
      #wm attributes . -topmost 1
   }
   if { ${autoMsgDisplay} == "true" && [SharedData_getMiscData STARTUP_DONE] == "true" } {
      if { ${raiseAlarm} == "true" } {
         MsgCenter_setHeaderStatus ${table_w_} alarm
         if { [expr ${MSG_ALARM_COUNTER} > ${MSG_BELL_TRIGGER}] && ${MSG_CENTER_USE_BELL} == true } {
            bell
         }
         set MSG_ALARM_ID [after 1500 [list MsgCengter_processAlarm ${table_w_} true]]
      }
   
      MsgCenter_show
   }
}

proc MsgCenter_stopBell { table_w_ } {
   global MSG_ALARM_ON MSG_ALARM_ID MSG_ALARM_COUNTER

   set MSG_ALARM_ON false
   set MSG_ALARM_COUNTER 0
   if { [info exists MSG_ALARM_ID] } {
      after cancel ${MSG_ALARM_ID}
   }
   MsgCenter_setHeaderStatus ${table_w_} alarm_bg
}

proc MsgCenter_close {} {
   ::log::log debug "MsgCenter_close..."
   wm withdraw [MsgCenter_getToplevel]
}

proc MsgCenter_show {} {
   set topW [MsgCenter_getToplevel]
   set currentStatus [wm state ${topW}]
   switch ${currentStatus} {
      withdrawn -
      iconic {
         wm deiconify ${topW}
      }
   }
   if { [SharedData_getMiscData STARTUP_DONE] == "true" } {
      raise ${topW}
   }
}

########################################
# thread procedures
# The MsgCenter Thread act as a singleton
# for new messages coming from all the
# monitored exps.
# It is either called from xflow standalone thread (one experiment)
# or from xflow_overview (multiple experiments).
# 
# Messages coming from each suite's thread
# should be sent to the MsgCenterThread_newMessage
########################################
proc MsgCenter_getThread {} {
   # start synchronizing this block, get an exclusive lock

   ::log::log debug "MsgCenter_getThread ..."
   set threadID [SharedData_getMsgCenterThreadId]
   if { ${threadID} == "" } {
      ::log::log debug "MsgCenter_getThread Creating new thread..."
      set threadID [thread::create {
         global env this_id
         set lib_dir $env(SEQ_XFLOW_BIN)/../lib
         set auto_path [linsert $auto_path 0 $lib_dir ]

         set this_id [thread::id]
         SharedData_setMsgCenterThreadId ${this_id}
         MsgCenter_init

         tk appname "Message Center"

         #
         # From here to the 'thread::wait' statement, define the procedure(s)
         # that will be called from your main program
         #
         # The 'thread::wait' is required to keep this thread alive indefinitely.
         #

         # called everytime a new message comes in from experiment threads
         proc MsgCenterThread_newMessage { calling_thread_id datestamp_ timestamp_ type_ node_ exp_ msg_ } {
            ::log::log debug "MsgCenterThread_newMessage calling_thread_id:${calling_thread_id} ${datestamp_} ${timestamp_} ${type_} ${node_} ${msg_} ${exp_}"
            MsgCenter_newMessage [MsgCenter_getTableWidget] ${datestamp_} ${timestamp_} ${type_} ${node_} ${msg_} ${exp_} 
            # if the exp is done reading messages, we send a notification out
            # to warn about new messages available in the msg center
            if { [SharedData_getMiscData ${calling_thread_id}_STARTUP_DONE] == true } {
               MsgCenter_sendNotification
            }
         }

         # called by xflow_overview to cleanup datestamp when not visible anymore
        proc MsgCenterThread_removeDatestamp { exp_ datestamp_ } {
           MsgCenter_removeMessages [MsgCenter_getTableWidget] ${exp_} ${datestamp_}
        }

         # called by xflow or xflow_overview to show msg center on demand
         proc MsgCenterThread_showWindow {} {
            MsgCenter_show
         }

         # called by xflow or xflow_overview to let msg center
         # that application startup is done
         proc MsgCenterThread_startupDone {} {
            global MSG_COUNTER
            MsgCenter_sendNotification
            # sort the msg by timestamp ascending order
            MsgCenter_initialSort [MsgCenter_getTableWidget]
            if { [SharedData_getMiscData AUTO_MSG_DISPLAY] == true && ${MSG_COUNTER} > 0 } {
               MsgCenter_show
            }
         }

         proc MsgCenterThread_quit {} {
            exit
         }

         # enter event loop
         thread::wait
      }]
   }

   ::log::log debug "MsgCenter_getThread returning id: ${threadID}"
   return ${threadID}
}

proc MsgCenter_setTitle { top_w } {
   global env
   set current_time [clock format [clock seconds] -format "%H:%M" -gmt 1]
   set winTitle "Message Center - User=$env(USER) Host=[exec hostname] Time=${current_time}"
   wm title [winfo toplevel ${top_w}] ${winTitle}

   # refresh title every minute
   set TimeAfterId [after 60000 [list MsgCenter_setTitle ${top_w}]]
}

########################################
# callback procedures
########################################
proc MsgCenter_DoubleClickCallback { table_widget } {
   global MsgTableColMap

   ::log::log debug "MsgCenter_DoubleClickCallback widget:${table_widget}"
   set selectedRow [${table_widget} curselection]
   # retrieve needed information
   set node [${table_widget} getcells ${selectedRow},$MsgTableColMap(NodeColNumber)]
   set expPath [${table_widget} getcells ${selectedRow},$MsgTableColMap(SuiteColNumber)]
   set datestamp [${table_widget} getcells ${selectedRow},$MsgTableColMap(DatestampColNumber)]
   set realDatestamp [Utils_getRealDatestampValue ${datestamp}]
   ::log::log debug "MsgCenter_DoubleClickCallback node:${node} expPath:${expPath} ${datestamp}"

   if { ${node} == "" || ${expPath} == "" } {
      return
   }

   Utils_busyCursor ${table_widget}
   set result [ catch {
      # start the suite flow if not started
      set isOverviewMode [SharedData_getMiscData OVERVIEW_MODE]
      set expThreadId [SharedData_getExpThreadId ${expPath} ${realDatestamp}]
      if { ${isOverviewMode} == "true" } {
         set overviewThreadId [SharedData_getMiscData OVERVIEW_THREAD_ID]
         thread::send ${overviewThreadId} "Overview_launchExpFlow ${expPath} ${realDatestamp}"

         # ask the suite thread to take care of showing the selected node in it's flow
         set convertedNode [SharedFlowNode_convertFromDisplayFormat ${node}]
         thread::send ${overviewThreadId} "xflow_findNode ${expPath} ${realDatestamp} ${convertedNode}"
      } else {

         # ask the suite thread to take care of showing the selected node in it's flow
         set convertedNode [SharedFlowNode_convertFromDisplayFormat ${node}]
         thread::send ${expThreadId} "xflow_findNode ${expPath} ${convertedNode}"
      }

      Utils_normalCursor ${table_widget}

   } message ]

   # any errors, put the cursor back to normal state
   if { ${result} != 0  } {

      set einfo $::errorInfo
      set ecode $::errorCode
      Utils_normalCursor ${table_widget}
      # report the error with original details
      return -code ${result} \
         -errorcode ${ecode} \
         -errorinfo ${einfo} \
         ${message}
   }
}

########################################
# end callback procedures
########################################

proc MsgCenter_init {} {
   global MSG_ALARM_ON MsgCenterMainGridRowMap
   global MSG_TABLE MSG_COUNTER MSG_ALARM_COUNTER
   global SHOW_ABORT_TYPE SHOW_INFO_TYPE SHOW_EVENT_TYPE
   global DEBUG_TRACE MSG_BELL_TRIGGER MSG_CENTER_USE_BELL

   set DEBUG_TRACE [SharedData_getMiscData DEBUG_TRACE]
   set MSG_BELL_TRIGGER [SharedData_getMiscData MSG_CENTER_BELL_TRIGGER]

   Utils_logInit

   # this variable is true when a new message comes in
   # and we need to warn the user about it
   set MSG_ALARM_ON false

   # this variable is used to count the number of times we warn the user
   # by flashing the msg center. After a defined number of times
   # we beep
   set MSG_ALARM_COUNTER 0

   # this variable is a list that is used to store all messages received.
   # each list is {timestamp datestamp status node  msg exp}
   # 
   # example for a list of 2 messages:
   # {20120418.07:02:10 20120418000000 abort /reps_mod/Forecasts/gem_loop/prep_pilot+2 \
   # {ABORTED job stopped , job_ID=c2sn2h0.cmc.ec.gc.ca.586135.0} /home/binops/afsi/par/maestro_suites/reps/forecast/er00}
   # {20120418.07:04:00 20120418000000 abort /reps_mod/Forecasts/gem_loop/prep_pilot+2 \
   # {ABORTED job stopped , job_ID=c2sn1h0.cmc.ec.gc.ca.586250.0} /home/binops/afsi/par/maestro_suites/reps/forecast/er00}
   set MSG_TABLE {}

   # counter for all received messages
   set MSG_COUNTER 0

   # reset active messages, the list of active messages is a bit different than the MSG_TABLE.
   # The active messages can be filtered out by "Message Type"
   MsgCenter_initActiveMessages

   # get the list of message filters
   set SHOW_ABORT_TYPE [SharedData_getMiscData SHOW_ABORT_TYPE]
   set SHOW_INFO_TYPE [SharedData_getMiscData SHOW_INFO_TYPE]
   set SHOW_EVENT_TYPE [SharedData_getMiscData SHOW_EVENT_TYPE]

   # is bell activated?
   set MSG_CENTER_USE_BELL true
   if { [SharedData_getMiscData USE_BELL] == false } {
      set MSG_CENTER_USE_BELL false
   }

   set topLevelW .
   set tableW .table
   
   if { ! [winfo exists ${tableW}] } {
      array set MsgCenterMainGridRowMap {
         Menu 0
         Toolbar 1
         MsgTable 2
      }

      #SharedData_initColors
      MsgCenter_setTkOptions

      MsgCenter_createWidgets

      MsgCenter_close
      
      wm protocol ${topLevelW} WM_DELETE_WINDOW [list MsgCenter_close]
      
      # point the node in its respective flow on double click
      bind [${tableW} bodytag] <Double-Button-1> [ list MsgCenter_DoubleClickCallback ${tableW}]
      
      MsgCenter_setTitle ${topLevelW}

      # give full space to message table
      grid columnconfigure ${topLevelW} 0 -weight 1

      # give new real estate to the msg table
      grid rowconfigure ${topLevelW} $MsgCenterMainGridRowMap(MsgTable) -weight 1

      wm minsize ${topLevelW} 800 200
   }
}


