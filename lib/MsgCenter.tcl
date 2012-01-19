#!/home/binops/afsi/ssm/domain2/tcl-tk_8.5.7_linux26-i686/bin/tclsh8.5
package require Tk
package require Tktable
package require autoscroll
package require tooltip

global env
set lib_dir $env(SEQ_XFLOW_BIN)/../lib
#puts "lib_dir=$lib_dir"
set auto_path [linsert $auto_path 0 $lib_dir ]

proc MsgCenter_setTkOptions {} {
   option add *activeBackground [SharedData_getColor ACTIVE_BG]
   option add *selectBackground [SharedData_getColor SELECT_BG]

   #ttk::style configure Xflow.Menu -background cornsilk4
}

proc MsgCenter_createMenus {} {
   global RowNumberMap
   set topFrame .topframe
   frame ${topFrame} -relief [SharedData_getMiscData MENU_RELIEF]
   MsgCenter_addFileMenu ${topFrame}
   MsgCenter_addPrefMenu ${topFrame}
   MsgCenter_addHelpMenu ${topFrame}
   grid ${topFrame} -row $RowNumberMap(Menu) -column 0 -sticky ew -padx 2
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
   global RowNumberMap
   set toolbarW .toolbar
   set bellW ${toolbarW}.button_bell
   set ackW ${toolbarW}.button_ack
   set clearW ${toolbarW}.button_clear
   set closeW ${toolbarW}.button_close
   frame ${toolbarW}

   set imageDir [SharedData_getMiscData IMAGE_DIR]
   image create photo ${toolbarW}.stop_bell -file ${imageDir}/bell_cross.ppm
   button ${bellW} -image ${toolbarW}.stop_bell -command [list MsgCenter_stopBell ${table_w_}]
   ::tooltip::tooltip ${bellW} "Stop ringing bell."

   image create photo ${toolbarW}.ack_msg -file ${imageDir}/message_ack.ppm
   button ${ackW} -image ${toolbarW}.ack_msg -command [list MsgCenter_ackMessages ${table_w_}]
   ::tooltip::tooltip ${ackW} "Acknowledge new messages."

   image create photo ${toolbarW}.clear_msg -file ${imageDir}/message_clear.ppm
   button ${clearW} -image ${toolbarW}.clear_msg -command [list MsgCenter_clearMessages ${clearW} ${table_w_}]
   ::tooltip::tooltip ${clearW} "Clear all messages."

   image create photo ${toolbarW}.close -file ${imageDir}/cancel.ppm
   button ${closeW} -image ${toolbarW}.close -command [list MsgCenter_close]
   ::tooltip::tooltip ${closeW} "Close Message Center."

   if { [SharedData_getMiscData OVERVIEW_MODE] == "true" } {
      set overviewW ${toolbarW}.button_overview
      image create photo ${toolbarW}.overview -file ${imageDir}/calendar_clock.ppm
      button ${overviewW} -image ${toolbarW}.overview -command {
         set overviewThreadId [SharedData_getMiscData OVERVIEW_THREAD_ID]
         thread::send -async ${overviewThreadId} "Overview_toFront"
      }
      ::tooltip::tooltip ${overviewW} "Show Overview Window."
      grid ${bellW} ${ackW} ${clearW} ${overviewW} ${closeW} -padx 2 -sticky w
   } else {
      grid ${bellW} ${ackW} ${clearW} ${closeW} -padx 2 -sticky w
   }

   grid ${toolbarW} -row $RowNumberMap(Toolbar) -column 0 -sticky ew -padx 2 -pady 2
   grid columnconfigure ${toolbarW} ${closeW} -weight 1
}

proc MsgCenter_createWidgets {} {
   global TimestampColNumber DatestampColNumber TypeColNumber
   global NodeColNumber MessageColNumber SuiteColNumber
   global MSG_ACTIVE_TABLE MSG_ACTIVE_COUNTER
   global RowNumberMap

   set tableW .table
   set yscrollW .sy
   set xscrollW .sx
   set defaultRows [SharedData_getMiscData MSG_CENTER_NUMBER_ROWS]
   set timeStampColWidth 16
   set dateStampColWidth 16
   set typeColWidth 8
   set nodeColWidth 30
   set msgColWidth 30
   set suiteColWidth 40
   set titleFont "-adobe-courier-bold-r-normal--14-100-100-100-m-90-iso8859-1"
   set rowFgColor [SharedData_getColor DEFAULT_ROW_BG]
   set tableBgColor [SharedData_getColor DEFAULT_BG]
   set headerBgColor [SharedData_getColor MSG_CENTER_ABORT_BG]
   set headerFgColor [SharedData_getColor DEFAULT_HEADER_FG]
   if { ! [winfo exists ${tableW}] } {
      DEBUG "MsgCenter_createWidgets ..." 5
      MsgCenter_createMenus
      MsgCenter_createToolbar ${tableW}
      table ${tableW} -cols 6 -rows ${defaultRows} -titlecols 0 -titlerows 1 -pady 6 -rowheight 1 \
         -colstretchmode all -rowstretchmode unset -variable MSG_ACTIVE_TABLE -state disabled -bg ${tableBgColor} \
         -yscrollcommand [list ${yscrollW} set] -xscrollcommand [list ${xscrollW} set] -selecttitle 1 -drawmode fast

      ${tableW} width ${TimestampColNumber} ${timeStampColWidth} \
         ${DatestampColNumber} ${dateStampColWidth} \
         ${TypeColNumber} ${typeColWidth} \
         ${NodeColNumber} ${nodeColWidth} \
         ${MessageColNumber} ${msgColWidth} \
         ${SuiteColNumber} ${suiteColWidth}

      ${tableW} tag configure title -bd 1 -bg ${headerBgColor} -relief raised -font ${titleFont} -fg ${headerFgColor}
      Utils_bindMouseWheel ${tableW} 2
   }

   # creating scrollbars
   scrollbar ${yscrollW} -command [list ${tableW} yview]
   scrollbar ${xscrollW} -command [list ${tableW} xview] -orient horizontal
   ::autoscroll::autoscroll ${yscrollW}
   ::autoscroll::autoscroll ${xscrollW}

   grid ${tableW} -row $RowNumberMap(MsgTable) -column 0 -sticky nsew -padx 2 -pady 2
   grid ${yscrollW} -row $RowNumberMap(MsgTable) -column 1 -sticky nsew -padx 2 -pady 2
   grid ${xscrollW} -sticky ew
}

proc MsgCenter_getTableWidget {} {
   return .table
}

proc MsgCenter_getToplevel {} {
   return .
}

proc MsgCenter_setHeaderStatus { table_w_ status_ } {
   set alarmBgColor [SharedData_getColor MSG_CENTER_ABORT_BG]
   set normalFgColor [SharedData_getColor DEFAULT_HEADER_FG]
   set normalBgColor [SharedData_getColor MSG_CENTER_ABORT_BG]
   set alarmAltBgColor [SharedData_getColor MSG_CENTER_ALT_BG]

   set currentBgColor [${table_w_} tag cget title -bg]
   if { ${status_} == "normal" } {
      ${table_w_} tag configure title -bg ${normalBgColor} -fg ${normalFgColor}
   } elseif { ${status_} == "alarm_bg" } {
      ${table_w_} tag configure title -bg ${alarmBgColor} -fg ${normalFgColor}
   } else {
      # alarm state
      if { ${currentBgColor} == ${alarmBgColor} } {
         ${table_w_} tag configure title -bg ${alarmAltBgColor}
      } else {
         ${table_w_} tag configure title -bg ${alarmBgColor}
      }
   }
}

proc MsgCenter_newMessage { table_w_ datestamp_ timestamp_ type_ node_ msg_ exp_ } {
   global TimestampColNumber DatestampColNumber TypeColNumber
   global NodeColNumber MessageColNumber SuiteColNumber
   global MSG_TABLE MSG_COUNTER MSG_ACTIVE_COUNTER
   incr MSG_COUNTER
   DEBUG "MsgCenter_newMessage node_:$node_ type_:$type_ msg_:$msg_"
   set displayedNodeText [::FlowNodes::convertToDisplayFormat ${node_}]
   set MSG_TABLE(${MSG_COUNTER},${TimestampColNumber}) ${timestamp_}
   set MSG_TABLE(${MSG_COUNTER},${DatestampColNumber}) ${datestamp_}
   set MSG_TABLE(${MSG_COUNTER},${TypeColNumber}) ${type_}
   set MSG_TABLE(${MSG_COUNTER},${NodeColNumber}) ${displayedNodeText}
   set MSG_TABLE(${MSG_COUNTER},${MessageColNumber}) ${msg_}
   set MSG_TABLE(${MSG_COUNTER},${SuiteColNumber}) ${exp_}

   set isMsgActive [MsgCenter_addActiveMessage ${datestamp_} ${timestamp_} ${type_} ${node_} ${msg_} ${exp_}]

   if { ${isMsgActive} == "true" } {

      # do we need to add more rows to the table?
      set currentNumberRows [${table_w_} cget -rows]
      if { [expr ${MSG_ACTIVE_COUNTER} > ${currentNumberRows}] } {
         # on ajoute 10
         ${table_w_} configure -rows [expr ${currentNumberRows} + 10]
      }
      ${table_w_} tag row NewMessageTag ${MSG_ACTIVE_COUNTER}
      ${table_w_} see ${MSG_ACTIVE_COUNTER},0
      MsgCengter_processAlarm ${table_w_}
      MsgCenter_sendNotification
   }

   # adjust field length
   # for limit setting in GUI
   set currentLength [SharedData_getMiscData MAX_NODE_LENGTH]
   set nodeLength [string length ${node_}]
   if { ${nodeLength} > ${currentLength} } {
      SharedData_setMiscData MAX_NODE_LENGTH [string length ${node_}]
      ${table_w_} width ${NodeColNumber} ${nodeLength} 
   }
}

# see if we need to send notification to xflow or xflow-overview
# for new messages
proc MsgCenter_sendNotification {} {
   global MSG_ACTIVE_COUNTER
   set isStartupDone [SharedData_getMiscData STARTUP_DONE]
   if { ${isStartupDone} == "true" && [expr ${MSG_ACTIVE_COUNTER} > 1] } {
      set isOverviewMode [SharedData_getMiscData OVERVIEW_MODE]
      if { ${isOverviewMode} == "true" } {
         set overviewThreadId [SharedData_getMiscData OVERVIEW_THREAD_ID]
         thread::send ${overviewThreadId} "Overview_newMessageCallback true"
      } else {
         set xflowThreadId [SharedData_getMiscData XFLOW_THREAD_ID]
         thread::send ${xflowThreadId} "xflow_newMessageCallback true"
      }
   }
}

proc MsgCenter_addActiveMessage { datestamp_ timestamp_ type_ node_ msg_ exp_ } {
   global TimestampColNumber DatestampColNumber TypeColNumber
   global NodeColNumber MessageColNumber SuiteColNumber
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
      DEBUG "MsgCenter_addActiveMessage adding ${datestamp_} ${timestamp_} ${type_} ${node_} ${msg_} ${exp_}" 5
      set displayedNodeText [::FlowNodes::convertToDisplayFormat ${node_}]
      incr MSG_ACTIVE_COUNTER
      set MSG_ACTIVE_TABLE(${MSG_ACTIVE_COUNTER},${TimestampColNumber}) ${timestamp_}
      set MSG_ACTIVE_TABLE(${MSG_ACTIVE_COUNTER},${DatestampColNumber}) ${datestamp_}
      set MSG_ACTIVE_TABLE(${MSG_ACTIVE_COUNTER},${TypeColNumber}) ${type_}
      set MSG_ACTIVE_TABLE(${MSG_ACTIVE_COUNTER},${NodeColNumber}) ${displayedNodeText}
      set MSG_ACTIVE_TABLE(${MSG_ACTIVE_COUNTER},${MessageColNumber}) ${msg_}
      set MSG_ACTIVE_TABLE(${MSG_ACTIVE_COUNTER},${SuiteColNumber}) ${exp_}
   }

   return ${isMsgActive}
}

# refresh shown messages based on user message type filters
proc MsgCenter_refreshActiveMessages { table_w_ } {
   global MSG_TABLE MSG_COUNTER
   global TimestampColNumber DatestampColNumber TypeColNumber
   global NodeColNumber MessageColNumber SuiteColNumber

   MsgCenter_ackMessages ${table_w_}
   set counter 1
   MsgCenter_initActiveMessages
   while { ${counter} <= ${MSG_COUNTER} } {
      set timestamp $MSG_TABLE(${counter},${TimestampColNumber})
      set datestamp $MSG_TABLE(${counter},${DatestampColNumber})
      set type $MSG_TABLE(${counter},${TypeColNumber})
      set node $MSG_TABLE(${counter},${NodeColNumber})
      set msg $MSG_TABLE(${counter},${MessageColNumber})
      set exp $MSG_TABLE(${counter},${SuiteColNumber})
      DEBUG "MsgCenter_refreshActiveMessages coun:$counter type:$type node:$node msg:$msg exp:$exp" 5
      MsgCenter_addActiveMessage ${datestamp} ${timestamp} ${type} ${node} ${msg} ${exp}
      incr counter
   }
}

proc MsgCenter_initActiveMessages {} {
   global TimestampColNumber DatestampColNumber TypeColNumber NodeColNumber MessageColNumber SuiteColNumber

   global MSG_ACTIVE_TABLE MSG_ACTIVE_COUNTER
   array unset MSG_ACTIVE_TABLE

   set MSG_ACTIVE_TABLE(0,${TimestampColNumber}) "Timestamp"
   set MSG_ACTIVE_TABLE(0,${DatestampColNumber}) "Datestamp"
   set MSG_ACTIVE_TABLE(0,${TypeColNumber}) "Type"
   set MSG_ACTIVE_TABLE(0,${NodeColNumber}) "Node"
   set MSG_ACTIVE_TABLE(0,${MessageColNumber}) "Message"
   set MSG_ACTIVE_TABLE(0,${SuiteColNumber}) "Suite"

   set MSG_ACTIVE_COUNTER 0
}

proc MsgCenter_ackMessages { table_w_ } {
   wm attributes . -topmost 0
   MsgCenter_stopBell ${table_w_}
   set rows [${table_w_} tag row NewMessageTag]
   foreach row ${rows} {
      ${table_w_} tag row NormalMessageTag ${row}
   }
   MsgCenter_setHeaderStatus ${table_w_} normal
   set isOverviewMode [SharedData_getMiscData OVERVIEW_MODE]
   if { ${isOverviewMode} == "true" } {
      set overviewThreadId [SharedData_getMiscData OVERVIEW_THREAD_ID]
      thread::send ${overviewThreadId} "Overview_newMessageCallback false"
   } else {
      set xflowThreadId [SharedData_getMiscData XFLOW_THREAD_ID]
      thread::send ${xflowThreadId} "xflow_newMessageCallback false"
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

      # reset default rows
      ${table_w_} configure -rows [SharedData_getMiscData MSG_CENTER_NUMBER_ROWS]
   }
}

proc MsgCengter_processAlarm { table_w_ {repeat_alarm false} } {
   global MSG_ALARM_ON MSG_ALARM_ID MSG_BELL_TRIGGER
   global MSG_ALARM_COUNTER

   set autoMsgDisplay [SharedData_getMiscData AUTO_MSG_DISPLAY]

   # flash
   set alarmBgColor [SharedData_getColor MSG_CENTER_ABORT_BG]
   set normalFgColor [SharedData_getColor DEFAULT_HEADER_FG]
   set raiseAlarm false

   # I don't start the alarm counter until the gui is up
   if  { [SharedData_getMiscData STARTUP_DONE] == "true" } {
      incr MSG_ALARM_COUNTER
   }

   DEBUG "MsgCengter_processAlarm MSG_ALARM_COUNTER:${MSG_ALARM_COUNTER} MSG_BELL_TRIGGER:${MSG_BELL_TRIGGER}" 5
   # only raise alarm if no other alarm already exists
   if { ${MSG_ALARM_ON} == "true" } {
      if { ${repeat_alarm} == "true" } {
         set raiseAlarm true
      }
   } else {
      set MSG_ALARM_ON true
      set raiseAlarm true
      # put the window on top of the rest
      wm attributes . -topmost 1
   }
   if { ${autoMsgDisplay} == "true" && [SharedData_getMiscData STARTUP_DONE] == "true" } {
      if { ${raiseAlarm} == "true" } {
         MsgCenter_setHeaderStatus ${table_w_} alarm
         if { [expr ${MSG_ALARM_COUNTER} > ${MSG_BELL_TRIGGER}] } {
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
   wm attributes . -topmost 0
   if { [info exists MSG_ALARM_ID] } {
      after cancel ${MSG_ALARM_ID}
   }
   MsgCenter_setHeaderStatus ${table_w_} alarm_bg
}

proc MsgCenter_refreshTable { table_w_ } {
   # workaround for refresh bug in table
   ${table_w_} width 0 [${table_w_} width 0]
   update idletasks
   ${table_w_} width 0 [${table_w_} width 0]
}

proc MsgCenter_createTags { table_w_ } {
   set newMsgFgColor [SharedData_getColor MSG_CENTER_ABORT_BG]
   set normalMsgFgColor [SharedData_getColor MSG_CENTER_NORMAL_FG]
   ${table_w_} tag configure NewMessageTag -fg ${newMsgFgColor}
   ${table_w_} tag configure NormalMessageTag -fg ${normalMsgFgColor}
}

proc MsgCenter_close {} {
   DEBUG "MsgCenter_close..." 5
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
      normal {
         if { [SharedData_getMiscData STARTUP_DONE] == "true" && [wm attributes . -topmost] == "0" } {
            wm withdraw ${topW} ; wm deiconify ${topW}
         }
      }
   }
}

########################################
# thread procedures
# The MsgCenter Thread act as a singleton
# for new messages coming from all the
# monitored suites.
# Messages coming from the each suite thread
# should be sent to the MsgCenterThread_newMessage
########################################
proc MsgCenter_getThread {} {
   # start synchronizing this block, get an exclusive lock

   DEBUG "MsgCenter_getThread ..." 5
   set threadID [SharedData_getMsgCenterThreadId]
   if { ${threadID} == "" } {
      DEBUG "MsgCenter_getThread Creating new thread..." 5
      set threadID [thread::create {
         global env this_id
         set lib_dir $env(SEQ_XFLOW_BIN)/../lib
         set auto_path [linsert $auto_path 0 $lib_dir ]

         set this_id [thread::id]
         SharedData_setMsgCenterThreadId ${this_id}
         MsgCenter_init
         #
         # From here to the 'thread::wait' statement, define the procedure(s)
         # that will be called from your main program
         #
         # The 'thread::wait' is required to keep this thread alive indefinitely.
         #

         proc MsgCenterThread_newMessage { datestamp_ timestamp_ type_ node_ exp_ msg_ } {
            DEBUG "MsgCenterThread_newMessage ${datestamp_} ${timestamp_} ${type_} ${node_} ${msg_} ${exp_}" 5
            MsgCenter_newMessage [MsgCenter_getTableWidget] ${datestamp_} ${timestamp_} ${type_} ${node_} ${msg_} ${exp_} 
         }

         proc MsgCenterThread_showWindow {} {
            MsgCenter_show
         }

         proc MsgCenterThread_startupDone {} {
	    global MSG_COUNTER
            MsgCenter_sendNotification
	    if { ${MSG_COUNTER} > 0 } {
	       MsgCenter_show
	    }
         }

         # enter event loop
         thread::wait
      }]
   }

   DEBUG "MsgCenter_getThread returning id: ${threadID}" 5
   return ${threadID}
}

proc MsgCenter_initThread {} {
   set threadID [SharedData_getMsgCenterThreadId]
   if { ${threadID} == "" } {
      set threadID [thread::create {
         global env
         set lib_dir $env(SEQ_XFLOW_BIN)/../lib
         set auto_path [linsert $auto_path 0 $lib_dir ]
   
         #
         # From here to the 'thread::wait' statement, define the procedure(s)
         # that will be called from your main program
         #
         # The 'thread::wait' is required to keep this thread alive indefinitely.
         #
         global this_id
         set this_id [thread::id]
   
         proc MsgCenterThread_newMessage { datestamp_ timestamp_ type_ node_ exp_ msg_ } {
            DEBUG "MsgCenterThread_newMessage ${datestamp_} ${timestamp_} ${type_} ${node_} ${msg_} ${exp_}" 5
            MsgCenter_newMessage [MsgCenter_getTableWidget] ${datestamp_} ${timestamp_} ${type_} ${node_} ${msg_} ${exp_} 
         }
         MsgCenter_init
         SharedData_setMsgCenterThreadId ${this_id}
         # enter event loop
         thread::wait
      }]
   }
}

########################################
# end thread procedures
########################################

########################################
# callback procedures
########################################
# %W
proc MsgCenter_Button3Callback { widget_ } {
   DEBUG "MsgCenter_Button3Callback widget:${widget_}" 5
}

proc MsgCenter_DoubleClickCallback { table_widget } {
   global NodeColNumber SuiteColNumber
   DEBUG "MsgCenter_DoubleClickCallback widget:${table_widget}" 5
   #puts "MsgCenter_DoubleClickCallback active cell: [${widget_} tag cell active]"
   #puts "MsgCenter_DoubleClickCallback active cell: [${widget_} tag cell active]"
   set currentCell [${table_widget} curselection]
   set selectedRow [lindex [split ${currentCell} ,] 0]
   set selectedCol [lindex [split ${currentCell} ,] 1]
   if { [expr ${selectedRow} > 0] && ${selectedCol} == ${NodeColNumber} } {
      # retrieve needed information
      set node [${table_widget} get ${selectedRow},${NodeColNumber}]
      set suitePath [${table_widget} get ${selectedRow},${SuiteColNumber}]
      DEBUG "MsgCenter_DoubleClickCallback node:${node} suitePath:${suitePath}" 5

      if { ${node} == "" || ${suitePath} == "" } {
         return
      }

      # start the suite flow if not started
      set isOverviewMode [SharedData_getMiscData OVERVIEW_MODE]
      set suiteThreadId [SharedData_getSuiteData ${suitePath} THREAD_ID]
      set suiteRecord [::SuiteNode::formatSuiteRecord ${suitePath}]
      if { ${isOverviewMode} == "true" } {
         set overviewThreadId [SharedData_getMiscData OVERVIEW_THREAD_ID]
         thread::send ${suiteThreadId} "thread_launchFLow ${overviewThreadId} ${suitePath}"
      }

      # ask the suite thread to take care of showing the selected node in it's flow
      set convertedNode [::FlowNodes::convertFromDisplayFormat ${node}]
      thread::send ${suiteThreadId} "xflow_findNode ${suiteRecord} ${convertedNode}"
   }
}

########################################
# end callback procedures
########################################

proc MsgCenter_init {} {
   global MSG_ALARM_ON RowNumberMap
   global MSG_TABLE MSG_COUNTER MSG_ALARM_COUNTER
   global SHOW_ABORT_TYPE SHOW_INFO_TYPE SHOW_EVENT_TYPE
   global DEBUG_TRACE DEBUG_LEVEL MSG_BELL_TRIGGER
   global TimestampColNumber DatestampColNumber TypeColNumber NodeColNumber MessageColNumber SuiteColNumber

   set TimestampColNumber 0
   set DatestampColNumber 1
   set TypeColNumber 2
   set NodeColNumber 3
   set MessageColNumber 4
   set SuiteColNumber 5

   set DEBUG_TRACE [SharedData_getMiscData DEBUG_TRACE]
   set DEBUG_LEVEL [SharedData_getMiscData DEBUG_LEVEL]
   set MSG_BELL_TRIGGER [SharedData_getMiscData MSG_CENTER_BELL_TRIGGER]

   set MSG_ALARM_ON false
   set MSG_ALARM_COUNTER 0

   array set RowNumberMap {
      Menu 0
      Toolbar 1
      MsgTable 2
   }
   set MSG_TABLE(0,${TimestampColNumber}) "Timestamp"
   set MSG_TABLE(0,${DatestampColNumber}) "Datestamp"
   set MSG_TABLE(0,${TypeColNumber}) "Type"
   set MSG_TABLE(0,${NodeColNumber}) "Node"
   set MSG_TABLE(0,${MessageColNumber}) "Message"
   set MSG_TABLE(0,${SuiteColNumber}) "Suite"

   set MSG_COUNTER 0

   MsgCenter_initActiveMessages

   set SHOW_ABORT_TYPE [SharedData_getMiscData SHOW_ABORT_TYPE]
   set SHOW_INFO_TYPE [SharedData_getMiscData SHOW_INFO_TYPE]
   set SHOW_EVENT_TYPE [SharedData_getMiscData SHOW_EVENT_TYPE]

   set topLevelW .
   set tableW .table
   
   if { ! [winfo exists ${tableW}] } {
      #SharedData_initColors
      MsgCenter_setTkOptions

      MsgCenter_createWidgets
      MsgCenter_createTags ${tableW}
      MsgCenter_close
      
      wm protocol ${topLevelW} WM_DELETE_WINDOW [list MsgCenter_close]
      
      bind ${tableW} <Button-3> [list MsgCenter_Button3Callback %W]
      bind ${tableW} <Double-Button-1> [ list MsgCenter_DoubleClickCallback %W]
      
      wm title ${topLevelW} "Maestro Message Center"
      grid columnconfigure ${topLevelW} 0 -weight 1
      # give new real estate to the msg table
      grid rowconfigure ${topLevelW} $RowNumberMap(MsgTable) -weight 1
   }
}


