#!/home/binops/afsi/ssm/domain2/tcl-tk_8.5.7_linux26-i686/bin/tclsh8.5
package require Tk
package require Tktable
package require autoscroll
package require tooltip

global env
set lib_dir $env(SEQ_XFLOW_BIN)/../lib
puts "lib_dir=$lib_dir"
set auto_path [linsert $auto_path 0 $lib_dir ]

proc MsgCenter_createToolbar { table_w_ } {
   set toolbarW .toolbar
   set bellW ${toolbarW}.button_bell
   set ackW ${toolbarW}.button_ack
   set closeW ${toolbarW}.button_close
   #frame ${toolbarW} -relief raised -bd 1
   frame ${toolbarW}

   set imageDir [SharedData_getMiscData IMAGE_DIR]
   image create photo ${toolbarW}.stop_bell -file ${imageDir}/bell_cross.ppm
   button ${bellW} -image ${toolbarW}.stop_bell -command [list MsgCenter_stopBell ${table_w_}]
   ::tooltip::tooltip ${bellW} "Stop ringing bell."

   image create photo ${toolbarW}.ack_msg -file ${imageDir}/message_ack.ppm
   button ${ackW} -image ${toolbarW}.ack_msg -command [list MsgCenter_ackMessages ${table_w_}]
   ::tooltip::tooltip ${ackW} "Acknowledge new messages."

   image create photo ${toolbarW}.close -file ${imageDir}/cancel.ppm
   button ${closeW} -image ${toolbarW}.close -command [list MsgCenter_close]
   ::tooltip::tooltip ${closeW} "Close Mesage Center."

   grid ${bellW} ${ackW} ${closeW} -padx 2 -pady 2 -sticky W
   #grid ${closeW} -padx 2 -pady 2 -sticky e
   grid ${toolbarW} -row 0 -column 0 -sticky ew -padx 2 -pady 2

   grid columnconfigure ${toolbarW} ${closeW} -weight 1
}

proc MsgCenter_createWidgets {} {
   global MSG_TABLE MSG_COUNTER

   set tableW .table
   set yscrollW .sy
   set xscrollW .sx
   set defaultRows 25
   set timeStampColWidth 16
   set typeColWidth 8
   set nodeColWidth 30
   set msgColWidth 30
   set suiteColWidth 40
   set titleFont "-adobe-courier-bold-r-normal--14-100-100-100-m-90-iso8859-1"
   set rowFgColor [SharedData_getColor DEFAULT_ROW_BG]
   set tableBgColor [SharedData_getColor DEFAULT_BG]
   #set headerBgColor [SharedData_getColor DEFAULT_HEADER_BG]
   set headerBgColor [SharedData_getColor STATUS_ABORT_BG]
   set headerFgColor [SharedData_getColor DEFAULT_HEADER_FG]
   if { ! [winfo exists ${tableW}] } {
      # toplevel ${top_w}
      DEBUG "MsgCenter_createWidgets ..." 5
      MsgCenter_createToolbar ${tableW}
      table ${tableW} -cols 5 -rows ${defaultRows} -titlecols 0 -titlerows 1 -pady 6 -rowheight 1 \
         -colstretchmode all -rowstretchmode all -variable MSG_TABLE -state disabled -bg ${tableBgColor} \
         -yscrollcommand [list ${yscrollW} set] -xscrollcommand [list ${xscrollW} set] -selecttitle 1 -drawmode fast

      ${tableW} width 0 ${timeStampColWidth} 1 ${typeColWidth} 2 ${nodeColWidth} \
         3 ${msgColWidth} 4 ${suiteColWidth}

      ${tableW} tag configure title -bd 1 -bg ${headerBgColor} -relief raised -font ${titleFont} -fg ${headerFgColor}

   }

   # creating scrollbars
   scrollbar ${yscrollW} -command [list ${tableW} yview]
   scrollbar ${xscrollW} -command [list ${tableW} xview] -orient horizontal
   ::autoscroll::autoscroll ${yscrollW}
   ::autoscroll::autoscroll ${xscrollW}

   grid ${tableW} -row 1 -column 0 -sticky nsew -padx 2 -pady 2
   grid ${yscrollW} -row 1 -column 1 -sticky nsew -padx 2 -pady 2
   grid ${xscrollW} -sticky ew


   array set MSG_TABLE {
      0,0 "Timestamp" 0,1 "Type" 0,2 "Node" 0,3 "Message" 0,4 "Suite"
   }
   set MSG_COUNTER 0
}

proc MsgCenter_getTableWidget {} {
   return .table
}

proc MsgCenter_getToplevel {} {
   return .
}

proc MsgCenter_setHeaderStatus { table_w_ status_ } {
   set alarmBgColor [SharedData_getColor STATUS_ABORT_BG]
   set normalFgColor [SharedData_getColor DEFAULT_HEADER_FG]
   # set normalBgColor [SharedData_getColor DEFAULT_HEADER_BG]
   set normalBgColor [SharedData_getColor STATUS_ABORT_BG]
   set alarmAltBgColor [SharedData_getColor ABORT_MSG_ALTERNATE_BG]

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

proc MsgCenter_addMessage { table_w_ timestamp_ type_ node_ msg_ exp_ } {
   global MSG_TABLE MSG_COUNTER
   incr MSG_COUNTER
   set MSG_TABLE(${MSG_COUNTER},0) ${timestamp_}
   set MSG_TABLE(${MSG_COUNTER},1) ${type_}
   set MSG_TABLE(${MSG_COUNTER},2) ${node_}
   set MSG_TABLE(${MSG_COUNTER},3) ${msg_}
   set MSG_TABLE(${MSG_COUNTER},4) ${exp_}

   ${table_w_} tag row NewMessageTag ${MSG_COUNTER}
   ${table_w_} see ${MSG_COUNTER},0

   MsgCengter_processAlarm ${table_w_}

   # adjust field length
   # for limit setting in GUI
   set currentLength [SharedData_getMiscData MAX_NODE_LENGTH]
   set nodeLength [string length ${node_}]
   if { ${nodeLength} > ${currentLength} } {
      SharedData_setMiscData MAX_NODE_LENGTH [string length ${node_}]
      ${table_w_} width 2 ${nodeLength} 
   }
   
}

proc MsgCenter_ackMessages { table_w_ } {
   MsgCenter_stopBell ${table_w_}
   set rows [${table_w_} tag row NewMessageTag]
   foreach row ${rows} {
      ${table_w_} tag row NormalMessageTag ${row}
   }
   MsgCenter_setHeaderStatus ${table_w_} normal
}

proc MsgCengter_processAlarm { table_w_ {auto_alarm false} } {
   global MSG_ALARM_ON MSG_ALARM_ID

   # flash
   set alarmBgColor [SharedData_getColor STATUS_ABORT_BG]
   set normalFgColor [SharedData_getColor DEFAULT_HEADER_FG]
   set raiseAlarm false

   # only raise alarm if no other alarm already exists
   if { ${MSG_ALARM_ON} == "true"} {
      if { ${auto_alarm} == "true" } {
         set raiseAlarm true
      }
   } else {
      set MSG_ALARM_ON true
      set raiseAlarm true
   }

   if { ${raiseAlarm} == "true" } {
      MsgCenter_setHeaderStatus ${table_w_} alarm
      # bell
      set MSG_ALARM_ID [after 1500 [list MsgCengter_processAlarm ${table_w_} true]]
   }
}

proc MsgCenter_stopBell { table_w_ } {
   global MSG_ALARM_ON MSG_ALARM_ID
   set MSG_ALARM_ON false
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
   set newMsgFgColor [SharedData_getColor STATUS_ABORT_BG]
   set normalMsgFgColor [SharedData_getColor NORMAL_MSG_FG]
   ${table_w_} tag configure NewMessageTag -fg ${newMsgFgColor}
   ${table_w_} tag configure NormalMessageTag -fg ${normalMsgFgColor}
}

proc MsgCenter_close {} {
   puts "MsgCenter_close..."
   wm withdraw [MsgCenter_getToplevel]
}

proc MsgCenter_show {} {
   set topW [MsgCenter_getToplevel]
   set currentStatus [wm state ${topW}]
   switch ${currentStatus} {
      withdrawn -
      iconic {
      }
      normal {
         wm withdraw ${topW}
      }
   }

   wm deiconify ${topW}
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
         #
         # From here to the 'thread::wait' statement, define the procedure(s)
         # that will be called from your main program
         #
         # The 'thread::wait' is required to keep this thread alive indefinitely.
         #

         proc MsgCenterThread_newMessage { timestamp_ type_ node_ exp_ msg_ } {
            DEBUG "MsgCenterThread_newMessage ${timestamp_} ${type_} ${node_} ${msg_} ${exp_}" 5
            MsgCenter_addMessage [MsgCenter_getTableWidget] ${timestamp_} ${type_} ${node_} ${msg_} ${exp_} 
         }

         proc MsgCenterThread_showWindow {} {
            MsgCenter_show
         }

         MsgCenter_init
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
   
         proc MsgCenterThread_newMessage { timestamp_ type_ node_ exp_ msg_ } {
            DEBUG "MsgCenterThread_newMessage ${timestamp_} ${type_} ${node_} ${msg_} ${exp_}" 5
            MsgCenter_addMessage [MsgCenter_getTableWidget] ${timestamp_} ${type_} ${node_} ${msg_} ${exp_} 
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
   puts "MsgCenter_Button3Callback widget:${widget_}"
}

proc MsgCenter_DoubleClickCallback { table_widget } {
   puts "MsgCenter_DoubleClickCallback widget:${table_widget}"
   #puts "MsgCenter_DoubleClickCallback active cell: [${widget_} tag cell active]"
   #puts "MsgCenter_DoubleClickCallback active cell: [${widget_} tag cell active]"
   set nodeColNumber 2
   set currentCell [${table_widget} curselection]
   set selectedRow [lindex [split ${currentCell} ,] 0]
   set selectedCol [lindex [split ${currentCell} ,] 1]
   if { [expr ${selectedRow} > 0] && ${selectedCol} == ${nodeColNumber} } {
      # retrieve needed information
      set node [${table_widget} get ${selectedRow},2]
      set suitePath [${table_widget} get ${selectedRow},4]
      puts "MsgCenter_DoubleClickCallback node:${node} suitePath:${suitePath}"

      # ask the suite thread to take care of showing the selected node in it's flow
      set threadId [SharedData_getSuiteData ${suitePath} THREAD_ID]
      set suiteRecord [::SuiteNode::formatSuiteRecord ${suitePath}]
      thread::send -async ${threadId} "::DrawUtils::pointNode ${suiteRecord} ${node}"
   }
}

########################################
# end callback procedures
########################################

# end 
########################################
# test procedures
#########################################
proc addTestMessages {} {
   set w .table
   MsgCenter_addMessage $w "10/06 18:12:58" "Info" \
      "/gem" "Initialization Completed."  "/users/dor/afsi/sul/.suites/gem_modv4"
   MsgCenter_addMessage $w "10/06 18:17:25" "Abort" \
      "/gem/gem_model" "Missing Data"  "/users/dor/afsi/sul/.suites/gem_modv4"
   MsgCenter_addMessage $w "10/06 20:30:34" "Info" \
      "/gem/gem_forecast" "Forecast Completed"  "/users/dor/afsi/sul/.suites/gem_modv4"
}

proc addTestOneMsg {} {
   set w .table
   MsgCenter_addMessage $w "10/12 13:12:58" "Abort" \
      "/gem" "Missing output directory."  "/users/dor/afsi/sul/.suites/gem_modv4"
}

proc testPointNode {} {
   set threadId [SharedData_getSuiteData /users/dor/afsi/sul/.suites/date_conc THREAD_ID]
   set suiteRecord [::SuiteNode::formatSuiteRecord /users/dor/afsi/sul/.suites/date_conc]
   DEBUG "testPointNode threadId:$threadId" 5
   thread::send -async ${threadId} "::DrawUtils::pointNode ${suiteRecord} /sample_mod/Family_2"
   DEBUG "testPointNode done..." 5
}

########################################
# end test procedures
#########################################

proc MsgCenter_init {} {
   global MSG_ALARM_ON
   set MSG_ALARM_ON false
   
   set topLevelW .
   set tableW .table

   if { ! [winfo exists ${tableW}] } {
      SharedData_initColors
      option add *activeBackground LightBlue
      option add *selectBackground LightBlue
      option add *selectColor red
      
      MsgCenter_createWidgets
      MsgCenter_createTags ${tableW}
      
      wm protocol ${topLevelW} WM_DELETE_WINDOW [list MsgCenter_close]
      
      bind ${tableW} <Button-3> [list MsgCenter_Button3Callback %W]
      bind ${tableW} <Double-Button-1> [ list MsgCenter_DoubleClickCallback %W]
      
      wm title ${topLevelW} "Maestro Message Center"
      grid columnconfigure ${topLevelW} 0 -weight 1
      grid rowconfigure ${topLevelW} 1 -weight 1
      grid rowconfigure ${topLevelW} 2 -weight 2
   }
}


