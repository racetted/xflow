#!/home/binops/afsi/ssm/domain2/tcl-tk_8.5.7_linux26-i686/bin/wish8.5
#!/home/binops/afsi/ssm/sw/linux26-i686/bin/tclsh8.4
#set auto_path [linsert $auto_path 0 /home/ordenv/ssm-domains/ssm-setup-1.0-ops/xflow_1.0_all/lib]
#set auto_path [linsert $auto_path 0 [exec pwd]]
#package require Tk
#package require tile
package require keynav
package require struct::record
package require autoscroll
package require tooltip
package require tablelist
package require cmdline
package require Thread
package require BWidget 1.9
package require img::gif
package require log

namespace import ::struct::record::*

global env
if { ! [info exists env(SEQ_XFLOW_BIN) ] } {
   puts "SEQ_XFLOW_BIN must be defined!"
   exit
}

set lib_dir $env(SEQ_XFLOW_BIN)/../lib
# puts "lib_dir=$lib_dir"
set auto_path [linsert $auto_path 0 $lib_dir ]

#::ttk::setTheme classic
package require DrawUtils
package require SuiteNode
package require FlowNodes

::DrawUtils::init

proc xflow_setTkOptions {} {
   option add *activeBackground [SharedData_getColor ACTIVE_BG]
   option add *selectBackground [SharedData_getColor SELECT_BG]
   catch { option add *troughColor [::tk::Darken [option get . background Scrollbar] 85] }

   # ttk::style configure Xflow.Menu -background cornsilk4
}

proc xflow_addFileMenu { parent } {
   if { $parent == "." } {
      set parent ""
   }
   set menuButtonW ${parent}.menub
   set menuW $menuButtonW.menu

   menubutton $menuButtonW -text File -underline 0 -menu $menuW \
      -relief [SharedData_getMiscData MENU_RELIEF]
   menu $menuW -tearoff 0

   $menuW add command -label "Quit" -underline 0 -command "xflow_quit" 

   pack $menuButtonW -side left -pady 2 -padx 2
   tooltip::tooltip $menuW -index "Quit" "test tooltip"
}

proc xflow_addViewMenu { parent } {
   global AUTO_MSG_DISPLAY FLOW_SCALE
   if { $parent == "." } {
      set parent ""
   }
   set menuButtonW ${parent}.viewb
   set menuW $menuButtonW.menu

   menubutton $menuButtonW -text View -underline 0 -menu $menuW \
      -relief [SharedData_getMiscData MENU_RELIEF]
   menu $menuW -tearoff 0

   if { [SharedData_getMiscData OVERVIEW_MODE] == "false" } {
      $menuW add checkbutton -label "Auto Message Display" -variable AUTO_MSG_DISPLAY \
         -command [list xflow_setAutoMsgDisplay] \
         -onvalue true -offvalue false
   }

   $menuW add checkbutton -label "Monitor Latest Logs" -variable MONITORING_LATEST \
      -onvalue 1 -offvalue 0 -command [ list xflow_logsMonitorChanged $parent ]

   $menuW add checkbutton -label "Show Shadow Status" -variable SHADOW_STATUS \
      -onvalue 1 -offvalue 0 -command [list xflow_redrawAllFlow]

   set displayMenu $menuW.displayMenu

   $menuW add cascade -label "Node Display" -underline 5 -menu ${displayMenu}
   menu ${displayMenu} -tearoff 0
   foreach item "normal catchup cpu machine_queue memory mpi wallclock" {
      set value ${item}
      ${displayMenu} add radiobutton -label ${item} -variable NODE_DISPLAY_PREF -value ${value} \
         -command [list xflow_redrawAllFlow]
   }

   set scaleMenu $menuW.scaleMenu
   $menuW add cascade -label "Flow Scale" -underline 5 -menu ${scaleMenu}
   menu ${scaleMenu} -tearoff 0
   ${scaleMenu} add radiobutton -label "scale-normal" -variable FLOW_SCALE -value 1 \
      -command [list xflow_redrawAllFlow]
   ${scaleMenu} add radiobutton -label "scale-2" -variable FLOW_SCALE -value 2 \
      -command [list xflow_redrawAllFlow]

   pack $menuButtonW -side left -pady 2 -padx 2
}

proc xflow_addHelpMenu { parent } {
   if { $parent == "." } {
      set parent ""
   }
   set menuButtonW ${parent}.helpb
   set menuW $menuButtonW.menu

   menubutton $menuButtonW -text Help -underline 0 -menu $menuW  \
      -relief [SharedData_getMiscData MENU_RELIEF]
   menu $menuW -tearoff 0

   $menuW add command -label "Experiment Support" -underline 11 -command [list xflow_showSupportCallback]
   $menuW add command -label "Maestro Commands" -underline 8 -command "xflow_maestroCmds ${parent}"
   $menuW add command -label "About" -underline 0 -command "About_show ${parent}"

   pack $menuButtonW -side left -pady 2 -padx 2
}

proc xflow_showSupportCallback {} {
   set suiteRecord [xflow_getActiveSuite]
   ExpOptions_showSupport  [${suiteRecord} cget -suite_path] [xflow_getWidgetName top_frame]
}

# no fancy format here, it's a simple dump of the content
# of $SEQ_XFLOW_BIN/../etc/commands_summary.txt into a text widget
proc xflow_maestroCmds { parent } {
   global env
   set topW .maestro_cmds_top

   if { [winfo exists ${topW}] } {
      wm withdraw ${topW} ; wm deiconify ${topW}
   } else {
      toplevel ${topW}
      Utils_positionWindow ${topW} ${parent}
      wm title ${topW} "Maestro Commands Summary"

      set txtW ${topW}.txt
      text ${txtW} -width 30 -wrap word -yscrollcommand [list ${topW}.yscroll set]
      
      # get the info 
      set infoFile $env(SEQ_XFLOW_BIN)/../etc/command_summary.txt
      if { [file readable ${infoFile}] } {
         set infoTxt [exec cat ${infoFile}]
         ${txtW} insert end ${infoTxt}
      }

      set closeButton [button ${topW}.close_button -text Close \
         -command [list destroy ${topW}]]

      # add vertical scroll, don't need horiz scroll since the text is wrapped
      scrollbar ${topW}.yscroll -command [list ${txtW}  yview ]
      # only show the scrollbars if required
      ::autoscroll::autoscroll ${topW}.yscroll

      grid ${txtW} -sticky wens -row 0 -column 0 -padx 5 -pady {5 2}
      grid ${topW}.yscroll -row 0 -column 1 -sticky ns
      grid ${closeButton} -row 1 -column 0 -pady 5

      grid rowconfigure ${topW} 0 -weight 1
      grid columnconfigure ${topW} 0 -weight 1

      wm geometry ${topW} =625x625
   }
}

proc xflow_createToolbar { parent } {
   ::log::log debug "xflow_createToolbar ${parent}"
   global MSG_CENTER_THREAD_ID

   set msgCenterW [xflow_getWidgetName msgcenter_button]
   set nodeKillW [xflow_getWidgetName nodekill_button]
   set catchupW [xflow_getWidgetName catchup_button]
   set findW [xflow_getWidgetName find_button]
   set refreshW [xflow_getWidgetName refresh_button]
   #set nodeListW [xflow_getWidgetName nodelist_button]
   #set nodeAbortListW [xflow_getWidgetName abortlist_button]
   set colorLegendW [xflow_getWidgetName legend_button]
   set closeW [xflow_getWidgetName close_button]
   #set depW [xflow_getWidgetName dep_button]
   set shellW [xflow_getWidgetName shell_button]
   set catchupTopW [xflow_getWidgetName catchup_toplevel]

   set imageDir [SharedData_getMiscData IMAGE_DIR]

   set noNewMsgImage [xflow_getWidgetName msg_center_img]
   set hasNewMsgImage [xflow_getWidgetName msg_center_new_img]
   image create photo ${noNewMsgImage} -file ${imageDir}/open_mail_sh.gif
   image create photo ${hasNewMsgImage} -file ${imageDir}/open_mail_new.gif
   image create photo ${parent}.node_kill_img -file ${imageDir}/node_kill.gif
   image create photo ${parent}.catchup_img -file ${imageDir}/catchup.gif
   image create photo ${parent}.find_img -file ${imageDir}/find.png
   #image create photo ${parent}.node_list_img -file ${imageDir}/node_list.ppm
   #image create photo ${parent}.node_abort_list_img -file ${imageDir}/node_abort_list.ppm
   image create photo ${parent}.refresh_img -file ${imageDir}/refresh.gif
   image create photo ${parent}.close -file ${imageDir}/cancel.gif
   image create photo ${parent}.color_legend_img -file ${imageDir}/color_legend.gif
   #image create photo ${parent}.ignore_dep_true -file ${imageDir}/dep_on.ppm
   #image create photo ${parent}.ignore_dep_false -file ${imageDir}/dep_off.ppm
   image create photo ${parent}.shell_img -file ${imageDir}/terminal.ppm

   button ${msgCenterW} -padx 0 -pady 0 -image ${noNewMsgImage} -command {
      thread::send -async ${MSG_CENTER_THREAD_ID} "MsgCenterThread_showWindow"
   } -relief flat
   ::tooltip::tooltip ${msgCenterW} "Show Message Center."

   button ${nodeKillW} -image ${parent}.node_kill_img -command [list xflow_nodeKillDisplay ${parent} ] -relief flat
   tooltip::tooltip ${nodeKillW}  "Open job killing dialog"

   button ${catchupW} -image ${parent}.catchup_img -command [list Catchup_createMainWidgets ${catchupTopW} [winfo toplevel ${parent}]] -relief flat
   tooltip::tooltip ${catchupW}  "Open exp catchup window"

   button ${shellW} -image ${parent}.shell_img -command xflow_launchShellCallback -relief flat
   tooltip::tooltip ${shellW}  "Start shell at exp home"

   button ${findW} -image ${parent}.find_img -relief flat -command [list xflow_showFindWidgets]
   tooltip::tooltip ${findW}  "Find a node."

   button ${refreshW} -image ${parent}.refresh_img -relief flat -command [list xflow_refreshFlow]
   tooltip::tooltip ${refreshW}  "Flow refresh."

   #button ${nodeListW} -image ${parent}.node_list_img  -state disabled -relief flat
   #tooltip::tooltip ${nodeListW} "Open succesfull node listing dialog -- future feature."

   #button ${nodeAbortListW} -image ${parent}.node_abort_list_img -state disabled -relief flat
   #tooltip::tooltip ${nodeAbortListW} "Open abort node listing dialog -- future feature."

   button ${closeW} -image ${parent}.close -command [list xflow_quit] -relief flat
   ::tooltip::tooltip ${closeW} "Close application."

   button ${colorLegendW} -image ${parent}.color_legend_img -command [list xflow_showColorLegend ${colorLegendW}] -relief flat
   tooltip::tooltip ${colorLegendW} "Show color legend." 

   #button ${depW} -relief flat -image ${parent}.ignore_dep_false -command [list xflow_changeIgnoreDep ${depW} ${parent}.ignore_dep_true ${parent}.ignore_dep_false] -state disabled

   if { [SharedData_getMiscData OVERVIEW_MODE] == "true" } {
      set overviewW [xflow_getWidgetName overview_button]
      image create photo ${parent}.overview -file ${imageDir}/calendar_clock.gif
      button ${overviewW} -relief flat -image ${parent}.overview -command {
         set overviewThreadId [SharedData_getMiscData OVERVIEW_THREAD_ID]
         thread::send -async ${overviewThreadId} "Overview_toFront"
      }
      ::tooltip::tooltip ${overviewW} "Show overview window."
      ::tooltip::tooltip ${closeW} "Close window."
      grid ${msgCenterW} ${overviewW} ${nodeKillW} ${catchupW} ${shellW} ${findW} ${refreshW} ${colorLegendW} ${closeW} -sticky w -padx 2
   } else {
      grid ${msgCenterW} ${nodeKillW} ${catchupW} ${shellW} ${findW} ${refreshW} ${colorLegendW} ${closeW} -sticky w -padx 2
   }

}

proc xflow_showColorLegend { caller_w } {
   set topW .color_legend
   if { [winfo exists ${topW}] } {
      wm withdraw ${topW} ; wm deiconify ${topW}
   } else {
      toplevel ${topW}
      Utils_positionWindow ${topW} ${caller_w}
      wm title ${topW} Legend

      set statusFrame [ labelframe ${topW}.status_frame -text "Node Status" ]

      set rowCounter 0
      set statusList { begin init submit abort end catchup wait unknown}
      foreach status ${statusList} {
         label ${statusFrame}.l${status} -text ${status} \
            -fg [::DrawUtils::getFgStatusColor ${status}] \
            -bg [::DrawUtils::getBgStatusColor ${status}] -padx 10 -bd 2

         grid ${statusFrame}.l${status} -sticky wens -column 0 -row ${rowCounter} -padx 2 -pady 2

         grid rowconfigure ${statusFrame} ${rowCounter} -weight 1
         incr rowCounter
      }

      set closeButton [button ${topW}.close_button -text Close \
         -command [list destroy ${topW}]]

      
      grid ${statusFrame} -sticky wens -row 0 -column 0 -padx 5 -pady {5 2}
      grid ${closeButton} -row 1 -column 0 -pady 5
      grid columnconfigure ${statusFrame} 0 -weight 1

      grid rowconfigure ${topW} 0 -weight 1
      grid columnconfigure ${topW} 0 -weight 1

      wm geometry ${topW} =175x300
   }
}

# this function creates the widgets that allows
# the user to set/query the current datestamp
proc xflow_addDatestampWidget { parent_widget } {
   set dtFrame ${parent_widget}
   set dateEntry [xflow_getWidgetName exp_date_entry]
   set buttonFrame [xflow_getWidgetName exp_date_button_frame]

   labelframe ${dtFrame} -text "Exp Datestamp (yyyymmddhh)"
   tooltip::tooltip ${dtFrame} "Current Datestamp"

   entry ${dateEntry} -width 11
   tooltip::tooltip $dateEntry "Enter a value then set the experiment datestamp."

   frame ${buttonFrame}

   set imageDir [SharedData_getMiscData IMAGE_DIR]
   image create photo ${buttonFrame}.set_image -file ${imageDir}/ok.gif
   image create photo ${buttonFrame}.refresh_image -file ${imageDir}/refresh.gif

   set setButton [button ${buttonFrame}.set_button -relief flat -image ${buttonFrame}.set_image \
      -command [list xflow_setDateStamp ${dtFrame}]]
   tooltip::tooltip ${setButton} "Sets new datestamp value."

   set refreshButton [button ${buttonFrame}.refresh_button -relief flat -image ${buttonFrame}.refresh_image \
      -command [list xflow_getDateStamp ${dtFrame}]]
   tooltip::tooltip $refreshButton "Reloads the current experiment datestamp value."

   #pack $setButton $refreshButton -side left -pady 2 -padx 5
   pack $setButton $refreshButton -side left -pady 2 -padx 2
   pack $dateEntry -side left -pady 2 -padx 2
   pack $buttonFrame -pady 2 -side left
   #pack $dtFrame -side left -pady 2 -padx 2 -fill x -expand 1
}

# this function creates the widgets that allows
# the user to view the exp in history mode
# It retrieves the list of exp dates with $SEQ_EXP_HOME/logs/*_nodelog files
proc xflow_addMonitorDateWidget { parent_widget } {

   set monitorFrame ${parent_widget}
   labelframe ${monitorFrame} -text "Monitoring Datestamp (yyyymmddhh)"
   set monitorEntryCombo [xflow_getWidgetName monitor_date_combo]
   #bind $monitorFrame <Double-Button-1> [list xflow_viewHideDateButtons . .date .date_hidden 20 ]
   tooltip::tooltip $monitorFrame "Monitor Exp History Logs"

   ttk::combobox ${monitorEntryCombo}

   set buttonFrame [xflow_getWidgetName monitor_date_button_frame]
   frame ${buttonFrame}
   set imageDir [SharedData_getMiscData IMAGE_DIR]
   image create photo ${buttonFrame}.set_image -file ${imageDir}/ok.gif
   image create photo ${buttonFrame}.refresh_image -file ${imageDir}/refresh.gif

   set setButton [xflow_getWidgetName monitor_date_set_button]
   button ${setButton} -relief flat -image ${buttonFrame}.set_image \
      -command [list xflow_setMonitorDate ${monitorFrame}]
   tooltip::tooltip $setButton "Sets the datestamp value being displayed in the flow."

   set refreshButton [button ${buttonFrame}.refresh_button -relief flat -image ${buttonFrame}.refresh_image \
      -command [list xflow_populateMonitorDate ${monitorFrame}]]
   tooltip::tooltip $refreshButton "Refresh the datestamp list."

   # by default the monitor widgets are disabled
   xflow_changeMonitorWidgetState disabled

   pack $setButton $refreshButton -side left -pady 2 -padx 2
   pack ${monitorEntryCombo} -side left -pady 2 -padx 2 -fill x
   pack $buttonFrame -pady 2 -side left
   # pack $monitorFrame -side left -pady 2 -padx 2 -fill x -expand 1

   tooltip::tooltip ${monitorEntryCombo} "Select value of the date being displayed in the flow."
}

# creates the widget for the find node functionality
proc xflow_createFindWidgets { _parent_widget } {
   global FIND_MATCH_CASE
   set findLabel [xflow_getWidgetName find_label]
   set findEntry [xflow_getWidgetName find_entry]
   set findCloseB [xflow_getWidgetName find_close_button]
   set findNextB [xflow_getWidgetName find_next_button]
   set findPreviousB [xflow_getWidgetName find_previous_button]
   set findCloseImg [xflow_getWidgetName find_close_image]
   set findNextImg [xflow_getWidgetName find_next_image]
   set findPreviousImg [xflow_getWidgetName find_previous_image]
   set findCaseCheck [xflow_getWidgetName find_matchcase_check]
   Label ${findLabel} -text "Find:"
   Entry ${findEntry} -width 25
   bind ${findEntry} <Return> [list xflow_findCallback ${findEntry} next]

   set imageDir [SharedData_getMiscData IMAGE_DIR]
   image create photo ${findNextImg} -file [SharedData_getMiscData IMAGE_DIR]/[xflow_getWidgetName find_next_image_file]
   image create photo ${findPreviousImg} -file [SharedData_getMiscData IMAGE_DIR]/[xflow_getWidgetName find_previous_image_file]
   image create photo ${findCloseImg} -file [SharedData_getMiscData IMAGE_DIR]/[xflow_getWidgetName find_close_image_file]

   Button ${findCloseB} -image ${findCloseImg} -relief flat
   Button ${findNextB} -image ${findNextImg} -relief flat -text Next -compound left -underline 0  -command [list xflow_findCallback ${findEntry} next]
   Button ${findPreviousB} -image ${findPreviousImg} -relief flat -text Previous -compound left -underline 0  -command [list xflow_findCallback ${findEntry} previous]
   checkbutton ${findCaseCheck} -text "Match case" -indicatoron true -variable FIND_MATCH_CASE \
      -command {
         # reset the search everytime the case is changed
         set XFLOW_FIND_TEXT ""
      }

   set FIND_MATCH_CASE 0

   bind . <Control-Key-f> [list xflow_showFindWidgets]
   bind . <Key-F3> [list xflow_findCallback ${findEntry} next]
   bind . <Shift-Key-F3> [list xflow_findCallback ${findEntry} previous]
   pack ${findCloseB} ${findLabel} ${findEntry} ${findNextB} ${findPreviousB} ${findCaseCheck} -side left -padx 2 -pady 2
}

# this is call whenever the user hits on next or previous on the find 
proc xflow_findCallback { _entry_w _next_or_previous } {
   global XFLOW_FIND_TEXT XFLOW_FIND_RESULTS XFLOW_FIND_INDEX XFLOW_FIND_AFTER_ID
   global FIND_MATCH_CASE NodeHighLightRestoreCmd
   ::log::log debug "xflow_findCallback _entry_w:${_entry_w} _next_or_previous:${_next_or_previous}"
   set findFrame [xflow_getWidgetName find_frame]
   if { [grid info ${findFrame}] == "" } {
      # the find window is close, do nothing
      return
   }

   if { ! [info exists XFLOW_FIND_TEXT] } {
      set XFLOW_FIND_TEXT ""
   }
   if { [info exists XFLOW_FIND_AFTER_ID] } {
      after cancel ${XFLOW_FIND_AFTER_ID}
      eval $NodeHighLightRestoreCmd
   }

   set findText [${_entry_w} cget -text]
   if { ${findText} == "" } {
      return
   }
   set activeSuiteRecord [xflow_getActiveSuite]
   if { ${findText} != ${XFLOW_FIND_TEXT} } {
      # new find
      set XFLOW_FIND_TEXT ${findText}
      set XFLOW_FIND_RESULTS {}
      set rootNode [${activeSuiteRecord} cget -root_node]
      ::FlowNodes::searchForNode ${rootNode} ${findText} ${FIND_MATCH_CASE} XFLOW_FIND_RESULTS
      if { [llength ${XFLOW_FIND_RESULTS}] != 0 } {
         # found something
         set XFLOW_FIND_INDEX 0
         ::log::log debug "new search ound node: [lindex ${XFLOW_FIND_RESULTS} ${XFLOW_FIND_INDEX}]"
      }
   } else {
      # existing search
      if { ${_next_or_previous} == "next" } {
         incr XFLOW_FIND_INDEX
         if { ${XFLOW_FIND_INDEX} == [llength ${XFLOW_FIND_RESULTS}] } {
            set XFLOW_FIND_INDEX 0
         }
      } else {
         # assume previous
         incr XFLOW_FIND_INDEX -1
         if { ${XFLOW_FIND_INDEX} == -1 } {
            set XFLOW_FIND_INDEX [expr [llength ${XFLOW_FIND_RESULTS}] - 1]
         }
      }
      ::log::log debug "found node: [lindex ${XFLOW_FIND_RESULTS} ${XFLOW_FIND_INDEX}]"
   }
   if { [llength ${XFLOW_FIND_RESULTS}] != 0 } {
      set foundNode [lindex ${XFLOW_FIND_RESULTS} ${XFLOW_FIND_INDEX}]
      set mainFlowCanvas [xflow_getMainFlowCanvas]
      # if the node is collapsed, uncollapse it
      if { [::FlowNodes::uncollapseBranch ${foundNode} ${mainFlowCanvas}] != "" } {
         xflow_drawflow ${mainFlowCanvas} 0
      }

      set foundTag [::DrawUtils::highLightFindNode ${activeSuiteRecord} ${foundNode} ${mainFlowCanvas}]
      # make sure the node is visible
      ::DrawUtils::viewCanvasItem [xflow_getMainFlowCanvas] ${foundTag}

      set XFLOW_FIND_AFTER_ID [after 5000 eval $NodeHighLightRestoreCmd]
   }
}

proc xflow_showFindWidgets {} {
   set findFrame [xflow_getWidgetName find_frame]
   set findEntry [xflow_getWidgetName find_entry]
   grid ${findFrame}
   focus ${findEntry}
}

# this function is only called in xflow standalone mode.
# It propagates the Auto Message Display configuration. Alghouh this configuration
# is already global for the xflow thread, it is also used by the message center so it needs to go through the
# SharedData so that the msg center thread can fetch it.
proc xflow_setAutoMsgDisplay {} {
   global AUTO_MSG_DISPLAY
   ::log::log debug "xflow_setAutoMsgDisplay AUTO_MSG_DISPLAY new value: ${AUTO_MSG_DISPLAY}"
   SharedData_setMiscData AUTO_MSG_DISPLAY ${AUTO_MSG_DISPLAY}
}

# generic callback for whoever wants to call the xflow_selectSuiteTab
# it simply redraws the exp flow
proc xflow_selectSuiteCallback { } {
   xflow_selectSuiteTab [xflow_getWidgetName flow_frame] [xflow_getActiveSuite]
}

# this function adds a background image to an exp flow canvas.
# The image is created once when the canvas is created; this function is called
# when the flow is redrawn or the window is resized
proc xflow_AddCanvasBg { canvas } {
   # image already created at canvas creaton time
   set imageBg ${canvas}.bg_image
   set imageTagName ${canvas}_bg_image

   ${canvas} delete ${imageTagName}
   ${canvas} create image 0 0 -anchor nw -image ${imageBg} -tags ${imageTagName}
   ${canvas} lower ${imageTagName}
}

proc xflow_changeMonitorWidgetState { new_state } {
   ::log::log debug "xflow_changeMonitorWidgetState called ${new_state}"
   set monitorFrame [xflow_getWidgetName monitor_date_frame]
   set monitorEntryCombo [xflow_getWidgetName monitor_date_combo]
   set setButton [xflow_getWidgetName monitor_date_set_button]

   $setButton configure -state ${new_state}
   ${monitorEntryCombo} configure -state ${new_state}
   ${monitorEntryCombo} set latest
}

# this function is called when the user changes the
# "Monitoring Latest Logs" configuration,
# enabling or disabling access to select datestamps in history mode
proc xflow_logsMonitorChanged { parent_w } {
   global MONITORING_LATEST
   ::log::log debug "xflow_logsMonitorChanged called"
   if { $parent_w == "." } {
      set parent_w ""
   }

   set top [winfo toplevel $parent_w]
   Utils_busyCursor $top
   catch {
      if { $MONITORING_LATEST == 0 } {
         # view history mode, enable monitor widgets
         xflow_changeMonitorWidgetState normal
      } else {
         # view latest log, disable monitor widgets
         xflow_changeMonitorWidgetState disabled

         # when the user shift back to read latest
         # we need to reread the latest log file
         # and redraw the flow
         set suiteRecord [xflow_getActiveSuite]

         $suiteRecord configure -read_offset 0 -active_log ""
         ::FlowNodes::resetNodeStatus [$suiteRecord cget -root_node]
         set isOverviewMode [SharedData_getMiscData OVERVIEW_MODE]
         # startup mode puts the log reader in update data records only
         # and does not update the flow on each log entry
         xflow_initStartupMode
         if { ${isOverviewMode} == "true" } {
            set overviewThreadId [SharedData_getMiscData OVERVIEW_THREAD_ID]
            # we need to read the log files using the overview thread so that updates
            # on the exp root node will be propagated to the overview window
            LogReader_readFile $suiteRecord ${overviewThreadId}
         } else {
            LogReader_readFile $suiteRecord [thread::id]
         }
         xflow_stopStartupMode
         # redraw the flow
         xflow_selectSuiteCallback
      }
   }

   Utils_normalCursor $top
}

# this function is called when the user click on the arrows to
# close or open the control bar in a run window
proc xflow_viewHideDateButtons { parent currentFrame replacementFrame height } {
   puts "xflow_viewHideDateButtons currentFrame:$currentFrame replacementFrame:$replacementFrame height:$height"
   grid forget $currentFrame
   if { $height != "" } {  
       puts "xflow_viewHideDateButtons here 0"
       $replacementFrame configure -height $height
      #grid $replacementFrame -row 2 -column 0 -columnspan 2 -sticky nsew -padx 2 -pady 2
      grid $replacementFrame -row 1 -column 1 -columnspan 2 -sticky nsew -padx 2 -pady 2
   } else {
       puts "xflow_viewHideDateButtons here 1"
      #grid $replacementFrame -row 2 -column 0 -columnspan 2 -sticky nsew -padx 2 -pady 2
      grid $replacementFrame -row 1 -column 1 -columnspan 2 -sticky nsew -padx 2 -pady 2
   }
}

# NOT USED for now
proc xflow_addListButtonsWidget { monitorFrame } {

   if { $monitorFrame == "." } {
      set monitorFrame ""
   }
   set imageNodeKill ${monitorFrame}.node_kill_img
   set imageNodeList ${monitorFrame}.node_list_img
   set imageNodeAbortList ${monitorFrame}.node_abort_list_img
   set imageDir [SharedData_getMiscData IMAGE_DIR]

   image create photo ${imageNodeKill} -file ${imageDir}/node_kill.ppm
   image create photo ${imageNodeList} -file ${imageDir}/node_list.ppm
   image create photo ${imageNodeAbortList} -file ${imageDir}/node_abort_list.ppm

   set killButton [button $monitorFrame.kill_button -image ${imageNodeKill} -text "Nodekill" \
      -command [list xflow_nodeKillDisplay $monitorFrame ] ]
   tooltip::tooltip $killButton "Open job killing dialog"
   set listerButton [button $monitorFrame.list_button -image ${imageNodeList} -text "Nodelister ( success )" \
      -command [list nodeListDisplay $monitorFrame success ] ]
   tooltip::tooltip $listerButton "Open succesfull node listing dialog -- future feature."
   set abortListerButton [button $monitorFrame.abortlist_button -image ${imageNodeAbortList} -text "Nodelister ( abort )" \
      -command [list nodeListDisplay $monitorFrame abort ] ]
   tooltip::tooltip $abortListerButton "Open abort node listing dialog -- future feature."

   $abortListerButton configure -state disabled
   $listerButton configure -state disabled
   pack $monitorFrame.kill_button -side left -pady 2 -padx 2
   pack $monitorFrame.list_button -side left -pady 2 -padx 2
   pack $monitorFrame.abortlist_button -side left -pady 2 -padx 2

}

# this function creates the widgets for the node kill window
# that is invoked from the xflow toolbar
proc xflow_nodeKillDisplay { parent_w } {

   global env
   set shadowColor [SharedData_getColor SHADOW_COLOR]
   set bgColor [SharedData_getColor CANVAS_COLOR]
   set id [clock seconds]
   set tmpdir $env(TMPDIR)
   set tmpfile "${tmpdir}/test$id"
   set suiteRecord [xflow_getActiveSuite]
   set suitePath [$suiteRecord cget -suite_path]
   set killPath [SharedData_getMiscData SEQ_UTILS_BIN]/nodekill 
   set cmd "export SEQ_EXP_HOME=$suitePath; $killPath -listall > $tmpfile 2>&1"
   ::log::log debug "xflow_nodeKillDisplay ksh -c $cmd"
   catch { eval [exec ksh -c $cmd ] }

   ##set fullList [list showAllListings $node $type $canvas $canvas.list]
   if { $parent_w == "" } {
      set parent_w "."
   }

   set soloWindow $parent_w.nodekill 

   if { [winfo exists $soloWindow] } {
        destroy $soloWindow
    }

   toplevel $soloWindow
   wm geometry ${soloWindow} +[winfo pointerx ${parent_w}]+[winfo pointery ${parent_w}]
   
   frame $soloWindow.frame -relief raised -bd 2 -bg $bgColor
   pack $soloWindow.frame -fill both -expand 1 
   listbox $soloWindow.list -yscrollcommand "$soloWindow.yscroll set" \
	  -xscrollcommand "$soloWindow.xscroll set"  \
	  -height 10 -width 70 -selectmode extended -bg $bgColor -fg $shadowColor
   scrollbar $soloWindow.yscroll -command "$soloWindow.list yview"  -bg $bgColor
   scrollbar $soloWindow.xscroll -command "$soloWindow.list xview" -orient horizontal -bg $bgColor

   set cancelButton [button $soloWindow.cancel_button -text "Cancel" \
      -command [list destroy $soloWindow ]]
   tooltip::tooltip $cancelButton "Close this window"
   pack $cancelButton -side right -padx 4 -pady 2

   set killButton [button $soloWindow.kill_button -text "Kill Selected Jobs" \
      -command [list xflow_killNode $soloWindow.list ]]
   tooltip::tooltip $killButton "Send kill signals to selected job_ID"
   pack $killButton -side right -pady 2

   pack $soloWindow.xscroll -fill x -side bottom -in $soloWindow.frame
   pack $soloWindow.yscroll -side right -fill y -in $soloWindow.frame
   pack $soloWindow.list -expand 1 -fill both -padx 1m -side left -in $soloWindow.frame

   set resultingFile [open $tmpfile] 

   while { [gets $resultingFile line ] >= 0 } {
         $soloWindow.list insert end $line 
   }

   catch {[exec rm -f $tmpfile]}

}

# this function retrieves the selected entries from
# the node kill window and attempts to kill the running
# jobs by invoking the maestro-utils nodekill executable.
proc xflow_killNode { list_widget } {

   set indexlist [ $list_widget curselection ]
   ::log::log debug "xflow_killNode list_widget:$list_widget indexlist:$indexlist"
   set listOfNodes ""
   for {set iterator 0} {$iterator < [llength $indexlist]} {incr iterator} {
      set listOfNodes [ linsert $listOfNodes end [ $list_widget get [ lindex $indexlist $iterator ]]]
   }
   set suiteRecord [xflow_getActiveSuite]
   set suitePath [$suiteRecord cget -suite_path]
   set seqExec [SharedData_getMiscData SEQ_UTILS_BIN]/nodekill
   set numOfEntries [llength $listOfNodes]

   for {set iterator 0} {$iterator < $numOfEntries} {incr iterator} {
      set listEntryValue [ split [ lindex $listOfNodes $iterator ] " " ]
      set jobFullPath [lindex $listEntryValue 8]
      if { [string first "/sequencing/jobinfo/" ${jobFullPath}] != -1 } {
         set jobStartIndex [expr [string first "/sequencing/jobinfo/" ${jobFullPath}] + [string length "/sequencing/jobinfo/"] - 1]
         set jobPath [string range ${jobFullPath} ${jobStartIndex} end]
         set nodeID [file tail ${jobPath}]
         set node [file dirname ${jobPath}]/[lindex $listEntryValue end]
         ::log::log debug "xflow_killNode command: $seqExec  -n $node -job_id $nodeID"
         Sequencer_runCommandLogAndWindow $suitePath $seqExec "Node Kill [file tail $node]" top -n $node -job_id $nodeID
         
      } else {
         Utils_raiseError [winfo toplevel ${list_widget}] "Kill Node" "Application Error: Unable to retrieve Task Id."
      }
   }
}

# this function is called to populate the list of
# available monitor experiment dates in the
# in the Monitoring Datestamp frame
proc xflow_populateMonitorDate { monitor_frame } {

   set suite_record [xflow_getActiveSuite]
   set suitePath [${suite_record} cget -suite_path]
   set dateList [LogReader_getAvailableDates $suitePath]
   set monitorEntryCombo [xflow_getWidgetName monitor_date_combo]
   
   set values ""
   foreach date $dateList {
      set values "$values [Utils_getVisibleDatestampValue ${date}]"
   }
   ${monitorEntryCombo} configure -values $values
}

# this function is called when the user selects a monitoring datestamp
# value. It will redisplay the flow reflecting the content of the new datestamp
# exp log file. Currently, the behavior is different whether the xflow is running
# in standalone mode or within the xflow_overview. In overview mode, a new exp window
# is launched so that the latest log window is always visible. In standalone mode, the
# new flow simply overwrites the existing flow.
proc xflow_setMonitorDate { parent_w } {
   global MONITOR_DATESTAMP
   ::log::log debug "xflow_setMonitorDate called"
   set top [winfo toplevel $parent_w]
   Utils_busyCursor $top
   catch {
      set suiteRecord [xflow_getActiveSuite]
      set suitePath [$suiteRecord cget -suite_path]
      set dateList [LogReader_getAvailableDates $suitePath]
   
      set dateEntryCombo [xflow_getWidgetName monitor_date_combo]
      set dateValue [$dateEntryCombo get]
   
      foreach date $dateList {
         if { [string match [Utils_getRealDatestampValue ${dateValue}] $date] } {
            set found 1
            break
         }
      }
      if { $found == 0 } {
         Utils_raiseError [winfo toplevel $parent_w] "Datestamp" "Selected date does not exists!\nPlease choose another date."
      } else {
         # MONITOR_DATESTAMP is also used for listings and history
         set MONITOR_DATESTAMP [Utils_getRealDatestampValue ${dateValue}]
         ::log::log debug "xflow_setMonitorDate ${MONITOR_DATESTAMP}"
         set isOverviewMode [SharedData_getMiscData OVERVIEW_MODE]
         if { ${isOverviewMode} == "true" } {
            set monitorThreadId [xflow_getMonitoredThread]
            # in overview mode, the monitor thread takes care of it
            ::log::log debug "xflow_setMonitorDate thread::send ${monitorThreadId} xflowThread_monitorNewDate ${suitePath} ${MONITOR_DATESTAMP}"
            thread::send ${monitorThreadId} "xflowThread_monitorNewDate ${suitePath} ${MONITOR_DATESTAMP}"
            # reset MONITOR_DATESTAMP, main window should still point to current datestamp in overview mode
            set MONITOR_DATESTAMP ""
         } else {
            # in standalone mode
            # point the exp to the history log
            $suiteRecord configure -read_offset 0 -active_log ${MONITOR_DATESTAMP}
            # make sure all nodes are reset
            ::FlowNodes::resetNodeStatus [$suiteRecord cget -root_node]
            #xflow_initStartupMode
            # read the log file
            #LogReader_readFile $suiteRecord [thread::id]
            #xflow_stopStartupMode
            # update the flow
            #xflow_redrawAllFlow

            set thisThreadId [thread::id]
            set callingThreadId [SharedData_getMiscData ${thisThreadId}_CALLING_THREAD_ID]
            xflow_displayFlow ${callingThreadId}
         }
      }
   }

   Utils_normalCursor $top
}

proc xflow_readFlowXml {} {
   global SEQ_EXP_HOME
   ::log::log debug "xflow_readFlowXml SEQ_EXP_HOME:${SEQ_EXP_HOME}"
   set suitePath ${SEQ_EXP_HOME}
   readMasterfile ${suitePath}/EntryModule/flow.xml $suitePath "" ""
   set activeSuiteRecord [SuiteNode::getSuiteRecordFromPath ${suitePath}]
   xflow_setActiveSuite $activeSuiteRecord
}

# this is used to set a variable that will be used mainly
# when reading the exp log files.
# when the variable is set to false (init mode)... log entries will only
# update the data records and do not update the flow as it would
# under normal condition... This is mainly used at the initial phase
# when the log file is read completely i.e. when user switches to history mode
# or when user changes datestamp...
proc xflow_initStartupMode {} {
   SharedData_setMiscData [thread::id]_STARTUP_DONE false
}

# stop the startup mode... New entries found in the exp log
# file now update both the data records & the flow
proc xflow_stopStartupMode {} {
   SharedData_setMiscData [thread::id]_STARTUP_DONE true
}

# change the "Monitor Latest Logs" configuration
proc xflow_setMonitoringLatest { value } {
   global MONITORING_LATEST MONITOR_DATESTAMP
   set MONITORING_LATEST ${value}

   if { ${MONITORING_LATEST} == "1" } {
      set MONITOR_DATESTAMP ""
   }
}

# this function sets the monitoring datestamp in
# the proper widget... Mainly for overview mode when
# history datestamp is launched in a new exp window
proc xflow_setMonitorDateWidget {} {
   set dateEntryCombo [xflow_getWidgetName monitor_date_combo]
   set dateValue [xflow_getMonitoringDatestamp]
   $dateEntryCombo set [Utils_getVisibleDatestampValue ${dateValue}]
}

# currently, this is mainly for overview mode...
# there is a single thread created for each exp that takes care of
# displaying flows in history mode so that the currently active datestamp
# coming from $SEQ_EXP_HOME/ExpDate is always displayed
proc xflow_getMonitoredThread {} {
   global MONITOR_THREAD_ID DEBUG_TRACE

   if { ${MONITOR_THREAD_ID} == "" } {
      # Creates the singleton thread if it does not exists
      ::log::log debug "xflow_getMonitoredThread Creating new thread..."
      set MONITOR_THREAD_ID [thread::create {
         global env
         set lib_dir $env(SEQ_XFLOW_BIN)/../lib
         set auto_path [linsert $auto_path 0 $lib_dir ]
         package require SuiteNode
         package require Tk
         package require log

         set DEBUG_TRACE [SharedData_getMiscData DEBUG_TRACE]

         # this function is meant to be called in overview mode only.
         # when user views exp in history mode from the initial exp flow window,
         # this function is called to create a new window with the history log.
         # For the moment, a single thread is created to handle the history mode for
         # a specific exp.
         proc xflowThread_monitorNewDate { exp_path datestamp } {
            global XFLOW_STANDALONE MONITORING_LATEST MONITOR_DATESTAMP MONITOR_THREAD_ID SEQ_EXP_HOME 
            global LOOP_RESOURCES_DONE
            ::log::log debug "xflowThread_monitorNewDate thread_id:[thread::id] exp_path:$exp_path "

            set SEQ_EXP_HOME ${exp_path}
            xflow_init
            set LOOP_RESOURCES_DONE false
            set XFLOW_STANDALONE 1
            set MONITORING_LATEST 0
            set MONITOR_DATESTAMP ${datestamp}
            set MONITOR_THREAD_ID [thread::id]
            set thisThreadId [thread::id]
            ::log::log debug "xflowThread_monitorNewDate thread_id:[thread::id] datestamp:${datestamp} overview_mode?  [SharedData_getMiscData OVERVIEW_MODE]"
            xflow_readFlowXml
            xflow_displayFlow [thread::id]
            xflow_setMonitorDateWidget
            ::log::log debug "xflowThread_monitorNewDate thread_id:[thread::id] datestamp:${datestamp} DONE"
         }

         # enter event loop
         thread::wait
      }]
   }

   ::log::log debug "xflow_getMonitoredThread returning id: ${MONITOR_THREAD_ID}"
   return ${MONITOR_THREAD_ID}
}

# this function sets the datestamp field in the "Exp Datestamp" frame to the
# value given by tictac executable ($SEQ_EXP_DATE/ExpDate)
# It also sets the global value MONITOR_DATESTAMP that is used to retrieve
# datestamp based utilities such as node listing and node history
proc xflow_getDateStamp { parent_w {suite_record ""} } {
   global MONITOR_DATESTAMP MONITORING_LATEST
   if { ${suite_record} == "" } {
      set suite_record [xflow_getActiveSuite]
   }
   set dateStamp [xflow_retrieveDateStamp $parent_w ${suite_record}]
   set shortDatestamp [Utils_getVisibleDatestampValue ${dateStamp}]
   set dateEntry [xflow_getWidgetName exp_date_entry]
   $dateEntry delete 0 end
   $dateEntry insert 0 $shortDatestamp

   if { ${MONITORING_LATEST} == 1 } {
      set MONITOR_DATESTAMP $dateStamp
   }

   ::log::log debug "xflow_getDateStamp dateStamp:$shortDatestamp"
}

# this function is mainly used as a notification from the
# LogReader when it detects that the ${SEQ_EXP_HOME}/ExpDate has changed
# so that the displayed datestamp should be changed in the gui.
proc xflow_datestampChanged { suite_record } {
   set dateFrame [xflow_getWidgetName exp_date_frame]
   if { [winfo exists $dateFrame] } {
      xflow_getDateStamp $dateFrame ${suite_record}
   }
}

# this function returns the current exp datestamp value as given
# by the maestro tictac command. The format is '%Y%M%D%H%Min%S' i.e. 20110216000000
proc xflow_retrieveDateStamp { parent_w suite_record } {

   set dateExec "[SharedData_getMiscData SEQ_BIN]/tictac"
   set suitePath [${suite_record} cget -suite_path]
   set cmd "export SEQ_EXP_HOME=$suitePath;$dateExec -f '%Y%M%D%H%Min%S'"
   set dateStamp ""
   if [ catch { set dateStamp [exec ksh -c $cmd] } message ] {
      Utils_raiseError [winfo toplevel $parent_w] "Datestamp" $message
   }
   return $dateStamp
}

# this function is called when the user sets a new datestamp in the
# "Exp Datestamp" field. 
# - It calls maestro tictac to set the exp datestamp
# - Resets flow node status
# - Reads the log file of the exp datestamp
# - redraw the flow
proc xflow_setDateStamp { parent_w } {
   global MONITOR_DATESTAMP
   set top [winfo toplevel $parent_w]
   set dateExec "[SharedData_getMiscData SEQ_BIN]/tictac"
   set suiteRecord [xflow_getActiveSuite]
   set suitePath [$suiteRecord cget -suite_path]
   set dateEntry [xflow_getWidgetName exp_date_entry]

   Utils_busyCursor $top

   catch {
      set dateStamp [$dateEntry get]
      set cmd "export SEQ_EXP_HOME=$suitePath;$dateExec -s $dateStamp"
      ::log::log debug "xflow_setDateStamp $cmd"
      if [ catch { exec ksh -c $cmd } message ] {
         Utils_raiseError $top "Datestamp" $message
      }
      set MONITOR_DATESTAMP $dateStamp
      $suiteRecord configure -read_offset 0
      ::FlowNodes::resetNodeStatus [$suiteRecord cget -root_node]

      set thisThreadId [thread::id]
      set callingThreadId [SharedData_getMiscData ${thisThreadId}_CALLING_THREAD_ID]
      xflow_displayFlow ${callingThreadId}

      #set isOverviewMode [SharedData_getMiscData OVERVIEW_MODE]
      #xflow_initStartupMode
      #if { ${isOverviewMode} == "true" } {
      #   set overviewThreadId [SharedData_getMiscData OVERVIEW_THREAD_ID]
      #   LogReader_readFile $suiteRecord ${overviewThreadId}
      #} else {
      #   LogReader_readFile $suiteRecord [thread::id]
      #}
      #xflow_stopStartupMode

      #xflow_selectSuiteCallback
   }

   Utils_normalCursor $top
}

# this function returns the resource information that needs to be displayed
# besides the node name. Based on the user preferences View->"Node Display"
proc xflow_getNodeDisplayPrefText { node } {
   set text ""
   set displayPref [xflow_getNodeDisplayPref]
   set attrName ${displayPref}
   set attrValue ""

   if { ${displayPref} == "machine_queue" } {
      set attrName "machine"
   }
   if { ${displayPref} != "normal" } {
      if { [string match "*task" [$node cget -flow.type]] } {
            set attrValue "[$node cget -${attrName}]"
            if { ${displayPref} == "machine_queue" } {
               set queue [$node cget -queue]
               if { ${queue} != "null" } {
                  set attrValue "${attrValue}:${queue}"
               }
            }
      } else {
         # for containers, only catchup, memory and machine are relevant
         #if { ${displayPref} == "catchup" || ${displayPref} == "machine_queue" || ${displayPref} == "memory" } {
         #   set attrValue "[$node cget -${attrName}]"
         #}
      }
   }

   if { ${attrValue} != "" } {
      set text "(${attrValue})"
   }

   return $text
}

# find a node in the flow and point to it
# the real_node might have an extension attached to
# it example: /a/b/c+12+1
# if multiple indexes are given... the last one can be either a npt or loop index
# the others can only be loop indexes
proc xflow_findNode { suite_record real_node } {
   ::log::log debug "xflow_findNode ${suite_record} ${real_node}"
   set nodeWithouExt [::FlowNodes::getNodeFromDisplayFormat ${real_node}]
   set extensionPart [::FlowNodes::getExtFromDisplayFormat ${real_node}]
   set flowNode [::SuiteNode::getFlowNodeMapping ${suite_record} ${nodeWithouExt}]

   # split the list using + as separator
   set extList [split ${extensionPart} +]
   set extLen [llength ${extList}]
   # start at 1 cause the first element of the extList is a dummy empty value
   set indexCount 1
   set loopList [${flowNode} cget -flow.loops]
   set refreshNode ""
   # loop throught the list of indexes
   while { ${indexCount} < ${extLen} } {
      set extValue +[lindex ${extList} ${indexCount}]
      if { [${flowNode} cget -flow.type] == "npass_task" } {
         ${flowNode} configure -current ${extValue}
         set refreshNode ${flowNode}
      } else {
         # must be a loop extension
         set loopNode [lindex ${loopList} [expr ${indexCount} - 1]]
         ${loopNode} configure -current ${extValue}
      }
      if { ${refreshNode} == "" } {
         set refreshNode ${loopNode}
      }
      incr indexCount
   }

   set collapsedParentNode [::FlowNodes::uncollapseBranch ${flowNode} [xflow_getMainFlowCanvas] ]
   if { ${refreshNode} != "" || ${collapsedParentNode} != "" } {
      xflow_drawflow [xflow_getMainFlowCanvas]
   }
   update idletasks
    ::DrawUtils::pointNode ${suite_record} ${flowNode}
}

# this function is the starting point to draw the experiment flow.
# It recursively draws the whole flow from a starting point, which is
# the root node
# parameters:
#   canvas: canvas where the flow will be drawn
#   node: the node that needs to be drawn
#   position: specifies the position of the node within its parent
#   first_node: set to true only for the experiment root node.
proc xflow_drawNode { canvas node position {first_node false} } {
   global REFRESH_MODE FLOW_SCALE
   ::log::log debug "xflow_drawNode drawing sub node:$node position:$position "
   if { [::FlowNodes::isParentCollapsed ${node} ${canvas}] } {
      ::log::log debug "xflow_drawNode parent is collapsed, not drawing node:$node"
      return;
   }

   set boxW [SharedData_getMiscData CANVAS_BOX_WIDTH]
   set boxH [SharedData_getMiscData CANVAS_BOX_HEIGHT]
   set pady [SharedData_getMiscData CANVAS_PAD_Y]
   set padTx [SharedData_getMiscData CANVAS_PAD_TXT_X]
   set padTy [SharedData_getMiscData CANVAS_PAD_TXT_Y]
   set shadowColor [SharedData_getColor SHADOW_COLOR]
   set deltaY [::DrawUtils::getLineDeltaSpace ${node}]
   set drawshadow on
   if { ${FLOW_SCALE} != "1" } {
      set drawshadow off
   }

   set suiteRecord [xflow_getActiveSuite]
   ::FlowNodes::initNode $node $canvas
   set parentNode [${node} cget -flow.parent]
   if { $parentNode == "" || ${first_node} == "true" } {
      set linex2 [SharedData_getMiscData CANVAS_X_START]
      set liney2 [expr [SharedData_getMiscData CANVAS_Y_START] + ${deltaY}]
      ::log::log debug "xflow_drawNode linex2:$linex2 liney2:$liney2"
   } else {
      ::FlowNodes::initNode ${parentNode} ${canvas}
      # use a dashline leading to modules, elsewhere use a solid line
      set lineColor [SharedData_getColor FLOW_SUBMIT_ARROW]
      switch [$node cget -flow.type] {
         "module" {
            set drawline "drawdashline"
          }
          default {
            set drawline "drawline"
          }
      }

      # get the coordinates of the submitter
      foreach { px1 py1 px2 py2 } [::FlowNodes::getDisplayCoords $parentNode $canvas] { break }

      # first draw left arrow, the shape depends on the position of the
      # subnode and previous nodes being drawn
      # if position is 0, means first node job so same level as parent node only x coords changes
      set lineTagName "flow_element ${node}.submit_tag"

      if { $position == 0 } {
         set linex1 $px2
         set liney1 [expr $py1 + ($py2 - $py1) / 2 + $deltaY]
         set liney2 $liney1
         # nodedeltax mainly for nptask, size of index widgets different than box
         set linex2 [expr $linex1 + $boxW/2/${FLOW_SCALE} + [::DrawUtils::getNodeDeltaX $parentNode $canvas]]
         ::DrawUtils::$drawline $canvas $linex1 $liney1 $linex2 $liney2 last $lineColor $drawshadow $shadowColor ${lineTagName}
      } else {
         # draw L-shape arrow
         # first draw vertical line
         if { $REFRESH_MODE == "true" } {
            # drawing at same position
            set nextY [::FlowNodes::getDisplayY $node $canvas]
         } else {
            set nextY [::SuiteNode::getDisplayNextY $suiteRecord $canvas]
         }
         ::FlowNodes::setDisplayY ${node} $canvas ${nextY}

         #set linex1 [expr $px2 + $boxW/4/3]
         set linex1 [expr $px2 + $boxW/2/${FLOW_SCALE}/3]
         set linex2 $linex1
         set liney1 [expr $py1 + ($py2 - $py1) / 2 ]
         set liney2 [expr $nextY + (( $boxH/4 + $pady)/${FLOW_SCALE}) + $deltaY]
         ::DrawUtils::$drawline $canvas $linex1 $liney1 $linex2 $liney2 none $lineColor $drawshadow $shadowColor ${lineTagName}
         # then draw hor line with arrow at end
         set linex2 [expr $px2 + $boxW/2/${FLOW_SCALE}]
         set liney1 $liney2
         ::DrawUtils::$drawline $canvas $linex1 $liney1 $linex2 $liney2 last $lineColor  $drawshadow $shadowColor ${lineTagName}
      }
   }
   set isCollapsed [::FlowNodes::isCollapsed $node $canvas]
   set children [$node cget -flow.children]
   set normalTxtFill [SharedData_getColor NORMAL_RUN_TEXT]
   set normalFill [::DrawUtils::getBgStatusColor init]
   set outline [SharedData_getColor NORMAL_RUN_OUTLINE]
   # now draw the node
   set tx1 [expr $linex2 + ${padTx}/${FLOW_SCALE}]
   set ty1 $liney2
   foreach { tx1 ty1 } [xflow_addSingleReservIndicator ${canvas} ${node} ${tx1} ${ty1}] {break}

   set text [$node cget -flow.name]
   set nodeExtension [::FlowNodes::getNodeExtension $node]
   set extDisplay [::FlowNodes::getExtDisplay $node $nodeExtension]
   if { $extDisplay != "" } {
      set text "${text}${extDisplay}"
   }
   if { !(($children == "none") ||  ($children == "")) && $isCollapsed == 1} {
      set text ${text}+
   }
   set dispPref [xflow_getNodeDisplayPrefText $node]
   if { $dispPref != "" } {
      set text "${text}\n${dispPref}"
   }
   set currentExtension [::FlowNodes::getNodeExtension $node]
   set status [FlowNodes::getMemberStatus $node $currentExtension ]

   #set helpText "node: [file tail ${node}${currentExtension}] \nstatus: ${status}"
   switch [$node cget -flow.type] {
      "family" {
         ::DrawUtils::drawBoxSansOutline $canvas $tx1 $ty1 $text $text $normalTxtFill $outline $normalFill $node $drawshadow $shadowColor
         ::FlowNodes::addToFamilyList $node
      }
      "module" {
	 ::DrawUtils::drawBoxSansOutline $canvas $tx1 $ty1 $text $text $normalTxtFill $outline $normalFill $node $drawshadow $shadowColor
      }
      "task" {
         ::DrawUtils::drawBox $canvas $tx1 $ty1 $text $text $normalTxtFill $outline $normalFill $node $drawshadow $shadowColor
      }

      "npass_task" {
         ::DrawUtils::drawBox $canvas $tx1 $ty1 $text $text $normalTxtFill $outline $normalFill $node $drawshadow $shadowColor
         set indexListW [::DrawUtils::getIndexWidgetName ${node} ${canvas}]
         # bind ${indexListW} <<ComboboxSelected>> [list xflow_indexedNodeSelectionCallback ${node} ${canvas} %W]
         ${indexListW} configure -modifycmd [list xflow_indexedNodeSelectionCallback ${node} ${canvas} ${indexListW}]
      }
      "loop" {
         set text "${text}\n[::FlowNodes::getLoopInfo $node]"
         ::DrawUtils::drawOval $canvas $tx1 $ty1 $text $text $normalTxtFill $outline $normalFill $node $drawshadow $shadowColor
         set helpText "[::FlowNodes::getLoopTooltip ${node}]"
         set indexListW [::DrawUtils::getIndexWidgetName ${node} ${canvas}]
         ${indexListW} configure -modifycmd [list xflow_indexedNodeSelectionCallback ${node} ${canvas} ${indexListW}]
         ::tooltip::tooltip $canvas -item ${node} ${helpText}
         # reset the text to be used for generic tooltip on scaling mode
         set text "${helpText}"
      }
      "case" {
         ::DrawUtils::drawLosange $canvas $tx1 $ty1 $text $normalTxtFill $outline $normalFill $node $drawshadow $shadowColor
      }
      "outlet" {
         ::DrawUtils::drawOval $canvas $tx1 $ty1 $text $text $normalTxtFill $outline $normalFill $node $drawshadow $shadowColor
      }
      default {
         error "Invalid node type:[$node cget -flow.type] in proc xflow_drawNode()"
      }
   }
   if { ${FLOW_SCALE} != "1" } { ::tooltip::tooltip $canvas -item ${node} ${text} }

   ::DrawUtils::drawNodeStatus $node [xflow_getShawdowStatus]
   Utils_bindMouseWheel $canvas 20
   $canvas bind $node <Double-Button-1> [ list xflow_changeCollapsed $canvas $node %X %Y]
   $canvas bind $node <Button-2> [ list xflow_historyCallback $node $canvas "" 48] 
   $canvas bind $node <Button-3> [ list xflow_nodeMenu $canvas $node %X %Y]

   if { $isCollapsed == 0 } {
      # get the childs to display
      if { !(($children == "none") ||  ($children == ""))} {
         set nodePosition 0
         foreach child $children {
            #::log::log debug "xflow_drawNode drawing subjob:$subjob"
            set childNode $node/$child
            xflow_drawNode $canvas $childNode $nodePosition
            incr nodePosition
         }
      }
   }

   ::log::log debug "xflow_drawNode drawing sub node:$node done"
}

# add a striped circle before the node box to indicate the
# the start of a single reservation branch
# returns coords of modified x and y after image creation if exists
#                    modified x is start_x + width of created img
#                    y is startY
# else returns startX and startY
# 
proc xflow_addSingleReservIndicator { _canvas _node _startX _startY } {
   global SingleReservImg
   if { [${_node} cget -flow.work_unit] == 1 } {
      if { [info exists SingleReservImg] == 0 } {
         set SingleReservImg [image create photo -file [SharedData_getMiscData IMAGE_DIR]/round_stripe.png]
      }

      ${_canvas} create image ${_startX} ${_startY} -image ${SingleReservImg} -tags "flow_element ${_node} ${_node}.work_unit"
      return [list [expr ${_startX} + [image height $SingleReservImg] + 1] ${_startY}]
   }
   return [list ${_startX} ${_startY}]
}

# This function is called when user click on a box with button 3
# It will display a popup menu for the current node.
proc xflow_nodeMenu { canvas node x y } {
   global ignoreDep 
   ::log::log debug "xflow_nodeMenu() node:$node"
   set suiteRecord [xflow_getActiveSuite]

   # highlights the selected node
   ::DrawUtils::highLightNode ${suiteRecord} ${node} ${canvas}

   set popMenu .popupMenu
   set infoMenu ${popMenu}.info_menu
   set listingMenu ${popMenu}.listing_menu
   set submitMenu ${popMenu}.submit_menu
   set submitDependMenu ${popMenu}.submit_dep_menu
   set submitNoDependMenu ${popMenu}.submit_nodep_menu
   set miscMenu ${popMenu}.misc_menu
   if { [winfo exists ${popMenu}] } {
      destroy ${popMenu}
   }

   menu ${popMenu} -title [${node} cget -flow.name]

   # when the menu is destroyed, clears the highlighted node
   bind ${popMenu} <Unmap> {
      global NodeHighLightRestoreCmd
      eval $NodeHighLightRestoreCmd
   }

   set historyMenu ${popMenu}.history_menu
   set historyOptions [xflow_getNodeHistoryOptions]
      
   ${popMenu} add cascade -label "History" -underline 0 -menu [menu ${historyMenu}]
   foreach {itemName itemValue} ${historyOptions} {
      ${historyMenu} add command -label ${itemName} -command [list xflow_historyCallback $node $canvas $popMenu ${itemValue}]
   }

   ${popMenu} add cascade -label "Info" -underline 0 -menu [menu ${infoMenu}]
   ${popMenu} add cascade -label "Listing" -underline 0 -menu [menu ${listingMenu}]
   ${popMenu} add cascade -label "Submit" -underline 0 -menu [menu ${submitMenu}]
   ${popMenu} add cascade -label "Misc" -underline 0 -menu [menu ${miscMenu}]

   set children [$node cget -flow.children]
   set isCollapsed [::FlowNodes::isCollapsed $node $canvas]
   if { $children != "" && $isCollapsed } {
      ${popMenu} add command -label "Expand All" -command [list xflow_expandAllCallback $node $canvas $popMenu]
   }
   if { [$node cget -flow.type] == "loop" } {
      xflow_addLoopNodeMenu ${popMenu} ${canvas} ${node}
   } elseif { [$node cget -flow.type] == "npass_task" } {
      xflow_addNptNodeMenu ${popMenu} ${canvas} ${node}
   } else {

      #${infoMenu} add command -label "Node History" -command [list xflow_historyCallback $node $canvas $popMenu 0 ]
      ${infoMenu} add command -label "Node Info" -command [list xflow_nodeInfoCallback $node $canvas $popMenu]
      ${infoMenu} add command -label "Node Batch" -command [list xflow_batchCallback $node $canvas $popMenu ]

      set currentExtension [::FlowNodes::getNodeExtension $node]
      set status [::FlowNodes::getMemberStatus $node $currentExtension]
      if { ${status} == "begin" } {
	  ${listingMenu} add command -label "Monitor Listing" -command [list xflow_tailfCallback $node $canvas ]
      }
      ${listingMenu} add command -label "Node Listing" -command [list xflow_listingCallback $node $canvas $popMenu]
      ${listingMenu} add command -label "All Node Listing" -command [list xflow_allListingCallback $node $canvas $popMenu success]
      ${listingMenu} add command -label "Node Abort Listing" \
         -command [list xflow_abortListingCallback $node $canvas $popMenu] \
         -foreground [::DrawUtils::getBgStatusColor abort]

      ${listingMenu} add command -label "All Node Abort Listing" \
         -command [list xflow_allListingCallback $node $canvas $popMenu abort] \
         -foreground [::DrawUtils::getBgStatusColor abort]

      ${miscMenu} add command -label "New Window" -command [list xflow_newWindowCallback $node $canvas $popMenu]
      ${miscMenu} add command -label "View Workdir" -command [list xflow_launchWorkCallback $node $canvas ]
      if { [$node cget -flow.type] != "task" } {
         ${submitMenu} add command -label "Submit" -command [list xflow_submitCallback $node $canvas $popMenu continue ]
         ${submitMenu} add cascade -label "NO Dependency" -underline 4 -menu [menu ${submitNoDependMenu}]
         ${submitNoDependMenu} add command -label "Submit" \
            -command [list xflow_submitCallback $node $canvas $popMenu continue dep_off]
         ${infoMenu} add command -label "Node Config" -command [list xflow_configCallback $node $canvas $popMenu ]
         ${infoMenu} add command -label "Node Full Config" -command [list xflow_evalConfigCallback $node $canvas $popMenu ]
         ${miscMenu} add command -label "Initbranch" -command [list xflow_initbranchCallback $node $canvas $popMenu]
      } else {
         ${submitMenu} add command -label "Submit & Continue" -underline 9 -command [list xflow_submitCallback $node $canvas $popMenu continue ]
         ${submitMenu} add command -label "Submit & Stop" -underline 9 -command [list xflow_submitCallback $node $canvas $popMenu stop ]

         ${submitMenu} add cascade -label "NO Dependency" -underline 4 -menu [menu ${submitNoDependMenu}]
         ${submitNoDependMenu} add command -label "Submit & Continue" -underline 9 \
            -command [list xflow_submitCallback $node $canvas $popMenu continue dep_off ]
         ${submitNoDependMenu} add command -label "Submit & Stop" -underline 9 \
            -command [list xflow_submitCallback $node $canvas $popMenu stop dep_off ]

         ${infoMenu} add command -label "Node Source" -command [list xflow_sourceCallback $node $canvas $popMenu]
         ${infoMenu} add command -label "Node Config" -command [list xflow_configCallback $node $canvas $popMenu]
         ${infoMenu} add command -label "Node Full Config" -command [list xflow_evalConfigCallback $node $canvas $popMenu]
         ${miscMenu} add command -label "Initnode" -command [list xflow_initnodeCallback $node $canvas $popMenu]
      }
      ${miscMenu} add command -label "End" -command [list xflow_endCallback $node $canvas $popMenu]
      ${miscMenu} add command -label "Abort" -command [list xflow_abortCallback $node $canvas $popMenu]
      ${infoMenu} add command -label "Node Resource" -command [list xflow_resourceCallback $node $canvas $popMenu ]
   }

   ${miscMenu} add command -label "Kill Node" -command [list xflow_killNodeFromDropdown $node $canvas $popMenu]

   $popMenu add separator
   $popMenu add command -label "Close"
   
   tk_popup $popMenu $x $y
}

# creates the popup menu for a loop node
proc xflow_addLoopNodeMenu { popmenu_w canvas node } {
   ::log::log debug "xflow_addLoopNodeMenu() node:$node"

   set infoMenu ${popmenu_w}.info_menu
   set listingMenu ${popmenu_w}.listing_menu
   set submitMenu ${popmenu_w}.submit_menu
   set submitNoDependMenu ${popmenu_w}.submit_nodep_menu
   set miscMenu ${popmenu_w}.misc_menu

   ${infoMenu} add command -label "Node History" -command [list xflow_historyCallback $node $canvas ${popmenu_w}]
   ${infoMenu} add command -label "Node Info" -command [list xflow_nodeInfoCallback $node $canvas ${popmenu_w}]
   ${infoMenu} add command -label "Node Config" -command [list xflow_configCallback $node $canvas ${popmenu_w}]
   ${infoMenu} add command -label "Node Full Config" -command [list xflow_evalConfigCallback $node $canvas ${popmenu_w}]
   ${infoMenu} add command -label "Loop Node Batch" -command [list xflow_batchCallback $node $canvas ${popmenu_w} 1]
   ${infoMenu} add command -label "Member Node Batch" -command [list xflow_batchCallback $node $canvas ${popmenu_w} 0]
   ${infoMenu} add command -label "Node Resource" -command [list xflow_resourceCallback $node $canvas ${popmenu_w} ]

   set currentExtension [::FlowNodes::getNodeExtension $node]
   set status [::FlowNodes::getMemberStatus $node $currentExtension]
   if { ${status} == "begin" } {
       ${listingMenu} add command -label "Monitor Listing" -command [list xflow_tailfCallback $node $canvas ]
   }
   ${listingMenu} add command -label "Loop Listing" -command [list xflow_listingCallback $node $canvas ${popmenu_w} 1]
   ${listingMenu} add command -label "Loop Abort Listing" \
      -command [list xflow_abortListingCallback $node $canvas ${popmenu_w} 1] \
      -foreground [::DrawUtils::getBgStatusColor abort]

   ${listingMenu} add command -label "Member Listing" -command [list xflow_listingCallback $node $canvas ${popmenu_w}]
   ${listingMenu} add command -label "Member Abort Listing" \
      -command [list xflow_abortListingCallback $node $canvas ${popmenu_w}] \
      -foreground [::DrawUtils::getBgStatusColor abort]


   ${submitMenu} add command -label "Loop Submit" -command [list xflow_submitLoopCallback $node $canvas ${popmenu_w} continue ]
   ${submitMenu} add command -label "Member Submit" -command [list xflow_submitCallback $node $canvas ${popmenu_w} continue ]
   ${submitMenu} add cascade -label "NO Dependency" -underline 4 -menu [menu ${submitNoDependMenu}]
   ${submitNoDependMenu} add command -label "Loop Submit" \
      -command [list xflow_submitLoopCallback $node $canvas ${popmenu_w} continue dep_off]
   ${submitNoDependMenu} add command -label "Member Submit" \
      -command [list xflow_submitCallback $node $canvas ${popmenu_w} continue dep_off]

   ${miscMenu} add command -label "New Window" -command [list xflow_newWindowCallback $node $canvas ${popmenu_w}]
   ${miscMenu} add command -label "View Workdir" -command [list xflow_launchWorkCallback $node $canvas ]
   ${miscMenu} add command -label "Loop End" -command [list xflow_endLoopCallback $node $canvas ${popmenu_w}]
   ${miscMenu} add command -label "Loop Initbranch" -command [list xflow_initbranchLoopCallback $node $canvas ${popmenu_w}]
   ${miscMenu} add command -label "Member End" -command [list xflow_endCallback $node $canvas ${popmenu_w}]
   ${miscMenu} add command -label "Member Initbranch" -command [list xflow_initbranchCallback $node $canvas ${popmenu_w}]
   ${miscMenu} add command -label "Abort" -command [list xflow_abortCallback $node $canvas ${popmenu_w}]
}

# creates the popup menu for a npt node
proc xflow_addNptNodeMenu { popmenu_w canvas node } {

   set infoMenu ${popmenu_w}.info_menu
   set listingMenu ${popmenu_w}.listing_menu
   set submitMenu ${popmenu_w}.submit_menu
   set submitNoDependMenu ${popmenu_w}.submit_nodep_menu
   set miscMenu ${popmenu_w}.misc_menu

   ${infoMenu} add command -label "Node History" -command [list xflow_historyCallback $node $canvas ${popmenu_w}]
   ${infoMenu} add command -label "Node Info" -command [list xflow_nodeInfoCallback $node $canvas ${popmenu_w}]
   ${infoMenu} add command -label "Node Batch" -command [list xflow_batchCallback $node $canvas ${popmenu_w} ]
   ${infoMenu} add command -label "Node Source" -command [list xflow_sourceCallback $node $canvas ${popmenu_w} ]
   ${infoMenu} add command -label "Node Config" -command [list xflow_configCallback $node $canvas ${popmenu_w} ]
   ${infoMenu} add command -label "Node Full Config" -command [list xflow_evalConfigCallback $node $canvas ${popmenu_w}]
   ${infoMenu} add command -label "Node Resource" -command [list xflow_resourceCallback $node $canvas ${popmenu_w} ]

   set currentExtension [::FlowNodes::getNodeExtension $node]
   set status [::FlowNodes::getMemberStatus $node $currentExtension]
   if { ${status} == "begin" } {
       ${listingMenu} add command -label "Monitor Listing" -command [list xflow_tailfCallback $node $canvas ]
   }
   ${listingMenu} add command -label "Node Listing" -command [list xflow_listingCallback $node $canvas ${popmenu_w}]
   ${listingMenu} add command -label "All Node Listing" -command [list xflow_allListingCallback $node $canvas ${popmenu_w} success]
   ${listingMenu} add command -label "Node Abort Listing" \
      -command [list xflow_abortListingCallback $node $canvas ${popmenu_w}] \
      -foreground [::DrawUtils::getBgStatusColor abort]

   ${listingMenu} add command -label "All Node Abort Listing" \
      -command [list xflow_allListingCallback $node $canvas ${popmenu_w} abort] \
      -foreground [::DrawUtils::getBgStatusColor abort]


   ${submitMenu} add command -label "Submit & Continue" -command [list xflow_submitNpassTaskCallback $node $canvas ${popmenu_w} continue ]
   ${submitMenu} add command -label "Submit & Stop" -command [list xflow_submitNpassTaskCallback $node $canvas ${popmenu_w} stop ]
   ${submitMenu} add cascade -label "NO Dependency" -underline 4 -menu [menu ${submitNoDependMenu}]
   ${submitNoDependMenu} add command -label "Submit & Continue" -underline 9 \
      -command [list xflow_submitNpassTaskCallback $node $canvas ${popmenu_w} continue dep_off ]
   ${submitNoDependMenu} add command -label "Submit & Stop" -underline 9 \
      -command [list xflow_submitNpassTaskCallback $node $canvas ${popmenu_w} stop dep_off ]

   ${miscMenu} add command -label "New Window" -command [list xflow_newWindowCallback $node $canvas ${popmenu_w}]
   ${miscMenu} add command -label "View Workdir" -command [list xflow_launchWorkCallback $node $canvas ]
   ${miscMenu} add command -label "Initnode" -command [list xflow_initnodeCallback $node $canvas ${popmenu_w}]
   ${miscMenu} add command -label "End" -command [list xflow_endNpasssTaskCallback $node $canvas ${popmenu_w}]
   ${miscMenu} add command -label "Abort" -command [list xflow_abortNpasssTaskCallback $node $canvas ${popmenu_w}]
   
}

# returns a list of menu items to be shown in the node history menu
# the items is taken from maestrorc if defined else defaults
# return value is list of items-hourvalue
# {"48 Hours" "48" "7 Days" "168"}
proc xflow_getNodeHistoryOptions {} {
   global NODE_HIST_OPTIONS
   if { [info exists NODE_HIST_OPTIONS] } {
      return ${NODE_HIST_OPTIONS}
   } else {
      # format is ValueUnit ie 48H 7D
      set historyOptions [SharedData_getMiscData NODE_HISTORY_OPTIONS]
      if { ${historyOptions} == "" } {
         set historyOptions {24H 48H 3D 4D 5D 6D 7D 14D 30D}
      }
      set histFormat "%d%s"
      set NODE_HIST_OPTIONS {}
      foreach histOption ${historyOptions} {
         if { [scan ${histOption} ${histFormat} decValue unitValue] == 2 } {
            switch ${unitValue} {
               "h" -
               "H" {
                  lappend NODE_HIST_OPTIONS "${decValue} Hours"
                  lappend NODE_HIST_OPTIONS ${decValue}
               }
               d -
               D {
                  lappend NODE_HIST_OPTIONS "${decValue} Days"
                  lappend NODE_HIST_OPTIONS [expr ${decValue} * 24]
               }
               default {
                  puts "Invalid value in .maestrorc node_history_options: ${histOption}"
               }
            }
         }
      }
   }
   return ${NODE_HIST_OPTIONS}
}

# this menu is called when the user request a new partial flow window to be launched
# starting from a selected node
proc xflow_newWindowCallback { node canvas caller_menu } {
   ::log::log debug "xflow_newWindowCallback node:$node canvas:$canvas"
   set suiteRecord [xflow_getActiveSuite]
   if { [::FlowNodes::isNodeFromOverview $node] } {
      set displayNode [::FlowNodes::getNodeFromOverview $node]
   } else {
      set displayNode $node
   }

   # replaces / with _
   set topWidget .toplevel_[regsub -all "/" $displayNode _]

   if { [winfo exist $topWidget] } {
      destroy $topWidget
   }
   toplevel $topWidget

   Utils_positionWindow $topWidget $canvas
   wm title $topWidget "Root=$displayNode"

   set formattedName [::SuiteNode::formatName [$suiteRecord cget -suite_path]]
   set drawFrame ${topWidget}.${formattedName}

   frame $drawFrame
   set newCanvas [xflow_createFlowCanvas $drawFrame]
   grid $drawFrame -sticky nsew

   set sizeGripWidget [ttk::sizegrip $topWidget.sizeGrip]
   grid ${sizeGripWidget} -sticky se

   # make the drawing expand x y directions
   grid rowconfigure $topWidget 0 -weight 1
   grid columnconfigure $topWidget 0 -weight 1

   set suiteRecord [xflow_getActiveSuite]

   ::SuiteNode::setDisplayRoot $suiteRecord $newCanvas $displayNode

   # post process when window closes
   wm protocol $topWidget WM_DELETE_WINDOW [list xflow_closeSpawnedWindow $suiteRecord $newCanvas $topWidget ]
   xflow_drawflow $newCanvas

   # expand the view by default
   xflow_expandAllCallback $displayNode $newCanvas ""
}

proc xflow_getFlowFrame {} {
   return
}

# this function is called to show the history of a node
# By default, the middle mouse on a node shows the history for the last 48 hours.
# The "Node History" from the Info menu on the node shows only the current datestamp
proc xflow_historyCallback { node canvas caller_menu {history 48} {full_loop 0} } {
   ::log::log debug "xflow_historyCallback node:$node canvas:$canvas $full_loop"

   set seqExec [SharedData_getMiscData SEQ_UTILS_BIN]/nodehistory
   set suiteRecord [xflow_getActiveSuite]

   set seqNode [::FlowNodes::getSequencerNode $node]
   set nodeExt [::FlowNodes::getListingNodeExtension $node $full_loop]
   ::log::log debug "xflow_historyCallback nodeExt:$nodeExt"
   if { $nodeExt == "-1" } {
      Utils_raiseError $canvas "node listing" [getErrorMsg NO_LOOP_SELECT]
   } else {
      if { $nodeExt != "" } {
         set nodeExt ".${nodeExt}"
      }

      # set datestamp for history to monitoring date if different from latest, else take datestamp from experiment.
      set dateStamp [xflow_getMonitoringDatestamp]
      if { $dateStamp == "" } {
          set dateStamp [xflow_retrieveDateStamp $canvas $suiteRecord]
      }

      Sequencer_runCommandWithWindow [$suiteRecord cget -suite_path] $seqExec \
         "Node History [file tail $node]$nodeExt -history $history" bottom \
         -n $seqNode$nodeExt -history $history -edate $dateStamp 
   }
}

# shows the node information and is invoked from the "Node Info" menu item.
proc xflow_nodeInfoCallback { node canvas caller_menu } {
   global env
   set seqExec "[SharedData_getMiscData SEQ_BIN]/nodeinfo"
   set suiteRecord [xflow_getActiveSuite]

   set suiteName [$suiteRecord cget -suite_name]
   set nodeTail [file tail $node]
   set infoWidget [string tolower .${suiteName}_${nodeTail}_nodeInfo]

   if { [winfo exists $infoWidget] } {
      destroy $infoWidget
   }
   set seqExpHome [$suiteRecord cget -suite_path]
   set nodeInfoExec "[SharedData_getMiscData SEQ_BIN]/nodeinfo"
   set seqNode [::FlowNodes::getSequencerNode $node]
   if { [$node cget -flow.type] == "npass_task" } {
      set seqLoopArgs [::FlowNodes::getNptArgs ${node} ]
      if { ${seqLoopArgs} == "-1" } {
         set seqLoopArgs ""
      }
   } else {
      set seqLoopArgs [::FlowNodes::getLoopArgs $node]
   }

   Sequencer_runCommandWithWindow [$suiteRecord cget -suite_path] ${nodeInfoExec} "Node Info ${nodeTail}" top -n $seqNode  ${seqLoopArgs}
}

# this command is invoked from the Misc->initbranch menu item
# It sends an initbranch signal to the maestro sequencer for the
# current container node. It deletes all sequencer related node status files for
# the current node and all its child nodes.
proc xflow_initbranchCallback { node canvas caller_menu } {
   set seqExec "[SharedData_getMiscData SEQ_BIN]/maestro"
   set suiteRecord [xflow_getActiveSuite]

   set seqNode [::FlowNodes::getSequencerNode $node]
   set seqLoopArgs [::FlowNodes::getLoopArgs $node]
   if { $seqLoopArgs == "" && [::FlowNodes::hasLoops $node] } {
      Utils_raiseError $canvas "initbranch" [getErrorMsg NO_LOOP_SELECT]
   } else {
      Sequencer_runCommandWithWindow [$suiteRecord cget -suite_path] $seqExec "initbranch [file tail $node] $seqLoopArgs" top \
         -n $seqNode -s initbranch -f continue $seqLoopArgs      
   }
   #$node configure -flow.status initialize
   #::DrawUtils::drawNodeStatus $node
}

# this command is invoked from the Misc->initnode menu item
# It sends an initnode signal to the maestro sequencer for the
# current task node. It deletes all sequencer related node status files for
# the current node.
proc xflow_initnodeCallback { node canvas caller_menu } {
   set seqExec "[SharedData_getMiscData SEQ_BIN]/maestro"
   set suiteRecord [xflow_getActiveSuite]
   set seqNode [::FlowNodes::getSequencerNode $node]
   set seqLoopArgs [::FlowNodes::getLoopArgs $node]
   if { $seqLoopArgs == "" && [::FlowNodes::hasLoops $node] } {
      Utils_raiseError $canvas "initnode" [getErrorMsg NO_LOOP_SELECT]
   } else {
      ::log::log notice "${seqExec} -n $seqNode -s initnode -f continue $seqLoopArgs"
      Sequencer_runCommandWithWindow [$suiteRecord cget -suite_path] $seqExec "initnode [file tail $node] $seqLoopArgs" top \
        -n $seqNode -s initnode -f continue $seqLoopArgs
      
   }
}

# this command is invoked from the Misc->initbranch menu item
# It sends an initbranch signal to the maestro sequencer for the
# current loop node. It deletes all sequencer related node status files for
# the current loop node and all its child iteration nodes.
proc xflow_initbranchLoopCallback { node canvas caller_menu } {
   set seqExec "[SharedData_getMiscData SEQ_BIN]/maestro"
   set suiteRecord [xflow_getActiveSuite]
   set seqNode [::FlowNodes::getSequencerNode $node]
   set seqLoopArgs [::FlowNodes::getParentLoopArgs $node]
   if { $seqLoopArgs == "-1" && [::FlowNodes::hasLoops $node] } {
      Utils_raiseError $canvas "initbranch" [getErrorMsg NO_LOOP_SELECT]
   } else {
      ::log::log notice "${seqExec} -n $seqNode -s initbranch -f continue $seqLoopArgs"
      Sequencer_runCommandWithWindow [$suiteRecord cget -suite_path] $seqExec "initbranch [file tail $node] $seqLoopArgs" top \
        -n $seqNode -s initbranch -f continue $seqLoopArgs
      
   }
}

# forces an abort to be sent to maestro sequencer
proc xflow_abortCallback { node canvas caller_menu } {
   set seqExec "[SharedData_getMiscData SEQ_BIN]/maestro"
   set suiteRecord [xflow_getActiveSuite]
   set seqNode [::FlowNodes::getSequencerNode $node]
   set seqLoopArgs [::FlowNodes::getLoopArgs $node]
   if { $seqLoopArgs == "" && [::FlowNodes::hasLoops $node] } {
      Utils_raiseError $canvas "node abort" [getErrorMsg NO_LOOP_SELECT]
   } else {
      ::log::log notice "${seqExec} -n $seqNode -s abort -f continue $seqLoopArgs"
      Sequencer_runCommandWithWindow [$suiteRecord cget -suite_path] $seqExec "abort [file tail $node] $seqLoopArgs" top \
         -n $seqNode -s abort -f continue $seqLoopArgs
   }
}

proc xflow_endNpasssTaskCallback { node canvas caller_menu } {
   set seqExec "[SharedData_getMiscData SEQ_BIN]/maestro"
   set suiteRecord [xflow_getActiveSuite]
   set seqNode [::FlowNodes::getSequencerNode $node]
   set indexListW [::DrawUtils::getIndexWidgetName $node $canvas]
   set indexListValue ""
   if { [winfo exists ${indexListW}] } {
      set indexListValue [${indexListW} get]
      ::log::log debug "xflow_abortNpasssTaskCallback indexListValue:$indexListValue"
   }
   if { ${indexListValue} == "latest" } {
      Utils_raiseError $canvas "Npass_Task submit" [getErrorMsg NO_INDEX_SELECT]
   } else {
      set seqNpassTaskArgs [::FlowNodes::getNptArgs ${node} ${indexListValue}]
   
      if { $seqNpassTaskArgs == "-1" } {
         Utils_raiseError $canvas "Npass_Task submit" [getErrorMsg NO_INDEX_SELECT]
      } else {
         ::log::log debug "xflow_abortNpasssTaskCallback $seqNpassTaskArgs"
         ::log::log notice "${seqExec} -n $seqNode -s end $seqNpassTaskArgs"
         Sequencer_runCommandWithWindow [$suiteRecord cget -suite_path] $seqExec "end [file tail $node] $seqNpassTaskArgs" top \
           -n $seqNode -s end $seqNpassTaskArgs
      }
   }
}

proc xflow_abortNpasssTaskCallback { node canvas caller_menu } {
   set seqExec "[SharedData_getMiscData SEQ_BIN]/maestro"
   set suiteRecord [xflow_getActiveSuite]
   set seqNode [::FlowNodes::getSequencerNode $node]
   set indexListW [::DrawUtils::getIndexWidgetName $node $canvas]
   set indexListValue ""
   if { [winfo exists ${indexListW}] } {
      set indexListValue [${indexListW} get]
      ::log::log debug "xflow_abortNpasssTaskCallback indexListValue:$indexListValue"
   }
   if { ${indexListValue} == "latest" } {
      Utils_raiseError $canvas "Npass_Task submit" [getErrorMsg NO_INDEX_SELECT]
   } else {
      set seqNpassTaskArgs [::FlowNodes::getNptArgs ${node} ${indexListValue}]
   
      if { $seqNpassTaskArgs == "-1" } {
         Utils_raiseError $canvas "Npass_Task submit" [getErrorMsg NO_INDEX_SELECT]
      } else {
         ::log::log debug "xflow_abortNpasssTaskCallback $seqNpassTaskArgs"
         ::log::log notice "${seqExec} -n $seqNode -s abort $seqNpassTaskArgs"
         Sequencer_runCommandWithWindow [$suiteRecord cget -suite_path] $seqExec "submit [file tail $node] $seqNpassTaskArgs" top \
           -n $seqNode -s abort $seqNpassTaskArgs
      }
   }
}

# launch an xterm at $SEQ_EXP_HOME
proc xflow_launchShellCallback {} {
    global env
    set suiteRecord [xflow_getActiveSuite]
    set expPath [${suiteRecord} cget -suite_path]
     Utils_launchShell $env(TRUE_HOST) ${expPath} ${expPath} "SEQ_EXP_HOME=${expPath}"
}

# launch an xterm in ${TASK_BASEDIR} on the execution host
proc xflow_launchWorkCallback { node canvas {full_loop 0} } {
    ::log::log debug "xflow_launchWorkCallback node$node canvas$canvas"
    set seqExecWork "[SharedData_getMiscData SEQ_UTILS_BIN]/nodework"
    set seqNode [::FlowNodes::getSequencerNode $node]
    set nodeExt [::FlowNodes::getListingNodeExtension $node $full_loop]
    set suiteRecord [xflow_getActiveSuite]
    set expPath [${suiteRecord} cget -suite_path]

    # set datestamp for history to monitoring date if different from latest, else take datestamp from experiment.
    set dateStamp [xflow_getMonitoringDatestamp]
    if { $dateStamp == "" } {
	set dateStamp [xflow_retrieveDateStamp $canvas $suiteRecord]
    }

    if { $nodeExt == "-1" } {
	Utils_raiseError $canvas "node listing" [getErrorMsg NO_LOOP_SELECT]
    } else {
	::log::log debug "$seqExecWork -n ${seqNode} -ext ${nodeExt}"
	if [ catch { set workpath [split [exec ksh -c "export SEQ_EXP_HOME=${expPath};export SEQ_DATE=${dateStamp}; $seqExecWork -n ${seqNode} -ext ${nodeExt}"] ':'] } message ] {
	    Utils_raiseError . "Retrieve node output" $message
	    return 0
	}
	set taskBasedir "[lindex $workpath 1]${seqNode}${nodeExt}"
    Utils_launchShell [lindex $workpath 0] ${expPath} [lindex $workpath 1] "TASK_BASEDIR=[lindex $workpath 1]"
    }	
}

# this function is invoked from the "Kill Node" menu item.
# It displays the available jobids of currently running tasks
# for the user to kill.
proc xflow_killNodeFromDropdown { node canvas caller_menu } {

   global env
   set shadowColor [SharedData_getColor SHADOW_COLOR]
   set bgColor [SharedData_getColor CANVAS_COLOR]
   set id [clock seconds]
   set tmpdir $env(TMPDIR)
   set tmpfile "${tmpdir}/test$id"
   set suiteRecord [xflow_getActiveSuite]
   set suitePath [$suiteRecord cget -suite_path]
   set seqNode [::FlowNodes::getSequencerNode $node]
   set killPath [SharedData_getMiscData SEQ_UTILS_BIN]/nodekill 
   set cmd "export SEQ_EXP_HOME=$suitePath; $killPath -n $seqNode -list > $tmpfile 2>&1"
   ::log::log debug "xflow_killNodeFromDropdown ksh -c $cmd"
   catch { eval [exec ksh -c $cmd ] }


   set soloWindow $canvas.nodekill 

   if { [winfo exists $soloWindow] } {
        destroy $soloWindow
    }

   toplevel $soloWindow

   frame $soloWindow.frame -relief raised -bd 2 -bg $bgColor
   pack $soloWindow.frame -fill both -expand 1 
   listbox $soloWindow.list -yscrollcommand "$soloWindow.yscroll set" \
	  -xscrollcommand "$soloWindow.xscroll set"  \
	  -height 10 -width 70 -selectmode extended -bg $bgColor -fg $shadowColor
   scrollbar $soloWindow.yscroll -command "$soloWindow.list yview"  -bg $bgColor
   scrollbar $soloWindow.xscroll -command "$soloWindow.list xview" -orient horizontal -bg $bgColor

   set cancelButton [button $soloWindow.cancel_button -text "Cancel" \
      -command [list destroy $soloWindow ]]
   tooltip::tooltip $cancelButton "Close this window"
   pack $cancelButton -side right

   set killButton [button $soloWindow.kill_button -text "Kill Selected Jobs" \
      -command [list xflow_killNode $soloWindow.list ]]
   tooltip::tooltip $killButton "Send kill signals to selected job_ID"
   pack $killButton -side right

   pack $soloWindow.xscroll -fill x -side bottom -in $soloWindow.frame
   pack $soloWindow.yscroll -side right -fill y -in $soloWindow.frame
   pack $soloWindow.list -expand 1 -fill both -padx 1m -side left -in $soloWindow.frame

   set resultingFile [open $tmpfile] 

   while { [gets $resultingFile line ] >= 0 } {
         $soloWindow.list insert end $line 
   }

   catch {[exec rm -f $tmpfile]}
}

# forces and end signal to be sent to the maestro sequencer for the current node.
proc xflow_endCallback { node canvas caller_menu } {
   set seqExec "[SharedData_getMiscData SEQ_BIN]/maestro"

   set suiteRecord [xflow_getActiveSuite]

   set seqNode [::FlowNodes::getSequencerNode $node]
   set seqLoopArgs [::FlowNodes::getLoopArgs $node]
   if { $seqLoopArgs == "" && [::FlowNodes::hasLoops $node] } {
      Utils_raiseError $canvas "node end" [getErrorMsg NO_LOOP_SELECT]
   } else {
      ::log::log notice "$seqExec -n $seqNode -s end -f continue $seqLoopArgs"
      Sequencer_runCommandWithWindow [$suiteRecord cget -suite_path] $seqExec "end [file tail $node] $seqLoopArgs" top \
         -n $seqNode -s end -f continue $seqLoopArgs
   }

}

# forces and end signal to be sent to the maestro sequencer for the current loop node.
proc xflow_endLoopCallback { node canvas caller_menu } {
   set seqExec "[SharedData_getMiscData SEQ_BIN]/maestro"

   set suiteRecord [xflow_getActiveSuite]

   set seqNode [::FlowNodes::getSequencerNode $node]
   set seqLoopArgs [::FlowNodes::getParentLoopArgs $node]
   if { $seqLoopArgs == "-1" && [::FlowNodes::hasLoops $node] } {
      Utils_raiseError $canvas "loop end" [getErrorMsg NO_LOOP_SELECT]
   } else {
      ::log::log notice "$seqExec -n $seqNode -s end -f continue $seqLoopArgs"
      Sequencer_runCommandWithWindow [$suiteRecord cget -suite_path] $seqExec "end [file tail $node] $seqLoopArgs" top \
         -n $seqNode -s end -f continue $seqLoopArgs
      
   }
}

# displays the content of a task node (.tsk)
proc xflow_sourceCallback { node canvas caller_menu} {
   global SESSION_TMPDIR
   set seqExec "[SharedData_getMiscData SEQ_UTILS_BIN]/nodesource"
   set suiteRecord [xflow_getActiveSuite]
   set seqNode [::FlowNodes::getSequencerNode $node]
   set textViewer [SharedData_getMiscData TEXT_VIEWER]
   set defaultConsole [SharedData_getMiscData DEFAULT_CONSOLE]

   set winTitle "Node Source [file tail $node]"
   regsub -all " " ${winTitle} _ tempfile
   set outputfile "${SESSION_TMPDIR}/${tempfile}_[clock seconds]"

   set seqCmd "${seqExec} -n ${seqNode}"
   Sequencer_runCommand [$suiteRecord cget -suite_path] ${outputfile} ${seqCmd}

   if { ${textViewer} == "default" } {
      create_text_window ${winTitle} ${outputfile} top .
   } else {
      set editorCmd "${textViewer} ${outputfile}"
      ::log::log debug "xflow_sourceCallback running ${defaultConsole} ${editorCmd}"
      TextEditor_goKonsole ${defaultConsole} ${winTitle} ${editorCmd}
   }
}

# displays the content of a config file (.cfg) if it is available.
proc xflow_configCallback { node canvas caller_menu} {
   global SESSION_TMPDIR
   set seqExec "[SharedData_getMiscData SEQ_UTILS_BIN]/nodeconfig"
   set suiteRecord [xflow_getActiveSuite]
   set seqNode [::FlowNodes::getSequencerNode $node]

   set textViewer [SharedData_getMiscData TEXT_VIEWER]
   set defaultConsole [SharedData_getMiscData DEFAULT_CONSOLE]

   set winTitle "Node Config [file tail $node]"
   regsub -all " " ${winTitle} _ tempfile
   set outputfile "${SESSION_TMPDIR}/${tempfile}_[clock seconds]"

   set seqCmd "${seqExec} -n ${seqNode}"
   Sequencer_runCommand [$suiteRecord cget -suite_path] ${outputfile} ${seqCmd}

   if { ${textViewer} == "default" } {
      create_text_window ${winTitle} ${outputfile} top .
   } else {
      set editorCmd "${textViewer} ${outputfile}"
      ::log::log debug "xflow_sourceCallback running ${defaultConsole} ${editorCmd}"
      TextEditor_goKonsole ${defaultConsole} ${winTitle} ${editorCmd}
   }
}

proc xflow_evalConfigCallback { node canvas caller_menu } {
   global SESSION_TMPDIR
   set seqExec "[SharedData_getMiscData SEQ_UTILS_BIN]/chaindot.py"
   set suiteRecord [xflow_getActiveSuite]
   set seqNode [::FlowNodes::getSequencerNode $node]

   set textViewer [SharedData_getMiscData TEXT_VIEWER]
   set defaultConsole [SharedData_getMiscData DEFAULT_CONSOLE]

   set winTitle "Node Full Config [file tail $node]"
   regsub -all " " ${winTitle} _ tempfile
   set outputfile "${SESSION_TMPDIR}/${tempfile}_[clock seconds]"

   set seqCmd "${seqExec} -n ${seqNode} -e [$suiteRecord cget -suite_path] -o ${outputfile}"
   Sequencer_runCommand [$suiteRecord cget -suite_path] /dev/null ${seqCmd}

   if { ${textViewer} == "default" } {
      create_text_window ${winTitle} ${outputfile} top .
   } else {
      set editorCmd "${textViewer} ${outputfile}"
      ::log::log debug "xflow_sourceCallback running ${defaultConsole} ${editorCmd}"
      TextEditor_goKonsole ${defaultConsole} ${winTitle} ${editorCmd}
   }
}

# displays the resource file (.def) if it is available
proc xflow_resourceCallback { node canvas caller_menu } {
   global SESSION_TMPDIR
   set seqExec "[SharedData_getMiscData SEQ_UTILS_BIN]/noderesource"
   set suiteRecord [xflow_getActiveSuite]
   set seqNode [::FlowNodes::getSequencerNode $node]
   set textViewer [SharedData_getMiscData TEXT_VIEWER]
   set defaultConsole [SharedData_getMiscData DEFAULT_CONSOLE]

   set winTitle "Node Resource [file tail $node]"
   regsub -all " " ${winTitle} _ tempfile
   set outputfile "${SESSION_TMPDIR}/${tempfile}_[clock seconds]"

   set seqCmd "${seqExec} -n ${seqNode}"
   Sequencer_runCommand [$suiteRecord cget -suite_path] ${outputfile} ${seqCmd}

   if { ${textViewer} == "default" } {
      create_text_window ${winTitle} ${outputfile} top .
   } else {
      set editorCmd "${textViewer} ${outputfile}"
      ::log::log debug "xflow_resourceCallback running ${defaultConsole} ${editorCmd}"
      TextEditor_goKonsole ${defaultConsole} ${winTitle} ${editorCmd}
   }
}

# displays the latest batch command file generated by maestro
proc xflow_batchCallback { node canvas caller_menu {full_loop 0} } {
   global SESSION_TMPDIR
   set seqExec "[SharedData_getMiscData SEQ_UTILS_BIN]/nodebatch"
   set suiteRecord [xflow_getActiveSuite]
   set seqNode [::FlowNodes::getSequencerNode $node]
   set nodeExt [::FlowNodes::getListingNodeExtension $node $full_loop]
   set textViewer [SharedData_getMiscData TEXT_VIEWER]
   set defaultConsole [SharedData_getMiscData DEFAULT_CONSOLE]

   if { $nodeExt == "-1" } {
      Utils_raiseError $canvas "node listing" [getErrorMsg NO_LOOP_SELECT]
   } else {

      if { $nodeExt != "" } {
         set nodeExt ".${nodeExt}"
      }

      set winTitle "Node Batch [file tail ${node}]${nodeExt}"
      regsub -all " " ${winTitle} _ tempfile
      set outputfile "${SESSION_TMPDIR}/${tempfile}_[clock seconds]"
   
      set seqCmd "${seqExec} -n ${seqNode}${nodeExt}"
      Sequencer_runCommand [$suiteRecord cget -suite_path] ${outputfile} ${seqCmd}
   
      if { ${textViewer} == "default" } {
         create_text_window ${winTitle} ${outputfile} top .
      } else {
         set editorCmd "${textViewer} ${outputfile}"
         ::log::log debug "xflow_sourceCallback running ${defaultConsole} ${editorCmd}"
         TextEditor_goKonsole ${defaultConsole} ${winTitle} ${editorCmd}
      }
   }
}

# this function submits a node for execution to the maestro sequencer.
# 
# - the flow parameter is either "stop" or "continue" and specifies whether the flow should
# continue or stop executing upon completion of the current node
# - local_ignore should be set to "dep_off" for local dependencies to be ignored.
proc xflow_submitCallback { node canvas caller_menu flow {local_ignore_dep dep_on} } {
   global env
   set ignoreDepFlag ""
   if { ${local_ignore_dep} == "dep_off" } {
      set ignoreDepFlag " -i"
   }

   set seqExec "[SharedData_getMiscData SEQ_BIN]/maestro"

   set suiteRecord [xflow_getActiveSuite]
   set seqNode [::FlowNodes::getSequencerNode $node]
   set seqLoopArgs [::FlowNodes::getLoopArgs $node]
   if { $seqLoopArgs == "" && [::FlowNodes::hasLoops $node] } {
      Utils_raiseError $canvas "node submit" [getErrorMsg NO_LOOP_SELECT]
   } else {
      # Sequencer_runCommandWithWindow [$suiteRecord cget -suite_path] $seqExec "submit [file tail $node] $seqLoopArgs" top \
      #   -n $seqNode -s submit -f $flow $ignoreDepFlag $seqLoopArgs
      Sequencer_runCommandLogAndWindow [$suiteRecord cget -suite_path] $seqExec "submit [file tail $node] $seqLoopArgs" top \
         -n $seqNode -s submit -f $flow $ignoreDepFlag $seqLoopArgs
   }
}

# same as previous but for loop node
proc xflow_submitLoopCallback { node canvas caller_menu flow {local_ignore_dep dep_on}} {
   set ignoreDepFlag ""
   if { ${local_ignore_dep} == "dep_off" } {
      set ignoreDepFlag " -i"
   }
   set seqExec "[SharedData_getMiscData SEQ_BIN]/maestro"

   set suiteRecord [xflow_getActiveSuite]

   set seqNode [::FlowNodes::getSequencerNode $node]
   set seqLoopArgs [::FlowNodes::getParentLoopArgs $node]
   if { $seqLoopArgs == "-1" && [::FlowNodes::hasLoops $node] } {
      Utils_raiseError $canvas "loop submit" [getErrorMsg NO_LOOP_SELECT]
   } else {
      # Sequencer_runCommandWithWindow [$suiteRecord cget -suite_path] $seqExec "submit [file tail $node] $seqLoopArgs" top \
      #   -n $seqNode -s submit -f $flow ${ignoreDepFlag} $seqLoopArgs 
      Sequencer_runCommandLogAndWindow [$suiteRecord cget -suite_path] $seqExec "submit [file tail $node] $seqLoopArgs" top \
         -n $seqNode -s submit -f $flow ${ignoreDepFlag} $seqLoopArgs 

   }
}

# same as previous but for npt node
proc xflow_submitNpassTaskCallback { node canvas caller_menu flow {local_ignore_dep dep_on} } {

   ::log::log debug "xflow_submitNpassTaskCallback node:$node canvas:$canvas"
   set ignoreDepFlag ""
   if { ${local_ignore_dep} == "dep_off" } {
      set ignoreDepFlag " -i"
   }

   set seqExec "[SharedData_getMiscData SEQ_BIN]/maestro"

   set suiteRecord [xflow_getActiveSuite]

   set seqNode [::FlowNodes::getSequencerNode $node]
   # retrieve index value from widget
   set indexListW [::DrawUtils::getIndexWidgetName $node $canvas]
   set indexListValue ""
   if { [winfo exists ${indexListW}] } {
      set indexListValue [${indexListW} get]
      ::log::log debug "xflow_submitNpassTaskCallback indexListValue:$indexListValue"
   }
   if { ${indexListValue} == "latest" } {
      Utils_raiseError $canvas "Npass_Task submit" [getErrorMsg NO_INDEX_SELECT]
   } else {
      set seqNpassTaskArgs [::FlowNodes::getNptArgs ${node} ${indexListValue}]
   
      if { $seqNpassTaskArgs == "-1" } {
         Utils_raiseError $canvas "Npass_Task submit" [getErrorMsg NO_INDEX_SELECT]
      } else {
         ::log::log debug "xflow_submitNpassTaskCallback $seqNpassTaskArgs"
         # Sequencer_runCommandWithWindow [$suiteRecord cget -suite_path] $seqExec "submit [file tail $node] $seqNpassTaskArgs" top \
         #   -n $seqNode -s submit -f $flow ${ignoreDepFlag} $seqNpassTaskArgs
         Sequencer_runCommandLogAndWindow [$suiteRecord cget -suite_path] $seqExec "submit [file tail $node] $seqNpassTaskArgs" top \
            -n $seqNode -s submit -f $flow ${ignoreDepFlag} $seqNpassTaskArgs

      }
   }
}

# this function is invoked to do a 'tail -f' of tha currently-running task
proc xflow_tailfCallback { node canvas {full_loop 0} } {
    global env
    ::log::log debug "xflow_tailfCallback node$node canvas$canvas"
    set seqNode [::FlowNodes::getSequencerNode $node]
    set nodeExt [::FlowNodes::getListingNodeExtension $node $full_loop]
    set suiteRecord [xflow_getActiveSuite]
    set expPath [${suiteRecord} cget -suite_path]

    # set datestamp for history to monitoring date if different from latest, else take datestamp from experiment.
    set dateStamp [xflow_getMonitoringDatestamp]
    if { $dateStamp == "" } {
	set dateStamp [xflow_retrieveDateStamp $canvas $suiteRecord]
    }

    if { $nodeExt == "-1" } {
	Utils_raiseError $canvas "node listing" [getErrorMsg NO_LOOP_SELECT]
    } else {
	if { $nodeExt != "" } {
	    set nodeExt ".${nodeExt}"
	}
	if [ catch { set listPath [exec ksh -c "ls -rt1 ${expPath}/sequencing/output${seqNode}${nodeExt}.${dateStamp}.pgmout* | tail -n 1"] } message ] {
	    Utils_raiseError . "Retrieve node output" $message
	    return 0
	}
	Utils_launchShell $env(TRUE_HOST) ${expPath} ${expPath} "Monitoring=${seqNode}${nodeExt}" "tail -f ${listPath}"
    }
}

# this function is invoked to show the latest succesfull node listing
proc xflow_listingCallback { node canvas caller_menu {full_loop 0} } {
   global SESSION_TMPDIR
   ::log::log debug "xflow_listingCallback node:$node canvas:$canvas"
   set listingExec [SharedData_getMiscData SEQ_UTILS_BIN]/nodelister
   set suiteRecord [xflow_getActiveSuite]

   set seqNode [::FlowNodes::getSequencerNode $node]
   set nodeExt [::FlowNodes::getListingNodeExtension $node $full_loop]
   set datestamp [xflow_getMonitoringDatestamp]
   set listingViewer [SharedData_getMiscData TEXT_VIEWER]
   set defaultConsole [SharedData_getMiscData DEFAULT_CONSOLE]

   if { $nodeExt == "-1" } {
      Utils_raiseError $canvas "node listing" [getErrorMsg NO_LOOP_SELECT]
   } else {
      if { $nodeExt != "" } {
         set nodeExt ".${nodeExt}"
      }
      # title is used only for default viewer
      set winTitle "Node Listing [file tail $node]${nodeExt}.${datestamp}"
      regsub -all " " ${winTitle} _ tempfile
      set outputfile "${SESSION_TMPDIR}/${tempfile}_[clock seconds]"

      set seqCmd "${listingExec} -n ${seqNode}${nodeExt} -d ${datestamp}"
      Sequencer_runCommand [$suiteRecord cget -suite_path] ${outputfile} ${seqCmd}

      if { ${listingViewer} == "default" } {
         create_text_window ${winTitle} ${outputfile} top .
      } else {
         set editorCmd "${listingViewer} ${outputfile}"
         TextEditor_goKonsole ${defaultConsole} ${winTitle} ${editorCmd}
      }
   }
}

# this funtion is invoked to list all the successfull node listing for this node.
# this means all available listings in different datestamps
proc xflow_allListingCallback { node canvas caller_menu type } {
  global env
   set shadowColor [SharedData_getColor SHADOW_COLOR]
   set bgColor [SharedData_getColor CANVAS_COLOR]
   set id [clock seconds]
   set tmpdir $env(TMPDIR)
   set tmpfile "${tmpdir}/test$id"
   set suiteRecord [xflow_getActiveSuite]
   set seqNode [::FlowNodes::getSequencerNode $node]
   #set nodeExt [::FlowNodes::getListingNodeExtension $node 0]
   set suitePath [$suiteRecord cget -suite_path]
   set listerPath [SharedData_getMiscData SEQ_UTILS_BIN]/nodelister
   set cmd "export SEQ_EXP_HOME=$suitePath; $listerPath -n ${seqNode} -type $type -list > $tmpfile 2>&1"
   ::log::log debug  "xflow_allListingCallback ksh -c $cmd"
   catch { eval [exec ksh -c $cmd ] }

   ##set fullList [list showAllListings $node $type $canvas $canvas.list]
   set listingW .listing_${type}_${node}
   if { [winfo exists ${listingW}] } {
      destroy ${listingW}
   }
   toplevel ${listingW}
   wm geometry ${listingW} +[winfo pointerx ${caller_menu}]+[winfo pointery ${caller_menu}]

   wm title  ${listingW} "${type} listings ${node}"
   frame ${listingW}.frame -relief raised -bd 2 -bg $bgColor
   pack ${listingW}.frame -fill both -expand 1
   listbox ${listingW}.list -yscrollcommand "${listingW}.yscroll set" \
          -xscrollcommand "${listingW}.xscroll set"  \
          -height 10 -width 70 -selectmode multiple -bg $bgColor -fg $shadowColor
   scrollbar ${listingW}.yscroll -command "${listingW}.list yview"  -bg $bgColor
   scrollbar ${listingW}.xscroll -command "${listingW}.list xview" -orient horizontal -bg $bgColor

   pack ${listingW}.xscroll -fill x -side bottom -in ${listingW}.frame
   pack ${listingW}.yscroll -side right -fill y -in ${listingW}.frame
   pack ${listingW}.list -expand 1 -fill both -padx 1m -side left -in ${listingW}.frame

   set resultingFile [open $tmpfile] 

   while { [gets $resultingFile line ] >= 0 } {
       if { [string first "On" $line] >= 0 } {
       set mach [string trimleft $line "On "]
       ${listingW}.list insert end $line
       } else {
       ${listingW}.list insert end "[string trim $line "\n"] $mach"
       }
   }

   catch {[exec rm -f $tmpfile]}
   bind ${listingW}.list <Double-Button-1> [list xflow_showAllListingItem ${suiteRecord} ${listingW}.list ${type}]
}

# this function is invoked to display the node listings selected from the
# "All Node Listing" window
proc xflow_showAllListingItem { suite_record listw list_type} {
   global SESSION_TMPDIR
   ::log::log debug "xflow_showAllListingItem selection: [$listw curselection]"
   set selectedIndexes [$listw curselection]
   set listingExec [SharedData_getMiscData SEQ_UTILS_BIN]/nodelister
   set suitePath [${suite_record} cget -suite_path]
   set listingViewer [SharedData_getMiscData TEXT_VIEWER]
   set defaultConsole [SharedData_getMiscData DEFAULT_CONSOLE]

   foreach selectIndex $selectedIndexes {
      set selectedValue [$listw get $selectIndex]
      if { [string first "On " $selectedValue] != 0 } {
         set splittedArgs [split $selectedValue]
     set mach [lindex $splittedArgs end]
         set listingFile [lindex $splittedArgs end-1]
         set splittedFile [split [file tail $listingFile] .]

         set winTitle "${list_type} Listing [file tail ${listingFile}]"
         regsub -all " " ${winTitle} _ tempfile
         set outputfile "${SESSION_TMPDIR}/${tempfile}_[clock seconds]"

         set seqCmd "${listingExec} -f $listingFile@$mach"
         Sequencer_runCommand ${suitePath} ${outputfile} ${seqCmd}
         if { ${listingViewer} == "default" } {
            create_text_window ${winTitle} ${outputfile} top .
         } else {
            set editorCmd "${listingViewer} ${outputfile}"
            TextEditor_goKonsole ${defaultConsole} ${winTitle} ${editorCmd}
         }
      }
   }
}

# this funtion is invoked to show the latest abort listing
proc xflow_abortListingCallback { node canvas caller_menu {full_loop 0} } {
   global SESSION_TMPDIR
   ::log::log debug "xflow_abortListingCallback node:$node canvas:$canvas"
   set abortListingExec [SharedData_getMiscData SEQ_UTILS_BIN]/nodelister
   set suiteRecord [xflow_getActiveSuite]
   set seqNode [::FlowNodes::getSequencerNode $node]
   set nodeExt [::FlowNodes::getListingNodeExtension $node $full_loop]
   set datestamp [xflow_getMonitoringDatestamp]
   set listingViewer [SharedData_getMiscData TEXT_VIEWER]
   set defaultConsole [SharedData_getMiscData DEFAULT_CONSOLE]

   if { $nodeExt == "-1" } {
      Utils_raiseError $canvas "node listing" [getErrorMsg NO_LOOP_SELECT]
   } else {
      if { $nodeExt != "" } {
         set nodeExt ".${nodeExt}"
      }
      # title is used only for default viewer
      set winTitle "abort Listing [file tail $node]${nodeExt}.${datestamp}"
      regsub -all " " ${winTitle} _ tempfile
      set outputfile "${SESSION_TMPDIR}/${tempfile}_[clock seconds]"

      set seqCmd "${abortListingExec} -n ${seqNode}${nodeExt} -type abort -d ${datestamp}"
      Sequencer_runCommand [$suiteRecord cget -suite_path] ${outputfile} ${seqCmd}

      if { ${listingViewer} == "default" } {
         create_text_window ${winTitle} ${outputfile} top .
      } else {
         set editorCmd "${listingViewer} ${outputfile}"
         TextEditor_goKonsole ${defaultConsole} ${winTitle} ${editorCmd}
      }
   }
}

# this function is called when the user selects an index from the npt or loop
# listbox. It redraws the flow starting from the selected widget
proc xflow_indexedNodeSelectionCallback { node canvas combobox_w} {
   ::log::log debug "xflow_indexedNodeSelectionCallback node:$node $combobox_w"

   set member [${combobox_w} get]

   if { $member != "latest" && [lindex $member 0] != "+" } {
      set member +${member}
   }
   $node configure -current $member

   xflow_redrawNodes ${node} ${canvas}
}

# this function is called to expand a node and all of its child nodes
proc xflow_expandAllCallback { node canvas caller_menu } {
   ::FlowNodes::uncollapseAll $node $canvas
   destroy $caller_menu
   xflow_drawflow $canvas
}

# this should only be called for flow windows that
# are spawned using the "new window" callback
proc xflow_closeSpawnedWindow { suite canvas toplevel_win} {
   ::log::log debug "xflow_closeSpawnedWindow suite:$suite canvas:$canvas toplevel_win:$toplevel_win"
   set rootNode [::SuiteNode::getDisplayRoot $suite $canvas]
   # recursively remove the display from all nodes in the canvas
   ::FlowNodes::removeDisplayFromNode $rootNode $canvas 1

   # remove the canvas from the suite
   ::SuiteNode::removeDisplayFromSuite $suite $canvas
   destroy $toplevel_win
}

# callback when user click on a box with button 1 to collapse/expand a node
proc xflow_changeCollapsed { canvas binder x y } {
   #::log::log debug "xflow_changeCollapsed called canvas:$canvas binder:$binder x:$x y:$y"
   if { [${binder} cget -flow.children] == "" } {
      ::log::log debug "changeCollapse: node has no children"
      return
   }

   set isCollapsed [::FlowNodes::isCollapsed $binder $canvas]
   if { $isCollapsed == 0 } {
      ::FlowNodes::setCollapsed $binder $canvas 1
   } else {
      ::FlowNodes::setCollapsed $binder $canvas 0
   }

   #::log::log debug "xflow_changeCollapsed: new collapse value:[${binder} cget -flow.display.collapse]"
   xflow_drawflow $canvas 0
}

# redraws the flow starting from a node... without having
# to clear all the canvas
proc xflow_redrawNodes { node {canvas ""} } {
   global cmdList
   global REFRESH_MODE
   ::log::log debug "xflow_redrawNodes node:$node"
   set REFRESH_MODE true
   set cmdList ""
   catch {
      if { $canvas == "" } {
         # get the list of all canvases where the node appears
         set canvasList [::FlowNodes::getDisplayList $node]
      } else {
         set canvasList $canvas
      }
      foreach canvas $canvasList {
         set cmdList {}
         # instead of removing the nodes one by one, I'm collecting all the cmds
         # and run it at once to avoid less flickering on the gui
         ::DrawUtils::clearBranch ${canvas} ${node} cmdList
         set nodePosition [::FlowNodes::getPosition ${node}]
         eval ${cmdList}
         xflow_drawNode ${canvas} ${node} ${nodePosition}
         xflow_resetScrollRegion ${canvas}
         xflow_addBgImage ${canvas} [winfo width ${canvas}] [winfo height ${canvas}] true
      }
   }
   set REFRESH_MODE false
}

# redraws the flow for all canvas... if the user has multiple windows open
# on the same experiment
proc xflow_redrawAllFlow {} {
   set suiteRecord [xflow_getActiveSuite]
   # the active suite could be empty if the redraw is
   # called from the LogReader in overview mode
   if { ${suiteRecord} != "" } {
      set canvasList [::SuiteNode::getCanvasList ${suiteRecord}]
      foreach canvasW $canvasList {
         xflow_drawflow $canvasW 0
      }
   }
}

# user clicks on refresh button in the
# toolbar
# - deletes all nodes
# - rereads flow.xml for each module
# - reread the log file
# - redisplay the flow
proc xflow_refreshFlow { } {
   global PROGRESS_REPORT_TXT
   set suiteRecord [xflow_getActiveSuite]

   set progressW [ProgressDlg .pdrefresh -title "Flow Refresh" -parent .  -textvariable PROGRESS_REPORT_TXT]
   set PROGRESS_REPORT_TXT "Refreshing experiment ..."
   # for some reason, I need to call the update for the progress dlg to appear properly
   update idletasks

   set result [ catch {

      global NODE_RESOURCE_DONE LOOP_RESOURCES_DONE
      set LOOP_RESOURCES_DONE false
      set NODE_RESOURCE_DONE false
      # clear all nodes
      set PROGRESS_REPORT_TXT "Deleting node data ..."
      update idletasks
      ::FlowNodes::clearAllNodes
      record delete instance ${suiteRecord}

      set thisThreadId [thread::id]
      set callingThreadId [SharedData_getMiscData ${thisThreadId}_CALLING_THREAD_ID]
      if { [SharedData_getMiscData OVERVIEW_MODE] == "false" } {
         set PROGRESS_REPORT_TXT "Parsing module's flow.xml ..."
         update idletasks
         xflow_readFlowXml
         xflow_initStartupMode
         xflow_displayFlow ${callingThreadId}
         xflow_stopStartupMode
      } else {
         set overviewThreadId [SharedData_getMiscData OVERVIEW_THREAD_ID]
         set PROGRESS_REPORT_TXT "Parsing module's flow.xml ..."
         update idletasks
         xflow_readFlowXml
         xflow_initStartupMode
         set PROGRESS_REPORT_TXT "Processing log file ..."
         update idletasks
         LogReader_readFile ${suiteRecord} ${overviewThreadId}
         xflow_displayFlow ${callingThreadId}
         xflow_stopStartupMode
      }

      destroy ${progressW}

   } message ]


   # any errors, put the cursor back to normal state
   if { ${result} != 0  } {

      set einfo $::errorInfo
      set ecode $::errorCode
      destroy ${progressW}

      # report the error with original details
      return -code ${result} \
         -errorcode ${ecode} \
         -errorinfo ${einfo} \
         ${message}
   }
}

# draws the experiment flow
proc xflow_drawflow { canvas {initial_display "1"} } {
   global SEQ_EXP_HOME
   ::log::log debug "xflow_drawflow() canvas:$canvas"

   if { [::FlowNodes::isFlowModified ${SEQ_EXP_HOME}] == "true" } {
      ::log::log debug "xflow_drawflow() xflow_refreshFlow"
      xflow_refreshFlow
      return
   }

   if { [winfo exists ${canvas}] } {
      ::log::log debug "xflow_drawflow() found existing canvas:$canvas"
      #::DrawUtils::clearCanvas $canvas
      #xflow_clearCanvasFlow ${canvas}
      set suiteRecord [xflow_getActiveSuite]
      # reset the default spacing for drawing flow
      ::SuiteNode::resetDisplayData ${suiteRecord} ${canvas}
      set rootNode [::SuiteNode::getDisplayRoot $suiteRecord $canvas]

      set callback xflow_changeCollapsed
      xflow_clearCanvasFlow ${canvas}
      xflow_drawNode $canvas $rootNode 0 true
      xflow_resetScrollRegion ${canvas}
      # resize the window depending on size of canvas elements
      xflow_resizeWindow ${canvas}
   
      if { $initial_display == "1" } {
         $canvas yview moveto 0
      }

   }
   ::log::log debug "xflow_drawflow() done"

}

# this function resizes the xflow main window depending on the
# items in the canvas
proc xflow_resizeWindow { canvas } {
   global FLOW_RESIZED
   ::log::log debug "xflow_resizeWindow canvas:${canvas}"

   if { ${FLOW_RESIZED} == true } {
      ::log::log debug "xflow_resizeWindow FLOW_RESIZED== true returing without resize"
      return
   }

   if { [SharedData_getMiscData FLOW_GEOMETRY] == "" } {
      if { [winfo exists ${canvas}] } {
         set topLevel [winfo toplevel ${canvas}]
         set suiteRecord [xflow_getActiveSuite]
         set heightMax [lindex [wm maxsize ${topLevel}] 1]
         set widthMax [lindex [wm maxsize ${topLevel}] 0]
         set canvasMaximX [::SuiteNode::getDisplayMaximumX ${suiteRecord} ${canvas}]
         set canvasMaximY [::SuiteNode::getDisplayMaximumY ${suiteRecord} ${canvas}]
         set windowW [expr ${canvasMaximX} + 50]
         set windowH [expr ${canvasMaximY} + 135]
         if { [expr ${windowH} > ${heightMax}] } {
            ::log::log debug "xflow_resizeWindow height ${windowH} > ${heightMax} (default)"
            set windowH ${heightMax}
         }
         if { [expr ${windowW} > ${widthMax}] } {
            ::log::log debug "xflow_resizeWindow width ${windowW} > ${widthMax} (default)"
            set windowW ${widthMax}
         }
         wm geometry ${topLevel} =${windowW}x${windowH}
      }
   } else {
      # limit the size of the flow window
      # read value from ~/.maestrorc
      set flowGeometry [SharedData_getMiscData FLOW_GEOMETRY]
      wm geometry . =${flowGeometry}
   }
}

proc xflow_resetScrollRegion { _canvas } {
   set delta 5
   foreach { x1 y1 x2 y2 } [${_canvas} bbox flow_element] {
      set x1 [expr ${x1} - ${delta}]
      set y1 [expr ${y1} - ${delta}]
      set x2 [expr ${x2} + ${delta}]
      set y2 [expr ${y2} + ${delta}]
   }
   ${_canvas} configure -scrollregion [list ${x1} ${y1} ${x2} ${y2}] -yscrollincrement 5 -xscrollincrement 5
}

# this function is a leftover when xflow was supporting multipe exps.
# It is still use yet only to parse the exp flow.xml file.
proc xflow_createCanvasFrame { parent suitePath bind_cmd {page_h 1} {page_w 1}} {
   global env
   ::log::log debug "xflow_createCanvasFrame parent:$parent suiteList:$suiteList bind_cmd:$bind_cmd "
   set suiteName [file tail $suitePath]
   set drawFrame $parent.[::SuiteNode::formatName $suitePath]
   frame $drawFrame

   grid columnconfigure $parent 0 -weight 1
   grid rowconfigure $parent 0 -weight 1

   #readMasterfile ${suitePath}/EntryModule/flow.xml $suitePath "" ""
   #set suiteRecord [::SuiteNode::formatSuiteRecord $suitePath]
   #set rootNode [${suiteRecord} cget -root_node]
   #xflow_getNodeResources ${rootNode} $suitePath 1
}

# this command is called from a variable trace
# the proc definition requires 3 parameters for variable tracing
# however, defaults to empty strings... no need to pass parameters
# when called manually
proc xflow_nodeResourceCallback { {name1 ""} {name2 ""} {op ""} } {
   global NODE_RESOURCE_DONE NODE_DISPLAY_PREF
   global nodeResourceText
   # we only load the resources once
   if { ${NODE_DISPLAY_PREF} != "normal" } {
      if { ! [info exists NODE_RESOURCE_DONE] || ${NODE_RESOURCE_DONE} == "false" } {
         set activeSuiteRecord [xflow_getActiveSuite]
         if { ${activeSuiteRecord} != "" } {
            set destroProgessCmd ""
            if { [wm state .] == "normal" } {
               set progressW [ProgressDlg .pd -parent . -title "Node Display Preferrences" -textvariable nodeResourceText]
               # Utils_positionWindow ${progressW}
               set destroProgessCmd "destroy ${progressW}"
            }

            set nodeResourceText "Loading node resources ..."
            # for some reason, I need to call the update for the progress dlg to appear properly
            update idletasks
            ::log::log debug "xflow_nodeResourceCallback retrieving resources for [${activeSuiteRecord} cget -suite_path]"
            set rootNode [${activeSuiteRecord} cget -root_node]
            xflow_getNodeResources ${rootNode} [${activeSuiteRecord} cget -suite_path] 1
            set NODE_RESOURCE_DONE true
            # catch { destroy ${progressW} }
            eval ${destroProgessCmd}
            unset nodeResourceText
         }
      }
   }
}

# this function retrives the node resource info by executing
# the maestro-utils nodeinfo. Recursivity can also be enabled using
# is_recursive function parameter.
proc xflow_getNodeResources { node suite_path {is_recursive 0} } {
   global env
   ::log::log debug "xflow_getNodeResources node:$node"

   set nodeInfoExec "[SharedData_getMiscData SEQ_BIN]/nodeinfo"
   set seqNode [::FlowNodes::getSequencerNode $node]
   set outputFile $env(TMPDIR)/nodeinfo_output_[file tail $node]_[clock seconds]

   # for now we only care about batch resources from tasks
   ::log::log debug "${nodeInfoExec} -n ${seqNode} -f res |  sed -e 's:node.:$node configure -:' -e 's:=: :'"
   set code [catch {set output [exec ksh -c "export SEQ_EXP_HOME=${suite_path};${nodeInfoExec} -n ${seqNode} -f res |  sed -e 's:node.:$node configure -:' -e 's:=: :' > ${outputFile} 2> /dev/null "]} message]

   if { $code != 0 } {
      Utils_raiseError . "Get Node Resource" $message
      return 0
   }
   if [ catch { eval [exec cat ${outputFile}] } message ] {
      ::log::log debug "\n$message"
   }

   catch { close $fileId }

   if { $is_recursive } {
      set childList [$node cget -flow.children]
      if { $childList != "" } {
         foreach childName $childList {
            set childNode $node/$childName
            xflow_getNodeResources $childNode $suite_path $is_recursive
         }
      }
   }
}

# at startup fetches all the loop node attributes once only to be able to display
# the loop parameters
proc xflow_getAllLoopResourcesCallback { node suite_path } {
   global LOOP_RESOURCES_DONE 
   if { ! [info exists LOOP_RESOURCES_DONE] || ${LOOP_RESOURCES_DONE} == "false" } {
      ::log::log debug "xflow_getAllLoopResourcesCallback getting resources..."
      xflow_getAllLoopResources ${node} ${suite_path}
      set LOOP_RESOURCES_DONE true
   }
}

# retrieve loop attributes recursively
proc xflow_getAllLoopResources { node suite_path } {
   if { [$node cget -flow.type] == "loop" } {
      xflow_getLoopResources ${node} ${suite_path}
   } 
   set childList [$node cget -flow.children]
   if { $childList != "" } {
      foreach childName $childList {
         set childNode $node/$childName
         xflow_getAllLoopResources $childNode $suite_path
      }
   }
}

# now that the loops attributes are stored in the node resource xml file,
# this function calls the nodeinfo to retrieve loop attributes.
proc xflow_getLoopResources { node suite_path } {
   global env
   ::log::log debug "xflow_getLoopResources node:$node"

   if { [$node cget -flow.type] != "loop" } {
      ::log::log debug "xflow_getLoopResources nothing to be done for non-loop node"
      return
   }

   set nodeInfoExec "[SharedData_getMiscData SEQ_BIN]/nodeinfo"
   set seqNode [::FlowNodes::getSequencerNode $node]
   set outputFile $env(TMPDIR)/nodeinfo_output_[file tail $node]_[clock seconds]

   # retrieve loop attributes by parsing output of nodeinfo node.specific i.e.
   # node.specific.TYPE=Default
   # node.specific.START=2
   # node.specific.END=10
   # node.specific.STEP=2
   # node.specific.TYPE=Default
   ::log::log debug "xflow_getLoopResources ${nodeInfoExec} -n ${seqNode} | grep node.specific| sed -e 's:node.specific.::' -e 's:=: :'"
   if [ catch { exec ksh -c "export SEQ_EXP_HOME=${suite_path};${nodeInfoExec} -n ${seqNode} | grep node.specific| sed -e 's:node.specific.::' -e 's:=: :'  > ${outputFile} 2> /dev/null" } message ] {
      Utils_raiseError . "Get Loop Resources" $message
      return 0
   }

   ::log::log debug "xflow_getLoopResources cat ${outputFile}"
   array set valueList {}
   if [ catch { array set valueList [exec cat ${outputFile}] } message ] {
      ::log::log debug "\n$message"
   }

   # maps the node.specific attribute name to the
   # node record attribute name
   array set attrMap { 
      TYPE loop_type
      START start
      STEP step
      END end
      SET set
   }

   foreach { name value } [array get valueList] {
      if { [info exists attrMap(${name})] } {
         set attrName $attrMap(${name})
         ${node} configure -${attrName} ${value}
      } else {
         ::log::log debug "xflow_getLoopResources invalid loop attribute token name:$name value:$value"
      }
   }
}

# this is leftover code when the xflow was able to display multiple exps
# using tabs. This function is still used to refresh the content of an exp flow,
# however xflow supports only one exp now.
proc xflow_selectSuiteTab { parent suite_record } {

   ::log::log debug "xflow_selectSuiteTab parent:$parent suite_record:${suite_record}"

   set title "xflow experiment path = [${suite_record} cget -suite_path]"
   wm title . $title

   xflow_setActiveSuite ${suite_record}
   #set formattedName [::SuiteNode::formatName [${suite_record} cget -suite_path]]
   #set drawFrame ${parent}.${formattedName}
   set drawFrame ${parent}.draw_frame
   set canvas [xflow_createFlowCanvas $drawFrame]
   xflow_getDateStamp [xflow_getWidgetName exp_date_frame] ${suite_record}

   xflow_drawflow $canvas
}

# not used for now, will be used when we implement global dependency configuration
proc xflow_isIgnoreDepTrue {} {
   global ignoreDep
   if { ${ignoreDep} == "" } {
      return false
   }
   return true
}

# not used for now, will be used when we implement global dependency configuration
proc xflow_changeIgnoreDep { source_w dep_off_img dep_on_img } {
   global ignoreDep
   set currentImg [${source_w} cget -image]
   if { ${currentImg} == ${dep_on_img} } {
      set ignoreDep ""
      ${source_w} configure -image ${dep_off_img}
      ::tooltip::tooltip ${source_w} "Future feature: Click to ignore dependency: currently on."
   } else {
      set ignoreDep " -i"
      ${source_w} configure -image ${dep_on_img}
      ::tooltip::tooltip ${source_w} "Future feature: Click to enable dependency: currently off."
   }
}

# this function creates an empty canvas in the parent
# container widget if it does not exists.
# Creates canvas with scrollbars and laods bg image
# It returns the new canvas or the existing one.
proc xflow_createFlowCanvas { parent } {
   ::log::log debug "xflow_createFlowCanvas parent:$parent "
   set drawFrame $parent
   set canvas ${drawFrame}.canvas
   set canvasColor [SharedData_getColor CANVAS_COLOR]
   if { ! [winfo exists $canvas] } {

      set canvas ${drawFrame}.canvas

      if { [winfo exists ${drawFrame}.yscroll] == 0 } {
         frame ${drawFrame}.xframe
      
         scrollbar ${drawFrame}.yscroll -command [list $canvas yview ]
         scrollbar ${drawFrame}.xscroll -orient horizontal -command [list $canvas xview]
         set pad 12
         frame ${drawFrame}.pad -width $pad -height $pad
   
         grid ${drawFrame}.xframe -row 2 -column 0 -columnspan 2 -sticky ewns
         grid ${drawFrame}.yscroll -row 0 -column 1 -sticky ns

         grid ${drawFrame}.pad -row 0 -column 1 -in ${drawFrame}.xframe -sticky es
         grid ${drawFrame}.xscroll -row 0 -column 0 -sticky ew -in ${drawFrame}.xframe
   
         grid columnconfigure ${drawFrame}.xframe 0 -weight 1
         grid rowconfigure ${drawFrame}.xframe 1 -weight 1
   
         # only show the scrollbars if required
         ::autoscroll::autoscroll ${drawFrame}.yscroll
         ::autoscroll::autoscroll ${drawFrame}.xscroll
      }
      canvas $canvas -yscrollcommand [list ${drawFrame}.yscroll set] \
         -xscrollcommand [list ${drawFrame}.xscroll set] -relief raised -bg $canvasColor
      # bind dragging right mouse button to drag canvas
      bind $canvas <1> {
         global CANVAS_DRAG_X CANVAS_DRAG_Y
         %W scan mark %x %y
         set CANVAS_DRAG_X %x
         set CANVAS_DRAG_Y %y
      }

      bind $canvas <B1-Motion> {
         global CANVAS_DRAG_X CANVAS_DRAG_Y
         # the code below is mainly to limit the drag of the canvas
         # within the scrollable area... Else the canvas would end up
         # dragged to a place where there is no background image... ugly
         if { ! ([info exists CANVAS_DRAG_X] && [info exists CANVAS_DRAG_Y]) } { return }
         foreach { leftx rightx } [%W xview] {break}
         foreach { topy bottomy } [%W yview] {break}
         set dragtox %x
         set dragtoy %y
         if { ${leftx} == "0.0" && ${rightx} == "1.0" } {
            # no horizontal drag allowed
            set dragtox ${CANVAS_DRAG_X}
         } else {
            if { [expr %x - ${CANVAS_DRAG_X}] > 0  } {
               if { ${leftx} == "0.0" } {
                  # can't drag to right if nothing to drag
                  set dragtox [winfo width %W]
               }
            } else {
               if { ${rightx} == "1.0" } {
                  # can't drag to left if nothing to drag
                  set dragtox 0
               }
            }
         }

         if { ${topy} == "0.0" && ${bottomy} == "1.0" } {
            # no vertical drag allowed
            set dragtoy ${CANVAS_DRAG_Y}
         } else {
            if { [expr %y - ${CANVAS_DRAG_Y}] > 0 } {
               if { ${topy} == "0.0" } {
                  # can't drag to bottom if nothing to drag
                  set dragtoy [winfo height %W]
               }
            } else {
               if { ${bottomy} == "1.0" } {
                  # can't drag to top if nothing to drag
                  set dragtoy 0
               }
            }
         }
         %W scan dragto ${dragtox} ${dragtoy}
      }

      bind $canvas <Configure> {
         
         global CANVAS_RESIZE_ID
         xflow_addBgImage [xflow_getMainFlowCanvas] %w %h true
      }


      grid $canvas -row 0 -column 0 -sticky nsew


      # make the canvas expandable to right & bottom
      grid columnconfigure ${drawFrame} 0 -weight 1
      grid rowconfigure ${drawFrame} 0 -weight 1

      grid ${drawFrame} -row 0 -column 0 -sticky nsew
   }
   return $canvas
}

proc xflow_clearCanvasFlow { _canvas } {
   if { [winfo exists ${_canvas}] } {

      # retrieve all flow elements to delete
      ${_canvas} delete flow_element
   }
   update idletasks
}

proc xflow_addBgImage { _canvas _width _height {force false} } {

   global FLOW_BG_SOURCE_IMG FLOW_TILED_IMG
   package require img::gif

   Utils_busyCursor [winfo toplevel ${_canvas}]

   if { [${_canvas} find withtag backgroundBitmap] == "" } {
      set FLOW_BG_SOURCE_IMG [image create photo -file [xflow_getWidgetName bg_image]]
      set FLOW_TILED_IMG [image create photo]
      # does not exists, create new one
      ${_canvas} create image 0 0 \
         -anchor nw \
         -image ${FLOW_TILED_IMG} \
         -tags backgroundBitmap

      ${_canvas} lower backgroundBitmap
      bind ${_canvas} <Destroy> { 
         global FLOW_BG_SOURCE_IMG FLOW_TILED_IMG
         global XFLOW_BG_WIDTH XFLOW_BG_HEIGHT
         catch { image delete ${FLOW_BG_SOURCE_IMG} ${FLOW_TILED_IMG} }
         catch { unset XFLOW_BG_WIDTH XFLOW_BG_HEIGHT }
      }
   }

   xflow_tileBgImage ${_canvas} ${FLOW_BG_SOURCE_IMG} ${FLOW_TILED_IMG} ${_width} ${_height}

   Utils_normalCursor [winfo toplevel ${_canvas}]
 }

 proc xflow_tileBgImage {canvas sourceImage tiledImage _width _height} {
   global XFLOW_BG_WIDTH XFLOW_BG_HEIGHT
   set canvasBox [${canvas} bbox all]
   set canvasItemsW [lindex ${canvasBox} 2]
   set canvasItemsH [lindex ${canvasBox} 3]
   set usedW ${canvasItemsW}
   set usedH ${canvasItemsH}


   # if the canvas is bigger than the number of elements, we use the
   # canvas width and height
   if { ${_width} > ${canvasItemsW} } {
      set usedW [expr ${_width} + 50]
   }
   if { ${_height} > ${canvasItemsH} } {
      set usedH [expr ${_height} + 50]
   }

   if { ! [info exists XFLOW_BG_WIDTH] } {
      set XFLOW_BG_WIDTH ${usedW}
      set XFLOW_BG_HEIGHT ${usedH}
      $tiledImage copy $sourceImage -to 0 0 ${XFLOW_BG_WIDTH} ${XFLOW_BG_HEIGHT}
   } else {
      if { ${usedW} > ${XFLOW_BG_WIDTH} || ${usedH} > ${XFLOW_BG_HEIGHT} } {
         set XFLOW_BG_WIDTH ${usedW}
         set XFLOW_BG_HEIGHT ${usedH}
         $tiledImage copy $sourceImage -to 0 0 ${XFLOW_BG_WIDTH} ${XFLOW_BG_HEIGHT}
      }
   }
 }

proc setErrorMessages {} {
  global ERROR_MSG_LIST
  set ERROR_MSG_LIST(NO_LOOP_SELECT) "Cannot retrieve loop member for parent loop container! Please select a loop index."
  set ERROR_MSG_LIST(INVALID_NPT_SELECT) "Cannot mix latest selection with index selection!"
  set ERROR_MSG_LIST(NO_INDEX_SELECT) "You must provide a valid index value for this node!"
}

proc getErrorMsg { key } {
  global ERROR_MSG_LIST
   return $ERROR_MSG_LIST($key)
}

proc xflow_setActiveSuite { suite } {
   global ACTIVE_SUITE
   set ACTIVE_SUITE $suite
}

proc xflow_getActiveSuite {} {
   global ACTIVE_SUITE

   if { [info exists ACTIVE_SUITE] } {
      return $ACTIVE_SUITE
   } else {
      ::log::log debug "xflow_getActiveSuite empty"
      return ""
   }
}

# function called when user quits the application.
# In overview mode, this is also called by the overview for exp thread cleanup
# if required.
proc xflow_quit {} {
   global XFLOW_STANDALONE MONITOR_THREAD_ID
   global SESSION_TMPDIR TITLE_AFTER_ID XFLOW_FIND_AFTER_ID

   ::log::log debug "xflow_quit exiting Xflow thread id:[thread::id]"
   set suiteRecord [xflow_getActiveSuite]
   set isOverviewMode [SharedData_getMiscData OVERVIEW_MODE]

   catch { after cancel ${TITLE_AFTER_ID} }
   catch { after cancel ${XFLOW_FIND_AFTER_ID} }
   if { [info exists SESSION_TMPDIR] } {
      ::log::log debug "xflow_quit deleting tmp dir ${SESSION_TMPDIR}"
      catch { file delete -force ${SESSION_TMPDIR} }
      set SESSION_TMPDIR ""
   }
   if { ${isOverviewMode} == "true" } {
      # we are in overview mode
      set childWidgets [winfo children .]
      foreach childW ${childWidgets} {
         if { ${childW} != ".#BWidget" } {
            # I can't destroy the bwidget one, causing problems
            # to bwidget nodes
            destroy ${childW}
         }
      }
      wm withdraw .
   } else {
      LogReader_cancelAfter $suiteRecord
      exit
   }
}

# this function is only used in xflow standalone mode
# it is called by the msg center thread to notify the xflow
# of new messages available. It will maily update the msg center
# icon to a new message state.
proc xflow_newMessageCallback { has_new_msg } {
   ::log::log debug "xflow_newMessageCallback has_new_msg:$has_new_msg"
   set msgCenterWidget [xflow_getWidgetName msgcenter_button]
   set noNewMsgImage [xflow_getWidgetName msg_center_img]
   set hasNewMsgImage [xflow_getWidgetName msg_center_new_img]
   set normalBgColor [option get ${msgCenterWidget} background Button]
   set newMsgBgColor  [SharedData_getColor COLOR_MSG_CENTER_MAIN]
   if { [winfo exists ${msgCenterWidget}] } {
      set currentImage [${msgCenterWidget} cget -image]
      if { ${has_new_msg} == "true" && ${currentImage} != ${hasNewMsgImage} } {
         ${msgCenterWidget} configure -image ${hasNewMsgImage} -bg ${newMsgBgColor} -bd 1
      } elseif { ${has_new_msg} == "false" && ${currentImage} != ${noNewMsgImage} } {
         ${msgCenterWidget} configure -image ${noNewMsgImage} -bg ${normalBgColor} -bd 1
      }
   }
}

# this is the place to validate essential suite
# data for startup
proc xflow_validateSuite {} {
   global env SEQ_EXP_HOME
   if { ! [info exists env(SEQ_EXP_HOME)] } {
      Utils_fatalError . "Xflow Startup Error" "SEQ_EXP_HOME environment variable not set! Exiting..."
   }

   set entryModTruePath ""
   set SEQ_EXP_HOME $env(SEQ_EXP_HOME)
   catch { set entryModTruePath [ exec true_path ${SEQ_EXP_HOME}/EntryModule ] }
   if { ${entryModTruePath} == "" } {
      Utils_fatalError . "Xflow Startup Error" "Cannot access ${SEQ_EXP_HOME}/EntryModule. Exiting..."
   }
}

# this function is called to create the widgets of the xflow main window
proc xflow_createWidgets {} {
   global SEQ_EXP_HOME

   ::log::log debug "xflow_createWidgets"
   wm iconify .
   set topFrame [frame [xflow_getWidgetName top_frame]]
   xflow_addFileMenu $topFrame
   xflow_addViewMenu $topFrame
   xflow_addHelpMenu $topFrame

   # exp label frame
   set expLabelFrame [frame [xflow_getWidgetName exp_label_frame]]
   set expLabelFont ExpLabelFont
   if { [lsearch [font names] ExpLabelFont] == -1 } {
      # create the font if not exists
      font create ExpLabelFont
      font configure ${expLabelFont} -size 25 -weight bold
   }

   set expLabel [label ${expLabelFrame}.exp_label -text [file tail ${SEQ_EXP_HOME}] -font ${expLabelFont}]
   grid ${expLabel} 
   #grid ${expLabelFrame} -row 3 -column 0 -sticky w
   pack ${expLabelFrame} -side left -padx {20 0}

   set secondFrame [frame  [xflow_getWidgetName second_frame]]
   set toolbarFrame [xflow_getWidgetName toolbar_frame]
   labelframe ${toolbarFrame} -text Toolbar
   xflow_createToolbar ${toolbarFrame}   

   # date bar is the 2nd widget
   set expDateFrame [xflow_getWidgetName exp_date_frame]
   set monDateFrame [xflow_getWidgetName monitor_date_frame]
   xflow_addDatestampWidget ${expDateFrame}

   # monitor date
   xflow_addMonitorDateWidget ${monDateFrame}

   # find frame
   set findFrame [frame [xflow_getWidgetName find_frame]]
   xflow_createFindWidgets ${findFrame}
   set findCloseB [xflow_getWidgetName find_close_button]
   ${findCloseB} configure -command [list grid remove ${findFrame}]


   # this displays the widget on the second frame
   grid ${toolbarFrame} -row 0 -column 0 -sticky nsew -padx 2 -ipadx 2
   grid ${expDateFrame} -row 0 -column 1 -sticky nsew -padx 2 -pady 0 -ipadx 2
   grid ${monDateFrame} -row 0 -column 2 -sticky nsew -padx 2 -pady 0 -ipadx 2
   #grid ${expLabelFrame} -row 0 -column 3 -padx { 20 0 }

   # flow_frame is the 3nd widget
   set flowFrame [frame [xflow_getWidgetName flow_frame]]
   set drawFrame [frame ${flowFrame}.draw_frame]

   grid columnconfigure ${flowFrame} 0 -weight 1
   grid rowconfigure ${flowFrame} 0 -weight 1

   # this displays the widgets in the main window layout
   grid $topFrame -row 0 -column 0 -sticky w -padx 2
   grid ${secondFrame} -row 1 -column 0  -sticky nsew -pady 2
   grid ${findFrame} -row 2 -column 0  -sticky nsew -pady 2 -padx 2
   grid remove ${findFrame}
   grid ${flowFrame}  -row 3 -column 0 -columnspan 2 -sticky nsew -padx 2 -pady 2
   grid columnconfigure . 0 -weight 1
   grid columnconfigure . 1 -weight 1
   grid rowconfigure . 3 -weight 2

   set sizeGripW [xflow_getWidgetName main_size_grip]
   ttk::sizegrip ${sizeGripW}
   bind ${sizeGripW} <B1-Motion> { 
      catch {
         global FLOW_RESIZED
         ttk::sizegrip::Drag   %W %X %Y
         set FLOW_RESIZED true
      }
   }

   grid ${sizeGripW} -row 4 -column 1 -sticky se
   
   wm geometry . =1200x800
}

proc xflow_setExpLabel { _displayName } {
   global SEQ_EXP_HOME
   set expLabelFrame [xflow_getWidgetName exp_label_frame]
   set datestamp [xflow_getMonitoringDatestamp]
   if { $datestamp == "" } {
      set datestamp [xflow_retrieveDateStamp ${expLabelFrame} [xflow_getActiveSuite]]
   }
   set displayValue ${_displayName}
   if { ${datestamp} != "" } {
      set hour [Utils_getHourFromDatestamp ${datestamp}]
      set displayValue ${_displayName}-${hour}
   }
   ${expLabelFrame}.exp_label configure -text ${displayValue}
}

# this function is called to create an exp flow.
# 1) in xflow standalone mode, this function is called at startup and when the user views the exp in
# history mode.
# 2) in overview mode, this function is called everytime the user wants to view the exp flow with the latest
# datestamp or in history mode. Note that in overview mode, a thread is created for each exp and another tread is created
# for each exp in history mode.
proc xflow_displayFlow { calling_thread_id } {
   global env XFLOW_STANDALONE SEQ_EXP_HOME PROGRESS_REPORT_TXT
   global MONITORING_LATEST MONITOR_DATESTAMP FLOW_RESIZED
   
   set suitePath ${SEQ_EXP_HOME}
   ::log::log debug "xflow_displayFlow thread id:[thread::id]"
   ::log::log notice "xflow_displayFlow thread id:[thread::id] ${suitePath}"
   set overview_x ""
   foreach {overview_x overview_y} [SharedData_getMiscData OVERVIEW_MAIN_COORDS] { break }
   if { ${overview_x} != "" } {
      xflow_positionFlowWindow . ${overview_x} ${overview_y}
      ::log::log notice "xflow_positionFlowWindow ${suitePath} . ${overview_x} ${overview_y}"
   }

   set FLOW_RESIZED false
   set topFrame [xflow_getWidgetName top_frame]
   xflow_createTmpDir

   if { ! [winfo exists ${topFrame}] } {
      set PROGRESS_REPORT_TXT "Creating widgets..."
      xflow_createWidgets
   }
   set displayName [ExpOptions_getDisplayName ${suitePath}]
   xflow_setExpLabel ${displayName}

   ::log::log debug "xflow_displayFlow suitePath ${suitePath}"
   set activeSuiteRecord [xflow_getActiveSuite]
   set rootNode [${activeSuiteRecord} cget -root_node]

   set PROGRESS_REPORT_TXT "Getting loop node resources ..."
   ::log::log notice "xflow_displayFlow thread id:[thread::id] ${suitePath} getting loop resources"
   xflow_getAllLoopResourcesCallback ${rootNode} ${SEQ_EXP_HOME}
   # resource will only be loaded if needed
   ::log::log notice "xflow_displayFlow thread id:[thread::id] ${suitePath} getting node resources"
   xflow_nodeResourceCallback

   # initial monitor dates
   xflow_populateMonitorDate [xflow_getWidgetName monitor_date_frame]

   if { ${MONITORING_LATEST} == "1" } {
      # the thread id associated to an exp path is mainly used by
      # the xflow_overview... The overview needs it to send signals
      # to the thread that is used to monitor the active exp log.
      # NOT set if in exp history mode
      ::log::log debug "xflow_displayFlow SharedData_setSuiteData ${SEQ_EXP_HOME} THREAD_ID [thread::id]"
      SharedData_setSuiteData ${SEQ_EXP_HOME} THREAD_ID [thread::id]
   }

   if { [SharedData_getMiscData OVERVIEW_MODE] == "true" &&
        ${MONITORING_LATEST} == "0" && ${MONITOR_DATESTAMP} != "" } {
      # we are in overview mode and exp history viewing mode
      # point the suite to the exp history log file
      ${activeSuiteRecord} configure -read_offset 0 -active_log ${MONITOR_DATESTAMP}
      # reset every node... overview is reusing thread in history mode
      ::FlowNodes::resetNodeStatus  [${activeSuiteRecord} cget -root_node]
      # read the content of the log file
      xflow_initStartupMode
      set PROGRESS_REPORT_TXT "Processing log file ..."
      LogReader_readFile ${activeSuiteRecord} ${calling_thread_id}
      xflow_stopStartupMode
      # then show the flow
      xflow_selectSuiteCallback
   } else {
      # normal mode
      if { ${XFLOW_STANDALONE} == "1" && [SharedData_getMiscData OVERVIEW_MODE] == "false" } {
        # in overview mode, the log has already been read once before it reached here,
        # no need to read again... only read for xflow standalone
        xflow_initStartupMode
        set PROGRESS_REPORT_TXT "Processing log file ..."
        LogReader_readFile $activeSuiteRecord $calling_thread_id
        xflow_stopStartupMode
      }
      ::log::log notice "xflow_displayFlow ${suitePath} xflow_selectSuiteCallback()"
      xflow_selectSuiteCallback
   }

   xflow_setTitle ${topFrame} ${suitePath}
   xflow_toFront .
   ::log::log notice "xflow_displayFlow ${suitePath} thread id:[thread::id] done"
   # Console_create

   #if { ${_overview_x} != "" } {
   #   xflow_positionFlowWindow . ${_overview_x} ${_overview_y}
   #}
}

# Position the flow windows relative to the main overview window.
# Only done the first time the flow is launched...Next time reuses the same 
# positioning.
# _toplevel is the toplevel of the current flow
# _overview_x is the x coord of the upper left corner of the overview window
# _overview_y is the y coord of the upper left corner of the overview window
proc xflow_positionFlowWindow { _toplevel _overview_x _overview_y} {
   global XFLOW_INIT_POSITION
   ::log::log debug "xflow_positionFlowWindow _overview_x:$_overview_x _overview_y:$_overview_y"
   #puts "xflow_positionFlowWindow _overview_x:$_overview_x _overview_y:$_overview_y"
   # the XFLOW_POS_COUNTER is shared among all exp threads
   if { ! [info exists XFLOW_INIT_POSITION] } {
      if { [SharedData_getMiscData XFLOW_POS_COUNTER] != "" } {
         set counter [SharedData_getMiscData XFLOW_POS_COUNTER]
         incr counter
         if { ${counter} == 20 } {
            set counter 1
         }
      } else {
         set counter 1
      }
      set XFLOW_INIT_POSITION 1
      SharedData_setMiscData XFLOW_POS_COUNTER ${counter}
      # I'm using the overview main window x and y and the XFLOW_POS_COUNTER to
      # position a window relative to the main window
      set newx [expr ${_overview_x} + ${counter} * 40]
      set newy [expr ${_overview_y} + 200 + ${counter} * 40]
      wm geometry ${_toplevel} +${newx}+${newy}
      #puts "xflow_positionFlowWindow wm geometry ${_toplevel} +${newx}+${newy}"
   }
}

proc xflow_toFront { toplevel_w } {
   
   switch [wm state ${toplevel_w}] {
      withdrawn -
      "iconic" {
         wm deiconify ${toplevel_w}
      }
   }
   raise ${toplevel_w}
}

proc xflow_getMonitoringDatestamp {} {
   global MONITOR_DATESTAMP
   if { ! [info exists MONITOR_DATESTAMP] } {
     set MONITOR_DATESTAMP ""
   }
   return $MONITOR_DATESTAMP
}

proc xflow_getNodeDisplayPref {} {
   global NODE_DISPLAY_PREF
   if { ! [info exists NODE_DISPLAY_PREF] } {
      set NODE_DISPLAY_PREF normal
   }
   return $NODE_DISPLAY_PREF
}

proc xflow_getShawdowStatus {} {
   global SHADOW_STATUS
   if { ! [info exists SHADOW_STATUS] } {
      set SHADOW_STATUS 0
   }
   return $SHADOW_STATUS
}

proc xflow_setTitle { top_w exp_path } {
   global env TITLE_AFTER_ID
   if { [winfo exists ${top_w}] } {
      set current_time [clock format [clock seconds] -format "%H:%M" -gmt 1]
      set winTitle "[file tail ${exp_path}] - Xflow - Exp=${exp_path} User=$env(USER) Host=[exec hostname] Time=${current_time}"
      wm title [winfo toplevel ${top_w}] ${winTitle}

      # refresh title every minute
      set TITLE_AFTER_ID [after 60000 [list xflow_setTitle ${top_w} ${exp_path}]]
   }
}

proc xflow_getMainFlowCanvas {} {
   set flowFrame [xflow_getWidgetName flow_frame]
   set canvasW ${flowFrame}.draw_frame.canvas
   return ${canvasW}
}

proc out {} {
   proc Console_create {} {
      # create console
      set consoleW .expConsole
      toplevel ${consoleW}
      set textF ${consoleW}.textframe 
      set textW ${textF}.textwidget
      ttk::frame ${textF}
      text ${textW}
      pack ${textF} -expand 1 -fill both
      pack ${textW} -expand 1 -fill both
   }
   
   proc Console_insertMessage { msg } {
      set textW .expConsole.textframe.textwidget
      if { [winfo exists ${textW}] } {
         ${textW} insert end "${msg}\n"
      }
   }
}

proc xflow_parseCmdOptions {} {
   global env argv XFLOW_STANDALONE AUTO_MSG_DISPLAY MSG_CENTER_THREAD_ID APP_LOGFILE
   set rcFile ""
   if { [info exists argv] } {
      set options {
         {main ""}
         {logfile.arg "" "App log file"}
         {debug "Turn debug on"}
         {noautomsg ""}
         {rc.arg "" "maestrorc preferrence file"}
      }
      
      set usage "\[options] \noptions:"
      if [ catch { array set params [::cmdline::getoptions argv $options $usage] } message ] {
         puts "\n$message"
         exit 1
      }
      set XFLOW_STANDALONE 0
      if { $params(main) } {
         set XFLOW_STANDALONE 1
      }
      if { $params(noautomsg) } {
         set AUTO_MSG_DISPLAY false
      }
   } else {
      set XFLOW_STANDALONE 0
   }

   # this section is only executed when xflow is run as a standalone application
   if { ${XFLOW_STANDALONE} == 1 } {
      puts "SEQ_XFLOW_BIN=$env(SEQ_XFLOW_BIN)"
      SharedData_init

      if { $params(logfile) != "" } {
         puts "xflow writing to log file: $params(logfile)"
         SharedData_setMiscData APP_LOG_FILE $params(logfile)
         ::log::log notice "xflow Application startup user=$env(USER) host:[exec hostname]"
      } 

      if { $params(debug) } {
         puts "xflow enabling debug trace"
         SharedData_setMiscData DEBUG_TRACE 1
      } 

      if { ! ($params(rc) == "") } {
         puts "xflow using maestrorc file: $params(rc)"
         set rcFile $params(rc)
      }

      SharedData_readProperties ${rcFile}
      xflow_init
      xflow_validateSuite
      xflow_readFlowXml
      xflow_displayFlow [thread::id]
      SharedData_setMiscData STARTUP_DONE true
      SharedData_setMiscData [thread::id]_STARTUP_DONE true
      thread::send -async ${MSG_CENTER_THREAD_ID} "MsgCenterThread_startupDone"
   }

}

proc xflow_getWidgetName { key } {
   global array XflowWidgetNames
   set value ""
   if { [info exists XflowWidgetNames($key)] } {
      set value $XflowWidgetNames($key)
   } else {
      error "xflow_getWidgetName invalid widget key name:${key}"
   }
   return ${value}
}

# adds the name of widgets in an array. The widget names are
# accessible through the xflow_getWidgetName proc with the use
# of the key. I'm only storing name of widgets that are reference
# more than once in the code... Widgets that are created once and
# not referred, don't care
proc xflow_setWidgetNames {} {
   global array XflowWidgetNames
   array set XflowWidgetNames {

      top_frame .top_frame
      second_frame .second_frame
      find_frame .find_frame
      flow_frame .flow_frame
      main_size_grip .size_grip

      exp_label_frame .top_frame.exp_label_frame

      toolbar_frame .second_frame.toolbar
      msgcenter_button .second_frame.toolbar.button_msgcenter
      nodekill_button .second_frame.toolbar.button_nodekill
      catchup_button .second_frame.toolbar.button_catchup
      find_button .second_frame.toolbar.button_find
      refresh_button .second_frame.toolbar.button_refresh
      nodelist_button .second_frame.toolbar.button_nodelist
      abortlist_button .second_frame.toolbar.button_nodeabortlist
      dep_button .second_frame.toolbar.button_dep
      legend_button .second_frame.toolbar.button_colorlegend
      close_button .second_frame.toolbar.button_close
      overview_button .second_frame.toolbar.button_overview
      shell_button .second_frame.toolbar.button_shell
      msg_center_img .second_frame.toolbar.msg_center_img
      msg_center_new_img .second_frame.toolbar.msg_center_new_img

      exp_date_frame  .second_frame.date_frame
      exp_date_entry  .second_frame.date_frame.entry
      exp_date_button_frame .second_frame.date_frame.button_frame
      monitor_date_frame .second_frame.mon_date_frame
      monitor_date_combo .second_frame.mon_date_frame.entry_combo
      monitor_date_combo .second_frame.mon_date_frame.entry_combo
      monitor_date_button_frame .second_frame.mon_date_frame.button_frame
      monitor_date_set_button .second_frame.mon_date_frame.button_frame.set_button

      find_close_button .find_frame.close_button
      find_label .find_frame.entry_label
      find_entry .find_frame.entry_field
      find_next_button .find_frame.next_button
      find_previous_button .find_frame.previous_button
      find_matchcase_check .find_frame.matchcase_check
      find_close_image .find_frame.close_img
      find_next_image .find_frame.next_img
      find_previous_image .find_frame.previous_img
      find_close_image_file cancel_small.png
      find_next_image_file next_down.png
      find_previous_image_file previous_up.png

      bg_image artist-canvas_2.gif
      catchup_toplevel .catchup_top
   }

   if { [SharedData_getMiscData BACKGROUND_IMAGE] != "" } {
      set XflowWidgetNames(bg_image) [SharedData_getMiscData BACKGROUND_IMAGE]
   } else {
      set XflowWidgetNames(bg_image) [SharedData_getMiscData IMAGE_DIR]/artist-canvas_2.gif
   }
}

proc xflow_init {} {
   global env DEBUG_TRACE
   global NODE_DISPLAY_PREF AUTO_MSG_DISPLAY
   global SHADOW_STATUS MONITORING_LATEST
   global MSG_CENTER_THREAD_ID MONITOR_THREAD_ID
   global REFRESH_MODE SESSION_TMPDIR FLOW_SCALE

   set REFRESH_MODE false
   set MONITOR_THREAD_ID ""
   set SHADOW_STATUS 0
   set MONITORING_LATEST 1
   # initate array containg name for widgets used in the application
   SharedData_setMiscData SEQ_BIN [Sequencer_getPath]
   SharedData_setMiscData SEQ_UTILS_BIN [Sequencer_getUtilsPath]
   SharedData_setMiscData IMAGE_DIR $env(SEQ_XFLOW_BIN)/../etc/images

   Utils_logInit
   xflow_setWidgetNames 

   set DEBUG_TRACE [SharedData_getMiscData DEBUG_TRACE]
   set NODE_DISPLAY_PREF  [SharedData_getMiscData NODE_DISPLAY_PREF]
   set MSG_CENTER_THREAD_ID [MsgCenter_getThread]
   SharedData_setMiscData XFLOW_THREAD_ID [thread::id]
   if { ! [info exists AUTO_MSG_DISPLAY] } {
      set AUTO_MSG_DISPLAY [SharedData_getMiscData AUTO_MSG_DISPLAY]
   } else {
      ::log::log debug "xflow_init SharedData_setMiscData AUTO_MSG_DISPLAY ${AUTO_MSG_DISPLAY}"
      SharedData_setMiscData AUTO_MSG_DISPLAY ${AUTO_MSG_DISPLAY}
   }
   set FLOW_SCALE 1
   if { [SharedData_getMiscData FLOW_SCALE] != "" } {
      set FLOW_SCALE [SharedData_getMiscData FLOW_SCALE]
   }

   setErrorMessages

   xflow_setTkOptions

   keynav::enableMnemonics .
   wm protocol . WM_DELETE_WINDOW xflow_quit

   xflow_createTmpDir
}

# creates a tmp dir for listings, text files
proc xflow_createTmpDir {} {
   global env SESSION_TMPDIR

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
      ::log::log debug "xflow_createTmpDir deleting ${myTmpDir}"
      file delete -force ${myTmpDir}
   }
   ::log::log debug "xflow_createTmpDir creating ${myTmpDir}"
   file mkdir ${myTmpDir}
   set SESSION_TMPDIR ${myTmpDir}
}

global XFLOW_STANDALONE

xflow_parseCmdOptions

# trace the variable to see if we need to load the resources
trace add variable NODE_DISPLAY_PREF write xflow_nodeResourceCallback
