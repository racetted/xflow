package require Tk
#package require Tktable
package require tablelist
package require autoscroll
package require tooltip
package require log

global env
set lib_dir $env(SEQ_XFLOW_BIN)/../lib
# puts "lib_dir=$lib_dir"
set auto_path [linsert $auto_path 0 $lib_dir ]

proc MsgCenter_setTkOptions {} {
   option add *activeBackground [SharedData_getColor ACTIVE_BG]
   option add *selectBackground [SharedData_getColor SELECT_BG]
   catch { option add *troughColor [::tk::Darken [option get . background Scrollbar] 85] }

   #ttk::style configure Xflow.Menu -background cornsilk4
}

proc MsgCenter_SetNotebOption {notebookW_} {
   set font12 [list Helvetica 12 bold]
   set font10 [list Helvetica 10 bold]
   
   ttk::style configure msg.TNotebook   
   ttk::style configure msg.TNotebook.Tab 
   ttk::style configure msg.TNotebook.Tab -foreground black
   ttk::style map msg.TNotebook.Tab -background  [list selected [SharedData_getColor SELECT_BG] active [SharedData_getColor ACTIVE_BG] disabled black]
   ttk::style map msg.TNotebook.Tab -foreground [list selected white active white disabled black]
   ttk::style configure msg.TNotebook.Tab -font $font12
   ttk::style map msg.TNotebook.Tab -font [list selected $font12 active $font12 disabled $font12]
   ${notebookW_} configure -style msg.TNotebook
}

proc MsgCenter_createMenus {} {
   global MsgCenterMainGridRowMap
   set topFrame [MsgCenter_getToplevel].topframe
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
   global SHOW_ABORT_TYPE SHOW_EVENT_TYPE SHOW_INFO_TYPE SHOW_SYSINFO_TYPE
   set menuButtonW ${parent}.pref_menub
   set menuW $menuButtonW.menu

   menubutton $menuButtonW -text Preferences -underline 0 -menu $menuW
   menu $menuW -tearoff 0

   set msgTypeMenuW $menuW.msgtypemenu
   $menuW add cascade -label "Message Type" -underline 0 -menu $msgTypeMenuW

   menu $msgTypeMenuW -tearoff 0
   $msgTypeMenuW add checkbutton -label "Abort" -variable SHOW_ABORT_TYPE \
      -onvalue true -offvalue false -command [list MsgCenter_refreshActiveMessages [MsgCenter_getTableWidget] 1]
   trace add variable SHOW_ABORT_TYPE write [list MsgCenter_filterCallback ${parent} Abort]
   $msgTypeMenuW add checkbutton -label "Event" -variable SHOW_EVENT_TYPE \
      -onvalue true -offvalue false -command [list MsgCenter_refreshActiveMessages [MsgCenter_getTableWidget] 1]
   trace add variable SHOW_EVENT_TYPE write [list MsgCenter_filterCallback ${parent} Event]
   $msgTypeMenuW add checkbutton -label "Info" -variable SHOW_INFO_TYPE \
      -onvalue true -offvalue false -command [list MsgCenter_refreshActiveMessages [MsgCenter_getTableWidget] 1]
   $msgTypeMenuW add checkbutton -label "Sysinfo" -variable SHOW_SYSINFO_TYPE \
      -onvalue true -offvalue false -command [list MsgCenter_refreshActiveMessages [MsgCenter_getTableWidget] 1]
   trace add variable SHOW_INFO_TYPE write [list MsgCenter_filterCallback ${parent} Info]
   trace add variable SHOW_SYSINFO_TYPE write [list MsgCenter_filterCallback ${parent} Sysinfo]

   pack $menuButtonW -side left -padx 2
   
}

# adds a confirmation for message type filtering out
proc MsgCenter_filterCallback { _sourceW _messageType {_name1 ""} {_name2 ""} {_op ""} } {
   set msgTypeToVariableMapping { Abort SHOW_ABORT_TYPE Event SHOW_EVENT_TYPE Info SHOW_INFO_TYPE Sysinfo SHOW_SYSINFO_TYPE }

   set globalVarName [string map ${msgTypeToVariableMapping} ${_messageType}]
   if { ${globalVarName} != "" } {
      global ${globalVarName}
      if { [info exists ${globalVarName}] && [set ${globalVarName}] == false } {
         set answer [tk_messageBox -parent ${_sourceW} -type okcancel \
             -title "Message Center Notification" -icon warning \
	     -message "Are you sure you want to filter out all [string toupper ${_messageType}] messages?" ]

         if { $answer == "cancel" } {
	    set ${globalVarName} true
            return
         }
      }
      ::log::log notice "Message Center message type filter change: type=${_messageType} value:[set ${globalVarName}]"
   }
}

proc MsgCenter_addHelpMenu { parent } {
   set menuButtonW ${parent}.help_menub
   set menuW $menuButtonW.menu

   menubutton $menuButtonW -text Help -underline 0 -menu $menuW
   menu $menuW -tearoff 0
   pack $menuButtonW -side right -padx 2 
}

# display is to right of menu as bold text
proc MsgCenter_createLabel { parent } {
   set labelFrame [frame ${parent}.label_frame]
   set labelW [label ${labelFrame}.label -font [xflow_getExpLabelFont] -text [DisplayGrp_getWindowsLabel]]
   grid ${labelW} -sticky nesw
   pack ${labelFrame} -side left -padx {20 0}
}

proc MsgCenter_createToolbar { table_w_ } {
   global MsgCenterMainGridRowMap
   set toolbarW [MsgCenter_getToplevel].toolbar
   set bellW ${toolbarW}.button_bell
   set ackW ${toolbarW}.button_ack
   set clearW ${toolbarW}.button_clear
   set submitW ${toolbarW}.button_submit
   set submitStopW ${toolbarW}.button_submit_stop
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

   image create photo ${toolbarW}.bulk_submit -file ${imageDir}/bulk_submit.png
   button ${submitW} -image ${toolbarW}.bulk_submit -relief flat -command [list MsgCenter_submitNodes ${table_w_}]
   ::tooltip::tooltip ${submitW} "Submit & flow continue."

   image create photo ${toolbarW}.bulk_submit_stop -file ${imageDir}/bulk_submit_stop.png
   button ${submitStopW} -image ${toolbarW}.bulk_submit_stop -relief flat -command [list MsgCenter_submitNodes ${table_w_} stop]
   ::tooltip::tooltip ${submitStopW} "Submit & flow stop."

   image create photo ${toolbarW}.close -file ${imageDir}/cancel.gif
   button ${closeW} -image ${toolbarW}.close -relief flat -command [list MsgCenter_close]
   ::tooltip::tooltip ${closeW} "Close Message Center."

   if { [SharedData_getMiscData OVERVIEW_MODE] == "true" } {
      set overviewW ${toolbarW}.button_overview
      image create photo ${toolbarW}.overview -file ${imageDir}/calendar_clock.gif
      button ${overviewW} -image ${toolbarW}.overview -relief flat -command Overview_toFront
      ::tooltip::tooltip ${overviewW} "Show Overview Window."
      grid ${bellW} ${ackW} ${clearW} ${submitW} ${submitStopW} ${overviewW} ${closeW} -padx 2 -sticky w
   } else {
      grid ${bellW} ${ackW} ${clearW} ${submitW} ${submitStopW} ${closeW} -padx 2 -sticky w
   }

   grid ${toolbarW} -row $MsgCenterMainGridRowMap(Toolbar) -column 0 -sticky ew -padx 2 -pady 2
   grid columnconfigure ${toolbarW} ${closeW} -weight 1
}

proc MsgCenter_submitNodes { table_widget {flow continue}} {
   global env MsgTableColMap LISTJOB_TO_SUB

   Utils_busyCursor [winfo toplevel ${table_widget}]

   set result [ catch {
      set LISTJOB_TO_SUB {}
      set resultList     {}
      set selections [${table_widget} curselection]
      set id         [clock seconds]
      foreach selectedRow ${selections} {

         set node             [${table_widget} getcells ${selectedRow},$MsgTableColMap(NodeColNumber)]
         set convertedNode    [SharedFlowNode_convertFromDisplayFormat ${node}]
         set nodeWithouthExt  [SharedFlowNode_getNodeFromDisplayFormat ${convertedNode}]
         set extension        [SharedFlowNode_getExtFromDisplayFormat ${convertedNode}]
         set expPath          [${table_widget} getcells ${selectedRow},$MsgTableColMap(SuiteColNumber)]
         set visibleDatestamp [${table_widget} getcells ${selectedRow},$MsgTableColMap(DatestampColNumber)]
         set datestamp        [Utils_getRealDatestampValue ${visibleDatestamp}]
         # append to the list in order
         lappend resultList [list "${expPath}" "${nodeWithouthExt}" "${datestamp}" "${extension}" "${id}"] 
      }

      # sort the list to get rid of duplicate entries
      set resultList [lsort -unique ${resultList}]
      set nofItems   [llength ${resultList}]
      set last_item  false
      set count 0
      set seqExec "maestro"
      while { ${count} < ${nofItems} } {
         foreach { expPath node datestamp extension id} [lindex  ${resultList} ${count}] { break }
         ::log::log debug "MsgCenter_submitNodes expPath:${expPath} node:${node} datestamp:${datestamp} ext:${extension}"

         set flowNode    [SharedData_getExpNodeMapping ${expPath} ${datestamp} ${node}]
	 set seqLoopArgs [xflow_getSeqLoopArgs ${expPath} ${datestamp} ${flowNode} ${extension} ${table_widget} true]

         ::log::log debug "MsgCenter_submitNodes ${seqExec} -d ${datestamp} -n ${node} -s submit ${seqLoopArgs} -f ${flow}"
         set winTitle "submit ${node} ${seqLoopArgs} - Exp=${expPath}"
         if { [expr ${count} + 1] == ${nofItems} } {
             set last_item true
         }
         set commandArgs "-d ${datestamp} -n ${node} -s submit ${seqLoopArgs} -f ${flow}"
         # ::log::log notice "${seqExec} ${commandArgs}"
	 Sequencer_runSubmit ${expPath} ${datestamp} [winfo toplevel ${table_widget}] $seqExec ${winTitle} top 1  ${commandArgs} $id ${last_item}
         update idletasks

         incr count
      }
      # end while

      foreach selectedRow ${selections} {
         MsgCenter_addSubmitAction ${table_widget} ${selectedRow} ${flow}
      }
      Utils_normalCursor [winfo toplevel ${table_widget}]

   } message ]

   # any errors, put the cursor back to normal state
   if { ${result} != 0  } {
      set einfo $::errorInfo
      set ecode $::errorCode
      Utils_normalCursor [winfo toplevel ${table_widget}]
      # report the error with original details
      return -code ${result} \
         -errorcode ${ecode} \
         -errorinfo ${einfo} \
         ${message}
   }
}

# adds an image icon next to the given row base on the
# the given action
proc MsgCenter_addSubmitAction { table_widget row action } {
   global SubmitImgIcon SubmitStopImgIcon
   global MsgTableColMap

   if { ! [info exists SubmitImgIcon] } {
      set imageDir [SharedData_getMiscData IMAGE_DIR]
      set SubmitImgIcon [image create photo -file ${imageDir}/bulk_submit_small.png]
      set SubmitStopImgIcon [image create photo -file ${imageDir}/bulk_submit_stop_small.png]
   }

   if { ${action} == "continue" } {
      set actionImg ${SubmitImgIcon}
   } else {
      set actionImg ${SubmitStopImgIcon}
   }

   ${table_widget} cellconfigure ${row},$MsgTableColMap(ActionColNumber) -image ${actionImg}
}
proc MsgCenter_createNotebook { table_w_ } {
  global BGAll BGAbort BGEvent BGInfo  BGSysinfo
  global MsgCenterMainGridRowMap
  
  set TNotebook [MsgCenter_getToplevel].note
  ttk::frame ${TNotebook} 
  ttk::notebook ${TNotebook}.nb

  # Invoke the widget only if it is currently pressed and enabled:
  ${TNotebook}.nb add [frame ${TNotebook}.nb.all]     -text "All"     -image $BGAll     -compound left
  ${TNotebook}.nb add [frame ${TNotebook}.nb.abort]   -text "Abort"   -image $BGAbort   -compound left
  ${TNotebook}.nb add [frame ${TNotebook}.nb.event]   -text "Event"   -image $BGEvent   -compound left
  ${TNotebook}.nb add [frame ${TNotebook}.nb.info]    -text "Info"    -image $BGInfo    -compound left
  ${TNotebook}.nb add [frame ${TNotebook}.nb.sysinfo] -text "Sysinfo" -image $BGSysinfo -compound left
  ${TNotebook}.nb select ${TNotebook}.nb.all
  ttk::notebook::enableTraversal ${TNotebook}.nb
 
  bind ${TNotebook}.nb <<NotebookTabChanged>> [list MsgCenter_refreshActiveMessages ${table_w_} 0]
  bind ${TNotebook}.nb  <Button-2> [list MsgCenter_displayMsgTabMenu ${table_w_} %W %x %y %X %Y]
  bind ${TNotebook}.nb  <Button-3> [list MsgCenter_displayMsgTabMenu ${table_w_} %W %x %y %X %Y ]
  bind ${TNotebook}.nb  <Double-1> [list MsgCenter_setMsgActive     ${table_w_} %W %x %y]

  pack ${TNotebook}.nb -side left -padx {5 0} 
  grid ${TNotebook} -row $MsgCenterMainGridRowMap(Notetab) -column 0 -sticky nsew -padx 2 -pady 2
  ::tooltip::tooltip ${TNotebook}.nb.all "Acknowledge new messages."

  MsgCenter_SetNotebOption ${TNotebook}.nb
}

proc MsgCenter_setMsgActive {table_w_ parent x y} {
  global LOG_ACTIVATION_IDS
  
  set message_type   [lindex [string tolower [$parent tab [$parent index @$x,$y] -text]] 0]
  if { ![info exists LOG_ACTIVATION_IDS(${message_type})] } { 
      changeMsgLogActivation ${table_w_} $parent $x $y $message_type deactivate always
   } else {
      changeMsgLogActivation ${table_w_} $parent $x $y $message_type activate
   }
}

proc MsgCenter_displayMsgTabMenu {table_w_ parent x y X Y} {
  global LOG_ACTIVATION_IDS
  
  set message_type   [lindex [string tolower [$parent tab [$parent index @$x,$y] -text]] 0]
  #set isMsgLogActive [$parent tab [$parent index @$x,$y] -state]

  set widget ${parent}.message_log_menu
  if { [winfo exists $widget] } {
      destroy $widget
  }
  menu $widget -tearoff 1
  set activationMenu $widget.active_menu
  # check if the message type is enabled or disabled
  set disablePeriods {1 15 30 60 "always"}
  if { ![info exists LOG_ACTIVATION_IDS(${message_type})] } { 
     ${widget} add cascade -label "Deactivate $message_type Signal" -underline 0 \
             -menu [menu ${activationMenu} -tearoff 1]
      foreach period $disablePeriods {
       if { ! ($period == "always") } {
           set label "$period Min"
           set value [expr $period * 60000]
        } else {
           set label $period
           set value $period
        }
        $activationMenu add command -label "$label" \
            -command [list changeMsgLogActivation ${table_w_} $parent $x $y $message_type deactivate $value]
     }
   } else {
        $widget add command -label "Activate $message_type Signal" \
          -command [list changeMsgLogActivation ${table_w_} $parent $x $y $message_type activate]
   }
   $widget add separator
   $widget add command -label "Close" -command [list destroy ${widget}]
   tk_popup $widget $X $Y
}

proc changeMsgLogActivation {table_w_  parent x y message_type change_type {period always} } {
  global LOG_ACTIVATION_IDS

   set notebookW [MsgCenter_getNoteBookWidget]
   ::log::log debug "changeMsgLogActivation parent:$parent change_type:$change_type period:$period"
   switch $change_type {
      activate  { if { !($message_type == "all") } {
                    if { [info exists LOG_ACTIVATION_IDS(${message_type})] } {
                       after cancel $LOG_ACTIVATION_IDS(${message_type})           
                       unset LOG_ACTIVATION_IDS(${message_type})
                     }
                  } else {
                     foreach tab [$parent tabs] { 
                       set txt [lindex [string tolower [$parent tab $tab -text]] 0]
                       if { [info exists LOG_ACTIVATION_IDS(${txt})] } {
                         after cancel $LOG_ACTIVATION_IDS(${txt})           
                         unset LOG_ACTIVATION_IDS(${txt})
                       } 
                     }
                  }
                  MsgCenter_refreshActiveMessages ${table_w_} 0

                }
      deactivate { if { !($message_type == "all") } {
                     set txt [lindex [string tolower [$parent tab [$parent index @$x,$y] -text]] 0]
                     Msg_Center_Active ${table_w_} $parent $x $y $txt $period
                   } else {
                     foreach tab [$parent tabs] { 
                       set txt [lindex [string tolower [$parent tab $tab -text]] 0] 
                       if { [info exists LOG_ACTIVATION_IDS(${txt})] } {
                         after cancel $LOG_ACTIVATION_IDS(${txt})           
                         unset LOG_ACTIVATION_IDS(${txt})
                         MsgCenter_refreshActiveMessages ${table_w_} 0
                       } 
                       Msg_Center_Active ${table_w_} $parent $x $y $txt $period
                      
                     }    
                   }
                 }
   }
   MsgCenter_SetNotebOption ${notebookW}
   update
}

proc Msg_Center_SetImgTab {txt car period} {
   global BGAbort BGEvent BGInfo BGSysinfo BGAll
   
  set imageDir [SharedData_getMiscData IMAGE_DIR]
  switch ${car} {
        Active  { if { ($period == "always") } {
                     set img_name ${imageDir}/deactiv.png
                  } else {
                      set img_name ${imageDir}/deactiv_perm.png
                  }
                  switch ${txt} {
                     all     {$BGAll     configure -file ${img_name} -width 16 -height 16}
                     abort   {$BGAbort   configure -file ${img_name} -width 16 -height 16}
                     event   {$BGEvent   configure -file ${img_name} -width 16 -height 16} 
                     info    {$BGInfo    configure -file ${img_name} -width 16 -height 16}
                     sysinfo {$BGSysinfo configure -file ${img_name} -width 16 -height 16}
                   }
                } 
        Initial { $BGAll     put gray55 -to 0 0 16 16 
                  $BGAbort   put gray55 -to 0 0 16 16
                  $BGEvent   put gray55 -to 0 0 16 16 
                  $BGInfo    put gray55 -to 0 0 16 16
                  $BGSysinfo put gray55 -to 0 0 16 16
                 }
       
  }

}

proc Msg_Center_Active {table_w_ W x y txt period } {
  global BGAbort BGEvent BGInfo BGSysinfo BGAll
  global LOG_ACTIVATION_IDS
  
  Msg_Center_SetImgTab $txt Active $period
  if { !($period == "always") } {
    catch { set LOG_ACTIVATION_IDS(${txt}) [after $period [list changeMsgLogActivation ${table_w_} $W $x $y $txt activate]]}
  } elseif { ($period == "always") } {
    catch { set LOG_ACTIVATION_IDS(${txt}) $period }
  }
}

proc MsgCenter_createWidgets {} {
   global MSG_ACTIVE_TABLE MSG_ACTIVE_COUNTER
   global MsgCenterMainGridRowMap MsgTableColMap

   set topLevelW [MsgCenter_getToplevel]
   if { ! [winfo exists ${topLevelW}] } {
      toplevel ${topLevelW}
   }

   set tableW ${topLevelW}.table
   if { ! [winfo exists ${tableW}] } {
      MsgCenter_createMenus
      MsgCenter_createToolbar  ${tableW}
      MsgCenter_createNotebook ${tableW}

      array set MsgTableColMap {
         TimestampColNumber 0
         DatestampColNumber 1
         TypeColNumber 2
         ActionColNumber 3
         NodeColNumber 4
         MessageColNumber 5
         SuiteColNumber 6
         UnackColNumber 7
      }

      set yscrollW ${topLevelW}.sy
      set xscrollW ${topLevelW}.sx
      set rowFgColor    [SharedData_getColor COLOR_MSG_CENTER_MAIN]
      set tableBgColor  [SharedData_getColor DEFAULT_BG]
      set headerBgColor [SharedData_getColor COLOR_MSG_CENTER_MAIN]
      set headerFgColor [SharedData_getColor DEFAULT_HEADER_FG]
      set stripeBgColor [SharedData_getColor MSG_CENTER_STRIPE_BG]
      set normalBgColor [SharedData_getColor MSG_CENTER_NORMAL_BG]
      set defaultAlign center
     
      set columns [list 0 Timestamp ${defaultAlign} \
                        0 Datestamp ${defaultAlign} \
                        0 Type ${defaultAlign} \
                        0 "" ${defaultAlign} \
                        0 Node ${defaultAlign} \
                        0 Message ${defaultAlign} \
                        0 Suite ${defaultAlign} \
                        0 Unack ${defaultAlign}]

      tablelist::tablelist ${tableW} -selecttype cell -selectmode extended -columns ${columns} \
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
      scrollbar ${yscrollW} -command [list ${tableW}  yview]
      scrollbar ${xscrollW} -command [list ${tableW}  xview] -orient horizontal
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

proc MsgCenter_getNoteBookWidget {} {
   return .msgCenter.note.nb
}

proc MsgCenter_getTableWidget {} {
   return .msgCenter.table
}

proc MsgCenter_getToplevel {} {
   return .msgCenter
}

# sets the color of the table headers.
# When a new messsage comes in,
# we flash the table headers so this function is called
# might be called multiple times
proc MsgCenter_setHeaderStatus { table_w_ status_ } {
   set alarmBgColor    [SharedData_getColor COLOR_MSG_CENTER_MAIN]
   set normalFgColor   [SharedData_getColor DEFAULT_HEADER_FG]
   set normalBgColor   [SharedData_getColor COLOR_MSG_CENTER_MAIN]
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

proc Msg_IncrArrayElement {var key key2 key3 {incr 1}} {
    upvar $var a 
    if {[info exists a(${key}_${key2}_${key3})]} {
        incr a(${key}_${key2}_${key3}) $incr
    } else {
        set a(${key}_${key2}_${key3}) $incr
    } 
}

proc MsgCenter_ModifText  {} {
   global MSG_COUNTER MSG_TABLE
   global msg_info_List msg_tt_list exp_path_frame
   global msg_active_List  env datestamp_msgframe
   global LAUNCH_XFLOW_MUTEX List_Xflow
   global SHOW_MSGBAR LIST_TAG

   set notebookW [MsgCenter_getNoteBookWidget]
   set counter    0
   array set ll_nb {
       all     0
       abort   0
       event   0
       info    0
       sysinfo 0
   }
   array set l_total {
       all     0
       abort   0
       event   0
       info    0
       sysinfo 0
   }
   array set List_Msg_text {}
   while { ${counter} < ${MSG_COUNTER} } {
      foreach {timestamp datestamp type action node msg exp isMsgack} [lindex ${MSG_TABLE} ${counter}] {break}
      incr l_total($type)
      incr l_total(all)
      if {!$isMsgack} {
        Msg_IncrArrayElement List_Msg_text $exp $type $datestamp
        incr ll_nb($type)
        incr ll_nb(all)
      }
      incr counter
   }
   foreach tab [$notebookW tabs] {
      set label  [lindex [$notebookW tab $tab -text] 0]
      set Txt    [string tolower $label]
      set txt    [list $label "($ll_nb($Txt))"]
      $notebookW tab $tab -text ${txt}
   }
   array unset msg_info_List *
   array set msg_info_List   [array get List_Msg_text]
   array set msg_active_List [array get ll_nb]
   array set msg_tt_list     [array get l_total]

   set topOverview [Overview_getToplevel]
   if { [winfo exists $topOverview] } { 
      # avoid calling this for every message at startup
      if { [SharedData_getMiscData STARTUP_DONE] == true } {
         Overview_createMsgCenterbar ${topOverview}
      }
      set msgFrame ${topOverview}.toolbar.msg_frame
      if { [winfo exists $msgFrame] && ${SHOW_MSGBAR} == "true"} {
         Overview_addMsgCenterWidget ${exp_path_frame} ${datestamp_msgframe} ${LIST_TAG}
      }
   }

   set counter       0
   set deleteIndexes {}
   set nb_elm [llength ${List_Xflow}]
   while { ${counter} < ${nb_elm} } {
      foreach {exp_path dates topFrame} [lindex ${List_Xflow} ${counter}] {break}
      if { [winfo exists $topFrame] } {
         xflow_addMsgCenterWidget ${exp_path} ${dates}
      } else {
         lappend deleteIndexes ${counter}
      }
      incr counter
   }
   set deleteIndexes [lreverse ${deleteIndexes}]
   foreach deleteIndex ${deleteIndexes} {
      set List_Xflow [lreplace ${List_Xflow} ${deleteIndex} ${deleteIndex}]
   } 
}

#
# this function is called when a new message comes in
# 
proc MsgCenter_newMessage { table_w_ datestamp_ timestamp_ type_ node_ msg_ exp_ } {
   global MSG_TABLE MSG_COUNTER MSG_ACTIVE_COUNTER
   global MSG_ACTIVE_TABLE
  
   set istoadd true 
   
   set isUnack 0
   set is_exist [list ${timestamp_} ${datestamp_} ${type_} "" ${node_} ${msg_} ${exp_}]
   if { [lsearch -glob ${MSG_TABLE} ${is_exist}* ] < 0 } {
     #incr MSG_COUNTER
     ::log::log debug "MsgCenter_newMessage node_:$node_ type_:$type_ msg_:$msg_"
     lappend MSG_TABLE [list ${timestamp_} ${datestamp_} ${type_} "" ${node_} ${msg_} ${exp_} ${isUnack}]
     set MSG_COUNTER   [llength ${MSG_TABLE}]
     set isMsgActive   [MsgCenter_addActiveMessage ${datestamp_} ${timestamp_} ${type_} ${node_} ${msg_} ${exp_} ${isUnack} ${istoadd}]

     if { ${isMsgActive} == "true" } {
        set isOverviewMode [SharedData_getMiscData OVERVIEW_MODE]
        if { [SharedData_getMiscData STARTUP_DONE] == true || $isOverviewMode == true} {
          set notebookW [MsgCenter_getNoteBookWidget]
          set currentMsgTab [MsgCenter_getCurrentMessageTab]
     
          if { ${currentMsgTab} == ${type_} || (${currentMsgTab} ==  "all" && $istoadd == "true")} {
             MsgCenter_refreshActiveMessages ${table_w_} 0
          } else {
             ${notebookW} select ${notebookW}.${type_}
          }
          set MSG_ACTIVE_COUNTER [llength ${MSG_ACTIVE_TABLE}]
          #${table_w_} see ${MSG_ACTIVE_COUNTER}
        }
        # for sysinfo, we don't flash or beep
        switch ${type_} {
           sysinfo {
	   }
	   default {
                MsgCengter_processAlarm ${table_w_} ${type_}
           }
        }
     }
     MsgCenter_ModifText
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
   global MSG_TABLE  MSG_COUNTER NB_ACTIVE_ELM

   set isStartupDone [SharedData_getMiscData STARTUP_DONE]
   if { ${isStartupDone} == "true" } { 
      set isOverviewMode [SharedData_getMiscData OVERVIEW_MODE]
      
      set newMessageFlag false
      if { $NB_ACTIVE_ELM(all) == 1 } { 
         set newMessageFlag true
      }

      if { ${isOverviewMode} == "true" } {
         Overview_newMessageCallback ${newMessageFlag}
      } else {
         set exp [MsgCenter_getFieldFromLastMessage $MsgTableColMap(SuiteColNumber)]
         set datestamp [MsgCenter_getFieldFromLastMessage $MsgTableColMap(DatestampColNumber)]
	 xflow_newMessageCallback ${exp} ${datestamp} ${newMessageFlag}
      }
   }
}

proc MsgCenter_addActiveMessage { datestamp_ timestamp_ type_ node_ msg_ exp_ isMsgack_ isadd_} {
   global SHOW_ABORT_TYPE SHOW_INFO_TYPE SHOW_SYSINFO_TYPE SHOW_EVENT_TYPE
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
      sysinfo {
         if { ${SHOW_SYSINFO_TYPE} == "true" } {
            set isMsgActive true
         }
      }
      event {
         if { ${SHOW_EVENT_TYPE} == "true" } {
            set isMsgActive true
         }
      }
   }

   if { ${isMsgActive} == "true" && ${isadd_} == "true" }  {
      ::log::log debug "MsgCenter_addActiveMessage adding ${datestamp_} ${timestamp_} ${type_} ${node_} ${msg_} ${exp_}"
      set displayedNodeText [SharedFlowNode_convertToDisplayFormat ${node_}]
      # add 2 spaces between date and time
      set displayedTimestamp [join [split ${timestamp_} .] "  "]
      # show only first 10 digits of datestamp
      set displayedDatestamp [Utils_getVisibleDatestampValue ${datestamp_} [SharedData_getMiscData DATESTAMP_VISIBLE_LEN]]
      set is_exist [lsearch -glob ${MSG_ACTIVE_TABLE} [list ${displayedTimestamp} ${displayedDatestamp} ${type_} "" ${displayedNodeText} ${msg_} ${exp_} *]]
      #puts "OK ${is_exist}"
      if { ${is_exist} == "-1"} { 
        incr MSG_ACTIVE_COUNTER
        lappend MSG_ACTIVE_TABLE [list ${displayedTimestamp} ${displayedDatestamp} ${type_} "" ${displayedNodeText} ${msg_} ${exp_} ${isMsgack_}]
      }
   }
   #set MSG_ACTIVE_COUNTER [llength ${MSG_ACTIVE_TABLE}]
   return ${isMsgActive}
}

# refresh shown messages based on user message type filters
# this function is called when the user changes the "Message Type" settings
# under the Preferences menunodelogger -n /post_processing_misc/loop_sm_00-120 -s event -m test -d 20141002000000 
# 
proc MsgCenter_refreshActiveMessages { table_w_ { unack_ 0 }} {
   global MSG_TABLE MSG_COUNTER MSG_ALARM_ON LOG_ACTIVATION_IDS
   global BGAll BGAbort BGEvent BGInfo  BGSysinfo
   global array NB_ACTIVE_ELM MSG_ACTIVE_COUNTER

   set bg_color [SharedData_getColor COLOR_MSG_CENTER_MAIN]
   array set NB_ACTIVE_ELM { 
         all     0
         abort   0
         event   0
         info    0
         sysinfo 0
   }

   set currentMsgTab [MsgCenter_getCurrentMessageTab]
   # reset active messages
   MsgCenter_initActiveMessages
   set counter 0
   set normal_color gray55
 
   # reprocess all received messages
   while { ${counter} < ${MSG_COUNTER} } {
      foreach {timestamp datestamp type action node msg exp isMsgack} [lindex ${MSG_TABLE} ${counter}] {break}
      if { ${isMsgack} == "0" && !$NB_ACTIVE_ELM($type)} {
         set NB_ACTIVE_ELM(${type}) 1
         set NB_ACTIVE_ELM(all) 1
      }
      if { ${currentMsgTab} == ${type} || ${currentMsgTab} == "all"} {
        ::log::log debug "MsgCenter_refreshActiveMessages coun:$counter type:$type node:$node msg:$msg exp:$exp"
        MsgCenter_addActiveMessage ${datestamp} ${timestamp} ${type} ${node} ${msg} ${exp} ${isMsgack} true
      }
      incr counter
   }
   
   foreach elm [array names NB_ACTIVE_ELM] {
       switch ${elm} {
           all    { if { ![info exists LOG_ACTIVATION_IDS($elm)] && !$NB_ACTIVE_ELM($elm)} {
                       $BGAll put $normal_color -to 0 0 16 16
                     } elseif { ![info exists LOG_ACTIVATION_IDS(${elm})] } {
                       $BGAll put $bg_color -to 0 0 16 16
                     }
                   }
           abort   { if { ![info exists LOG_ACTIVATION_IDS($elm)] && !$NB_ACTIVE_ELM($elm)} {
                       $BGAbort put $normal_color -to 0 0 16 16
                     } elseif { ![info exists LOG_ACTIVATION_IDS(${elm})] } {
                       $BGAbort put $bg_color -to 0 0 16 16
                     }
                   }
           event   { if { ![info exists LOG_ACTIVATION_IDS($elm)] && !$NB_ACTIVE_ELM($elm)} {
                       $BGEvent put $normal_color -to 0 0 16 16
                     } elseif { ![info exists LOG_ACTIVATION_IDS(${elm})]} {
                       $BGEvent put $bg_color -to 0 0 16 16
                     }        
                   } 
           info    { if { ![info exists LOG_ACTIVATION_IDS($elm)] && !$NB_ACTIVE_ELM($elm)} {
                        $BGInfo  put $normal_color -to 0 0 16 16
                     } elseif { ![info exists LOG_ACTIVATION_IDS(${elm})]} { 
                        $BGInfo  put $bg_color -to 0 0 16 16
                     }
                   }
           sysinfo { if { ![info exists LOG_ACTIVATION_IDS($elm)] && !$NB_ACTIVE_ELM($elm)} {
                        $BGSysinfo put $normal_color -to 0 0 16 16
                     } elseif { ![info exists LOG_ACTIVATION_IDS(${elm})]} {
                        $BGSysinfo put $bg_color -to 0 0 16 16
                     }
                   }
        }
    } 
   
   if {${unack_} == "0"} {
      MsgCenter_initMessages ${table_w_}
   } else { 
      MsgCenter_ackMessages ${table_w_}
   }  
   MsgCenter_initialSort ${table_w_}
   ${table_w_} see ${MSG_ACTIVE_COUNTER}

   if { [SharedData_getMiscData OVERVIEW_MODE] == false && [SharedData_getMiscData STARTUP_DONE] == true } {
       MsgCenter_sendNotification
   }
}

proc Ack_MsgCenter_List { message_tab } {
  global BGAll BGAbort BGEvent BGInfo BGSysinfo
  global MSG_TABLE MSG_COUNTER LOG_ACTIVATION_IDS
  
  array set NB_ACTIVE_ELM { 
         all     1
         abort   0
         event   0
         info    0
         sysinfo 0
  }
  set notebookW [MsgCenter_getNoteBookWidget]
  set counter 0
  while { ${counter} < ${MSG_COUNTER} } {
    foreach {timestamp datestamp type action node msg exp isMsgack} [lindex ${MSG_TABLE} ${counter}] {break}
    if { ${isMsgack} == "0" && (${message_tab} == ${type} || ${message_tab} == "all")} {
      set MSG_TABLE [lreplace ${MSG_TABLE} ${counter} ${counter} [lreplace [lindex ${MSG_TABLE} ${counter}] end end 1]]
      if { !$NB_ACTIVE_ELM($type)} {
         set NB_ACTIVE_ELM(${type}) 1
      }
    } elseif { ${isMsgack} == "0" && ${message_tab} != ${type}} {
        set NB_ACTIVE_ELM(all) 0
    }
    incr counter
  } 
  foreach elm [array names NB_ACTIVE_ELM] {
     if { $NB_ACTIVE_ELM($elm)} {
       switch ${elm} {
         all     { $BGAll     put gray55 -to 0 0 16 16}
         abort   { $BGAbort   put gray55 -to 0 0 16 16}
         event   { $BGEvent   put gray55 -to 0 0 16 16} 
         info    { $BGInfo    put gray55 -to 0 0 16 16}
         sysinfo { $BGSysinfo put gray55 -to 0 0 16 16}
       }  
     }
     if { [info exists LOG_ACTIVATION_IDS(${elm})] } {
       Msg_Center_SetImgTab ${elm} Active $LOG_ACTIVATION_IDS(${elm})
     } 
  }
  MsgCenter_SetNotebOption ${notebookW}
  MsgCenter_ModifText
}

proc MsgCenter_initActiveMessages {} {
   global MSG_ACTIVE_TABLE MSG_ACTIVE_COUNTER

   set MSG_ACTIVE_TABLE {}
   set MSG_ACTIVE_COUNTER 0
}

# displays table messages according to the acknowledge state
proc MsgCenter_initMessages { table_w_ } {
   global MsgTableColMap 
  
   set normalFg [SharedData_getColor MSG_CENTER_NORMAL_FG]
   foreach row [${table_w_} searchcolumn $MsgTableColMap(UnackColNumber) 1 -exact -all] {
       ${table_w_} rowconfigure ${row} -fg ${normalFg}
   }
   # look for rows that have unack state
   set normalFg [SharedData_getColor COLOR_MSG_CENTER_MAIN]
   foreach row [${table_w_} searchcolumn $MsgTableColMap(UnackColNumber) 0 -exact -all] {
      ${table_w_} rowconfigure ${row} -fg ${normalFg}        
   }
   MsgCenter_setHeaderStatus ${table_w_} alarm_bg
}

# acknowledge table messages
# if the message_tab is given as argument, it will be used instead of getting the current user selection
# it is mainly used to force clearing of all message types when switching to another flow (different datestamp)
# in xflow standalone mode
proc MsgCenter_ackMessages { table_w_ {message_tab ""} } {
   global MsgTableColMap
   global MSG_ACTIVE_COUNTER NB_ACTIVE_ELM

   #wm attributes . -topmost 0
   MsgCenter_stopBell ${table_w_}

   if { ${message_tab} == "" } {
      set currentMsgTab [MsgCenter_getCurrentMessageTab]
   } else {
      set currentMsgTab ${message_tab}
   }

   Ack_MsgCenter_List ${currentMsgTab}

   set normalFg [SharedData_getColor MSG_CENTER_NORMAL_FG]
   foreach row [${table_w_} searchcolumn $MsgTableColMap(UnackColNumber) 0 -exact -all] {
      ${table_w_} rowconfigure ${row} -fg ${normalFg}
      ${table_w_} cellconfigure ${row},$MsgTableColMap(UnackColNumber) -text 1
   }

   # look for rows that have unack state
   foreach row [${table_w_} searchcolumn $MsgTableColMap(UnackColNumber) 1 -exact -all] {
     ${table_w_} rowconfigure ${row} -fg ${normalFg}
   }
   MsgCenter_setHeaderStatus ${table_w_} normal

   set isOverviewMode [SharedData_getMiscData OVERVIEW_MODE]

   if { ${currentMsgTab} == "all" } {
      # reset all types to acknowledged
      foreach msgType "all abort event info sysinfo" {
         set NB_ACTIVE_ELM(${msgType}) 0
      } 
   } else {
      # reset current tab to acknowledged
      set NB_ACTIVE_ELM(${currentMsgTab}) 0
      set allAck true
      # check if everything was acknowledged
      foreach msgType "abort event info sysinfo" {
         if { $NB_ACTIVE_ELM(${msgType}) == 1 } {
            set allAck false
	    break
	 }
      } 
      if { ${allAck} == true } {
         set NB_ACTIVE_ELM(all) 0
      }
   }

   MsgCenter_sendNotification
   ${table_w_} see ${MSG_ACTIVE_COUNTER}
}

proc MsgCenter_getCurrentMessageTab {} {
   set currentTab ""   
   set notebookW [MsgCenter_getNoteBookWidget]
   if { [winfo exists ${notebookW}] } {
      set label [string tolower [$notebookW tab [$notebookW index current] -text]]
      set currentTab [lindex ${label} 0]
   }
   return ${currentTab}
}

proc MsgCenter_clearAllMessages {} {
   set tableW [MsgCenter_getTableWidget]
   MsgCenter_ackMessages ${tableW} all
   Msgcenter_Init_List ${tableW} all
}

# if the messageTab is given as argument, it will be used instead of getting the current user selection
# it is mainly used to force clearing of all message types when switching to another flow (different datestamp)
# in xflow standalone mode
proc Msgcenter_Init_List {table_w_ {message_tab ""} } {
  global MSG_TABLE MSG_COUNTER
  
  if { ${message_tab} == "" } {
     set currentMsgTab [MsgCenter_getCurrentMessageTab]
  } else {
     set currentMsgTab ${message_tab}
  }

  set counter 0
  set deleteIndexes {}
  while { ${counter} < ${MSG_COUNTER} } {
    foreach {timestamp datestamp type action node msg exp isMsgack} [lindex ${MSG_TABLE} ${counter}] {break}
    if { (${currentMsgTab} == ${type} || ${currentMsgTab} == "all")} {
      lappend deleteIndexes ${counter}
    }
    incr counter
  }
  set deleteIndexes [lreverse ${deleteIndexes}]
   foreach deleteIndex ${deleteIndexes} {
      set MSG_TABLE [lreplace ${MSG_TABLE} ${deleteIndex} ${deleteIndex}]
   }
   set MSG_COUNTER [llength ${MSG_TABLE}]
   MsgCenter_refreshActiveMessages ${table_w_} 0
}

proc MsgCenter_clearMessages { source_w table_w_ } {
   global MSG_COUNTER MSG_TABLE MSG_ACTIVE_COUNTER

   if { ${MSG_ACTIVE_COUNTER} > 0 } {
      set answer [tk_messageBox -parent ${source_w} -type okcancel \
         -title "Message Center" -icon warning -message \
         "Are you sure you want to clear all messages?"]

      if { $answer == "cancel" } {
         return
      }
      MsgCenter_ackMessages ${table_w_}
      Msgcenter_Init_List   ${table_w_}
      MsgCenter_ModifText
   }
}

# removes msg from the MSG_TABLE when not used anymore...
# datestamp is obsolete from xflow_overview
proc MsgCenter_removeMessages { exp datestamp {refresh_msg_center true} } {
   global MSG_TABLE MsgTableColMap MSG_TABLE_CMP
   global MSG_COUNTER

   set tableW [MsgCenter_getTableWidget]
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
   set MSG_COUNTER [llength ${MSG_TABLE}]
   if { ${refresh_msg_center} == true } {
      # only refresh the message center counts when the refresh_msg_center is true 
      # allows the overview to do only the refresh once when needed and not every time the removeMessages is called
      MsgCenter_refreshActiveMessages ${tableW} 0
      MsgCenter_ModifText
      # make sure that status of msg center button in overview and/or xflow reflects new messages after remove
      MsgCenter_sendNotification
   }

   ::log::log notice "MsgCenter_removeMessages for exp:${exp} datestamp:${datestamp} DONE"
}

proc MsgCengter_processAlarm { table_w_ type_ {repeat_alarm false}} {
   global MSG_ALARM_ON MSG_ALARM_ID MSG_BELL_TRIGGER LOG_ACTIVATION_IDS
   global MSG_ALARM_COUNTER MSG_CENTER_USE_BELL
   global MSG_ALARM_AFTER_ID MsgTableColMap
   
   set autoMsgDisplay [SharedData_getMiscData AUTO_MSG_DISPLAY]
   # flash
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
   }
   if { ${autoMsgDisplay} == "true" && [SharedData_getMiscData STARTUP_DONE] == "true" } {
      if { ${raiseAlarm} == "true" && ![info exists LOG_ACTIVATION_IDS(${type_})] } {
         MsgCenter_setHeaderStatus ${table_w_} alarm
         if { [expr ${MSG_ALARM_COUNTER} > ${MSG_BELL_TRIGGER}] && ${MSG_CENTER_USE_BELL} == true } {
            ::log::log debug "MsgCenter_processAlarm sounding bell..."
            bell
         }
         set MSG_ALARM_ID [after 1500 [list MsgCengter_processAlarm ${table_w_} ${type_} true]]
      }

      # msg center flood control. When more than 1000 requests are being processed
      # asynchronously, the MsgCenter_show command would go berserk with the display.
      # Setting a delay of 500 ms to show the msg center so that
      # multiple entries will cancel each other within the delay, only the last one will be working
      if { [info exists MSG_ALARM_AFTER_ID] } {
         after cancel ${MSG_ALARM_AFTER_ID}
      }

      if { ! [info exists LOG_ACTIVATION_IDS(${type_})] } {
         if { ${repeat_alarm} == false } {
            set MSG_ALARM_AFTER_ID [after 100 [list MsgCenter_show true]]
         } else {
            set MSG_ALARM_AFTER_ID [after 100 [list MsgCenter_show]]
	 }
      }
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

proc MsgCenter_show { {force false} } {
   ::log::log debug "MsgCenter_show force:${force}"
   set topW [MsgCenter_getToplevel]
   set currentStatus [wm state ${topW}]

   if { ${force} == false } {
      switch ${currentStatus} {
         withdrawn -
         iconic {
            wm deiconify ${topW}
         }
      }
      if { [SharedData_getMiscData STARTUP_DONE] == "true" && [SharedData_getMiscData MSG_CENTER_FOCUS_GRAB] == "true" } {
         raise ${topW}
      } else {
         lower ${topW}
      }
   } else {
      if { [SharedData_getMiscData STARTUP_DONE] == "true" } {
         # force remove and redisplay of msg center
         # Need to do this cause when the msg center is in another virtual
         # desktop, it is the only way for it to redisplay in the
         # current desktop
         wm withdraw ${topW}
         wm deiconify ${topW}
        if { [SharedData_getMiscData MSG_CENTER_FOCUS_GRAB] == "true" } {
          raise ${topW}
        } else { 
          lower ${topW}
        }   
      }
   }
}


# called everytime a new message comes in from experiment threads
proc MsgCenter_processNewMessage { datestamp_ timestamp_ type_ node_ msg_ exp_ } {
   global MSG_ALARM_ID MSG_CENTER_MUTEX NB_ACTIVE_ELM

   ::log::log debug "MsgCenter_processNewMessage ${datestamp_} ${timestamp_} ${type_} ${node_} ${msg_} ${exp_}"

   if { ! [info exists MSG_CENTER_MUTEX] } {
      ::log::log debug "MsgCenter_processNewMessage creating mutex"
      set MSG_CENTER_MUTEX [thread::mutex create ]
   }
   
   ::log::log debug "MsgCenter_processNewMessage ${datestamp_} ${timestamp_} ${type_} ${node_} ${msg_} ${exp_}"
   if [ catch { thread::mutex lock ${MSG_CENTER_MUTEX} } message ] {
      ::log::log debug "MsgCenter_processNewMessage no lock...trying later..."
      after 250 MsgCenter_processNewMessage \"${datestamp_}\" \"${timestamp_}\" \"${type_}\" \"${node_}\" \"${msg_}\" \"${exp_}\"
      return
   }

   if [ catch { 
      ::log::log debug "MsgCenterThread_processNewMessage ${datestamp_} ${timestamp_} ${type_} ${node_} ${msg_} ${exp_}"
      if { [SharedData_getMiscData STARTUP_DONE] == "true" } {
        set NB_ACTIVE_ELM(all) 1
        set NB_ACTIVE_ELM(${type_}) 1
      }
      ::log::log debug "calling MsgCenterThread_newMessage ${datestamp_} ${timestamp_} ${type_} ${node_} ${msg_} ${exp_}"
      MsgCenter_newMessage [MsgCenter_getTableWidget] ${datestamp_} ${timestamp_} ${type_} ${node_} ${msg_} ${exp_} 
      
      # if the exp is done reading messages, we send a notification out
      # to warn about new messages available in the msg center
      if { [SharedData_getMiscData STARTUP_DONE] == true } {
        MsgCenter_sendNotification
      }
   } message ] {
      puts stderr "ERROR in -- MsgCenter_processNewMessage: ${message}"
      catch { thread::mutex unlock ${MSG_CENTER_MUTEX} }
      ::log::log notice "ERROR in MsgCenter_processNewMessage: ${message}"
      set einfo $::errorInfo
      set ecode $::errorCode
      # report the error with original details

      return -code ${result} \
         -errorcode ${ecode} \
         -errorinfo ${einfo} \
         ${message}
   }

   catch { thread::mutex unlock ${MSG_CENTER_MUTEX} }
   # ::log::log notice "MsgCenterThread_processNewMessage ${datestamp_} ${timestamp_} ${type_} ${node_} ${msg_} ${exp_} DONE"
}

# called by xflow or xflow_overview to let msg center
# that application startup is done
proc MsgCenter_startupDone {} {
   global MSG_COUNTER
   MsgCenter_sendNotification
   # sort the msg by timestamp ascending order
   MsgCenter_initialSort [MsgCenter_getTableWidget]

   set topFrame [MsgCenter_getToplevel].topframe
   MsgCenter_createLabel ${topFrame}

   if { [SharedData_getMiscData AUTO_MSG_DISPLAY] == true && ${MSG_COUNTER} > 0 } {
      MsgCenter_show
   }
}

proc MsgCenter_setTitle { top_w } {
   global env
   set current_time [clock format [clock seconds] -format "%H:%M" -gmt 1]
   if { [SharedData_getMiscData OVERVIEW_MODE] == false } {
      set winTitle "[file tail $env(SEQ_EXP_HOME)] - Message Center - Exp=$env(SEQ_EXP_HOME) User=$env(USER) Host=[exec -ignorestderr hostname] Time=${current_time}"
   } else {
      set winTitle "Message Center - User=$env(USER) Host=[exec -ignorestderr hostname] Time=${current_time}"
   }
   wm title [winfo toplevel ${top_w}] ${winTitle}

   # refresh title every minute
   set TimeAfterId [after 60000 [list MsgCenter_setTitle ${top_w}]]
}

########################################
# callback procedures
########################################
proc MsgCenter_doubleClickCallback { table_widget } {
   global MsgTableColMap

   ::log::log debug "MsgCenter_doubleClickCallback widget:${table_widget}"
   MsgCenter_stopBell ${table_widget}
   set selectedRow [${table_widget} curselection]
   # retrieve needed information
   set node [${table_widget} getcells ${selectedRow},$MsgTableColMap(NodeColNumber)]
   set expPath [${table_widget} getcells ${selectedRow},$MsgTableColMap(SuiteColNumber)]
   set datestamp [${table_widget} getcells ${selectedRow},$MsgTableColMap(DatestampColNumber)]
   set realDatestamp [Utils_getRealDatestampValue ${datestamp}]
   ::log::log debug "MsgCenter_doubleClickCallback node:${node} expPath:${expPath} ${datestamp}"

   if { ${node} == "" || ${expPath} == "" } {
      return
   }

   Utils_busyCursor ${table_widget}
   set result [ catch {
      # start the suite flow if not started
      set isOverviewMode [SharedData_getMiscData OVERVIEW_MODE]
      if { ${isOverviewMode} == "true" } {
         Overview_launchExpFlow ${expPath} ${realDatestamp}
      }

      # ask the suite to take care of showing the selected node in it's flow
      set convertedNode [SharedFlowNode_convertFromDisplayFormat ${node}]
      xflow_findNode ${expPath} ${realDatestamp} ${convertedNode}

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

proc MsgCenter_rightClickCallback { table_widget w x y } {
   global MsgTableColMap

   ::log::log debug "MsgCenter_rightClickCallback widget:${w} x:$x y:$y"

   MsgCenter_stopBell ${table_widget}

   # convert screen coords to widget coords
   foreach {mytable myx myy} \
    [tablelist::convEventFields ${w} ${x} ${y}] {}

   # get the row on which the right was done
   set nearestCell [${mytable} containingcell ${myx} ${myy}]
   set nearestRow ""
   catch { set nearestRow [lindex [split ${nearestCell} ,] 0] }

   if { ${nearestRow} > -1 } {
      # clear and select 
      ${mytable} selection clear top bottom
      ${mytable} select set ${nearestRow}

      set selectedRow ${nearestRow}

      # retrieve needed information
      set node [${table_widget} getcells ${selectedRow},$MsgTableColMap(NodeColNumber)]
      set convertedNode [SharedFlowNode_convertFromDisplayFormat ${node}]
      set nodeWithouthExt [SharedFlowNode_getNodeFromDisplayFormat ${convertedNode}]
      set extensionPart [SharedFlowNode_getExtFromDisplayFormat ${convertedNode}]

      set expPath [${table_widget} getcells ${selectedRow},$MsgTableColMap(SuiteColNumber)]
      set datestamp [${table_widget} getcells ${selectedRow},$MsgTableColMap(DatestampColNumber)]
      set realDatestamp [Utils_getRealDatestampValue ${datestamp}]

      # here I need to check whether the node mapping is still stored in memory
      # if it is not, need to fetch it.
      # The node mapping is cleaned when the run goes out of the overview visibility
      # window
      if { [SharedData_isExpNodeMappingExists ${expPath} ${realDatestamp}] == false } {
         ::log::log debug "MsgCenter_rightClickCallback exp_path:${expPath} datestamp:${realDatestamp} loading NODE MAPPING"
         Utils_busyCursor ${table_widget}
         if [ catch {
	    # parse the flow.xml file to get the node mappings
            FlowXml_parse ${expPath}/EntryModule/flow.xml ${expPath} ${realDatestamp} ""
         } message ] {
            set errMsg "Error Parsing flow.xml file ${expPath}:\n$message"
            puts stderr "ERROR: MsgCenter_rightClickCallback Parsing flow.xml file exp_path:${expPath} datestamp:${realDatestamp}\n$message"
            ::log::log notice "ERROR: MsgCenter_rightClickCallback Parsing flow.xml file ${expPath}:\n$message."
            error ${message}
            return
         }
         # register the mapping data to be collected later on i.e. every hour
	 after 5000 [list OverviewExpStatus_addObsoleteDatestamp ${expPath} ${realDatestamp}]
         Utils_normalCursor ${table_widget}
      }
      set flowNode [SharedData_getExpNodeMapping ${expPath} ${realDatestamp} ${nodeWithouthExt}]
      
      # everything here is to allow the same node menu as xflow to be called from msg center
      set xflowToplevel [xflow_getToplevel ${expPath} ${realDatestamp}]
      if { ! [winfo exists ${xflowToplevel} ] } {
         # dummy window
         toplevel ${xflowToplevel}; wm withdraw ${xflowToplevel}
      }

      # puts "MsgCenter_rightClickCallback calling xflow_modeMenu..."
      xflow_setWidgetNames

      set winx [expr [winfo rootx ${w}] + ${x}]
      set winy [expr [winfo rooty ${w}] + ${y}]
      xflow_nodeMenu ${expPath} ${realDatestamp} [MsgCenter_getToplevel] ${flowNode} ${extensionPart} ${winx} ${winy}
   }
}

# returns current time as argument expected by processNewMessage function
proc MsgCenter_getCurrentTime {} {
   return [clock format [clock seconds] -format "%Y%m%d.%H:%M:%S"]
}

########################################
# end callback procedures
########################################

proc MsgCenter_init {} {
   global SHOW_ABORT_TYPE SHOW_INFO_TYPE SHOW_SYSINFO_TYPE SHOW_EVENT_TYPE NB_ACTIVE_ELM
   global DEBUG_TRACE MSG_BELL_TRIGGER MSG_CENTER_USE_BELL
   global BGAll BGAbort BGEvent BGInfo  BGSysinfo LOG_ACTIVATION_IDS
   global MSG_ALARM_ON MsgCenterMainGridRowMap  
   global MSG_TABLE MSG_COUNTER MSG_ALARM_COUNTER List_Xflow
  
   set DEBUG_TRACE [SharedData_getMiscData DEBUG_TRACE]
   set MSG_BELL_TRIGGER [SharedData_getMiscData MSG_CENTER_BELL_TRIGGER]

   # Utils_logInit
   # Utils_createTmpDir

   set List_Xflow {}
   array set NB_ACTIVE_ELM { 
         all     0
         abort   0
         event   0
         info    0
         sysinfo 0
   }

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
   set SHOW_SYSINFO_TYPE [SharedData_getMiscData SHOW_SYSINFO_TYPE]
   set SHOW_EVENT_TYPE [SharedData_getMiscData SHOW_EVENT_TYPE]

   set BGAll     [image create photo -width 16]
   set BGAbort   [image create photo -width 16]
   set BGEvent   [image create photo -width 16]
   set BGInfo    [image create photo -width 16]
   set BGSysinfo [image create photo -width 16]
   Msg_Center_SetImgTab null Initial  null
   # is bell activated?
   set MSG_CENTER_USE_BELL true
   if { [SharedData_getMiscData USE_BELL] == false } {
      set MSG_CENTER_USE_BELL false
   }

   set topLevelW [MsgCenter_getToplevel]
   set tableW ${topLevelW}.table
   
   if { ! [winfo exists ${tableW}] } {
      array set MsgCenterMainGridRowMap {
         Menu 0
         Toolbar 1
         Notetab 2
         MsgTable 3
      }

      #SharedData_initColors
      #MsgCenter_setTkOptions

      MsgCenter_createWidgets
      MsgCenter_close
      
      wm protocol ${topLevelW} WM_DELETE_WINDOW [list MsgCenter_close]
      
      # point the node in its respective flow on double click
      bind [${tableW} bodytag] <Double-Button-1> [ list MsgCenter_doubleClickCallback ${tableW}]

      # active menu on right-click
      bind [${tableW} bodytag] <Button-3> [list MsgCenter_rightClickCallback ${tableW} %W %x %y]
      MsgCenter_setTitle ${topLevelW}

      # give full space to message table
      grid columnconfigure ${topLevelW} 0 -weight 1

      # give new real estate to the msg table
      grid rowconfigure ${topLevelW} $MsgCenterMainGridRowMap(MsgTable) -weight 1

      wm minsize ${topLevelW} 800 200
   }
}


