#set auto_path [linsert $auto_path 0 /home/ordenv/ssm-domains/ssm-setup-1.0-ops/xflow_1.0_all/lib]
#set auto_path [linsert $auto_path 0 [exec pwd]]
#package require Tk
#package require tile
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
proc xflow_setTkOptions {} {
   option add *activeBackground [SharedData_getColor ACTIVE_BG]
   option add *selectBackground [SharedData_getColor SELECT_BG]
   catch { option add *troughColor [::tk::Darken [option get . background Scrollbar] 85] }

   # ttk::style configure Xflow.Menu -background cornsilk4
}

proc xflow_addFileMenu { exp_path datestamp parent } {
   if { $parent == "." } {
      set parent ""
   }
   set menuButtonW ${parent}.menub
   set menuW $menuButtonW.menu

   menubutton $menuButtonW -text File -underline 0 -menu $menuW \
      -relief [SharedData_getMiscData MENU_RELIEF]
   menu $menuW -tearoff 0

   $menuW add command -label "Quit" -underline 0 -command "xflow_quit ${exp_path} \"${datestamp}\"" 

   pack $menuButtonW -side left -pady 2 -padx 2
   tooltip::tooltip $menuW -index "Quit" "test tooltip"
}

proc xflow_addViewMenu { exp_path datestamp parent } {
   global AUTO_MSG_DISPLAY SUBMIT_POPUP COLLAPSE_DISABLED_NODES FLOW_SCALE_${exp_path}_${datestamp}
   global MSG_CENTER_FOCUS_GRAB

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

      $menuW add checkbutton -label "Submit Popup" -variable SUBMIT_POPUP \
         -command [list xflow_setSubmitPopup] \
         -onvalue true -offvalue false

      $menuW add checkbutton -label "Collapse Catchup State Nodes" -variable COLLAPSE_DISABLED_NODES \
      -onvalue true -offvalue false

   }

   $menuW add checkbutton -label "Show Shadow Status" -variable SHADOW_STATUS \
      -onvalue 1 -offvalue 0 -command [list xflow_redrawAllFlow ${exp_path} ${datestamp}]

   $menuW add checkbutton -label "Focus grab" -variable MSG_CENTER_FOCUS_GRAB \
      -command [list xflow_setMsgfocusgrab] \
      -onvalue true -offvalue false 

   set displayMenu $menuW.displayMenu

   $menuW add cascade -label "Node Display" -underline 5 -menu ${displayMenu}
   menu ${displayMenu} -tearoff 0
   foreach item "normal catchup cpu machine_queue memory mpi wallclock" { 
      set value ${item}
      ${displayMenu} add radiobutton -label ${item} -variable NODE_DISPLAY_PREF -value ${value} \
         -command [list xflow_redrawAllFlow ${exp_path} ${datestamp}]
   }

   ${displayMenu} add separator

   set itemList [list "Execution Time" "Begin Time" "End Time" "Submission Delay" "Delta Time From Start" "Relative Progress" "Relative Execution Time"]
   foreach item ${itemList} {
      set value ${item}
      ${displayMenu} add radiobutton -label ${item} -variable NODE_DISPLAY_PREF -value ${value} \
         -command [list xflow_redrawAllFlow ${exp_path} ${datestamp}]
   }

   set scaleMenu $menuW.scaleMenu
   $menuW add cascade -label "Flow Scale" -underline 5 -menu ${scaleMenu}
   menu ${scaleMenu} -tearoff 0
   ${scaleMenu} add radiobutton -label "scale-normal" -variable FLOW_SCALE_${exp_path}_${datestamp} -value 1 \
      -command [list xflow_redrawAllFlow ${exp_path} ${datestamp}]
   ${scaleMenu} add radiobutton -label "scale-2" -variable FLOW_SCALE_${exp_path}_${datestamp} -value 2 \
      -command [list xflow_redrawAllFlow ${exp_path} ${datestamp}]

   pack $menuButtonW -side left -pady 2 -padx 2
}

proc xflow_addHelpMenu { exp_path datestamp parent } {
   if { $parent == "." } {
      set parent ""
   }
   set menuButtonW ${parent}.helpb
   set menuW $menuButtonW.menu

   menubutton $menuButtonW -text Help -underline 0 -menu $menuW  \
      -relief [SharedData_getMiscData MENU_RELIEF]
   menu $menuW -tearoff 0

   $menuW add command -label "Experiment Support" -underline 11 -command [list ExpOptions_showSupportCallback ${exp_path} ${datestamp} [xflow_getToplevel ${exp_path} ${datestamp}]]
   $menuW add command -label "Maestro Commands" -underline 8 -command "xflow_maestroCmds ${parent}"
   $menuW add command -label "About" -underline 0 -command "About_show ${parent}"

   pack $menuButtonW -side left -pady 2 -padx 2
}

proc xflow_showSupportCallback { exp_path datestamp } {

   set hour ""
   if { ${datestamp} != "" } {
      set hour [Utils_getHourFromDatestamp ${datestamp}]
   }
   ExpOptions_showSupport ${exp_path} ${hour} [xflow_getWidgetName ${exp_path} ${datestamp} top_frame]
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
         set infoTxt [exec -ignorestderr  cat ${infoFile}]
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

proc xflow_createPluginToolbar { exp_path datestamp _toplevelW } {
    set pluginEnv "export SEQ_EXP_HOME=${exp_path}; export SEQ_DATE=${datestamp}"
    return [Utils_createPluginToolbar "xflow" ${_toplevelW} ${pluginEnv}]
}   

proc xflow_createToolbar { exp_path datestamp parent } {
   global CHECK_PERMISSION

   ::log::log debug "xflow_createToolbar exp_path:${exp_path} datestamp:${datestamp} parent:${parent} "

   set msgCenterW [xflow_getWidgetName ${exp_path} ${datestamp} msgcenter_button]
   set nodeKillW [xflow_getWidgetName ${exp_path} ${datestamp} nodekill_button]
   set catchupW [xflow_getWidgetName ${exp_path} ${datestamp} catchup_button]
   set findW [xflow_getWidgetName ${exp_path} ${datestamp} find_button]
   set refreshW [xflow_getWidgetName ${exp_path} ${datestamp} refresh_button]
   set trashW   [xflow_getWidgetName ${exp_path} ${datestamp} trash_button]
   set dkfontW  [xflow_getWidgetName ${exp_path} ${datestamp} dkfont_button]
   set colorLegendW [xflow_getWidgetName ${exp_path} ${datestamp} legend_button]
   set closeW [xflow_getWidgetName ${exp_path} ${datestamp} close_button]
   #set depW [xflow_getWidgetName dep_button]
   set shellW [xflow_getWidgetName ${exp_path} ${datestamp} shell_button]
   set catchupTopW [xflow_getWidgetName ${exp_path} ${datestamp} catchup_toplevel]
   set pluginFrame [xflow_createPluginToolbar ${exp_path} ${datestamp} ${parent}]

   set imageDir [SharedData_getMiscData IMAGE_DIR]

   set noNewMsgImage [xflow_getWidgetName ${exp_path} ${datestamp} msg_center_img]
   set hasNewMsgImage [xflow_getWidgetName ${exp_path} ${datestamp} msg_center_new_img]
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
   image create photo ${parent}.trash -file ${imageDir}/trash.gif
   image create photo ${parent}.dkfont -file ${imageDir}/font.gif
   #image create photo ${parent}.ignore_dep_false -file ${imageDir}/dep_off.ppm
   image create photo ${parent}.shell_img -file ${imageDir}/terminal.ppm

   button ${msgCenterW} -padx 0 -pady 0 -image ${noNewMsgImage} -command [list MsgCenter_show true] -relief flat
   ::tooltip::tooltip ${msgCenterW} "Show Message Center."

   button ${nodeKillW} -image ${parent}.node_kill_img -command [list xflow_nodeKillDisplay ${exp_path} ${datestamp} ${parent} ] -relief flat
   tooltip::tooltip ${nodeKillW}  "Open job killing dialog"

   button ${catchupW} -image ${parent}.catchup_img -command [list Catchup_createMainWidgets ${exp_path} ${catchupTopW} [winfo toplevel ${parent}]] -relief flat
   tooltip::tooltip ${catchupW}  "Open exp catchup window"

   button ${shellW} -image ${parent}.shell_img -command [list xflow_launchShellCallback ${exp_path}] -relief flat
   tooltip::tooltip ${shellW}  "Start shell at exp home"

   button ${findW} -image ${parent}.find_img -relief flat -command [list xflow_showFindWidgets ${exp_path} ${datestamp}]
   tooltip::tooltip ${findW}  "Find a node."

   button ${refreshW} -image ${parent}.refresh_img -relief flat -command [list xflow_refreshFlow ${exp_path} ${datestamp}]
   tooltip::tooltip ${refreshW}  "Flow refresh."
   
   button ${trashW} -image ${parent}.trash -relief flat -command  [list Trash_init ${exp_path} ${datestamp}]
   tooltip::tooltip ${trashW}  "Clean Experiment."

   button ${dkfontW} -image ${parent}.dkfont -relief flat -command  [list DkfFont_init ${exp_path} ${datestamp}]
   tooltip::tooltip ${dkfontW}  "Select Font."

   #button ${nodeListW} -image ${parent}.node_list_img  -state disabled -relief flat
   #tooltip::tooltip ${nodeListW} "Open succesfull node listing dialog -- future feature."

   #button ${nodeAbortListW} -image ${parent}.node_abort_list_img -state disabled -relief flat
   #tooltip::tooltip ${nodeAbortListW} "Open abort node listing dialog -- future feature."

   button ${closeW} -image ${parent}.close -command [list xflow_quit ${exp_path} ${datestamp}] -relief flat
   ::tooltip::tooltip ${closeW} "Close application."

   button ${colorLegendW} -image ${parent}.color_legend_img -command [list xflow_showColorLegend ${colorLegendW}] -relief flat
   tooltip::tooltip ${colorLegendW} "Show color legend." 

   #button ${depW} -relief flat -image ${parent}.ignore_dep_false -command [list xflow_changeIgnoreDep ${depW} ${parent}.ignore_dep_true ${parent}.ignore_dep_false] -state disabled

   if { [SharedData_getMiscData OVERVIEW_MODE] == "true" } {
      set overviewW [xflow_getWidgetName ${exp_path} ${datestamp} overview_button]
      image create photo ${parent}.overview -file ${imageDir}/calendar_clock.gif
      button ${overviewW} -relief flat -image ${parent}.overview -command {
         Overview_toFront
      }
      ::tooltip::tooltip ${overviewW} "Show overview window."
      ::tooltip::tooltip ${closeW} "Close window."
      
      if {$CHECK_PERMISSION == "true"} {
        grid ${msgCenterW} ${overviewW} ${nodeKillW} ${catchupW} ${shellW} ${findW} ${refreshW} ${trashW} ${dkfontW} ${colorLegendW} ${closeW} ${pluginFrame} -sticky w -padx 2
      } else {
        grid ${msgCenterW} ${overviewW} ${nodeKillW} ${catchupW} ${shellW} ${findW} ${refreshW} ${dkfontW} ${colorLegendW} ${closeW} ${pluginFrame} -sticky w -padx 2
      }
   } else {
      if {$CHECK_PERMISSION == "true"} {
          grid ${msgCenterW} ${nodeKillW} ${catchupW} ${shellW} ${findW} ${refreshW} ${trashW} ${dkfontW} ${colorLegendW} ${closeW} ${pluginFrame} -sticky w -padx 2
       } else {
          grid ${msgCenterW} ${nodeKillW} ${catchupW} ${shellW} ${findW} ${refreshW} ${dkfontW} ${colorLegendW} ${closeW} ${pluginFrame} -sticky w -padx 2
       }
   }

}

proc xflow_showColorLegend { caller_w } {
   set topW .color_legend
   if { [winfo exists ${topW}] } {
      wm withdraw ${topW} ; wm deiconify ${topW}
      Utils_positionWindow ${topW} ${caller_w}
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

proc xflow_newDatestampFound { exp_path datestamp } {
   set currentDatestamp [LogReader_getSingleDatestamp ${exp_path}]
   set newDatestampLaunch [SharedData_getMiscData XFLOW_NEW_DATESTAMP_LAUNCH]

   if { ${currentDatestamp} != "" && ${newDatestampLaunch} == "main" } {
      set topLevelW [xflow_getToplevel ${exp_path} ${currentDatestamp}]
      Utils_busyCursor ${topLevelW}
      xflow_closeExpDatestamp ${exp_path} ${currentDatestamp}
   }
   set topLevelW [xflow_getToplevel ${exp_path} ${datestamp}]
   Utils_busyCursor ${topLevelW}
   SharedData_setExpThreadId ${exp_path} ${datestamp} [thread::id]
   LogReader_startExpLogReader ${exp_path} ${datestamp} all false
   xflow_displayFlow ${exp_path} ${datestamp} true
   Utils_normalCursor ${topLevelW}
}
# this function creates the widgets that allows
# the user to set/query the current datestamp
proc xflow_addMsgCenterWidget { exp_path datestamp} {
   # puts "xflow_addMsgCenterWidget $exp_path $datestamp"
   set msgFrame [xflow_getWidgetName ${exp_path} ${datestamp} exp_msg_frame]
   set color    [SharedData_getColor COLOR_MSG_CENTER_MAIN]
  
   set labelFrame   [xflow_getWidgetName ${exp_path} ${datestamp} exp_msglabel_frame]
   set expName      [SharedData_getExpShortName ${exp_path}]
   set refStartTime [Overview_getRefTimings ${exp_path} [Utils_getHourFromDatestamp ${datestamp}] start]
   if { ${expName} != "" && ${refStartTime} != "" } {
     set labeltext "${expName}-[Utils_getHourFromDatestamp ${datestamp}]"
   } elseif {${expName} == "" && ${refStartTime} != ""} {
     set expName [SharedData_getExpDisplayName ${exp_path}]
     set labeltext "${expName}-[Utils_getHourFromDatestamp ${datestamp}]"
   } else {
     set labeltext "${expName}"
   }

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
      foreach widget [list $label_abortW $label_eventW $label_infoW $label_sysinfoW] {
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
   }

   ${msgFrame} configure -text "${labeltext} active message count"
   tooltip::tooltip ${msgFrame} "${labeltext} selected experiment has the following active (unacknowledged) messages"

   set newMsgColor   [SharedData_getColor COLOR_MSG_CENTER_MAIN]
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

   eval grid $label_abortW ${label_eventW} ${label_infoW} ${label_sysinfoW} -sticky w -padx \[list 2 0\] 
   #set labelW [label ${labelFrame}.info -justify center -text ${tooltipText} ]
   #pack $labelW -side left -pady 2 -padx 2
   pack $labelFrame -pady 2 -side left
   grid ${msgFrame} -row  0 -column 4 -sticky nsew -padx 2 -pady 0 -ipadx 2
}
# this function creates the widgets that allows
# the user to set/query the current datestamp
proc xflow_addDatestampWidget { exp_path datestamp parent_widget } {
   set dtFrame ${parent_widget}
   set dateEntryCombo [xflow_getWidgetName ${exp_path} ${datestamp}  exp_date_entry]
   set buttonFrame [xflow_getWidgetName ${exp_path} ${datestamp} exp_date_button_frame]

   set displayFormat [Utils_getDatestampFormat [SharedData_getMiscData DATESTAMP_VISIBLE_LEN] "display"]
   labelframe ${dtFrame} -text "Exp Datestamp (${displayFormat})"
   tooltip::tooltip ${dtFrame} "Current Datestamp"

   ttk::combobox ${dateEntryCombo}

   set hiddenDate [xflow_getWidgetName ${exp_path} ${datestamp} exp_date_hidden]
   label ${hiddenDate}

   frame ${buttonFrame}

   set imageDir [SharedData_getMiscData IMAGE_DIR]
   image create photo ${buttonFrame}.set_image -file ${imageDir}/ok.gif
   image create photo ${buttonFrame}.refresh_image -file ${imageDir}/refresh.gif
   image create photo ${buttonFrame}.new_win_image -file ${imageDir}/new_window.png

   set setButton [button ${buttonFrame}.set_button -relief flat -image ${buttonFrame}.set_image \
      -command [list xflow_setDatestampCallback ${exp_path} ${datestamp} ${dtFrame}]]
   tooltip::tooltip ${setButton} "Sets new datestamp value."

   set refreshButton [button ${buttonFrame}.refresh_button -relief flat -image ${buttonFrame}.refresh_image \
      -command [list xflow_populateDatestamp ${exp_path} ${datestamp} ${dtFrame}]]
   tooltip::tooltip $refreshButton "Reloads the current experiment datestamp value."

   set newWindButton [button ${buttonFrame}.new_win_button -relief flat -image ${buttonFrame}.new_win_image \
      -command [list xflow_launchFlowNewWindow ${exp_path} ${datestamp} ]]
   tooltip::tooltip ${newWindButton} "Launch flow in new window."
   pack $setButton $refreshButton ${newWindButton} -side left -pady 2 -padx 2

   pack ${dateEntryCombo} -side left -pady 2 -padx 2
   pack $buttonFrame -pady 2 -side left
}

# creates the widget for the find node functionality
proc xflow_createFindWidgets { _exp_path _datestamp _parent_widget } {
   global FIND_MATCH_CASE
   set findLabel [xflow_getWidgetName ${_exp_path} ${_datestamp} find_label]
   set findEntry [xflow_getWidgetName ${_exp_path} ${_datestamp} find_entry]
   set findCloseB [xflow_getWidgetName ${_exp_path} ${_datestamp} find_close_button]
   set findNextB [xflow_getWidgetName ${_exp_path} ${_datestamp} find_next_button]
   set findPreviousB [xflow_getWidgetName ${_exp_path} ${_datestamp} find_previous_button]
   set findCloseImg [xflow_getWidgetName ${_exp_path} ${_datestamp} find_close_image]
   set findNextImg [xflow_getWidgetName ${_exp_path} ${_datestamp} find_next_image]
   set findPreviousImg [xflow_getWidgetName ${_exp_path} ${_datestamp} find_previous_image]
   set findCaseCheck [xflow_getWidgetName ${_exp_path} ${_datestamp} find_matchcase_check]
   Label ${findLabel} -text "Find:"
   Entry ${findEntry} -width 25
   bind ${findEntry} <Return> [list xflow_findCallback ${_exp_path} ${_datestamp} ${findEntry} next]

   set imageDir [SharedData_getMiscData IMAGE_DIR]
   image create photo ${findNextImg} -file [SharedData_getMiscData IMAGE_DIR]/[xflow_getImageFile find_next_image_file]
   image create photo ${findPreviousImg} -file [SharedData_getMiscData IMAGE_DIR]/[xflow_getImageFile find_previous_image_file]
   image create photo ${findCloseImg} -file [SharedData_getMiscData IMAGE_DIR]/[xflow_getImageFile find_close_image_file]

   Button ${findCloseB} -image ${findCloseImg} -relief flat
   Button ${findNextB} -image ${findNextImg} -relief flat -text Next -compound left -underline 0  -command [list xflow_findCallback ${_exp_path} ${_datestamp} ${findEntry} next]
   Button ${findPreviousB} -image ${findPreviousImg} -relief flat -text Previous -compound left -underline 0  -command [list xflow_findCallback ${_exp_path} ${_datestamp} ${findEntry} previous]
   checkbutton ${findCaseCheck} -text "Match case" -indicatoron true -variable FIND_MATCH_CASE \
      -command {
         # reset the search everytime the case is changed
         set XFLOW_FIND_TEXT ""
      }

   set FIND_MATCH_CASE 0
   set topLevelW [xflow_getToplevel ${_exp_path} ${_datestamp}]
   bind ${topLevelW} <Control-Key-f> [list xflow_showFindWidgets ${_exp_path} ${_datestamp}]
   bind ${topLevelW} <Key-F3> [list xflow_findCallback ${_exp_path} ${_datestamp} ${findEntry} next]
   bind ${topLevelW} <Shift-Key-F3> [list xflow_findCallback ${_exp_path} ${_datestamp} ${findEntry} previous]
   pack ${findCloseB} ${findLabel} ${findEntry} ${findNextB} ${findPreviousB} ${findCaseCheck} -side left -padx 2 -pady 2
}

# this is call whenever the user hits on next or previous on the find 
proc xflow_findCallback { _exp_path _datestamp _entry_w _next_or_previous } {
   global XFLOW_FIND_TEXT XFLOW_FIND_RESULTS XFLOW_FIND_INDEX XFLOW_FIND_AFTER_ID_${_exp_path}_${_datestamp}
   global FIND_MATCH_CASE NodeHighLightRestoreCmd_${_exp_path}_${_datestamp}
   ::log::log debug "xflow_findCallback _entry_w:${_entry_w} _next_or_previous:${_next_or_previous}"
   set findFrame [xflow_getWidgetName ${_exp_path} ${_datestamp} find_frame]
   if { [grid info ${findFrame}] == "" } {
      # the find window is close, do nothing
      return
   }

   if { ! [info exists XFLOW_FIND_TEXT] } {
      set XFLOW_FIND_TEXT ""
   }
   if { [info exists XFLOW_FIND_AFTER_ID_${_exp_path}_${_datestamp}] } {
      after cancel [set XFLOW_FIND_AFTER_ID_${_exp_path}_${_datestamp}]
      eval [set NodeHighLightRestoreCmd_${_exp_path}_${_datestamp}]
   }

   set findText [${_entry_w} cget -text]
   if { ${findText} == "" } {
      return
   }
   if { ${findText} != ${XFLOW_FIND_TEXT} } {
      # new find
      set XFLOW_FIND_TEXT ${findText}
      set XFLOW_FIND_RESULTS {}
      set rootNode [SharedData_getExpRootNode ${_exp_path} ${_datestamp}]
      SharedFlowNode_findNodes ${_exp_path} ${rootNode} ${_datestamp} ${findText} ${FIND_MATCH_CASE} XFLOW_FIND_RESULTS
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
      set mainFlowCanvas [xflow_getMainFlowCanvas ${_exp_path} ${_datestamp}]
      # if the node is collapsed, uncollapse it
      if { [SharedFlowNode_uncollapseBranch ${_exp_path} ${foundNode} ${_datestamp}] != "" } {
         xflow_drawflow ${_exp_path} ${_datestamp} ${mainFlowCanvas} false
      }

      set foundTag [::DrawUtils::highLightFindNode ${_exp_path} ${_datestamp} ${foundNode} ${mainFlowCanvas}]
      # make sure the node is visible
      ::DrawUtils::viewCanvasItem [xflow_getMainFlowCanvas ${_exp_path} ${_datestamp}] ${foundTag}

      set XFLOW_FIND_AFTER_ID_${_exp_path}_${_datestamp} [after 5000 eval [set NodeHighLightRestoreCmd_${_exp_path}_${_datestamp}]]
   }
}

proc xflow_showFindWidgets { exp_path datestamp } {
   set findFrame [xflow_getWidgetName ${exp_path} ${datestamp} find_frame]
   set findEntry [xflow_getWidgetName ${exp_path} ${datestamp} find_entry]
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

# this function is only called in xflow standalone mode.
# It propagates the Auto Message Display configuration. Alghouh this configuration
# is already global for the xflow thread, it is also used by the message center so it needs to go through the
# SharedData so that the msg center thread can fetch it.
proc xflow_setMsgfocusgrab {} {
   global MSG_CENTER_FOCUS_GRAB
   ::log::log debug "xflow_setMsgfocusgrab MSG_FOCUS_GRAB new value: ${MSG_CENTER_FOCUS_GRAB}"
   SharedData_setMiscData MSG_CENTER_FOCUS_GRAB ${MSG_CENTER_FOCUS_GRAB}
}

# this function is only called in xflow standalone mode.
# It propagates the Output Display configuration
proc xflow_setSubmitPopup {} {
   global SUBMIT_POPUP
   ::log::log debug "xflow_setSubmitPopup SUBMIT_POPUP new value: ${SUBMIT_POPUP}"
   SharedData_setMiscData SUBMIT_POPUP ${SUBMIT_POPUP}
}

# this function creates the widgets for the node kill window
# that is invoked from the xflow toolbar
#
#
proc xflow_nodeKillDisplay { exp_path datestamp parent_w } {

   global env
   set shadowColor [SharedData_getColor SHADOW_COLOR]
   set bgColor [SharedData_getColor CANVAS_COLOR]

   ##set fullList [list showAllListings $node $type $canvas $canvas.list]
   if { $parent_w == "" } {
      set parent_w "."
   }

   set soloWindow $parent_w.nodekill 

   if { [winfo exists $soloWindow] } {
        destroy $soloWindow
    }

   toplevel $soloWindow
   set winTitle "Kill Nodes - Exp=${exp_path}"
   wm title ${soloWindow} ${winTitle}
   wm geometry ${soloWindow} +[winfo pointerx ${parent_w}]+[winfo pointery ${parent_w}]
   
   frame $soloWindow.frame -relief raised -bd 2 -bg $bgColor
   pack $soloWindow.frame -fill both -expand 1 
   set listboxW [ listbox $soloWindow.list -yscrollcommand "$soloWindow.yscroll set" \
	  -xscrollcommand "$soloWindow.xscroll set"  \
	  -height 10 -width 70 -selectmode extended -bg $bgColor -fg $shadowColor]
   scrollbar $soloWindow.yscroll -command "$soloWindow.list yview"  -bg $bgColor
   scrollbar $soloWindow.xscroll -command "$soloWindow.list xview" -orient horizontal -bg $bgColor

   ::autoscroll::autoscroll ${soloWindow}.yscroll
   ::autoscroll::autoscroll ${soloWindow}.xscroll

   set cancelButton [button $soloWindow.cancel_button -text "Close" \
      -command [list destroy $soloWindow ]]
   tooltip::tooltip $cancelButton "Close this window"
   pack $cancelButton -side right -padx 4 -pady 2

   set refreshButton [button $soloWindow.refresh_button -text "Refresh" \
      -command [list xflow_populateKillAllNodeListbox ${exp_path} ${datestamp} ${listboxW}]]
   tooltip::tooltip $refreshButton "Refresh entries"
   pack $refreshButton -side right -padx 2 -pady 2

   set killButton [button $soloWindow.kill_button -text "Kill Selected Jobs" \
      -command [list xflow_killNode ${exp_path} ${datestamp} "" $soloWindow.list ]]
   tooltip::tooltip $killButton "Send kill signals to selected job_ID"
   pack $killButton -side right -pady 2

   pack $soloWindow.xscroll -fill x -side bottom -in $soloWindow.frame
   pack $soloWindow.yscroll -side right -fill y -in $soloWindow.frame
   pack $soloWindow.list -expand 1 -fill both -padx 1m -side left -in $soloWindow.frame

   xflow_populateKillAllNodeListbox ${exp_path} ${datestamp} ${listboxW}
}

proc xflow_populateKillAllNodeListbox { exp_path datestamp listbox_w } {
   global env
   set id [clock seconds]
   set tmpdir $env(TMPDIR)
   set tmpfile "${tmpdir}/test$id"
   set killPath nodekill 
   set cmd "export SEQ_EXP_HOME=${exp_path}; $killPath -listall -d ${datestamp} > $tmpfile 2>&1"
   ::log::log debug "xflow_nodeKillDisplay ksh -c $cmd"
   catch { eval [exec -ignorestderr ksh -c $cmd ] }

   set resultingFile [open $tmpfile] 

   ${listbox_w} delete 0 end

   set separator "->"
   set dateseparator "@" 
   while { [gets $resultingFile line ] >= 0 } {
      set listEntryValue [ split ${line} " " ]
      set separatorIndex [lsearch ${listEntryValue} ${separator}]
      if { ${separatorIndex} != -1 } {
	      set dateIndex [expr ${separatorIndex} -3]
         set nodeIndex [expr ${separatorIndex} -1]
         set cellIndex [expr ${separatorIndex} +1]
         set nodeLeafIndex [expr ${separatorIndex} +2]
         set nodeBase [string trimleft [file dirname [lindex ${listEntryValue} ${nodeIndex}]] . ]
         set date "[lrange ${listEntryValue} ${dateIndex} [expr ${dateIndex} + 1]]"
         set nodeFullPath ${nodeBase}/[string trimleft [lindex  ${listEntryValue} ${nodeLeafIndex}] $dateseparator]
         set jobAndCell "[lindex [split [lindex ${listEntryValue} ${nodeIndex}] $dateseparator] 1] -> [lindex ${listEntryValue} ${cellIndex}]"

         ${listbox_w} insert end "${date} ${nodeFullPath} ${jobAndCell}"
      }
   }

   catch {[exec -ignorestderr rm -f $tmpfile]}
}

# this function retrieves the selected entries from
# the node kill window and attempts to kill the running
# jobs by invoking the maestro-utils nodekill executable.
proc xflow_killNode { exp_path datestamp node list_widget } {

   ::log::log debug "xflow_killNode  exp_path:${exp_path} datestamp:${datestamp} widget:${list_widget}"
   Utils_busyCursor [winfo toplevel ${list_widget}]
   set result [ catch {

      set indexlist [ $list_widget curselection ]
      ::log::log debug "xflow_killNode list_widget:$list_widget indexlist:$indexlist"
      set listOfNodes ""
      for {set iterator 0} {$iterator < [llength $indexlist]} {incr iterator} {
         set listOfNodes [ linsert $listOfNodes end [ $list_widget get [ lindex $indexlist $iterator ]]]
      }
      set seqExec nodekill
      set numOfEntries [llength $listOfNodes]

      set separator "->"
      set dateseparator "@" 

      for {set iterator 0} {$iterator < $numOfEntries} {incr iterator} {
         set foundId false
         set listEntryValue [ split [ lindex $listOfNodes $iterator ] " " ]
         set separatorIndex [lsearch ${listEntryValue} ${separator}]
         if { ${separatorIndex} != -1 } {
	         set killNode ${node}
            set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${killNode} ${datestamp}]

            if { ${node} == "" } {
	          # called from kill nodes... node must be fetched from listbox entry
               set killNode [lindex $listEntryValue [expr ${separatorIndex} - 2]]
               if { [string first . ${killNode}] != -1 } {
                  set killNode [string range ${killNode} 0 [expr [string first . ${killNode}] -1]]
      	      }
	            set seqNode ${killNode}
	         }
            set nodeID [lindex $listEntryValue [expr ${separatorIndex} - 1]]
	         set foundId true
            ::log::log debug "xflow_killNode command: $seqExec  -n $seqNode -job_id $nodeID"
            set winTitle "Node Kill ${seqNode} ID=${nodeID} Exp=${exp_path}"
           set commandArgs "-n ${seqNode} -job_id $nodeID"
           ::log::log notice "${seqExec} ${commandArgs}"
           Sequencer_runCommandWithWindow ${exp_path} ${datestamp} [xflow_getToplevel ${exp_path} ${datestamp}] $seqExec ${winTitle} top 1 ${commandArgs}
         }
         if { ${foundId} == false } {
            Utils_raiseError [winfo toplevel ${list_widget}] "Kill Node" "Application Error: Unable to retrieve Task Id."
         }
      }
      Utils_normalCursor [winfo toplevel ${list_widget}]

   } message ]

   # any errors, put the cursor back to normal state
   if { ${result} != 0  } {

      set einfo $::errorInfo
      set ecode $::errorCode
      Utils_normalCursor [winfo toplevel ${list_widget}]
      # report the error with original details
      return -code ${result} \
         -errorcode ${ecode} \
         -errorinfo ${einfo} \
         ${message}
   }
}

proc xflow_populateDatestamp { exp_path datestamp date_frame } {

   set dateList [LogReader_getAvailableDates ${exp_path}]
   set dateEntryCombo [xflow_getWidgetName ${exp_path} ${datestamp} exp_date_entry]
 
   set visibleLen [SharedData_getMiscData DATESTAMP_VISIBLE_LEN]
   set values ""
   foreach date $dateList {
      set values "$values [Utils_getVisibleDatestampValue ${date} ${visibleLen}]"
   }
   ${dateEntryCombo} configure -values $values 
   ${dateEntryCombo} set [Utils_getVisibleDatestampValue ${datestamp} ${visibleLen}]
}

proc xflow_launchFlowNewWindow { exp_path datestamp } {
   ::log::log debug "xflow_launchFlowNewWindow exp_path:$exp_path datestamp:$datestamp"
   set dateEntryCombo [xflow_getWidgetName ${exp_path} ${datestamp} exp_date_entry]
   set hiddenDateWidget [xflow_getWidgetName ${exp_path} ${datestamp} exp_date_hidden]
   set datestampEntryValue [${dateEntryCombo} get]   
   set top [winfo toplevel ${dateEntryCombo}]
   set seqDatestamp [Utils_getRealDatestampValue ${datestampEntryValue}]
   set currentWidth  [winfo width ${top}]
   set currentHeight  [winfo height ${top}]
   # do nothing if selected value is empty or is already current flow
   if { ${datestampEntryValue} != "" && ${seqDatestamp} != ${datestamp} } {
      SharedData_setExpFlowSize ${exp_path} ${seqDatestamp} ${currentWidth}x${currentHeight}
      set newTop [xflow_getToplevel ${exp_path} ${seqDatestamp}]
      if { [SharedData_getMiscData OVERVIEW_MODE] == true } {
         Overview_launchExpFlow ${exp_path} ${seqDatestamp}
      } else {
         xflow_newDatestampFound ${exp_path} ${seqDatestamp}
      }
      # set new window size to current one
      after 25 [list wm geometry ${newTop} =${currentWidth}x${currentHeight}]

      if { [SharedData_getMiscData XFLOW_NEW_DATESTAMP_LAUNCH] == "new" } {
         # reset to existing value in current flow
         ${dateEntryCombo} set [Utils_getVisibleDatestampValue ${datestamp} [SharedData_getMiscData DATESTAMP_VISIBLE_LEN]]
      }
   }

}


proc xflow_readFlowXml { exp_path datestamp } {
   ::log::log debug "xflow_readFlowXml exp_path:${exp_path}"
   FlowXml_parse ${exp_path}/EntryModule/flow.xml ${exp_path} ${datestamp} ""
}

# saves initial value of datestamp in datestamp widget
proc xflow_initDatestampEntry { exp_path datestamp } {
   set dateEntry [xflow_getWidgetName ${exp_path} ${datestamp} exp_date_entry]
   set hiddenDate [xflow_getWidgetName ${exp_path} ${datestamp} exp_date_hidden]
   $dateEntry set [Utils_getVisibleDatestampValue ${datestamp} [SharedData_getMiscData DATESTAMP_VISIBLE_LEN]]
   ${hiddenDate} configure -text [Utils_getVisibleDatestampValue ${datestamp} [SharedData_getMiscData DATESTAMP_VISIBLE_LEN]]
}

# this function is called when the user sets a new datestamp in the
# "Exp Datestamp" field. 
# - Resets flow node status
# - redraw the flow
proc xflow_setDatestampCallback { exp_path datestamp parent_w } {
   ::log::log debug "xflow_setDatestampCallback exp_path:$exp_path datestamp:$exp_path parent_w:$parent_w"
   set top [winfo toplevel $parent_w]

   set dateEntry [xflow_getWidgetName ${exp_path} ${datestamp} exp_date_entry]
   set dateEntryCombo [xflow_getWidgetName ${exp_path} ${datestamp} exp_date_entry]

   set newDatestamp [${dateEntryCombo} get]

   set visibleDatestampLen [SharedData_getMiscData DATESTAMP_VISIBLE_LEN]
   if { [Utils_validateVisibleDatestamp ${newDatestamp} ${visibleDatestampLen} ] == false } {
      tk_messageBox -title "Datestamp Error" -parent ${parent_w} -type ok -icon error \
         -message "Invalid datestamp value: ${newDatestamp}. Format must be [Utils_getDatestampFormat ${visibleDatestampLen} display]."
      return
   }

   set values [${dateEntryCombo} cget -values]
   # ask for a confirmation if the date is in the future and the date is set for the first time by the user.
   if { [lsearch -exact ${values} ${newDatestamp}] == -1 && 
        [clock scan ${newDatestamp} -format [Utils_getDatestampFormat ${visibleDatestampLen} "scan"]] >= [clock scan tomorrow] } {

      set answer [tk_messageBox -title "Datestamp Confirmation" -parent ${parent_w} -type okcancel -icon question \
         -message "The entered datestamp is beyond today's date, are you sure you want to set the date?" ]
      if { ${answer} == "cancel" } {
         return
      }
   }

   Utils_busyCursor $top
   # create log file is not exists
   set seqDatestamp [Utils_getRealDatestampValue ${newDatestamp}]

   # keep the new window the same size as the current one
   SharedData_setExpFlowSize ${exp_path} ${seqDatestamp} [winfo width ${top}]x[winfo height ${top}]

   set logfile ${exp_path}/logs/${seqDatestamp}_nodelog

   set hiddenDate [xflow_getWidgetName ${exp_path} ${datestamp} exp_date_hidden]
   set previousDatestamp [${hiddenDate} cget -text]

   if { ${previousDatestamp} != ${newDatestamp} } {

      if { [SharedData_getMiscData XFLOW_NEW_DATESTAMP_LAUNCH] != "" } {
         # add the datestamp so the monitor does not try to launch the xflow again
         LogMonitor_addOneExpDatestamp ${exp_path} ${seqDatestamp}
      }

      ::log::log debug "xflow_setDatestampCallback exp_path:${exp_path} seqDatestamp:${seqDatestamp}"

      ${hiddenDate} configure -text ${newDatestamp}

      if { ${previousDatestamp} != "" } {
         set previousRealDatestamp [Utils_getRealDatestampValue ${previousDatestamp}]
	 # xflow_cleanDatestampVars ${exp_path} ${datestamp}
      }

      if { [SharedData_getMiscData OVERVIEW_MODE] == true } {
         set expThreadId [ThreadPool_getNextThread]
         thread::send -async ${expThreadId} "LogReader_startExpLogReader ${exp_path} ${seqDatestamp} no_overview" LogReaderDone
	 vwait LogReaderDone
         SharedData_setExpThreadId ${exp_path} ${seqDatestamp} ${expThreadId}
      } else {
	 MsgCenter_clearAllMessages
         SharedData_setExpThreadId ${exp_path} ${seqDatestamp} [thread::id]
         SharedData_setMiscData STARTUP_DONE false
         LogReader_startExpLogReader ${exp_path} ${seqDatestamp} no_overview
         SharedData_setMiscData STARTUP_DONE true
      }

      set currentTop [xflow_getToplevel ${exp_path} ${datestamp}]
      set newTop [xflow_getToplevel ${exp_path} ${seqDatestamp}]
      set currentx [winfo x ${currentTop}]
      set currenty [winfo y ${currentTop}]

      # clean previous datestamp
      xflow_closeExpDatestamp ${exp_path} ${datestamp}
      # SharedData_removeExpThreadId ${exp_path} ${previousRealDatestamp}

      xflow_createWidgets ${exp_path} ${seqDatestamp} ${currentx} ${currenty}
      xflow_displayFlow ${exp_path} ${seqDatestamp} true
   }
   Utils_normalCursor $top
}

# this function returns the resource information that needs to be displayed
# besides the node name. Based on the user preferences View->"Node Display"
proc xflow_getNodeDisplayPrefText { exp_path datestamp node member } {
   # puts "xflow_getNodeDisplayPrefText ${exp_path} ${datestamp} ${node} ${member}"
   set text ""
   set displayPref [xflow_getNodeDisplayPref ${exp_path} ${datestamp}]
   set attrName ${displayPref}
   set attrValue ""

   if { [SharedFlowNode_getNodeType ${exp_path} ${node} ${datestamp}] == "module" } {
      set moduleName "[SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} name]"
      set moduleLocalName "[SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} local_name]"
      if { ${moduleName} != ${moduleLocalName} } {
         # puts "xflow_getNodeDisplayPrefText set text (${moduleLocalName})"
         set text "(${moduleLocalName})"
      }
   }

   if { ${displayPref} == "machine_queue" } {
      set attrName "machine"
   }

   switch ${displayPref} {
      "normal" {
      }
      
      "Execution Time" {
         set attrValue [SharedFlowNode_getExecTime ${exp_path} ${node} ${datestamp} ${member}]
      }

      "Begin Time" {
         set attrValue [SharedFlowNode_getBeginTime ${exp_path} ${node} ${datestamp} ${member}]
      }

      "End Time" {
         set attrValue [SharedFlowNode_getEndTime ${exp_path} ${node} ${datestamp} ${member}]
      }

      "Submission Delay" {
         set attrValue [SharedFlowNode_getSubmitDelay ${exp_path} ${node} ${datestamp} ${member}]
      }

      "Delta Time From Start" {
         set attrValue [SharedFlowNode_getDeltaFromStart ${exp_path} ${node} ${datestamp} ${member}]
      }

      "Relative Progress" {
         set attrValue [SharedFlowNode_getRelativeProgress ${exp_path} ${node} ${datestamp} ${member}]
      }

      "Relative Execution Time" {
         set attrValue [SharedFlowNode_getRelativeExecTime ${exp_path} ${node} ${datestamp} ${member}]
      }

      default {
         if { ${displayPref} == "catchup" || [string match "*task" [SharedFlowNode_getNodeType ${exp_path} ${node} ${datestamp}]] } {
            set seq_node [SharedFlowNode_getSequencerNode $exp_path $node $datestamp]
            set attrValue "[TsvInfo_getNodeInfo  ${exp_path} $seq_node ${datestamp} resources.$attrName]"
            if { ${displayPref} == "machine_queue" } {
               set queue [TsvInfo_getNodeInfo  ${exp_path} $seq_node ${datestamp} resources.queue]
               if { ${queue} != "null" } {
                  set attrValue "${attrValue}:${queue}"
               }
            }
            set attrValue "(${attrValue})"
            if { ${displayPref} == "cpu" } {
               set cpuMult [TsvInfo_getNodeInfo ${exp_path} $seq_node ${datestamp} resources.cpu_multiplier]
               if { ${cpuMult} != "1" } {
                  set attrValue "${attrValue}x(${cpuMult})"
               }
            }
         }
      }
   }

   if { ${attrValue} != "" } {
      if { ${text} != "" } {
         set text "${text}\n${attrValue}"
      } else {
         set text "${attrValue}"
      }
   }

   # puts "xflow_getNodeDisplayPrefText ${exp_path} ${datestamp} ${node} ${member}"
   return $text
}

# find a node in the flow and point to it
# the real_node might have an extension attached to
# it example: /a/b/c+12+1
# also accepts: /a/b/c.+12+1
# if multiple indexes are given... the last one can be either a npt or loop index
# the others can only be loop indexes
proc xflow_findNode { exp_path datestamp real_node } {
   ::log::log debug "xflow_findNode exp_path:${exp_path} datestamp:${datestamp} real_node:${real_node}"
   set nodeWithoutExt [SharedFlowNode_getNodeFromDisplayFormat ${real_node}]
   set extensionPart [SharedFlowNode_getExtFromDisplayFormat ${real_node}]
   set flowNode [SharedData_getExpNodeMapping ${exp_path} ${datestamp} ${nodeWithoutExt}]

   if { [SharedFlowNode_isNodeExist ${exp_path} ${flowNode} ${datestamp}] == false } {
      puts "WARNING: NODE ${real_node} NOT EXISTS!"
      return
   }

   # split the list using + as separator
   set extList [split ${extensionPart} +]
   set extLen [llength ${extList}]
   # start at 1 cause the first element of the extList is a dummy empty value
   set indexCount 1
   set loopList [SharedFlowNode_getLoops ${exp_path} ${flowNode} ${datestamp}]
   set refreshNode ""
   # loop throught the list of indexes
   while { ${indexCount} < ${extLen} } {
      # indexes until the last one are loop indexes... last one could also be npass_task
      set extValue +[lindex ${extList} ${indexCount}]
      if { ${indexCount} != [expr ${extLen} - 1] } {
         # not last iteration, must be loop 
         set loopNode [lindex ${loopList} [expr ${indexCount} - 1]]
         SharedFlowNode_setCurrentExt ${exp_path} ${loopNode} ${datestamp} ${extValue}
         set refreshNode ${loopNode}
      } else {
         # last iteration
         if { [SharedFlowNode_getNodeType ${exp_path} ${flowNode} ${datestamp}] == "npass_task" } {
            SharedFlowNode_setCurrentExt ${exp_path} ${flowNode} ${datestamp} ${extValue}
            set refreshNode ${flowNode}
         } else {
            # must be a loop extension
            set loopNode [lindex ${loopList} [expr ${indexCount} - 1]]
            SharedFlowNode_setCurrentExt ${exp_path} ${loopNode} ${datestamp} ${extValue}
            set refreshNode ${loopNode}
         }
      }
      incr indexCount
   }
   set collapsedParentNode [SharedFlowNode_uncollapseBranch ${exp_path} ${flowNode} ${datestamp}]
   if { ${refreshNode} != "" || ${collapsedParentNode} != "" } {
      xflow_drawflow ${exp_path} ${datestamp} [xflow_getMainFlowCanvas ${exp_path} ${datestamp}]
   }
   update idletasks
    ::DrawUtils::pointNode ${exp_path} ${datestamp} ${flowNode}


          # if the node is collapsed, uncollapse it
      if { [SharedFlowNode_uncollapseBranch ${exp_path} ${flowNode} ${datestamp}] != "" } {
         xflow_drawflow ${exp_path} ${datestamp} [xflow_getMainFlowCanvas ${exp_path} ${datestamp}]
 false
      }
}

# this function is the starting point to draw the experiment flow.
# It recursively draws the whole flow from a starting point, which is
# the root node
# parameters:
#   canvas: canvas where the flow will be drawn
#   node: the node that needs to be drawn
#   position: specifies the position of the node within its parent
#   first_node: set to true only for the experiment root node.
proc xflow_drawNode { exp_path datestamp canvas node position {first_node false} } {
   global FLOW_SCALE_${exp_path}_${datestamp} COLLAPSE_DISABLED_NODES
   ::log::log debug "xflow_drawNode drawing sub node:$node position:$position "
   set nodeType [SharedFlowNode_getNodeType ${exp_path} ${node} ${datestamp}]
   if { [SharedFlowNode_isParentCollapsed ${exp_path} ${node} ${datestamp}] == 1 } {
      ::log::log debug "xflow_drawNode parent is collapsed, not drawing node:$node"
      return;
   }
   set flowScale [set FLOW_SCALE_${exp_path}_${datestamp}]
   set boxW [SharedData_getMiscData CANVAS_BOX_WIDTH]
   set boxH [SharedData_getMiscData CANVAS_BOX_HEIGHT]
   set pady [SharedData_getMiscData CANVAS_PAD_Y]
   set padTx [SharedData_getMiscData CANVAS_PAD_TXT_X]
   set padTy [SharedData_getMiscData CANVAS_PAD_TXT_Y]
   set shadowColor [SharedData_getColor SHADOW_COLOR]
   set deltaY [::DrawUtils::getLineDeltaSpace ${exp_path} ${node} ${datestamp}  [xflow_getNodeDisplayPref ${exp_path} ${datestamp}]]
   set drawshadow on
   if { ${flowScale} != "1" } {
      set drawshadow off
   }
   set submitter [SharedFlowNode_getSubmitter ${exp_path} ${node} ${datestamp}]
   if { ${submitter} == "" || ${first_node} == "true" } {
      set linex2 [SharedData_getMiscData CANVAS_X_START]
      set liney2 [expr [SharedData_getMiscData CANVAS_Y_START] + ${deltaY}]
      ::log::log debug "xflow_drawNode linex2:$linex2 liney2:$liney2"
   } else {
      # SharedFlowNode_initNodeDatestampDisplay ${exp_path} ${submitter} ${datestamp}
      # use a dashline leading to modules, elsewhere use a solid line
      set lineColor [SharedData_getColor FLOW_SUBMIT_ARROW]
      switch ${nodeType} {
         "module" {
            set drawline "drawdashline"
          }
          default {
            set drawline "drawline"
          }
      }

      # get the coordinates of the submitter
      foreach { px1 py1 px2 py2 } [SharedFlowNode_getDisplayCoords ${exp_path} ${submitter} ${datestamp}] { break }

      # first draw left arrow, the shape depends on the position of the
      # subnode and previous nodes being drawn
      # if position is 0, means first node job so same level as parent node only x coords changes
      set lineTagName "flow_element ${node}.submit_tag"

      if { $position == 0 } {
         set linex1 $px2
         set liney1 [expr $py1 + ($py2 - $py1) / 2 + $deltaY]
         set liney2 $liney1
         # nodedeltax mainly for nptask, size of index widgets different than box
         set linex2 [expr $linex1 + $boxW/2/${flowScale} + [::DrawUtils::getNodeDeltaX ${exp_path} ${submitter} ${datestamp} $canvas]]
         ::DrawUtils::$drawline $canvas $linex1 $liney1 $linex2 $liney2 last $lineColor $drawshadow $shadowColor ${lineTagName}
      } else {
         # draw L-shape arrow
         # first draw vertical line
         if { [xflow_isRefreshMode ${exp_path} ${datestamp}] == "true" } {
            # drawing at same position
            set nextY [SharedFlowNode_getDisplayY ${exp_path} ${node} ${datestamp}]
         } else {
            set nextY [SharedData_getExpDisplayNextY ${exp_path} ${datestamp} $canvas]
         }
         SharedFlowNode_setDisplayY  ${exp_path} ${node} ${datestamp} ${nextY}

         #set linex1 [expr $px2 + $boxW/4/3]
         set linex1 [expr $px2 + $boxW/2/${flowScale}/3]
         set linex2 $linex1
         set liney1 [expr $py1 + ($py2 - $py1) / 2 ]
         set liney2 [expr $nextY + (( $boxH/4 + $pady)/${flowScale}) + $deltaY]
         ::DrawUtils::$drawline $canvas $linex1 $liney1 $linex2 $liney2 none $lineColor $drawshadow $shadowColor ${lineTagName}
         # then draw hor line with arrow at end
         set linex2 [expr $px2 + $boxW/2/${flowScale}]
         set liney1 $liney2
         ::DrawUtils::$drawline $canvas $linex1 $liney1 $linex2 $liney2 last $lineColor  $drawshadow $shadowColor ${lineTagName}
      }
   }
   set isCollapsed [ SharedFlowNode_isCollapsed ${exp_path} ${node} ${datestamp}]
   set submits [SharedFlowNode_getSubmits ${exp_path} ${node} ${datestamp}]
   set normalTxtFill [SharedData_getColor NORMAL_RUN_TEXT]
   set normalFill [::DrawUtils::getBgStatusColor init]
   set outline [SharedData_getColor NORMAL_RUN_OUTLINE]
   # now draw the node
   set tx1 [expr $linex2 + ${padTx}/${flowScale}]
   set ty1 $liney2
   foreach { tx1 ty1 } [xflow_addSingleReservIndicator ${exp_path} ${datestamp} ${node} ${canvas} ${tx1} ${ty1}] {break}

   set text [SharedFlowNode_getName ${exp_path} ${node} ${datestamp}]
   set nodeExtension [SharedFlowNode_getNodeExtension ${exp_path} ${node} ${datestamp}]
   set status [SharedFlowNode_getMemberStatus ${exp_path} ${node} ${datestamp} ${nodeExtension} ]
   if { ${isCollapsed} == 2 && ${COLLAPSE_DISABLED_NODES} == true && (${status} == "discret" || ${status} == "catchup") } {
      set isCollapsed 1
      SharedFlowNode_setCollapsed ${exp_path} ${node} ${datestamp} 1
   }
   set extDisplay [SharedFlowNode_getExtDisplay ${exp_path} ${node} ${datestamp} $nodeExtension]
   if { $extDisplay != "" } {
      set text "${text}${extDisplay}"
   }
   if { !((${submits} == "none") ||  (${submits} == "")) && $isCollapsed == 1} {
      set text ${text}+
   }
   set dispPref [xflow_getNodeDisplayPrefText ${exp_path} ${datestamp} ${node} ${nodeExtension}]
   
   if { $dispPref != "" } {
      set l_txt [split $dispPref "\n"]
      set txt_item [lindex $l_txt 0]
      set txt_cmp  [lindex $l_txt 0]

      if {[string match *orange* $txt_item]} {
        set txt_cmp [string map {orange ""} ${txt_cmp}]
      } elseif {[string match *red* $txt_item]} {
        set txt_cmp [string map {red ""} ${txt_cmp}]
      }
      if {[string match *normal* $txt_item]} {
        set text "${text}\n${dispPref}"
      } else {
        if {[string length $txt_cmp] > [string length ${text}]  && [llength $l_txt] == 1 && [string match *min* $txt_item]} {
          set nb_item [expr {([string length $txt_cmp] - [string length ${text}]) + 1}]
          set text "${text}\n[string repeat " " $nb_item]${dispPref}"
        } else {
          set nb_item [expr {([string length ${text}] - [string length $txt_cmp]) + 1}]
          if {([string length $txt_cmp] <= [string length ${text}])  && $nb_item <= 4 && [llength $l_txt] == 1 && [string match *min* $txt_item]} {
            set text "${text}\n[string repeat " " $nb_item]${dispPref}"
          } else {
            set text "${text}\n${dispPref}"
          }
        }
      }
   }
   switch ${nodeType} {
      "family" {
         ::DrawUtils::drawBoxSansOutline ${exp_path} ${datestamp} $canvas $tx1 $ty1 $text $text $normalTxtFill $outline $normalFill $node $drawshadow $shadowColor
         # ::FlowNodes::addToFamilyList $node
      }
      "module" {
	 ::DrawUtils::drawBoxSansOutline ${exp_path} ${datestamp} $canvas $tx1 $ty1 $text $text $normalTxtFill $outline $normalFill $node $drawshadow $shadowColor
      }
      "task" {
         ::DrawUtils::drawBox ${exp_path} ${datestamp} $canvas $tx1 $ty1 $text $text $normalTxtFill $outline $normalFill $node $drawshadow $shadowColor
      }

      "npass_task" {
         # ::DrawUtils::drawBox ${exp_path} ${datestamp} $canvas $tx1 $ty1 $text $text $normalTxtFill $outline $normalFill $node $drawshadow $shadowColor
         ::DrawUtils::drawRoundBox ${exp_path} ${datestamp} $canvas $tx1 $ty1 $text $text $normalTxtFill $outline $normalFill $node $drawshadow $shadowColor
         set indexListW [::DrawUtils::getIndexWidgetName ${node} ${canvas}]
         ${indexListW} configure -modifycmd [list xflow_indexedNodeSelectionCallback ${exp_path} ${node} ${datestamp} ${canvas} ${indexListW}]
      }
      "loop" {
         set text "${text}\n[TsvInfo_getLoopInfo $exp_path $node $datestamp]"
         ::DrawUtils::drawOval ${exp_path} ${datestamp} $canvas $tx1 $ty1 $text $text $normalTxtFill $outline $normalFill $node $drawshadow $shadowColor
         set helpText "[SharedFlowNode_getLoopTooltip  ${exp_path} ${node} ${datestamp}]"
         set indexListW [::DrawUtils::getIndexWidgetName ${node} ${canvas}]
         ${indexListW} configure -modifycmd [list xflow_indexedNodeSelectionCallback ${exp_path} ${node} ${datestamp} ${canvas} ${indexListW}]
         ::tooltip::tooltip $canvas -item ${node} ${helpText}
         # reset the text to be used for generic tooltip on scaling mode
         set text "${helpText}"
      }
      "switch_case" {
         set text "${text}\n[SharedFlowNode_getSwitchingInfo ${exp_path} ${node} ${datestamp}]"
         ::DrawUtils::drawLosange ${exp_path} ${datestamp} $canvas $tx1 $ty1 $text $normalTxtFill $outline $normalFill $node $drawshadow $shadowColor
         set indexListW [::DrawUtils::getIndexWidgetName ${node} ${canvas}]
         ${indexListW} configure -modifycmd [list xflow_indexedNodeSelectionCallback ${exp_path} ${node} ${datestamp} ${canvas} ${indexListW}]
      }
      "outlet" {
         ::DrawUtils::drawOval ${exp_path} ${datestamp} $canvas $tx1 $ty1 $text $text $normalTxtFill $outline $normalFill $node $drawshadow $shadowColor
      }
      default {
         error "Invalid node type:${nodeType} in proc xflow_drawNode()"
      }
   }
   if { ${flowScale} != "1" } { ::tooltip::tooltip $canvas -item ${node} ${text} }
   ::DrawUtils::drawNodeStatus ${exp_path} ${node} ${datestamp} ${canvas} [xflow_getShawdowStatus]
   xflow_MouseWheelCheck ${canvas}
   set currentExtension [SharedFlowNode_getNodeExtension ${exp_path} ${node} ${datestamp}]
   $canvas bind $node <Double-Button-1> [ list xflow_changeCollapsed ${exp_path} ${datestamp} ${node} ${canvas}]
   $canvas bind $node <Button-2> [ list xflow_historyCallback ${exp_path} ${datestamp} $node ${currentExtension} $canvas  48] 
   $canvas bind $node <Button-3> [ list xflow_nodeMenu ${exp_path} ${datestamp} $canvas $node ${currentExtension} %X %Y]

   if { $isCollapsed == 0 || $isCollapsed == 2 } {
      # get the childs to display
      if { !((${submits} == "none") ||  (${submits} == ""))} {
         set nodePosition 0
         foreach submitName ${submits} {
            set submitNode ${node}/${submitName}
            xflow_drawNode ${exp_path} ${datestamp} $canvas ${submitNode} $nodePosition
            incr nodePosition
         }
      }
   }

   ::log::log debug "xflow_drawNode drawing sub node:$node done"
}

proc xflow_MouseWheelCheck { canvas } {
   foreach { yviewLow yviewHigh } [${canvas} yview] {}
   if { ${yviewLow} == "0.0" } {
      # reached the limit don't allow scrolling
      bind ${canvas} <4> ""
   } else {
      bind ${canvas} <4> [list xflow_canvasMouseWheelCallback ${canvas} -20] 
   }
   if { ${yviewHigh} == "1.0" } {
      # reached the limit don't allow scrolling
      bind ${canvas} <5> ""
   } else {
      bind ${canvas} <5> [list xflow_canvasMouseWheelCallback ${canvas} 20] 
   }
}

proc xflow_canvasMouseWheelCallback { canvas units_value } {
   ${canvas} yview scroll ${units_value} units

   xflow_MouseWheelCheck ${canvas}
}

# add a striped circle before the node box to indicate the
# the start of a single reservation branch
# returns coords of modified x and y after image creation if exists
#                    modified x is start_x + width of created img
#                    y is startY
# else returns startX and startY
# 
proc xflow_addSingleReservIndicator { _exp_path _datestamp _node _canvas _startX _startY } {
   global SingleReservImg
   if { [SharedFlowNode_getWorkUnit ${_exp_path} ${_node} ${_datestamp}] == 1 } {
      if { [info exists SingleReservImg] == 0 } {
         set SingleReservImg [image create photo -file [SharedData_getMiscData IMAGE_DIR]/round_stripe.png]
      }

      ${_canvas} create image ${_startX} ${_startY} -image ${SingleReservImg} -tags "flow_element ${_node} ${_node}.work_unit"
      return [list [expr ${_startX} + [image height $SingleReservImg] + 1] ${_startY}]
   }
   return [list ${_startX} ${_startY}]
}

proc xflow_nodeMenuUnmapCallback { exp_path datestamp } {
   global NodeHighLightRestoreCmd_${exp_path}_${datestamp}
   catch { eval [set NodeHighLightRestoreCmd_${exp_path}_${datestamp}] }
}

proc xflow_showPluginMenu { parentMenu source_w exp_path datestamp node extension } {
    set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]
    set seqLoopArgs [xflow_getSeqLoopArgs ${exp_path} ${datestamp} ${node} ${extension} ${source_w}]
    set pluginEnv "export SEQ_NODE=${seqNode}; export SEQ_LOOP_ARGS=\"${seqLoopArgs}\""
    Utils_showPluginMenu "xflow" ${parentMenu} ${exp_path} ${datestamp} ${pluginEnv}
}

# This function is called when user click on a box with button 3
# It will display a popup menu for the current node.
proc xflow_nodeMenu { exp_path datestamp canvas node extension x y } {
   global ignoreDep  CHECK_PERMISSION SUITE_PERMISSION

   ::log::log debug "xflow_nodeMenu exp_path:$exp_path datestamp:$datestamp canvas:$canvas node:$node extension:$extension "

   set popMenu .popupMenu
   set infoMenu ${popMenu}.info_menu
   set editMenu ${popMenu}.edit_menu
   set listingMenu ${popMenu}.listing_menu
   set submitMenu ${popMenu}.submit_menu
   set submitDependMenu ${popMenu}.submit_dep_menu
   set submitNoDependMenu ${popMenu}.submit_nodep_menu
   set statusMenu ${popMenu}.status_menu
   set miscMenu ${popMenu}.misc_menu
   if { [winfo exists ${popMenu}] } {
      destroy ${popMenu}
   }

   menu ${popMenu} -title [SharedFlowNode_getName ${exp_path} ${node} ${datestamp}] -tearoffcommand [list xflow_nodeMenuTearoffCallback]

   # when the menu is destroyed, clears the highlighted node
   bind ${popMenu} <Unmap> [list xflow_nodeMenuUnmapCallback ${exp_path} ${datestamp}]

   set historyMenu ${popMenu}.history_menu
   set historyOptions [xflow_getNodeHistoryOptions]
      
   ${popMenu} add cascade -label "History" -underline 0 -menu [menu ${historyMenu}]
   foreach {itemName itemValue} ${historyOptions} {
      ${historyMenu} add command -label ${itemName} -command [list xflow_historyCallback ${exp_path} ${datestamp} $node $extension $canvas ${itemValue}]
   }

   ${popMenu} add cascade -label "Info" -underline 0 -menu [menu ${infoMenu}]
   ${popMenu} add cascade -label "Edit" -underline 0 -menu [menu ${editMenu}]
   ${popMenu} add cascade -label "Listing" -underline 0 -menu [menu ${listingMenu}]
   ${popMenu} add cascade -label "Submit" -underline 0 -menu [menu ${submitMenu}]
   ${popMenu} add cascade -label "Misc" -underline 0 -menu [menu ${miscMenu}]
   ${miscMenu} add cascade -label "Force status" -underline 0 -menu [menu ${statusMenu}]

   if {$CHECK_PERMISSION == false } {
      ${miscMenu} entryconfigure "Force status" -state disabled
   }
   set submits [SharedFlowNode_getSubmits ${exp_path} ${node} ${datestamp} ]
   set isCollapsed [SharedFlowNode_isCollapsed ${exp_path} ${node} ${datestamp}]
   if { ${submits} != "" && ${isCollapsed} } {
      ${popMenu} add command -label "Expand All" -command [list xflow_expandAllCallback ${exp_path} ${datestamp} $node $canvas $popMenu]
   }
   set nodeType [SharedFlowNode_getNodeType ${exp_path} ${node} ${datestamp}]
   if { ${nodeType} == "loop" } {
      xflow_addLoopNodeMenu ${exp_path} ${datestamp} ${popMenu} ${canvas} ${node} ${extension}
   } elseif { ${nodeType} == "npass_task" } {
      xflow_addNptNodeMenu ${exp_path} ${datestamp} ${popMenu} ${canvas} ${node} ${extension}
   } else {

      ${infoMenu} add command -label "Node Info" -command [list xflow_nodeInfoCallback ${exp_path} ${datestamp} $node ${extension} $canvas ]
      ${infoMenu} add command -label "Node Dependencies" -command [list xflow_nodeDepCallback ${exp_path} ${datestamp} $node ${extension} $canvas ]
      ${infoMenu} add command -label "Node Batch" -command [list xflow_batchCallback ${exp_path} ${datestamp} $node ${extension} $canvas ]

      set currentExtension [SharedFlowNode_getNodeExtension ${exp_path} ${node} ${datestamp}]
      set status [SharedFlowNode_getMemberStatus ${exp_path} ${node} ${datestamp} ${currentExtension}]

      ${listingMenu} add command -label "Latest Success Listing" -command [list xflow_listingCallback ${exp_path} ${datestamp} $node ${extension} $canvas ] \
         -foreground [::DrawUtils::getBgStatusColor end]
      ${listingMenu} add command -label "Latest Abort Listing" \
         -command [list xflow_abortListingCallback ${exp_path} ${datestamp} $node ${extension} $canvas ] \
         -foreground [::DrawUtils::getBgStatusColor abort]
      ${listingMenu} add command -label "Latest Submission Listing" -command [list xflow_submissionListingCallback ${exp_path} ${datestamp} $node ${extension} $canvas ]
      ${listingMenu} add command -label "Compare Latest Success/Abort Listings" -command [list xflow_diffLatestListings ${exp_path} ${datestamp} $node ${extension} $canvas]
      ${listingMenu} add command -label "All Node Listing" -command [list xflow_allListingCallback ${exp_path} ${datestamp} $node $canvas $popMenu]

      switch ${status} {
         begin {
            ${listingMenu} add command -label "Monitor Listing" -command [list xflow_tailfCallback ${exp_path} ${datestamp} $node ${extension} $canvas ] \
               -foreground [::DrawUtils::getBgStatusColor begin]
         }

         wait {
            ${infoMenu} insert 0 command -label "Follow Current Dependency" -command [list xflow_followDependency ${exp_path} ${datestamp} $node ${extension} ]
            ${listingMenu} add command -label "Monitor Listing" -command [list xflow_viewOutputFile  ${exp_path} ${datestamp} $node ${extension} $canvas] \
               -foreground [::DrawUtils::getBgStatusColor begin]
         }
         default {
            ${listingMenu} add command -label "Monitor Listing" -command [list xflow_viewOutputFile  ${exp_path} ${datestamp} $node ${extension} $canvas] \
               -foreground [::DrawUtils::getBgStatusColor begin]
         }
      }

      # ${miscMenu} add command -label "New Window" -command [list xflow_newWindowCallback $node $canvas $popMenu]
      ${miscMenu} add command -label "View Workdir" -command [list xflow_launchWorkCallback ${exp_path} ${datestamp} $node $canvas ]
      if { ${nodeType} != "task" } {
         ${submitMenu} add command -label "Submit" -command [list xflow_submitCallback ${exp_path} ${datestamp} $node ${extension} $canvas continue ]
         ${submitMenu} add cascade -label "NO Dependency" -underline 4 -menu [menu ${submitNoDependMenu}]
         ${submitNoDependMenu} add command -label "Submit" \
            -command [list xflow_submitCallback ${exp_path} ${datestamp} $node ${extension} $canvas continue dep_off]
         ${infoMenu} add command -label "Node Config" -command [list xflow_configCallback ${exp_path} ${datestamp} $node $canvas $popMenu "info"]
         ${infoMenu} add command -label "Evaluated Node Config" -command [list xflow_evalConfigCreateWidgets ${exp_path} ${datestamp} $node ${extension} ${popMenu}]
         ${infoMenu} add command -label "Node Full Config" -command [list xflow_fullConfigCallback ${exp_path} ${datestamp} $node $canvas $popMenu ]
         ${statusMenu} add command -label "Initialize branch" -command [list xflow_initbranchCallback ${exp_path} ${datestamp} $node ${extension} $canvas ]
         ${editMenu} add command -label "Node Config" -command [list xflow_configCallback ${exp_path} ${datestamp} $node $canvas $popMenu "edit"]
         ${editMenu} add command -label "Node Resource" -command [list xflow_resourceCallback ${exp_path} ${datestamp} $node $canvas $popMenu "edit"]
         if {$CHECK_PERMISSION == false} {
            ${submitMenu} entryconfigure "Submit"        -state disabled
            ${submitMenu} entryconfigure "NO Dependency" -state disabled
         }
         if {${SUITE_PERMISSION} == false} {
            ${editMenu}   entryconfigure "Node Config"   -state disabled
            ${editMenu}   entryconfigure "Node Resource" -state disabled
         }
      } else {
         ${submitMenu} add command -label "Submit & Continue" -underline 9 -command [list xflow_submitCallback ${exp_path} ${datestamp} $node ${extension} $canvas continue ]
         ${submitMenu} add command -label "Submit & Stop" -underline 9 -command [list xflow_submitCallback ${exp_path} ${datestamp} $node ${extension} $canvas stop ]

         ${submitMenu} add cascade -label "NO Dependency" -underline 4 -menu [menu ${submitNoDependMenu}]
         ${submitNoDependMenu} add command -label "Submit & Continue" -underline 9 \
            -command [list xflow_submitCallback ${exp_path} ${datestamp} $node ${extension} $canvas continue dep_off ]
         ${submitNoDependMenu} add command -label "Submit & Stop" -underline 9 \
            -command [list xflow_submitCallback ${exp_path} ${datestamp} $node ${extension} $canvas stop dep_off ]

         ${infoMenu} add command -label "Node Source" -command [list xflow_sourceCallback ${exp_path} ${datestamp} $node $canvas $popMenu "info"]
         ${infoMenu} add command -label "Node Config" -command [list xflow_configCallback ${exp_path} ${datestamp} $node $canvas $popMenu "info"]
         ${infoMenu} add command -label "Evaluated Node Config" -command [list xflow_evalConfigCreateWidgets ${exp_path} ${datestamp} $node ${extension} ${popMenu}]
         ${infoMenu} add command -label "Node Full Config" -command [list xflow_fullConfigCallback ${exp_path} ${datestamp} $node $canvas $popMenu]

         ${editMenu} add command -label "Node Config"   -command [list xflow_configCallback ${exp_path} ${datestamp} $node $canvas $popMenu "edit"]
         ${editMenu} add command -label "Node Source"   -command [list xflow_sourceCallback ${exp_path} ${datestamp} $node $canvas $popMenu "edit"]
         ${editMenu} add command -label "Node Resource" -command [list xflow_resourceCallback ${exp_path} ${datestamp} $node $canvas $popMenu "edit"]

         ${statusMenu} add command -label "Initialize node" -command [list xflow_initnodeCallback ${exp_path} ${datestamp} $node ${extension} $canvas ]
         ${miscMenu} add command -label "Save Workdir" -command [list xflow_saveWorkCallback ${exp_path} ${datestamp} $node $canvas ]
         if {$CHECK_PERMISSION == false} {
           ${submitMenu} entryconfigure "Submit & Continue" -state disabled
           ${submitMenu} entryconfigure "Submit & Stop"     -state disabled
           ${submitMenu} entryconfigure "NO Dependency"     -state disabled
           ${miscMenu}   entryconfigure "Save Workdir"      -state disabled 
         }
         if {${SUITE_PERMISSION} == false } {
           ${editMenu}   entryconfigure "Node Config"       -state disabled
           ${editMenu}   entryconfigure "Node Source"       -state disabled
           ${editMenu}   entryconfigure "Node Resource"     -state disabled      
         } 
          
      }
      ${statusMenu} add command -label "Begin" -command [list xflow_beginCallback ${exp_path} ${datestamp} $node ${extension} $canvas ]
      ${statusMenu} add command -label "End" -command [list xflow_endCallback ${exp_path} ${datestamp} $node ${extension} $canvas ]
      ${statusMenu} add command -label "Abort" -command [list xflow_abortCallback ${exp_path} ${datestamp} $node ${extension} $canvas]
      ${infoMenu}   add command -label "Node Resource" -command [list xflow_resourceCallback ${exp_path} ${datestamp} $node $canvas $popMenu "info"]
   }

   ${miscMenu} add command -label "Kill Node" -command [list xflow_killNodeFromDropdown ${exp_path} ${datestamp} $node ${extension} $canvas]
   if {$CHECK_PERMISSION == false} {
      ${miscMenu}   entryconfigure "Kill Node"      -state disabled
   }
   $popMenu add separator
   xflow_showPluginMenu ${popMenu} ${canvas} ${exp_path} ${datestamp} ${node} ${extension}
   
   tk_popup $popMenu $x $y

   # highlights the selected node
   catch { ::DrawUtils::highLightNode ${exp_path} ${node} ${datestamp} ${canvas} }
}

proc xflow_nodeMenuTearoffCallback { menu_w tearoff_w } {
   ::log::log debug  "xflow_nodeMenuTearoffCallback menu_w:$menu_w tearoff_w:$tearoff_w"
   if { [winfo exists ${tearoff_w}] } {
      wm minsize ${tearoff_w} 100 100
   }
}

# "Follow Current Dependency" callback
proc xflow_followDependency {  exp_path datestamp node extension } {
   ::log::log debug "xflow_followDependency exp_path:$exp_path datestamp:$datestamp node:$node extension:$extension"

   set waitStatusMsg [SharedFlowNode_getMemberStatusMsg ${exp_path} ${node} ${datestamp} ${extension}]

   ::log::log debug "xflow_followDependency waitStatusMsg:$waitStatusMsg"
   # set depExp [exec true_path ${exp_path}]
   set depExp ${exp_path}
   set isOcmDep false
   if { ${waitStatusMsg} != "" } {
      # parse wait msg looking for exp=, node=, index=, datestamp=
      foreach token ${waitStatusMsg} {
         switch -glob ${token} {
	    exp=* {
	       ::log::log debug "xflow_followDependency got exp: $token"
	       if { [string match */.ocm/* ${token}] } {
	          set isOcmDep true
	          set depExp [textutil::trimPrefix ${token} exp=]
	       } else {
	          # set depExp [exec true_path [::textutil::trimPrefix ${token} exp=]]
	          set depExp [::textutil::trimPrefix ${token} exp=]
	       }
	    }
	    node=* {
	       ::log::log debug "xflow_followDependency got node: $token"
	       # if an iteration is used, it would be part of the node
	       # i.e. /CMC-GRIB/Global/SGPD_GDPS/Switch_GRIB/Loop_Hours+12+18
	       set depNode [::textutil::trimPrefix ${token} node=]
	       if { [string index ${depNode} 0] != "/" && ${isOcmDep} == false } {
	          set depNode /${depNode}
	       }
	    }
	    datestamp=* {
	       ::log::log debug "xflow_followDependency got datestamp: $token"
	       set depDatestamp [::textutil::trimPrefix ${token} datestamp=]
	    }
	 }
      }

      set xflowToplevel [xflow_getToplevel ${depExp} ${depDatestamp}] 
      if { ${isOcmDep} == false } {
         # start the suite flow if not started
         set isOverviewMode [SharedData_getMiscData OVERVIEW_MODE]

         if { [ winfo exists ${xflowToplevel} ] == 0 || [winfo viewable ${xflowToplevel}] == false } {
	    if { [SharedData_getExpDisplayName ${depExp}] == "" } {
	       # read exp options if new exp
               ExpOptions_read ${depExp}
	    }
            if { ${isOverviewMode} == true } {
               Overview_launchExpFlow ${depExp} ${depDatestamp}
            } elseif { ${depExp} != ${exp_path} } {
               # standalone xflow mode with dependencies on an external maestro suite
               xflow_newDatestampFound ${depExp} ${depDatestamp}
            }
	 }

         # ask the suite to take care of showing the selected node in it's flow
	 ::log::log debug "xflow_followDependency calling xflow_findNode ${depExp} ${depDatestamp} ${depNode}"
         xflow_findNode ${depExp} ${depDatestamp} ${depNode}
      } else {
         # ocm dependencies... send a dialog with dependency info
         set topW ${depExp}_${depDatestamp}
         set topW [regsub -all {[\.]} ${topW} _]
         set topW .dep_dialog_${topW}

         set dialogText "OCM Dependency\n\nSuite: ${depExp}\n\nJob: ${depNode}\n\nDatestamp: ${depDatestamp}"
         set dlg [Dialog ${topW} -parent ${xflowToplevel} -modal none \
                 -separator 1 -title "OCM Dependency Dialog" -default 0 -cancel 1]
         $dlg add -name Ok -text Ok -command [list destroy ${topW}]
         set msg [message [$dlg getframe].msg -aspect 300 -text ${dialogText} -justify left -anchor c -font [xflow_getWarningFont]]
         pack $msg -fill both -expand yes -padx 50 -pady 50 

         $dlg draw
      }
   }
}

# creates the popup menu for a loop node
proc xflow_addLoopNodeMenu { exp_path datestamp popmenu_w canvas node extension } {
   global CHECK_PERMISSION SUITE_PERMISSION

   ::log::log debug "xflow_addLoopNodeMenu() exp_path:${exp_path} datestamp:${datestamp} node:$node"

   set infoMenu ${popmenu_w}.info_menu
   set editMenu ${popmenu_w}.edit_menu
   set listingMenu ${popmenu_w}.listing_menu
   set submitMenu ${popmenu_w}.submit_menu
   set submitNoDependMenu ${popmenu_w}.submit_nodep_menu
   set miscMenu ${popmenu_w}.misc_menu
   set statusMenu ${popmenu_w}.status_menu

   ${infoMenu} add command -label "Node Info" -command [list xflow_nodeInfoCallback ${exp_path} ${datestamp} $node ${extension} $canvas ]
   ${infoMenu} add command -label "Node Dependencies" -command [list xflow_nodeDepCallback ${exp_path} ${datestamp} $node ${extension} $canvas ]
   ${infoMenu} add command -label "Node Config" -command [list xflow_configCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w} "info"]
   ${infoMenu} add command -label "Evaluated Node Config" -command [list xflow_evalConfigCreateWidgets ${exp_path} ${datestamp} $node ${extension} ${popmenu_w}]
   ${infoMenu} add command -label "Node Full Config" -command [list xflow_fullConfigCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w}]
   ${infoMenu} add command -label "Loop Node Batch" -command [list xflow_batchCallback ${exp_path} ${datestamp} $node ${extension} $canvas 1]
   ${infoMenu} add command -label "Member Node Batch" -command [list xflow_batchCallback ${exp_path} ${datestamp} $node ${extension} $canvas 0]
   ${infoMenu} add command -label "Node Resource" -command [list xflow_resourceCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w} "info" ]
 
   ${editMenu} add command -label "Loop Config"   -command [list xflow_configCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w} "edit"]
   ${editMenu} add command -label "Loop Resource" -command [list xflow_resourceCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w} "edit"]

   set currentExtension [SharedFlowNode_getNodeExtension ${exp_path} ${node} ${datestamp}]
   set status [SharedFlowNode_getMemberStatus ${exp_path} ${node} ${datestamp} ${currentExtension}]

   ${listingMenu} add command -label "Loop Listing" -command [list xflow_listingCallback ${exp_path} ${datestamp} $node ${extension} $canvas 1]
   ${listingMenu} add command -label "Loop Abort Listing" \
      -command [list xflow_abortListingCallback ${exp_path} ${datestamp} $node ${extension} $canvas 1] \
      -foreground [::DrawUtils::getBgStatusColor abort]
   ${listingMenu} add command -label "Loop Submission Listing" -command [list xflow_submissionListingCallback ${exp_path} ${datestamp} $node ${extension} $canvas 1]
   ${listingMenu} add command -label "Member Listing" -command [list xflow_listingCallback ${exp_path} ${datestamp} $node ${extension} $canvas ]
   ${listingMenu} add command -label "Member Abort Listing" \
      -command [list xflow_abortListingCallback ${exp_path} ${datestamp} $node ${extension} $canvas ] \
      -foreground [::DrawUtils::getBgStatusColor abort]
   ${listingMenu} add command -label "Member Submission Listing" -command [list xflow_submissionListingCallback ${exp_path} ${datestamp} $node ${extension} $canvas ]
   ${listingMenu} add command -label "All Node Listing" -command [list xflow_allListingCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w}]

   switch ${status} {
      begin {
         ${listingMenu} add command -label "Monitor Listing" -command [list xflow_tailfCallback ${exp_path} ${datestamp} $node ${extension} $canvas ] \
            -foreground [::DrawUtils::getBgStatusColor begin]
      }
      wait {
         ${infoMenu} insert 0 command -label "Follow Current Dependency" -command [list xflow_followDependency ${exp_path} ${datestamp} $node ${extension} ]
         ${listingMenu} add command -label "Monitor Listing" -command [list xflow_viewOutputFile ${exp_path} ${datestamp} $node ${extension} $canvas] \
            -foreground [::DrawUtils::getBgStatusColor begin]
      }
      default {
         ${listingMenu} add command -label "Monitor Listing" -command [list xflow_viewOutputFile  ${exp_path} ${datestamp} $node ${extension} $canvas] \
            -foreground [::DrawUtils::getBgStatusColor begin]
      }
   }

   ${submitMenu} add command -label "Loop Submit" -command [list xflow_submitLoopCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w} continue ]
   ${submitMenu} add command -label "Member Submit" -command [list xflow_submitCallback ${exp_path} ${datestamp} $node ${extension} $canvas continue ]
   ${submitMenu} add cascade -label "NO Dependency" -underline 4 -menu [menu ${submitNoDependMenu}]
   ${submitNoDependMenu} add command -label "Loop Submit" \
      -command [list xflow_submitLoopCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w} continue dep_off]
   ${submitNoDependMenu} add command -label "Member Submit" \
      -command [list xflow_submitCallback ${exp_path} ${datestamp} $node ${extension} $canvas continue dep_off]

   # ${miscMenu} add command -label "New Window" -command [list xflow_newWindowCallback $node $canvas ${popmenu_w}]
   ${miscMenu} add command -label "View Workdir" -command [list xflow_launchWorkCallback ${exp_path} ${datestamp} $node $canvas ]
   ${statusMenu} add command -label "Loop Begin" -command [list xflow_beginLoopCallback ${exp_path} ${datestamp} $node ${extension} $canvas ]
   ${statusMenu} add command -label "Loop End" -command [list xflow_endLoopCallback ${exp_path} ${datestamp} $node ${extension} $canvas ]
   ${statusMenu} add command -label "Loop Initialize" -command [list xflow_initbranchLoopCallback ${exp_path} ${datestamp} $node $canvas ]
   ${statusMenu} add command -label "Member Begin" -command [list xflow_beginCallback ${exp_path} ${datestamp} $node ${extension} $canvas ]
   ${statusMenu} add command -label "Member End" -command [list xflow_endCallback ${exp_path} ${datestamp} $node ${extension} $canvas ]
   ${statusMenu} add command -label "Member Branch Initialize" -command [list xflow_initbranchCallback ${exp_path} ${datestamp} $node ${extension} $canvas ]
   ${statusMenu} add command -label "Abort" -command [list xflow_abortCallback ${exp_path} ${datestamp} $node ${extension} $canvas ]
   if {$CHECK_PERMISSION == false} { 
      ${submitMenu} entryconfigure "Loop Submit"   -state disabled
      ${submitMenu} entryconfigure "Member Submit" -state disabled
      ${submitMenu} entryconfigure "NO Dependency" -state disabled
      ${miscMenu}   entryconfigure "Force status"  -state disabled
   }
   if {${SUITE_PERMISSION} == false} {
      ${editMenu}   entryconfigure "Loop Config"   -state disabled
      ${editMenu}   entryconfigure "Loop Resource" -state disabled
   }
}

# creates the popup menu for a npt node
proc xflow_addNptNodeMenu { exp_path datestamp popmenu_w canvas node extension} {
   global CHECK_PERMISSION SUITE_PERMISSION

   set infoMenu ${popmenu_w}.info_menu
   set editMenu ${popmenu_w}.edit_menu
   set listingMenu ${popmenu_w}.listing_menu
   set submitMenu ${popmenu_w}.submit_menu
   set submitNoDependMenu ${popmenu_w}.submit_nodep_menu
   set miscMenu ${popmenu_w}.misc_menu
   set statusMenu ${popmenu_w}.status_menu

   ${infoMenu} add command -label "Node Info" -command [list xflow_nodeInfoCallback ${exp_path} ${datestamp} $node ${extension} $canvas ]
   ${infoMenu} add command -label "Node Dependencies" -command [list xflow_nodeDepCallback ${exp_path} ${datestamp} $node ${extension} $canvas ]
   ${infoMenu} add command -label "Node Batch" -command [list xflow_batchCallback ${exp_path} ${datestamp} $node ${extension} $canvas ]
   ${infoMenu} add command -label "Node Source" -command [list xflow_sourceCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w} "info"]
   ${infoMenu} add command -label "Node Config" -command [list xflow_configCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w} "info"]
   ${infoMenu} add command -label "Evaluated Node Config" -command [list xflow_evalConfigCreateWidgets ${exp_path} ${datestamp} $node ${extension} ${popmenu_w}]
   ${infoMenu} add command -label "Node Full Config" -command [list xflow_fullConfigCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w}]
   ${infoMenu} add command -label "Node Resource" -command [list xflow_resourceCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w} "info"]
   ${editMenu} add command -label "Node Source"   -command [list xflow_sourceCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w} "edit"]
   ${editMenu} add command -label "Node Config"   -command [list xflow_configCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w} "edit"]
   ${editMenu} add command -label "Node Resource" -command [list xflow_resourceCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w} "edit"]

   set currentExtension [SharedFlowNode_getNodeExtension ${exp_path} ${node} ${datestamp}]
   set status [SharedFlowNode_getMemberStatus ${exp_path} ${node} ${datestamp} ${currentExtension}]


   ${listingMenu} add command -label "Latest Success Listing" -command [list xflow_listingCallback ${exp_path} ${datestamp} $node ${extension} $canvas ] \
      -foreground [::DrawUtils::getBgStatusColor end]
   ${listingMenu} add command -label "Latest Abort Listing" \
      -command [list xflow_abortListingCallback ${exp_path} ${datestamp} $node ${extension} $canvas ] \
      -foreground [::DrawUtils::getBgStatusColor abort]
      ${listingMenu} add command -label "Latest Submission Listing" -command [list xflow_submissionListingCallback ${exp_path} ${datestamp} $node ${extension} $canvas ]
   ${listingMenu} add command -label "Compare Latest Success/Abort Listings" -command [list xflow_diffLatestListings ${exp_path} ${datestamp} $node ${extension} $canvas]
   ${listingMenu} add command -label "All Node Listing" -command [list xflow_allListingCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w}]

   switch ${status} {
      begin {
         ${listingMenu} add command -label "Monitor Listing" -command [list xflow_tailfCallback ${exp_path} ${datestamp} $node ${extension} $canvas ] \
            -foreground [::DrawUtils::getBgStatusColor begin]
      }
      wait {
         ${infoMenu} insert 0 command -label "Follow Current Dependency" -command [list xflow_followDependency ${exp_path} ${datestamp} $node ${extension} ]
         ${listingMenu} add command -label "Monitor Listing" -command [list xflow_viewOutputFile  ${exp_path} ${datestamp} $node ${extension} $canvas] \
            -foreground [::DrawUtils::getBgStatusColor begin]
      }
      default {
         ${listingMenu} add command -label "Monitor Listing" -command [list xflow_viewOutputFile  ${exp_path} ${datestamp} $node ${extension} $canvas] \
            -foreground [::DrawUtils::getBgStatusColor begin]
      }
   }

   ${submitMenu} add command -label "Submit & Continue" -command [list xflow_submitNpassTaskCallback ${exp_path} ${datestamp} $node ${extension} $canvas continue ]
   ${submitMenu} add command -label "Submit & Stop" -command [list xflow_submitNpassTaskCallback ${exp_path} ${datestamp} $node ${extension} $canvas stop ]
   ${submitMenu} add cascade -label "NO Dependency" -underline 4 -menu [menu ${submitNoDependMenu}]
   ${submitNoDependMenu} add command -label "Submit & Continue" -underline 9 \
      -command [list xflow_submitNpassTaskCallback ${exp_path} ${datestamp} $node ${extension} $canvas continue dep_off ]
   ${submitNoDependMenu} add command -label "Submit & Stop" -underline 9 \
      -command [list xflow_submitNpassTaskCallback ${exp_path} ${datestamp} $node ${extension} $canvas stop dep_off ]

   # ${miscMenu} add command -label "New Window" -command [list xflow_newWindowCallback $node $canvas ${popmenu_w}]
   ${miscMenu} add command -label "View Workdir" -command [list xflow_launchWorkCallback ${exp_path} ${datestamp} $node $canvas ]
   ${miscMenu} add command -label "Save Workdir" -command [list xflow_saveWorkCallback ${exp_path} ${datestamp} $node $canvas ]
   ${statusMenu} add command -label "Initnode" -command [list xflow_initnodeNpassTaskCallback ${exp_path} ${datestamp} $node ${extension} $canvas ]
   ${statusMenu} add command -label "End" -command [list xflow_endNpassTaskCallback ${exp_path} ${datestamp} $node ${extension} $canvas ]
   ${statusMenu} add command -label "Abort" -command [list xflow_abortNpassTaskCallback ${exp_path} ${datestamp} $node ${extension} $canvas ]
   if {$CHECK_PERMISSION == false} {
      ${submitMenu} entryconfigure "Submit & Continue" -state disabled
      ${submitMenu} entryconfigure "Submit & Stop"     -state disabled
      ${submitMenu} entryconfigure "NO Dependency"     -state disabled
      ${miscMenu}   entryconfigure "Save Workdir"      -state disabled
   } 
   if {${SUITE_PERMISSION} == false} {
     ${editMenu}   entryconfigure "Node Source"       -state disabled
     ${editMenu}   entryconfigure "Node Config"       -state disabled
      ${editMenu}   entryconfigure "Node Resource"     -state disabled        
  } 
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

# returns the loop arguments as needed by the maestro sequencer binaries
# like nodeinfo or maestro i.e. "-l gem_loop=3,transfer=001"
#
# the "extension" can be passed so that the extension is directly used
# instead of getting from the flow... this is mainly when the procedure
# is called from msg center with an abort where the extension is already specified.
# 
# 
# input arguments:
# extension is "+3+001" from the above example
# source_w must be reference to flow canvas if "extension" is ""
# raise_no_index_error if this value is true and the latest iteration is selected
#                      by the user, the proc will return -1 so that the caller can
#                      handle the error properly
# 
proc xflow_getSeqLoopArgs {  exp_path datestamp node extension source_w {raise_no_index_error false}} {
   ::log::log debug "xflow_getSeqLoopArgs exp_path:$exp_path datestamp:$datestamp node:$node extension:$extension "

   set seqLoopArgs ""
   if { [SharedFlowNode_getNodeType ${exp_path} ${node} ${datestamp}] == "npass_task" } {
      set loopIndex ""
      # retrieve index value from widget
      if { ${extension} == "" } {
         # in this case source_w must be canvas
         set indexListW [::DrawUtils::getIndexWidgetName $node ${source_w}]
         set nptIndex  ""
         if { [winfo exists ${indexListW}] } {
            set nptIndex  [${indexListW} get]
            if { ${nptIndex} == "latest" && ${raise_no_index_error} == true } {
               set seqLoopArgs -1
	    }
         }
      } else {
         # npt task could well be within loop nodes... split between loop part and npt part
         set lastIndex [string last + ${extension}]
         if { ${lastIndex} == 0 } {
            # no loop index
	    set loopIndex ""
	    set nptIndex ${extension}
         } else {
            # split the two
	    set loopIndex [string range ${extension} 0 [expr ${lastIndex} -1]]
	    set nptIndex  [string range ${extension} ${lastIndex} end]
         }
      }

      if { ${seqLoopArgs} != -1 } {
         set seqLoopArgs [SharedFlowNode_getNptArgs ${exp_path} ${node} ${datestamp} ${loopIndex} ${nptIndex}]
      }
   } else {
      set seqLoopArgs [SharedFlowNode_getLoopArgs ${exp_path} ${node} ${datestamp} ${extension}]
   }
   if { ${seqLoopArgs} == "-1" && ${raise_no_index_error} == false } {
      set seqLoopArgs ""
   }
   return ${seqLoopArgs}
}

# this function is called to show the history of a node
# By default, the middle mouse on a node shows the history for the last 48 hours.
# The "Node History" from the Info menu on the node shows only the current datestamp
proc xflow_historyCallback { exp_path datestamp node extension canvas {history 48} {full_loop 0} } {
   # ::log::log debug "xflow_historyCallback node:$node extension:$extension canvas:$canvas $full_loop"
   puts "xflow_historyCallback node:$node extension:$extension canvas:$canvas $full_loop"

   set seqExec nodehistory

   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]

   if { ${extension} == "" || ${extension} == "all" } {
      set nodeExt [SharedFlowNode_getListingNodeExtension ${exp_path} ${node} ${datestamp} ${full_loop}]
   } else {
      set nodeExt ${extension}
   }
   ::log::log debug "xflow_historyCallback nodeExt:$nodeExt"
   if { $nodeExt == "-1" } {
      Utils_raiseError $canvas "node listing" [xflow_getErroMsg NO_LOOP_SELECT]
   } else {
      if { $nodeExt != "" } {
         set nodeExt ".${nodeExt}"
      }

      set historyRange ""
      if { ${datestamp} != "" } {
         set historyRange "-history $history -edate $datestamp "
      }
      set winTitle "Node History ${seqNode}${nodeExt} -history $history - Exp=${exp_path}"
      Sequencer_runCommandWithWindow ${exp_path} ${datestamp} [winfo toplevel ${canvas}] $seqExec \
         ${winTitle} bottom 0 -n $seqNode$nodeExt ${historyRange}
   }
}

# shows the node information and is invoked from the "Node Info" menu item.
proc xflow_nodeInfoCallback { exp_path datestamp node extension canvas } {
   ::log::log debug "xflow_nodeInfoCallback exp_path:$exp_path datestamp:$datestamp node:$node extension:$extension"
   global env

   set nodeInfoExec "nodeinfo"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]
   set seqLoopArgs [xflow_getSeqLoopArgs ${exp_path} ${datestamp} ${node} ${extension} ${canvas}]
   set winTitle "Node Info ${seqNode} ${seqLoopArgs} - Exp=${exp_path}"
   Sequencer_runCommandWithWindow ${exp_path} ${datestamp} [winfo toplevel ${canvas}] ${nodeInfoExec} ${winTitle} top 0 -n $seqNode  ${seqLoopArgs}
}

proc xflow_nodeDepCallback { exp_path datestamp node extension canvas } {
   global env

   set nodeInfoExec "nodeinfo"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]
   set seqLoopArgs [xflow_getSeqLoopArgs ${exp_path} ${datestamp} ${node} ${extension} ${canvas}]

   set winTitle "Node Dependencies ${seqNode} ${seqLoopArgs} - Exp=${exp_path}"
   Sequencer_runCommandWithWindow ${exp_path} ${datestamp} [winfo toplevel ${canvas}] ${nodeInfoExec} ${winTitle} top 0 -n $seqNode  ${seqLoopArgs} -f dep
}

# this command is invoked from the Misc->initbranch menu item
# It sends an initbranch signal to the maestro sequencer for the
# current container node. It deletes all sequencer related node status files for
# the current node and all its child nodes.
proc xflow_initbranchCallback { exp_path datestamp node extension canvas  } {
   if { ${datestamp} == "" } {
      Utils_raiseError $canvas "init branch" [xflow_getErroMsg DATESTAMP_REQUIRED]
      return
   }
   set seqExec "maestro"

   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]
   set seqLoopArgs [SharedFlowNode_getLoopArgs ${exp_path} ${node} ${datestamp} ${extension}]
   if { $seqLoopArgs == "" && [SharedFlowNode_hasLoops ${exp_path} ${node} ${datestamp}] } {
      Utils_raiseError $canvas "initbranch" [xflow_getErroMsg NO_LOOP_SELECT]
   } else {
      set winTitle "initbranch ${seqNode} ${seqLoopArgs} - Exp=${exp_path}"
      Sequencer_runCommandWithWindow ${exp_path} ${datestamp} [xflow_getToplevel ${exp_path} ${datestamp}] $seqExec ${winTitle} top 1 \
         -n $seqNode -s initbranch -f continue $seqLoopArgs -d $datestamp
      ::log::log notice "${seqExec} -n $seqNode -s initbranch -f continue $seqLoopArgs (datestamp=${datestamp})"
   }
}

# this command is invoked from the Misc->initnode menu item
# It sends an initnode signal to the maestro sequencer for the
# current task node. It deletes all sequencer related node status files for
# the current node.
proc xflow_initnodeCallback { exp_path datestamp node extension canvas  } {
   if { ${datestamp} == "" } {
      Utils_raiseError $canvas "node init" [xflow_getErroMsg DATESTAMP_REQUIRED]
      return
   }
   set seqExec "maestro"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]

   set seqLoopArgs [SharedFlowNode_getLoopArgs ${exp_path} ${node} ${datestamp} ${extension}]
   if { $seqLoopArgs == "" && [SharedFlowNode_hasLoops ${exp_path} ${node} ${datestamp}] } {
      Utils_raiseError $canvas "initnode" [xflow_getErroMsg NO_LOOP_SELECT]
   } else {
      set winTitle "initnode ${seqNode} ${seqLoopArgs} - Exp=${exp_path}"
      Sequencer_runCommandWithWindow ${exp_path} ${datestamp} [xflow_getToplevel ${exp_path} ${datestamp}] $seqExec ${winTitle} top 1 \
         -n $seqNode -s initnode -f continue $seqLoopArgs
      ::log::log notice "${seqExec} -n $seqNode -s initnode -f continue $seqLoopArgs (datestamp=${datestamp})"
   }
}

# this command is invoked from the Misc->initbranch menu item
# It sends an initbranch signal to the maestro sequencer for the
# current loop node. It deletes all sequencer related node status files for
# the current loop node and all its child iteration nodes.
proc xflow_initbranchLoopCallback { exp_path datestamp node canvas  } {
   if { ${datestamp} == "" } {
      Utils_raiseError $canvas "init branch" [xflow_getErroMsg DATESTAMP_REQUIRED]
      return
   }

   set seqExec "maestro"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]

   set seqLoopArgs [SharedFlowNode_getParentLoopArgs ${exp_path} ${node} ${datestamp}]
   if { $seqLoopArgs == "-1" && [SharedFlowNode_hasLoops ${exp_path} ${node} ${datestamp}] } {
      Utils_raiseError $canvas "initbranch" [xflow_getErroMsg NO_LOOP_SELECT]
   } else {
      set winTitle "initbranch ${seqNode} ${seqLoopArgs} - Exp=${exp_path}"
      Sequencer_runCommandWithWindow ${exp_path} ${datestamp} [xflow_getToplevel ${exp_path} ${datestamp}] $seqExec ${winTitle} top 1 \
         -n $seqNode -s initbranch -f continue $seqLoopArgs
      ::log::log notice "${seqExec} -n $seqNode -s initbranch -f continue $seqLoopArgs (datestamp=${datestamp})"
   }
}

# forces an abort to be sent to maestro sequencer
proc xflow_abortCallback { exp_path datestamp node extension canvas } {
   if { ${datestamp} == "" } {
      Utils_raiseError $canvas "node abort" [xflow_getErroMsg DATESTAMP_REQUIRED]
      return
   }
   set seqExec "maestro"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]

   set seqLoopArgs [SharedFlowNode_getLoopArgs ${exp_path} ${node} ${datestamp} ${extension}]
   if { $seqLoopArgs == "" && [SharedFlowNode_hasLoops ${exp_path} ${node} ${datestamp}] } {
      Utils_raiseError $canvas "node abort" [xflow_getErroMsg NO_LOOP_SELECT]
   } else {
      set winTitle "abort ${seqNode} ${seqLoopArgs} - Exp=${exp_path}"
      Sequencer_runCommandWithWindow ${exp_path} ${datestamp}  [winfo toplevel ${canvas}] $seqExec ${winTitle} top 1 \
         -n $seqNode -s abort -f continue $seqLoopArgs
      ::log::log notice "${seqExec} -n $seqNode -s abort -f continue $seqLoopArgs (datestamp=${datestamp})"
   }
}

proc xflow_initnodeNpassTaskCallback { exp_path datestamp node extension canvas } {
   if { ${datestamp} == "" } {
      Utils_raiseError $canvas "node init" [xflow_getErroMsg DATESTAMP_REQUIRED]
      return
   }
   set seqExec "maestro"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]
   set seqLoopArgs [xflow_getSeqLoopArgs ${exp_path} ${datestamp} ${node} ${extension} ${canvas} true]

   if { ${seqLoopArgs} == "-1" } {
      Utils_raiseError $canvas "Npass_Task init" [xflow_getErroMsg NO_INDEX_SELECT]
   } else {
      ::log::log debug "xflow_abortNpassTaskCallback ${seqLoopArgs}"
         set winTitle "init ${seqNode} ${seqLoopArgs} - Exp=${exp_path}"
         Sequencer_runCommandWithWindow ${exp_path} ${datestamp} [winfo toplevel ${canvas}] $seqExec ${winTitle} top 1 \
            -n $seqNode -s initnode ${seqLoopArgs}
         ::log::log debug "xflow_abortNpassTaskCallback ${seqLoopArgs}"
         ::log::log notice "${seqExec} -n $seqNode -s initnode ${seqLoopArgs} (datestamp=${datestamp})"
   }
}

proc xflow_endNpassTaskCallback { exp_path datestamp node extension canvas } {
   if { ${datestamp} == "" } {
      Utils_raiseError $canvas "node end" [xflow_getErroMsg DATESTAMP_REQUIRED]
      return
   }
   set seqExec "maestro"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]
   set seqLoopArgs [xflow_getSeqLoopArgs ${exp_path} ${datestamp} ${node} ${extension} ${canvas} true]

   if { ${seqLoopArgs} == "-1" } {
      Utils_raiseError $canvas "Npass_Task end" [xflow_getErroMsg NO_INDEX_SELECT]
   } else {
      ::log::log debug "xflow_endNpassTaskCallback ${seqLoopArgs}"
         set winTitle "end ${seqNode} ${seqLoopArgs} - Exp=${exp_path}"
         Sequencer_runCommandWithWindow ${exp_path} ${datestamp} [winfo toplevel ${canvas}] $seqExec ${winTitle} top 1 \
            -n $seqNode -s end ${seqLoopArgs}
         ::log::log debug "xflow_endNpassTaskCallback ${seqLoopArgs}"
         ::log::log notice "${seqExec} -n $seqNode -s end ${seqLoopArgs} (datestamp=${datestamp})"
   }
}

proc xflow_abortNpassTaskCallback { exp_path datestamp node extension canvas } {
   if { ${datestamp} == "" } {
      Utils_raiseError $canvas "node abort" [xflow_getErroMsg DATESTAMP_REQUIRED]
      return
   }
   set seqExec "maestro"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]
   set seqLoopArgs [xflow_getSeqLoopArgs ${exp_path} ${datestamp} ${node} ${extension} ${canvas} true]

   if { ${seqLoopArgs} == "-1" } {
      Utils_raiseError $canvas "Npass_Task abort" [xflow_getErroMsg NO_INDEX_SELECT]
   } else {
      ::log::log debug "xflow_abortNpassTaskCallback ${seqLoopArgs}"
         set winTitle "abort ${seqNode} ${seqLoopArgs} - Exp=${exp_path}"
         Sequencer_runCommandWithWindow ${exp_path} ${datestamp} [winfo toplevel ${canvas}] $seqExec ${winTitle} top 1 \
            -n $seqNode -s abort ${seqLoopArgs}
         ::log::log debug "xflow_abortNpassTaskCallback ${seqLoopArgs}"
         ::log::log notice "${seqExec} -n $seqNode -s abort ${seqLoopArgs} (datestamp=${datestamp})"
   }
}

# launch an xterm at $SEQ_EXP_HOME
proc xflow_launchShellCallback { exp_path } {
    global env
     Utils_launchShell $env(TRUE_HOST) ${exp_path} ${exp_path} "SEQ_EXP_HOME=${exp_path}"
}

# launch an xterm in ${TASK_BASEDIR} on the execution host
proc xflow_launchWorkCallback { exp_path datestamp node canvas {full_loop 0} } {
   ::log::log debug "xflow_launchWorkCallback node$node canvas$canvas"
   if { ${datestamp} == "" } {
      Utils_raiseError $canvas "view workdir" [xflow_getErroMsg DATESTAMP_REQUIRED]
      return
   }
   set seqExecWork nodework
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]
   set nodeExt [SharedFlowNode_getListingNodeExtension ${exp_path} ${node} ${datestamp} ${full_loop}]

   if { $nodeExt == "-1" } {
      Utils_raiseError $canvas "node listing" [xflow_getErroMsg NO_LOOP_SELECT]
   } else {
      ::log::log debug "$seqExecWork -n ${seqNode} -ext ${nodeExt}"
      if [ catch { set workpath [split [exec -ignorestderr ksh -c "export SEQ_EXP_HOME=${exp_path};export SEQ_DATE=${datestamp}; $seqExecWork -n ${seqNode} -ext ${nodeExt}"] ':'] } message ] {
         Utils_raiseError . "Retrieve node output" $message
         return 0
      }
      set taskBasedir "[lindex $workpath 1]${seqNode}${nodeExt}"
      Utils_launchShell [lindex $workpath 0] ${exp_path} [lindex $workpath 1] "TASK_BASEDIR=[lindex $workpath 1]"
   }
}

proc xflow_saveWorkCallback { exp_path datestamp node canvas } {
   set seqExec nodesavework
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]
   set nodeExt [SharedFlowNode_getListingNodeExtension ${exp_path} ${node} ${datestamp}]

   if { $nodeExt == "-1" } {
      Utils_raiseError $canvas "node savework" [xflow_getErroMsg NO_LOOP_SELECT]
   } else {
      ::log::log debug "$seqExec -n ${seqNode} -ext ${nodeExt} -d ${datestamp}"
      set winTitle "node savework ${seqNode} ${nodeExt} - Exp=${exp_path}"
      Sequencer_runCommandWithWindow ${exp_path} ${datestamp} [winfo toplevel ${canvas}] $seqExec ${winTitle} top 1 \
            -n $seqNode -d ${datestamp} -ext ${nodeExt}
   }
}

# this function is invoked from the "Kill Node" menu item.
# It displays the available jobids of currently running tasks
# for the user to kill.
proc xflow_killNodeFromDropdown { exp_path datestamp node extension source_w {all_node_instances false} } {
   ::log::log debug "xflow_killNodeFromDropdown  exp_path:${exp_path} node:${node} datestamp:${datestamp}"
   puts "xflow_killNodeFromDropdown  exp_path:${exp_path} node:${node} datestamp:${datestamp} extension:${extension}"

   global env
   set shadowColor [SharedData_getColor SHADOW_COLOR]
   set bgColor [SharedData_getColor CANVAS_COLOR]
   set id [clock seconds]
   set tmpdir $env(TMPDIR)
   set tmpfile "${tmpdir}/test$id"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]
   if { ${all_node_instances} == true } {
      set seqLoopArgs ""
   } else {
      set seqLoopArgs [xflow_getSeqLoopArgs ${exp_path} ${datestamp} ${node} ${extension} ${source_w}]
   }

   set killPath nodekill 

   set soloWindow ${source_w}_${node}_nodekill
   regsub -all "/" ${soloWindow} _ ${soloWindow}

   if { [winfo exists $soloWindow] } {
        destroy $soloWindow
    }

    puts "xflow_killNodeFromDropdown soloWindow:$soloWindow"

   toplevel $soloWindow
   set winTitle "Kill Node - ${seqNode} ${seqLoopArgs} Exp=${exp_path}"
   wm title ${soloWindow} ${winTitle}
   Utils_positionWindow ${soloWindow} ${source_w}

   frame $soloWindow.frame -relief raised -bd 2 -bg $bgColor
   pack $soloWindow.frame -fill both -expand 1 
   set listboxW [listbox $soloWindow.list -yscrollcommand "$soloWindow.yscroll set" \
	  -xscrollcommand "$soloWindow.xscroll set"  \
	  -height 10 -width 70 -selectmode extended -bg $bgColor -fg $shadowColor]
   scrollbar $soloWindow.yscroll -command "$soloWindow.list yview"  -bg $bgColor
   scrollbar $soloWindow.xscroll -command "$soloWindow.list xview" -orient horizontal -bg $bgColor

   set cancelButton [button $soloWindow.cancel_button -text "Close" \
      -command [list destroy $soloWindow ]]
   tooltip::tooltip $cancelButton "Close this window"
   pack $cancelButton -side right -padx 2 -pady 2

   set refreshButton [button $soloWindow.refresh_button -text "Refresh" \
      -command [list xflow_populateKillNodeListbox ${exp_path} ${datestamp} ${node} ${seqLoopArgs} ${listboxW} ]]
   tooltip::tooltip $refreshButton "Refresh entries"
   pack $refreshButton -side right -padx 2 -pady 2

   set killButton [button $soloWindow.kill_button -text "Kill Selected Jobs" \
      -command [list xflow_killNode ${exp_path} ${datestamp} ${node} $soloWindow.list ]]
   tooltip::tooltip $killButton "Send kill signals to selected job_ID"
   pack $killButton -side right -padx 2 -pady 2

   set allButton [button $soloWindow.all_button -text "All Node Instances" \
      -command [list xflow_killNodeFromDropdown ${exp_path} ${datestamp} ${node} "" ${source_w} true]]
   pack $allButton -side right -padx 2 -pady 2

   pack $soloWindow.xscroll -fill x -side bottom -in $soloWindow.frame
   pack $soloWindow.yscroll -side right -fill y -in $soloWindow.frame
   pack $soloWindow.list -expand 1 -fill both -padx 1m -side left -in $soloWindow.frame

   ::autoscroll::autoscroll ${soloWindow}.yscroll
   ::autoscroll::autoscroll ${soloWindow}.xscroll

   xflow_populateKillNodeListbox ${exp_path} ${datestamp} ${node} ${seqLoopArgs} ${listboxW}
}


proc xflow_populateKillNodeListbox { exp_path datestamp node seqLoopArgs listbox_w } {
   global env
   set tmpdir $env(TMPDIR)
   set id [clock seconds]
   set tmpdir $env(TMPDIR)
   set tmpfile "${tmpdir}/test$id"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]
   ::log::log debug "xflow_populateKillNodeListbox exp_path:${exp_path} datestamp:${datestamp} seqNode:${seqNode} node:${node}"

   set killPath nodekill 

   set cmd "export SEQ_EXP_HOME=${exp_path}; $killPath -n $seqNode ${seqLoopArgs} -list > $tmpfile 2>&1"
   ::log::log debug "xflow_populateKillNodeListbox ksh -c $cmd"
   catch { eval [exec -ignorestderr ksh -c $cmd ] }

   ${listbox_w} delete 0 end
   set resultingFile [open $tmpfile] 

   set separator "->"
   set dateseparator "@"
   while { [gets ${resultingFile} line ] >= 0 } {
      set listEntryValue [ split ${line} " " ]
      set separatorIndex [lsearch ${listEntryValue} ${separator}]
      if { ${separatorIndex} != -1 } {
   	   set dateIndex [expr ${separatorIndex} -3]
         set cellIndex [expr ${separatorIndex} +1]
         set jobIndex [expr ${separatorIndex} -1]
         set jobAndExt [lindex ${listEntryValue} end]
         set date "[lrange ${listEntryValue} ${dateIndex} [expr ${dateIndex} + 1]]"
         set jobAndCell "[lindex [split [lindex ${listEntryValue} $jobIndex] $dateseparator] 1] -> [lindex ${listEntryValue} ${cellIndex}]"

         ${listbox_w} insert end "${date} ${jobAndCell} ${jobAndExt}"
      }
   }

   catch {[exec -ignorestderr rm -f $tmpfile]}
}

# forces and end signal to be sent to the maestro sequencer for the current node.
proc xflow_endCallback { exp_path datestamp node extension canvas } {
   if { ${datestamp} == "" } {
      Utils_raiseError $canvas "node end" [xflow_getErroMsg DATESTAMP_REQUIRED]
      return
   }
   set seqExec "maestro"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]

   set seqLoopArgs [SharedFlowNode_getLoopArgs ${exp_path} ${node} ${datestamp} ${extension}]
   if { $seqLoopArgs == "" && [SharedFlowNode_hasLoops ${exp_path} ${node} ${datestamp}] } {
      Utils_raiseError $canvas "node end" [xflow_getErroMsg NO_LOOP_SELECT]
   } else {
      set winTitle "end ${seqNode} ${seqLoopArgs} - Exp=${exp_path}"
      Sequencer_runCommandWithWindow ${exp_path} ${datestamp} [winfo toplevel ${canvas}] $seqExec ${winTitle} top 1 \
         -n $seqNode -s end -f continue $seqLoopArgs
      ::log::log notice "$seqExec -n $seqNode -s end -f continue $seqLoopArgs (datestamp=${datestamp})"
   }

}

# forces a begin signal to be sent to the maestro sequencer for the current node.
proc xflow_beginCallback { exp_path datestamp node extension canvas } {
   if { ${datestamp} == "" } {
      Utils_raiseError $canvas "node begin" [xflow_getErroMsg DATESTAMP_REQUIRED]
      return
   }
   set seqExec "maestro"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]

   set seqLoopArgs [SharedFlowNode_getLoopArgs ${exp_path} ${node} ${datestamp} ${extension}]
   if { $seqLoopArgs == "" && [SharedFlowNode_hasLoops ${exp_path} ${node} ${datestamp}] } {
      Utils_raiseError $canvas "node begin" [xflow_getErroMsg NO_LOOP_SELECT]
   } else {
      set winTitle "begin ${seqNode} ${seqLoopArgs} - Exp=${exp_path}"
      Sequencer_runCommandWithWindow ${exp_path} ${datestamp} [winfo toplevel ${canvas}] $seqExec ${winTitle} top 1 \
         -n $seqNode -s begin -f continue $seqLoopArgs
      ::log::log notice "$seqExec -n $seqNode -s begin -f continue $seqLoopArgs (datestamp=${datestamp})"
   }

}


# forces and end signal to be sent to the maestro sequencer for the current loop node.
proc xflow_endLoopCallback { exp_path datestamp node canvas caller_menu } {
   if { ${datestamp} == "" } {
      Utils_raiseError $canvas "node end" [xflow_getErroMsg DATESTAMP_REQUIRED]
      return
   }
   set seqExec "maestro"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]

   set seqLoopArgs [SharedFlowNode_getParentLoopArgs ${exp_path} ${node} ${datestamp}]
   if { $seqLoopArgs == "-1" && [SharedFlowNode_hasLoops ${exp_path} ${node} ${datestamp}] } {
      Utils_raiseError $canvas "loop end" [xflow_getErroMsg NO_LOOP_SELECT]
   } else {
      set winTitle "end ${seqNode} ${seqLoopArgs} - Exp=${exp_path}"
      Sequencer_runCommandWithWindow ${exp_path} ${datestamp} [xflow_getToplevel ${exp_path} ${datestamp}] $seqExec ${winTitle} top 1 \
         -n $seqNode -s end -f continue $seqLoopArgs
      ::log::log notice "$seqExec -n $seqNode -s end -f continue $seqLoopArgs (datestamp=${datestamp})"
   }
}

# forces a begin signal to be sent to the maestro sequencer for the current loop node.
proc xflow_beginLoopCallback { exp_path datestamp node canvas caller_menu } {
   if { ${datestamp} == "" } {
      Utils_raiseError $canvas "node begin" [xflow_getErroMsg DATESTAMP_REQUIRED]
      return
   }
   set seqExec "maestro"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]

   set seqLoopArgs [SharedFlowNode_getParentLoopArgs ${exp_path} ${node} ${datestamp}]
   if { $seqLoopArgs == "-1" && [SharedFlowNode_hasLoops ${exp_path} ${node} ${datestamp}] } {
      Utils_raiseError $canvas "loop begin" [xflow_getErroMsg NO_LOOP_SELECT]
   } else {
      set winTitle "begin ${seqNode} ${seqLoopArgs} - Exp=${exp_path}"
      Sequencer_runCommandWithWindow ${exp_path} ${datestamp} [xflow_getToplevel ${exp_path} ${datestamp}] $seqExec ${winTitle} top 1 \
         -n $seqNode -s begin -f continue $seqLoopArgs
      ::log::log notice "$seqExec -n $seqNode -s begin -f continue $seqLoopArgs (datestamp=${datestamp})"
   }
}



# displays the content of a task node (.tsk)
proc xflow_sourceCallback { exp_path datestamp node canvas caller_menu action} {
   global SESSION_TMPDIR
   set seqExec nodesource
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]

   set textViewer [SharedData_getMiscData TEXT_VIEWER]
   set defaultConsole [SharedData_getMiscData DEFAULT_CONSOLE]

   set winTitle "Node Source ${seqNode} - Exp=${exp_path}"
   regsub -all " " ${winTitle} _ tempfile
   regsub -all "/" ${tempfile} _ tempfile
   if {${action} == "edit"} {
      if {![info exists env(SEQ_EXP_HOME)]} {
         set  SEQ_EXP_HOME ${exp_path}
      }
      eval set outputfile [string trim [lindex [split [exec -ignorestderr ksh -c  "nodeinfo -n ${seqNode} -f task -e ${exp_path}"] "="] 1]]
      #outputfile [string trim [lindex [split [exec -ignorestderr ksh -c  "eval nodeinfo -n ${seqNode} -f task -e ${exp_path}"] "="] 1]]
   } else {
      set outputfile "${SESSION_TMPDIR}/${tempfile}_[clock seconds]"
      set seqCmd "${seqExec} -n ${seqNode}"
      Sequencer_runCommand ${exp_path} ${datestamp} ${outputfile} ${seqCmd} 0 "null"
   }
   if { ${textViewer} == "default" } {
      TextEditor_createWindow ${winTitle} ${outputfile} top .
   } else {
      set editorCmd "${textViewer} ${outputfile}"
      ::log::log debug "xflow_sourceCallback running ${defaultConsole} ${editorCmd}"
      TextEditor_goKonsole ${defaultConsole} ${winTitle} ${editorCmd}
   }
}

# displays the content of a config file (.cfg) if it is available.
proc xflow_configCallback { exp_path datestamp node canvas caller_menu action} {
   global SESSION_TMPDIR
   set seqExec "nodeconfig"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]

   set textViewer [SharedData_getMiscData TEXT_VIEWER]
   set defaultConsole [SharedData_getMiscData DEFAULT_CONSOLE]

   set winTitle "Node Config ${seqNode} - Exp=${exp_path}"
   regsub -all " " ${winTitle} _ tempfile
   regsub -all "/" ${tempfile} _ tempfile
   if {${action} == "edit"} {
      set SEQ_EXP_HOME ${exp_path}
      eval set outputfile [string trim [lindex [split [exec -ignorestderr ksh -c  "nodeinfo -n ${seqNode} -f cfg -e ${exp_path}"] "="] 1]]
   } else {
      set outputfile "${SESSION_TMPDIR}/${tempfile}_[clock seconds]"
      set seqCmd "${seqExec} -n ${seqNode}"
      Sequencer_runCommand ${exp_path} ${datestamp} ${outputfile} ${seqCmd} 0
   }
   if { ${textViewer} == "default" } {
      TextEditor_createWindow ${winTitle} ${outputfile} top .
   } else {
      set editorCmd "${textViewer} ${outputfile}"
      ::log::log debug "xflow_configCallback running ${defaultConsole} ${editorCmd}"
      TextEditor_goKonsole ${defaultConsole} ${winTitle} ${editorCmd}
   }
}

proc xflow_evalConfigCreateWidgets { exp_path datestamp node extension caller_w } {
   global env
   global xflow_EvalConfigFullConfigVar xflow_SubmitHostsVar
   if { ! [info exists xflow_SubmitHostsVar] } {
      set xflow_SubmitHostsVar ""
      set hostsFile $env(SEQ_XFLOW_BIN)/../etc/submit_hosts
      if { [file readable ${hostsFile}] } {
         set xflow_SubmitHostsVar [exec -ignorestderr cat ${hostsFile}]
      }
   }

   set parentW [winfo toplevel ${caller_w}]
   set topLevelWidget [xflow_getWidgetName ${exp_path} ${datestamp} evalconfig_toplevel]
   if { [winfo exists ${topLevelWidget}] } {
      destroy ${topLevelWidget}
   }
   toplevel ${topLevelWidget}
   set xflow_EvalConfigFullConfigVar false
   wm geometry ${topLevelWidget} +[winfo pointerx ${parentW}]+[winfo pointery ${parentW}]
   wm title ${topLevelWidget} "Evaluated Config [file tail ${node}] (${node}) - Exp=${exp_path}"
   wm minsize  ${topLevelWidget} 300 100

   set attrFrame [frame ${topLevelWidget}.attr_frame]
   set machineLabel [label ${attrFrame}.machine_label -text "Machine:"]
   set machineEntry [ComboBox ${attrFrame}.machine_entry -values ${xflow_SubmitHostsVar}]
   ::tooltip::tooltip ${machineEntry} "Machine target where the evaluation will be done."
   if { [llength ${xflow_SubmitHostsVar}] == 1 } {
      ${machineEntry} setvalue first
   }

   set fullConfigLabel [label ${attrFrame}.fullconfig_label -text "Full Config:"]
   set fullConfigEntry [checkbutton ${attrFrame}.fullconfig_entry -indicatoron true \
                        -onvalue true -offvalue false -variable xflow_EvalConfigFullConfigVar]
   ::tooltip::tooltip ${fullConfigEntry} "When enable, will do a full evaluation up to this node."

   set buttonFrame [frame ${topLevelWidget}.button_frame]
   set closeButton [button ${buttonFrame}.close_button -text Close -command [list destroy ${topLevelWidget}]]
   set applyButton [button ${buttonFrame}.apply_button -text Apply -command [list xflow_goEvalConfig ${exp_path} ${datestamp} ${node} ${extension} ${topLevelWidget}]]

   grid ${machineLabel} -row 0 -column 0 -padx 2 -pady 2 -sticky w
   grid ${machineEntry} -row 0 -column 1 -padx 2 -pady 2 -sticky nesw
   grid ${fullConfigLabel} -row 1 -column 0 -padx 2 -pady 2 -sticky w
   grid ${fullConfigEntry} -row 1 -column 1 -padx 2 -pady 2 -sticky nesw

   grid ${applyButton} ${closeButton} -padx { 2 2 } -pady 5 -sticky e
   grid ${attrFrame} -row 0 -padx 2 -sticky news
   grid ${buttonFrame} -row 1 -padx 5 -sticky e

   # allow widgets in column to take all available horiz space
   grid columnconfigure ${attrFrame} 1 -weight 1
   grid columnconfigure ${attrFrame} 0 -weight 1

   # allow widgets in first column to take all available horiz space
   grid columnconfigure ${topLevelWidget} 0 -weight 1

   # allow widgets in first row to take all available vert space space
   grid rowconfigure ${topLevelWidget} 0 -weight 1

   # this section fetches the node.machine as given by nodeinfo
   set machine ""
   catch {
      set nodeInfoExec "nodeinfo"
      set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]
      set machine [exec -ignorestderr ksh -c "export SEQ_EXP_HOME=${exp_path};${nodeInfoExec} -n ${seqNode} -d ${datestamp} -f res | grep node.machine | sed -e 's:node.machine=::' 2> /dev/null "]
   }
   if { ${machine} != "" } {
      ${machineEntry} configure -text ${machine}
   }
}

proc xflow_goEvalConfig { exp_path datestamp node extension toplevel_w } {
   global SESSION_TMPDIR env
   global xflow_EvalConfigFullConfigVar
   set attrFrame ${toplevel_w}.attr_frame
   set machineEntry ${attrFrame}.machine_entry

   set machineValue [${machineEntry} get]

   if { ${machineValue} == "" } {
     return
   }
   set fullcfg ""
   if { [info exists xflow_EvalConfigFullConfigVar] && ${xflow_EvalConfigFullConfigVar} == true } {
      set fullcfg "-f 1"
   }

   set seqExec "evaluate_vars"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]
   set seqLoopArgs [SharedFlowNode_getLoopArgs ${exp_path} ${node} ${datestamp} ${extension}]

   set textViewer [SharedData_getMiscData TEXT_VIEWER]
   set defaultConsole [SharedData_getMiscData DEFAULT_CONSOLE]

   set winTitle "Evaluated Node Config ${seqNode} - Exp=${exp_path}"
   regsub -all " " ${winTitle} _ tempfile
   regsub -all "/" ${tempfile} _ tempfile
   set outputfile "${SESSION_TMPDIR}/${tempfile}_[clock seconds]"
   set seqCmd "${seqExec} -n ${seqNode} ${seqLoopArgs} -m ${machineValue} -d ${datestamp} ${fullcfg}"
   ::log::log debug "xflow_goEvalConfig $seqCmd"
   Utils_busyCursor ${toplevel_w}
   catch {
      Sequencer_runCommand ${exp_path} ${datestamp} ${outputfile} ${seqCmd} 1
   }
   Utils_normalCursor ${toplevel_w}

   if { ${textViewer} == "default" } {
      TextEditor_createWindow ${winTitle} ${outputfile} top .
   } else {
      set editorCmd "${textViewer} ${outputfile}"
      ::log::log debug "xflow_goEvalConfig running ${defaultConsole} ${editorCmd}"
      TextEditor_goKonsole ${defaultConsole} ${winTitle} ${editorCmd}
   }
}

proc xflow_fullConfigCallback { exp_path datestamp node canvas caller_menu } {
   global SESSION_TMPDIR
   set seqExec "chaindot.py"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]

   set textViewer [SharedData_getMiscData TEXT_VIEWER]
   set defaultConsole [SharedData_getMiscData DEFAULT_CONSOLE]

   #set winTitle "Node Full Config [file tail $node]"
   set winTitle "Node Full Config ${seqNode} - Exp=${exp_path}"
   regsub -all " " ${winTitle} _ tempfile
   regsub -all "/" ${tempfile} _ tempfile
   set outputfile "${SESSION_TMPDIR}/${tempfile}_[clock seconds]"

   set seqCmd "${seqExec} -n ${seqNode} -e ${exp_path} -o ${outputfile}"
   Sequencer_runCommand ${exp_path} ${datestamp} /dev/null ${seqCmd} 1

   if { ${textViewer} == "default" } {
      TextEditor_createWindow ${winTitle} ${outputfile} top .
   } else {
      set editorCmd "${textViewer} ${outputfile}"
      ::log::log debug "xflow_fullConfigCallback running ${defaultConsole} ${editorCmd}"
      TextEditor_goKonsole ${defaultConsole} ${winTitle} ${editorCmd}
   }
}

# displays the resource file (.def) if it is available
proc xflow_resourceCallback { exp_path datestamp node canvas caller_menu action} {
   global SESSION_TMPDIR
   set seqExec "noderesource"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]

   set textViewer     [SharedData_getMiscData TEXT_VIEWER]
   set defaultConsole [SharedData_getMiscData DEFAULT_CONSOLE]

   # set winTitle "Node Resource [file tail $node]"
   set winTitle "Node Resource ${seqNode} - Exp=${exp_path}"
   regsub -all " " ${winTitle} _ tempfile
   regsub -all "/" ${tempfile} _ tempfile
   if {${action} == "edit"} {
      set SEQ_EXP_HOME ${exp_path}
      eval set outputfile [string trim [lindex [split [exec -ignorestderr ksh -c  "nodeinfo -n ${seqNode} -f res_path -e ${exp_path}"] "="] 1]]
    } else {
      set outputfile "${SESSION_TMPDIR}/${tempfile}_[clock seconds]"
      set seqCmd "${seqExec} -n ${seqNode}"
      Sequencer_runCommand ${exp_path} ${datestamp} ${outputfile} ${seqCmd} 0
   }
   if { ${textViewer} == "default" } {
      TextEditor_createWindow ${winTitle} ${outputfile} top .
   } else {
      set editorCmd "${textViewer} ${outputfile}"
      ::log::log debug "xflow_resourceCallback running ${defaultConsole} ${editorCmd}"
      TextEditor_goKonsole ${defaultConsole} ${winTitle} ${editorCmd}
   }
}

# displays the latest batch command file generated by maestro
proc xflow_batchCallback { exp_path datestamp node extension canvas {full_loop 0} } {
   global SESSION_TMPDIR
   set seqExec "nodebatch"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]

   if { ${extension} == "" } {
      set nodeExt [SharedFlowNode_getListingNodeExtension ${exp_path} ${node} ${datestamp} ${full_loop}]
   } else {
      if { ${full_loop} == 0 } {
         set nodeExt ${extension}
      } else {
         # get the parent part of the extension
         set nodeExt [string range ${extension} 0 [expr [string last + ${extension}] -1]]
      }
   }

   set textViewer [SharedData_getMiscData TEXT_VIEWER]
   set defaultConsole [SharedData_getMiscData DEFAULT_CONSOLE]

   if { $nodeExt == "-1" } {
      Utils_raiseError $canvas "node listing" [xflow_getErroMsg NO_LOOP_SELECT]
   } else {

      if { $nodeExt != "" } {
         set nodeExt ".${nodeExt}"
      }

      set winTitle "Node Batch ${seqNode} - Exp=${exp_path}"
      regsub -all " " ${winTitle} _ tempfile
      regsub -all "/" ${tempfile} _ tempfile

      set outputfile "${SESSION_TMPDIR}/${tempfile}_[clock seconds]"
   
      set seqCmd "${seqExec} -n ${seqNode}${nodeExt}"
      Sequencer_runCommand ${exp_path} ${datestamp} ${outputfile} ${seqCmd} 0
   
      if { ${textViewer} == "default" } {
         TextEditor_createWindow ${winTitle} ${outputfile} top .
      } else {
         set editorCmd "${textViewer} ${outputfile}"
         ::log::log debug "xflow_batchCallback running ${defaultConsole} ${editorCmd}"
         TextEditor_goKonsole ${defaultConsole} ${winTitle} ${editorCmd}
      }
   }
}

# this function submits a node for execution to the maestro sequencer.
# 
# - the flow parameter is either "stop" or "continue" and specifies whether the flow should
# continue or stop executing upon completion of the current node
# - local_ignore should be set to "dep_off" for local dependencies to be ignored.
proc xflow_submitCallback { exp_path datestamp node extension canvas flow {local_ignore_dep dep_on} } {
   global SESSION_TMPDIR

   if { ${datestamp} == "" } {
      Utils_raiseError $canvas "node submit" [xflow_getErroMsg DATESTAMP_REQUIRED]
      return
   }

   set ignoreDepFlag ""
   if { ${local_ignore_dep} == "dep_off" } {
      set ignoreDepFlag " -i"
   }

   set seqExec "maestro"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]
   set seqLoopArgs [SharedFlowNode_getLoopArgs ${exp_path} ${node} ${datestamp} ${extension}]
   if { $seqLoopArgs == "" && [SharedFlowNode_hasLoops ${exp_path} ${node} ${datestamp}] } {
      Utils_raiseError $canvas "node submit" [xflow_getErroMsg NO_LOOP_SELECT]
   } else {
      set winTitle "submit ${seqNode} ${seqLoopArgs} - Exp=${exp_path}"
      set commandArgs "-d ${datestamp} -n $seqNode -s submit -f $flow $ignoreDepFlag $seqLoopArgs"
      ::log::log notice "${seqExec} ${commandArgs}"
      Sequencer_runSubmit ${exp_path} ${datestamp} [winfo toplevel ${canvas}] $seqExec ${winTitle} top 1 ${commandArgs}
   }
}

# same as previous but for loop node
proc xflow_submitLoopCallback { exp_path datestamp node extension canvas flow {local_ignore_dep dep_on}} {
   set ignoreDepFlag ""
   set tmpExpression ""
   if { ${datestamp} == "" } {
      Utils_raiseError $canvas "node submit" [xflow_getErroMsg DATESTAMP_REQUIRED]
      return
   }
   if { ${local_ignore_dep} == "dep_off" } {
      set ignoreDepFlag " -i"
   }
   set seqExec "maestro"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]
   set seqLoopArgs [SharedFlowNode_getParentLoopArgs ${exp_path} ${node} ${datestamp}]
   if { $seqLoopArgs == "-1" && [SharedFlowNode_hasLoops ${exp_path} ${node} ${datestamp}] } {
      Utils_raiseError $canvas "loop submit" [xflow_getErroMsg NO_LOOP_SELECT]
   } else {
      if { [TsvInfo_haskey ${exp_path} ${seqNode} ${datestamp} loop.expression] } { 
         set tmpExpression [TsvInfo_getNodeInfo ${exp_path} ${seqNode} ${datestamp} loop.expression]
      }
      if { $tmpExpression == "" } {
         set loopStart [ expr abs([TsvInfo_getNodeInfo ${exp_path} ${seqNode} ${datestamp} loop.start])]
         set loopStep [ expr abs([TsvInfo_getNodeInfo ${exp_path} ${seqNode} ${datestamp} loop.step])]
         set loopSet [ expr abs([TsvInfo_getNodeInfo ${exp_path} ${seqNode} ${datestamp} loop.set])]
         set loopEnd [ expr abs([TsvInfo_getNodeInfo ${exp_path} ${seqNode} ${datestamp} loop.end])]
         if { $loopSet == 0 } {
            set loopSet 1
         }
         set jobNumber [expr int([expr abs([expr floor([expr (($loopEnd - $loopStart)/${loopStep})+1])])])]
         set answer [tk_messageBox -message "You are submitting a loop of $jobNumber job(s), ${loopSet} member(s) at a time" -type okcancel -icon info]
      } else {
         set answertxt "You are submitting a loop of "
         set expArray [split $tmpExpression ","]
         set firstFlag 1
         set minusOneFlag 0
         set lastEnd 0
         set lastEndIsExt 0
         set tmpExt 0
         set loopExts [SharedFlowNode_getLoopExtensions $exp_path $node $datestamp]
         foreach def $expArray {
            set defArray [split $def ":"]
            if { $firstFlag != 1 } {
               append answertxt ", then "
               if { $lastEnd == [lindex $defArray 0] && $lastEndIsExt == 1 } {
                  set minusOneFlag 1
                  set lastEndIsExt 0
               }
            } else {
               set firstFlag 0
            }
            set lastEnd [lindex $defArray 1]
            while { [expr {$tmpExt+[lindex $defArray 2]}] <= $lastEnd } {
               set tmpExt [expr {$tmpExt+[lindex $defArray 2]}]
            }
            if { $tmpExt == $lastEnd } {
               set lastEndIsExt 1
            }
            set jobNumber [expr int([expr abs([expr floor([expr (([lindex $defArray 1] - [lindex $defArray 0])/[lindex $defArray 2])+1])])])]
            if { $minusOneFlag == 1 } {
               set jobNumber [expr {$jobNumber-1}]
               set minusOneFlag 0
            }
            set loopSet [lindex $defArray 3]
            append answertxt "${jobNumber} job(s), ${loopSet} member(s) at a time"
         }
         set answer [tk_messageBox -message "${answertxt}" -type okcancel -icon info]
      }
      switch -- $answer {
         cancel return
      }
      set winTitle "submit ${seqNode} ${seqLoopArgs} - Exp=${exp_path}"
      set commandArgs "-d ${datestamp} -n $seqNode -s submit -f $flow ${ignoreDepFlag} $seqLoopArgs"
      ::log::log notice "${seqExec} ${commandArgs}"
      Sequencer_runSubmit ${exp_path} ${datestamp} [winfo toplevel ${canvas}] $seqExec ${winTitle} top 1 ${commandArgs}
   }
}

# same as previous but for npt node
proc xflow_submitNpassTaskCallback { exp_path datestamp node extension canvas  flow {local_ignore_dep dep_on} } {

   ::log::log debug "xflow_submitNpassTaskCallback node:$node canvas:$canvas extension:$extension"
   set ignoreDepFlag ""
   if { ${datestamp} == "" } {
      Utils_raiseError $canvas "node submit" [xflow_getErroMsg DATESTAMP_REQUIRED]
      return
   }
   if { ${local_ignore_dep} == "dep_off" } {
      set ignoreDepFlag " -i"
   }
   set seqExec "maestro"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]

   set seqLoopArgs [xflow_getSeqLoopArgs ${exp_path} ${datestamp} ${node} ${extension} ${canvas} true]

   if { ${seqLoopArgs} == "-1" } {
      Utils_raiseError $canvas "Npass_Task submit" [xflow_getErroMsg NO_INDEX_SELECT]
   } else {
      ::log::log debug "xflow_submitNpassTaskCallback ${seqLoopArgs}"
      set winTitle "submit ${seqNode} ${seqLoopArgs} - Exp=${exp_path}"
      set commandArgs "-d ${datestamp} -n $seqNode -s submit -f $flow ${ignoreDepFlag} $seqLoopArgs"
      ::log::log notice "${seqExec} ${commandArgs}"
      Sequencer_runSubmit ${exp_path} ${datestamp} [winfo toplevel ${canvas}] $seqExec ${winTitle} top 1 ${commandArgs}
   }
}

# this function is invoked to do a 'tail -f' of tha currently-running task
proc xflow_tailfCallback { exp_path datestamp node extension canvas {full_loop 0} } {
    global env
    ::log::log debug "xflow_tailfCallback node$node canvas$canvas"
   if { ${datestamp} == "" } {
      Utils_raiseError $canvas "monitor listing" [xflow_getErroMsg DATESTAMP_REQUIRED]
      return
   }
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]
   set nodeExt [SharedFlowNode_getListingNodeExtension ${exp_path} ${node} ${datestamp} ${full_loop}]

   if { $nodeExt == "-1" } {
      Utils_raiseError $canvas "monitor listing" [xflow_getErroMsg NO_LOOP_SELECT]
   } else {
      if { $nodeExt != "" } {
         set nodeExt ".${nodeExt}"
      }
      ::log::log debug "xflow_tailfCallback looking for ${exp_path}/sequencing/output${seqNode}${nodeExt}.${datestamp}.pgmout*"

      set outputFile [xflow_getOutputFile ${exp_path} ${datestamp} $node]

      if { [file readable ${outputFile}] } {

         set taskMonitorCmd [SharedData_getMiscData XFLOW_LISTING_MONITOR_CMD]
         if { ${taskMonitorCmd} == "" } {
            # use default
	    set taskMonitorCmd "tail -f ${outputFile}"
         } else {
            set machine ""
            # added code to get machine
            catch {
               set nodeInfoExec "nodeinfo"
               set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]
               set machine [exec -ignorestderr ksh -c "export SEQ_EXP_HOME=${exp_path};${nodeInfoExec} -n ${seqNode} -d ${datestamp} -f res | grep node.machine | sed -e 's:node.machine=::' 2> /dev/null "]
            }
	    set taskMonitorCmd "${taskMonitorCmd} ${outputFile} ${machine}"
         }
         Utils_launchShell $env(TRUE_HOST) ${exp_path} ${exp_path} "Monitoring=${seqNode}${nodeExt}" ${taskMonitorCmd}
      } else {
         if { ${extension} == "all" } {
            xflow_listingCallback ${exp_path} ${datestamp} $node ${extension} $canvas 1
         } else {
            xflow_listingCallback ${exp_path} ${datestamp} $node ${extension} $canvas
         }
      }
   }
}

proc xflow_genericEditorCallback { exp_path datestamp canvas caller_menu file_path {action "view"}} {
   global SESSION_TMPDIR
   puts "exp_path:${exp_path} datestamp:${datestamp} file_path:${file_path}"
   set textViewer [SharedData_getMiscData TEXT_VIEWER]
   set defaultConsole [SharedData_getMiscData DEFAULT_CONSOLE]

   set winTitle "View File Exp=${exp_path} File=[file tail ${file_path}]"
   regsub -all " " ${winTitle} _ tempfile
   regsub -all "/" ${tempfile} _ tempfile
   if { ${action} == "view" || ! [file exists ${file_path}] } { 
     set outputfile "${SESSION_TMPDIR}/${tempfile}_[clock seconds]"
   } else {
     set outputfile  ${file_path}
   } 

   if [ catch { set trueFile [file normalize ${file_path}] }  message ] {
      Utils_raiseError $canvas "Editor Error" "Unable to read file ${file_path}"
      return
   }

   if { [file readable ${trueFile}] } {
      if { ${action} == "view" } { 
        file copy [exec -ignorestderr true_path ${trueFile}] ${outputfile}
      }
   } else {
      set fileId [open ${outputfile} "w"] 
      if { ! [file exists ${file_path}] } {
         puts ${fileId} "File ${file_path} does not exist!"
      } else {
         puts ${fileId} "Cannot open ${file_path}!"
      }
      close ${fileId}
   }

   if { ${textViewer} == "default" } {
      TextEditor_createWindow ${winTitle} ${outputfile} top .
   } else {
      set editorCmd "${textViewer} ${outputfile}"
      ::log::log debug "xflow_genericEditorCallback running ${defaultConsole} ${editorCmd}"
      TextEditor_goKonsole ${defaultConsole} ${winTitle} ${editorCmd}
   }
}

# verifies if the temp output file for a node exists
# and returns the path to the file if it exists.
# returns "" if not exists
proc xflow_getOutputFile { exp_path datestamp node } {
   if { ${datestamp} == "" } {
      return ""
   }
   set currentExtension [SharedFlowNode_getNodeExtension ${exp_path} ${node} ${datestamp}]
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]
   if { $currentExtension == "all" } {
      set nodeExt  ""
   } else {
      set nodeExt ${currentExtension}
   }

   if { $nodeExt != "" } {
      set nodeExt ".${nodeExt}"
   }
   set outputFile ""
   ::log::log debug "xflow_getOutputFile looking for ${exp_path}/sequencing/output${seqNode}${nodeExt}.${datestamp}.pgmout*"
   catch { set outputFile [exec -ignorestderr ksh -c "ls -rt1 ${exp_path}/sequencing/output${seqNode}${nodeExt}.${datestamp}.pgmout* | tail -n 1"] }
   ::log::log debug "xflow_getOutputFile outputFile:${outputFile}"
   return ${outputFile}
}

proc xflow_viewOutputFile { exp_path datestamp node extension canvas } {
   ::log::log debug "xflow_viewOutputFile exp_path: ${exp_path} datestamp:${datestamp} node:${node} extension:${extension}"
   set listingViewer [SharedData_getMiscData TEXT_VIEWER]
   set defaultConsole [SharedData_getMiscData DEFAULT_CONSOLE]
   set outputFile [xflow_getOutputFile ${exp_path} ${datestamp} $node]

   set nodeExt ${extension}
   if { ${extension} == "" } {
      set nodeExt [SharedFlowNode_getListingNodeExtension ${exp_path} ${node} ${datestamp}]
   }
   if { [file readable ${outputFile}] } {
		        
      # title is used only for default viewer
      set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]
      set winTitle "Node Output ${seqNode}${nodeExt}- Exp=${exp_path}"

      if { ${listingViewer} == "default" } {
         TextEditor_createWindow ${winTitle} ${outputFile} top .
      } else {
         set editorCmd "${listingViewer} ${outputFile}"
         TextEditor_goKonsole ${defaultConsole} ${winTitle} ${editorCmd}
      }
   } else {
      if { ${extension} == "all" } {
         xflow_listingCallback ${exp_path} ${datestamp} $node ${extension} $canvas 1
      } else {
         xflow_listingCallback ${exp_path} ${datestamp} $node ${extension} $canvas
      }
   }
}

# this function is invoked to show the latest succesfull node listing
proc xflow_listingCallback { exp_path datestamp node extension canvas {full_loop 0} } {
   global SESSION_TMPDIR
   ::log::log debug "xflow_listingCallback node:$node extension:${extension} canvas:$canvas"
   if { ${datestamp} == "" } {
      Utils_raiseError $canvas "node listing" [xflow_getErroMsg DATESTAMP_REQUIRED]
      return
   }
   set listingExec nodelister
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]

   if { ${extension} == "" } {
      set nodeExt [SharedFlowNode_getListingNodeExtension ${exp_path} ${node} ${datestamp} ${full_loop}]
   } else {
      if { ${full_loop} == 0 } {
         set nodeExt ${extension}
      } else {
         # get the parent part of the extension
         set nodeExt [string range ${extension} 0 [expr [string last + ${extension}] -1]]
      }
   }

   set listingViewer [SharedData_getMiscData TEXT_VIEWER]
   set defaultConsole [SharedData_getMiscData DEFAULT_CONSOLE]

   
   if { $nodeExt == "-1" } {
      Utils_raiseError $canvas "node listing" [xflow_getErroMsg NO_LOOP_SELECT]
   } else {
      if { $nodeExt != "" } {
         set nodeExt ".${nodeExt}"
      }
      # title is used only for default viewer
      #set winTitle "Node Listing [file tail $node]${nodeExt}.${datestamp}"
      set winTitle "Node Listing ${seqNode}${nodeExt}.${datestamp} - Exp=${exp_path}"
      regsub -all " " ${winTitle} _ tempfile
      regsub -all "/" ${tempfile} _ tempfile
      set outputfile "${SESSION_TMPDIR}/${tempfile}_[clock seconds]"

      set seqCmd "${listingExec} -n ${seqNode}${nodeExt} -d ${datestamp}"
      Sequencer_runCommand ${exp_path} ${datestamp} ${outputfile} ${seqCmd} 1

      if { ${listingViewer} == "default" } {
         TextEditor_createWindow ${winTitle} ${outputfile} top .
      } else {
         set editorCmd "${listingViewer} ${outputfile}"
         TextEditor_goKonsole ${defaultConsole} ${winTitle} ${editorCmd}
      }
   }
}

# this funtion is invoked to list all the node listing for this node.
# this means all available listings in different datestamps
proc xflow_allListingCallback { exp_path datestamp node canvas caller_menu } {
  global env
   #puts "xflow_allListingCallback $exp_path $node $canvas $caller_menu"
   set shadowColor [SharedData_getColor SHADOW_COLOR]
   set bgColor [SharedData_getColor CANVAS_COLOR]
   set id [clock seconds]
   set tmpdir $env(TMPDIR)
   set tmpfile "${tmpdir}/test$id"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]
 
   set listerPath nodelister
   Utils_busyCursor [winfo toplevel ${canvas}]

   set result [ catch {
      set cmd "export SEQ_EXP_HOME=${exp_path}; $listerPath -n ${seqNode} -list > $tmpfile"
      ::log::log debug  "xflow_allListingCallback ksh -c $cmd"
      eval [exec -ignorestderr ksh -c $cmd ]
      ::log::log debug  "xflow_allListingCallback DONE: $cmd"
      
      set nodepath  [string range [file dirname ${seqNode}] 1 end]
      
      ##set fullList [list showAllListings $node $canvas $canvas.list]
      set listingW .listing_${node}
      regsub -all " " ${listingW} _
      regsub -all "/" ${listingW} _
      regsub -all "." ${listingW} _
      if { [winfo exists ${listingW}] } {
         destroy ${listingW}
      }
      toplevel ${listingW}
      wm geometry ${listingW} +[winfo pointerx ${caller_menu}]+[winfo pointery ${caller_menu}]
      wm title  ${listingW} "All listings ${node} - Exp=${exp_path}"

      #Images for the tabs
      set successImg [image create photo -width 10]
      set abortImg   [image create photo -width 10]
      set submitImg  [image create photo -width 10]
      $successImg put [::DrawUtils::getBgStatusColor end]      -to 0 0 10 10
      $abortImg   put [::DrawUtils::getBgStatusColor abort]    -to 0 0 10 10
      $submitImg  put [::DrawUtils::getBgStatusColor submit]   -to 0 0 10 10

      #Notebook widget for the tabs
      frame ${listingW}.nbframe
      set listingNb ${listingW}.nbframe.nb
      ttk::notebook ${listingNb}
      ${listingNb} add [frame ${listingNb}.successFrame] -text "Success" -image ${successImg} -compound left
      ${listingNb} add [frame ${listingNb}.abortFrame]   -text "Abort" -image ${abortImg} -compound left
      ${listingNb} add [frame ${listingNb}.submitFrame]  -text "Submission" -image ${submitImg} -compound left
      ${listingNb} select ${listingNb}.successFrame
      ttk::notebook::enableTraversal ${listingNb}
      
      #Bottom menu bar
      frame $listingW.mbar -relief raised -bd 2
      grid $listingW.mbar -column 1 -row 3 -sticky nsew
      button $listingW.mbar.quit -text Quit -command [list destroy ${listingW}]
      pack $listingW.mbar.quit -side right -pady .5m -padx 1m

      #Divide the window in 4 parts: success listings, abort listings, submission listings and compare listings
      set subf1 ${listingNb}.successFrame
      frame $subf1.successButtons
      pack $subf1.successButtons -side bottom -fill x
      set subf2 ${listingNb}.abortFrame
      frame $subf2.abortButtons
      pack $subf2.abortButtons -side bottom -fill x
      set subf4 ${listingNb}.submitFrame
      frame $subf4.submitButtons
      pack $subf4.submitButtons -side bottom -fill x

      grid ${listingW}.nbframe -column 1 -row 1 -sticky nsew
      grid rowconfigure ${listingW} 1 -weight 1
      pack ${listingNb} -padx 5 -fill x
      
      TitleFrame $listingW.diffFrame -text "Compare listings"
      grid ${listingW}.diffFrame -column 1 -row 2 -sticky nsew -pady 10
      set subf3 [${listingW}.diffFrame getframe]
      frame $subf3.diffButtons
      pack $subf3.diffButtons -side bottom -fill x

      grid columnconfigure ${listingW} 1 -weight 1
   
      #Buttons and help balloons for each frame
      button $subf1.successButtons.successView -text "View selected" -command [list xflow_showAllListingItem ${exp_path} ${datestamp} $subf1.list success]
      pack $subf1.successButtons.successView -side left -pady .5m -padx 1m
      button $subf1.successButtons.successDiffAdd -text "Add selected to diff list" -command [list xflow_addToDiffList $subf1 $subf3 success]
      pack $subf1.successButtons.successDiffAdd -side left -pady .5m -padx 1m
      balloon $subf1.successButtons.successDiffAdd "Only two listings can be added to the compare list"
      button $subf2.abortButtons.abortView -text "View selected" -command [list xflow_showAllListingItem ${exp_path} ${datestamp} $subf2.list2 abort]
      pack $subf2.abortButtons.abortView -side left -pady .5m -padx 1m
      button $subf2.abortButtons.abortDiffAdd -text "Add selected to diff list" -command [list xflow_addToDiffList $subf2 $subf3 abort]
      pack $subf2.abortButtons.abortDiffAdd -side left -pady .5m -padx 1m
      balloon $subf2.abortButtons.abortDiffAdd "Only two listings can be added to the compare list"
      button $subf4.submitButtons.submitView -text "View selected" -command [list xflow_showAllListingItem ${exp_path} ${datestamp} $subf4.list4 submit]
      pack $subf4.submitButtons.submitView -side left -pady .5m -padx 1m
      button $subf4.submitButtons.submitDiffAdd -text "Add selected to diff list" -command [list xflow_addToDiffList $subf4 $subf3 submit]
      pack $subf4.submitButtons.submitDiffAdd -side left -pady .5m -padx 1m
      balloon $subf4.submitButtons.submitDiffAdd "Only two listings can be added to the compare list"
      button $subf3.diffButtons.diff -text Diff -command [list xflow_diffListing ${exp_path} ${datestamp} $subf3.list3]
      pack $subf3.diffButtons.diff -side left -pady .5m -padx 1m
      balloon $subf3.diffButtons.diff "Compare listings from the list above"
      button $subf3.diffButtons.removeDiff -text "Remove selected" -command [list xflow_removeDiff $subf3.list3 $subf1.list $subf2.list2 $subf4.list4]
      pack $subf3.diffButtons.removeDiff -side left -pady .5m -padx 1m

      #Listboxes, where the listings are listed
      listbox $subf1.list -yscrollcommand "${subf1}.yscroll set" \
          -xscrollcommand "${subf1}.xscroll set" -selectbackground gray5 \
          -height 10 -width 70 -selectmode multiple -bg $bgColor -fg [::DrawUtils::getBgStatusColor end]
      listbox $subf2.list2 -yscrollcommand "${subf2}.yscroll2 set" \
          -xscrollcommand "${subf2}.xscroll2 set" -selectbackground gray5 \
          -height 10 -width 70 -selectmode multiple -bg $bgColor -fg [::DrawUtils::getBgStatusColor abort]
      listbox $subf4.list4 -yscrollcommand "${subf4}.yscroll4 set" \
          -xscrollcommand "${subf4}.xscroll4 set" -selectbackground gray5 \
          -height 10 -width 70 -selectmode multiple -bg $bgColor -fg $shadowColor
      listbox $subf3.list3 -height 2 -width 70 -selectmode multiple -bg $bgColor -fg $shadowColor -selectbackground gray5

      #Scrollbars for the listboxes
      scrollbar $subf1.yscroll -command "${subf1}.list yview"  -bg $bgColor
      scrollbar $subf1.xscroll -command "${subf1}.list xview" -orient horizontal -bg $bgColor
      scrollbar $subf2.yscroll2 -command "${subf2}.list2 yview"  -bg $bgColor
      scrollbar $subf2.xscroll2 -command "${subf2}.list2 xview" -orient horizontal -bg $bgColor
      scrollbar $subf4.yscroll4 -command "${subf4}.list4 yview"  -bg $bgColor
      scrollbar $subf4.xscroll4 -command "${subf4}.list4 xview" -orient horizontal -bg $bgColor

      pack $subf1.xscroll -fill x -side bottom -in $subf1
      pack $subf1.yscroll -side right -fill y -in $subf1
      pack $subf1.list -expand 1 -fill both -side left -in $subf1
      pack $subf2.xscroll2 -fill x -side bottom -in $subf2
      pack $subf2.yscroll2 -side right -fill y -in $subf2
      pack $subf2.list2 -expand 1 -fill both -padx 1m -side left -in $subf2
      pack $subf4.xscroll4 -fill x -side bottom -in $subf4
      pack $subf4.yscroll4 -side right -fill y -in $subf4
      pack $subf4.list4 -expand 1 -fill both -padx 1m -side left -in $subf4
      pack $subf3.list3 -expand 1 -fill both -padx 1m -side left -in $subf3
      
      #Parse the listings
      set resultingFile [open $tmpfile]
      while { [gets $resultingFile line ] >= 0 } {
          if { [string first "On" $line] >= 0 } {
             set mach [string trimleft $line "On "]
             $subf1.list insert end $line
             $subf2.list2 insert end $line
             $subf4.list4 insert end $line
          } else {
             if { [string first "success" $line] > 1 } {
                set tmpLine "[string trim $line "\n"] ${mach}"
                set splittedArgs [regexp -all -inline {\S+} $tmpLine]
                set listingName  [file tail $splittedArgs]
                set listingFile "$nodepath/$listingName"
                $subf1.list insert end "[lindex $splittedArgs end-4] [lindex $splittedArgs end-3] [lindex $splittedArgs end-2] $listingFile"
             } elseif { [string first "abort" $line] > 1 } {
                set tmpLine "[string trim $line "\n"] $mach"
                set splittedArgs [regexp -all -inline {\S+} $tmpLine]
                set listingName  [file tail $splittedArgs]
                set listingFile "$nodepath/$listingName"
                $subf2.list2 insert end "[lindex $splittedArgs end-4] [lindex $splittedArgs end-3] [lindex $splittedArgs end-2] $listingFile"
             } else {
                set tmpLine "[string trim $line "\n"] $mach"
                set splittedArgs [regexp -all -inline {\S+} $tmpLine]
                set listingName  [file tail $splittedArgs]
                set listingFile "$nodepath/$listingName"
                $subf4.list4 insert end "[lindex $splittedArgs end-4] [lindex $splittedArgs end-3] [lindex $splittedArgs end-2] $listingFile"
             }
          }
     }
     catch {[exec -ignorestderr rm -f $tmpfile]}

      bind $subf1.list  <Double-Button-1> [list xflow_showAllListingItem ${exp_path} ${datestamp} $subf1.list success]
      bind $subf2.list2 <Double-Button-1> [list xflow_showAllListingItem ${exp_path} ${datestamp} $subf2.list2 abort]
      bind $subf4.list4 <Double-Button-1> [list xflow_showAllListingItem ${exp_path} ${datestamp} $subf4.list4 submit]
      Utils_normalCursor [winfo toplevel ${canvas}]

   } message ]

   # any errors, put the cursor back to normal state
   if { ${result} != 0  } {

      set einfo $::errorInfo
      set ecode $::errorCode
      Utils_normalCursor [winfo toplevel ${canvas}]
      # report the error with original details
      return -code ${result} \
         -errorcode ${ecode} \
         -errorinfo ${einfo} \
         ${message}
   }
}

#balloon help taken from http://wiki.tcl.tk/3060
#pop up a help text after a 1s duration mouseover
proc balloon {w help} {
    bind $w <Any-Enter> "after 1000 [list balloon:show %W [list $help]]"
    bind $w <Any-Leave> "destroy %W.balloon"
}
proc balloon:show {w arg} {
    if {[eval winfo containing  [winfo pointerxy .]]!=$w} {return}
    set top $w.balloon
    catch {destroy $top}
    toplevel $top -bd 1 -bg black
    wm overrideredirect $top 1
    if {[string equal [tk windowingsystem] aqua]}  {
        ::tk::unsupported::MacWindowStyle style $top help none
    }   
    pack [message $top.txt -aspect 10000 -bg lightyellow \
             -text $arg]
    set wmx [winfo rootx $w]
    set wmy [expr [winfo rooty $w]+[winfo height $w]]
    wm geometry $top \
      [winfo reqwidth $top.txt]x[winfo reqheight $top.txt]+$wmx+$wmy
    raise $top
}

#This function is invoked to add selected listings to the compare list in the
# "All Node Listing" window
proc xflow_addToDiffList { listf subf3 type } {
   if { $type == "success" } {
      set listName "list"
   } elseif { $type == "abort" } {
      set listName "list2"
   } elseif { $type == "submit" } {
      set listName "list4"
   }

   ::log::log debug "xflow_addToDiffList selection: [${listf}.${listName} curselection]"
   set selectedIndexes [ $listf.${listName} curselection ]
   foreach selectIndex $selectedIndexes {
      if { [$subf3.list3 size] < 2 } {
         set line [$listf.${listName} get $selectIndex]
         if { [string first "On " $line] != 0 } {
            $subf3.list3 insert end $line
            if { $type == "success" } {
               $subf3.list3 itemconfigure [expr [$subf3.list3 size] - 1] -background [::DrawUtils::getBgStatusColor end] -foreground [::DrawUtils::getFgStatusColor end]
               $listf.${listName} itemconfigure $selectIndex -background [::DrawUtils::getBgStatusColor end] -foreground [::DrawUtils::getFgStatusColor end]
            } elseif { $type == "abort" } {
               $subf3.list3 itemconfigure [expr [$subf3.list3 size] - 1] -background [::DrawUtils::getBgStatusColor abort] -foreground [::DrawUtils::getFgStatusColor abort]
               $listf.${listName} itemconfigure $selectIndex -background [::DrawUtils::getBgStatusColor abort] -foreground [::DrawUtils::getFgStatusColor abort]
            } else {
               $subf3.list3 itemconfigure [expr [$subf3.list3 size] - 1] -background [::DrawUtils::getBgStatusColor submit] -foreground [::DrawUtils::getFgStatusColor submit]
               $listf.${listName} itemconfigure $selectIndex -background [::DrawUtils::getBgStatusColor submit] -foreground [::DrawUtils::getFgStatusColor submit]
            }
         }
      }
   }
}

#This function is invoked to remove selected compare listings from the
# "All Node Listing" window
proc xflow_removeDiff { listw successlist abortlist submitlist } {
   set selectedIndexes [$listw curselection]
   if { [llength $selectedIndexes] == 1 } {
      set tmpLine [$listw get [lindex $selectedIndexes 0]]
      $listw delete [lindex $selectedIndexes 0]
      if { [string first "success" $tmpLine] > 1 } {
        set tmpSize [$successlist size]
	for {set i 0} {$i < $tmpSize} {incr i} {
	  if { $tmpLine == [$successlist get $i] } {
	      $successlist itemconfigure $i -bg [SharedData_getColor CANVAS_COLOR] -fg [::DrawUtils::getBgStatusColor end]
	  }
	}
      } elseif { [string first "abort" $tmpLine] > 1 } {
         set tmpSize [$abortlist size]
         for {set i 0} {$i < $tmpSize} {incr i} {
	   if { $tmpLine == [$abortlist get $i] } {
	      $abortlist itemconfigure $i -bg [SharedData_getColor CANVAS_COLOR] -fg [::DrawUtils::getBgStatusColor abort]
	   }
         }
      } else {
         set tmpSize [$submitlist size]
         for {set i 0} {$i < $tmpSize} {incr i} {
	   if { $tmpLine == [$submitlist get $i] } {
	      $submitlist itemconfigure $i -bg [SharedData_getColor CANVAS_COLOR] -fg [SharedData_getColor SHADOW_COLOR]
	   }
         }
      }
   } elseif { [llength $selectedIndexes] == 2 } {
      set tmpLineList {}
      lappend tmpLineList [$listw get [lindex $selectedIndexes 0]]
      lappend tmpLineList [$listw get [lindex $selectedIndexes 1]]
      $listw delete [lindex $selectedIndexes 0] [lindex $selectedIndexes 1]
      foreach tmpLine $tmpLineList {
	if { [string first "success" $tmpLine] > 1 } {
	  set tmpSize [$successlist size]
	  for {set i 0} {$i < $tmpSize} {incr i} {
	    if { $tmpLine == [$successlist get $i] } {
		$successlist itemconfigure $i -bg [SharedData_getColor CANVAS_COLOR] -fg [::DrawUtils::getBgStatusColor end]
	    }
	  }
	} elseif { [string first "abort" $tmpLine] > 1 } {
	  set tmpSize [$abortlist size]
	  for {set i 0} {$i < $tmpSize} {incr i} {
	    if { $tmpLine == [$abortlist get $i] } {
		$abortlist itemconfigure $i -bg [SharedData_getColor CANVAS_COLOR] -fg [::DrawUtils::getBgStatusColor abort]
	    }
	  }
	} else {
	  set tmpSize [$submitlist size]
	  for {set i 0} {$i < $tmpSize} {incr i} {
	    if { $tmpLine == [$submitlist get $i] } {
		$submitlist itemconfigure $i -bg [SharedData_getColor CANVAS_COLOR] -fg [SharedData_getColor SHADOW_COLOR]
	    }
	  }
        }
      }
   }
}

# this function is invoked to call tkdiff for the compare listings from the
# "All Node Listing" window
proc xflow_diffListing { exp_path datestamp listw } {
   global SESSION_TMPDIR
   ::log::log debug "xflow_diffListing listing 1: [$listw get 0] /// listing 2: [$listw get 1]"
   set selectedIndexes "0 1"
   set listingExec nodelister
   set tclsh [ exec -ignorestderr which maestro_wish8.5]

   if { [$listw size] == 2 } {
    foreach selectIndex $selectedIndexes {
	set selectedValue [$listw get $selectIndex]
	if { [string first "On " $selectedValue] != 0 } {
	  set splittedArgs [split $selectedValue]
	  set mach [lindex $splittedArgs end]
	  set listingFile [lindex $splittedArgs end-1]

	  set winTitle "[file tail ${exp_path}] - Listing [file tail ${listingFile}]"
	  regsub -all " " ${winTitle} _ tempfile
	  regsub -all "/" ${tempfile} _ tempfile
	  set outputfile "${SESSION_TMPDIR}/${tempfile}_[clock seconds]"

          set seqCmd "${listingExec} -f ${exp_path}//listings/${mach}//$listingFile@$mach"
          Sequencer_runCommand ${exp_path} ${datestamp} ${outputfile} ${seqCmd} 1

	  lappend outputList $outputfile
	}
    }
    
    if { [catch { exec -ignorestderr which xxdiff } errmsg] } {
       set tkdiff_location [ exec -ignorestderr which tkdiff ] 
       exec -ignorestderr ${tclsh} $tkdiff_location [lindex $outputList 0] [lindex $outputList 1] &
    } else {
       exec -ignorestderr xxdiff [lindex $outputList 0] [lindex $outputList 1] --text &
    }
   }
}

# this function is invoked to display the node listings selected from the
# "All Node Listing" window
proc xflow_showAllListingItem { exp_path datestamp listw list_type} {
   global SESSION_TMPDIR
   ::log::log debug "xflow_showAllListingItem selection: [$listw curselection]"
   set selectedIndexes [$listw curselection]
   set listingExec nodelister
   set listingViewer [SharedData_getMiscData TEXT_VIEWER]
   set defaultConsole [SharedData_getMiscData DEFAULT_CONSOLE]

   foreach selectIndex $selectedIndexes {
      set selectedValue [$listw get $selectIndex]
      if { [string first "On " $selectedValue] != 0 } {
         set splittedArgs [split $selectedValue]
         set mach [lindex $splittedArgs end]
         set listingFile [lindex $splittedArgs end-1]
         set splittedFile [split [file tail $listingFile] .]

         set winTitle "[file tail ${exp_path}] - ${list_type} Listing [file tail ${listingFile}]"
         regsub -all " " ${winTitle} _ tempfile
         regsub -all "/" ${tempfile} _ tempfile
         set outputfile "${SESSION_TMPDIR}/${tempfile}_[clock seconds]"
         
         set seqCmd "${listingExec} -f ${exp_path}/listings/${mach}/$listingFile@$mach"
         Sequencer_runCommand ${exp_path} ${datestamp} ${outputfile} ${seqCmd} 1
         if { ${listingViewer} == "default" } {
            TextEditor_createWindow ${winTitle} ${outputfile} top .
         } else {
            set editorCmd "${listingViewer} ${outputfile}"
            TextEditor_goKonsole ${defaultConsole} ${winTitle} ${editorCmd}
         }
      }
   }
}

#this function is invoked to call tkdiff on the node latest success and abort listings
proc xflow_diffLatestListings { exp_path datestamp node extension canvas {full_loop 0} } {
   global SESSION_TMPDIR
   ::log::log debug "xflow_diffLatestListings node:$node canvas:$canvas"
   set tclsh [ exec -ignorestderr which maestro_wish8.5]
   if { ${datestamp} == "" } {
      Utils_raiseError $canvas "node listing" [xflow_getErroMsg DATESTAMP_REQUIRED]
      return
   }
   set listingExec nodelister
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]

   if { ${extension} == "" } {
      set nodeExt [SharedFlowNode_getListingNodeExtension ${exp_path} ${node} ${datestamp} ${full_loop}]
   } else {
      if { ${full_loop} == 0 } {
         set nodeExt ${extension}
      } else {
         # get the parent part of the extension
         set nodeExt [string range ${extension} 0 [expr [string last + ${extension}] -1]]
      }
   }

   if { $nodeExt == "-1" } {
      Utils_raiseError $canvas "node listing" [xflow_getErroMsg NO_LOOP_SELECT]
   } else {
      if { $nodeExt != "" } {
         set nodeExt ".${nodeExt}"
      }

      set successWinTitle "success Listing [file tail $node]${nodeExt}.${datestamp}"
      regsub -all " " ${successWinTitle} _ tempfile
      regsub -all "/" ${tempfile} _ tempfile
      set successOutputfile "${SESSION_TMPDIR}/${tempfile}_[clock seconds]"
      set abortWinTitle "abort Listing [file tail $node]${nodeExt}.${datestamp}"
      regsub -all " " ${abortWinTitle} _ tempfile
      regsub -all "/" ${tempfile} _ tempfile
      set abortOutputfile "${SESSION_TMPDIR}/${tempfile}_[clock seconds]"

      set successSeqCmd "${listingExec} -n ${seqNode}${nodeExt} -type success -d ${datestamp}"
      Sequencer_runCommand ${exp_path} ${datestamp} ${successOutputfile} ${successSeqCmd} 1
      set abortSeqCmd "${listingExec} -n ${seqNode}${nodeExt} -type abort -d ${datestamp}"
      Sequencer_runCommand ${exp_path} ${datestamp} ${abortOutputfile} ${abortSeqCmd} 1

      if { [catch { exec -ignorestderr which xxdiff } errmsg] } {
         set tkdiff_location [ exec -ignorestderr which tkdiff ] 
         exec -ignorestderr ${tclsh} $tkdiff_location $successOutputfile $abortOutputfile &
      } else {
         exec -ignorestderr xxdiff $successOutputfile $abortOutputfile --text &
      }
   }
}

# this funtion is invoked to show the latest abort listing
proc xflow_abortListingCallback { exp_path datestamp node extension canvas {full_loop 0} } {
   global SESSION_TMPDIR
   ::log::log debug "xflow_abortListingCallback node:$node canvas:$canvas"
   if { ${datestamp} == "" } {
      Utils_raiseError $canvas "node listing" [xflow_getErroMsg DATESTAMP_REQUIRED]
      return
   }
   set abortListingExec nodelister
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]
   set listingViewer [SharedData_getMiscData TEXT_VIEWER]
   set defaultConsole [SharedData_getMiscData DEFAULT_CONSOLE]

   if { ${extension} == "" } {
      set nodeExt [SharedFlowNode_getListingNodeExtension ${exp_path} ${node} ${datestamp} ${full_loop}]
   } else {
      if { ${full_loop} == 0 } {
         set nodeExt ${extension}
      } else {
         # get the parent part of the extension
         set nodeExt [string range ${extension} 0 [expr [string last + ${extension}] -1]]
      }
   }

   if { $nodeExt == "-1" } {
      Utils_raiseError $canvas "node listing" [xflow_getErroMsg NO_LOOP_SELECT]
   } else {
      if { $nodeExt != "" } {
         set nodeExt ".${nodeExt}"
      }
      # title is used only for default viewer
      # set winTitle "abort Listing [file tail $node]${nodeExt}.${datestamp}"
      set winTitle "abort Listing [file tail $node]${nodeExt}.${datestamp}"
      regsub -all " " ${winTitle} _ tempfile
      regsub -all "/" ${tempfile} _ tempfile
      set outputfile "${SESSION_TMPDIR}/${tempfile}_[clock seconds]"

      set seqCmd "${abortListingExec} -n ${seqNode}${nodeExt} -type abort -d ${datestamp}"
      #set s1 [exec ${abortListingExec} -n ${seqNode}${nodeExt} -type abort -d ${datestamp}]
      #if { [string first "listing not available" $s1 1] > 1 } {
      #   set seqCmd "${abortListingExec} -n ${seqNode}${nodeExt} -type abort"
      #}
      Sequencer_runCommand ${exp_path} ${datestamp} ${outputfile} ${seqCmd} 1

      if { ${listingViewer} == "default" } {
         TextEditor_createWindow ${winTitle} ${outputfile} top .
      } else {
         set editorCmd "${listingViewer} ${outputfile}"
         TextEditor_goKonsole ${defaultConsole} ${winTitle} ${editorCmd}
      }
   }
}

# this funtion is invoked to show the latest submission listing
proc xflow_submissionListingCallback { exp_path datestamp node extension canvas {full_loop 0} } {
   global SESSION_TMPDIR
   ::log::log debug "xflow_submissionListingCallback node:$node canvas:$canvas"
   if { ${datestamp} == "" } {
      Utils_raiseError $canvas "node listing" [xflow_getErroMsg DATESTAMP_REQUIRED]
      return
   }
   set submissionListingExec nodelister
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]
   set listingViewer [SharedData_getMiscData TEXT_VIEWER]
   set defaultConsole [SharedData_getMiscData DEFAULT_CONSOLE]

   if { ${extension} == "" } {
      set nodeExt [SharedFlowNode_getListingNodeExtension ${exp_path} ${node} ${datestamp} ${full_loop}]
   } else {
      if { ${full_loop} == 0 } {
         set nodeExt ${extension}
      } else {
         # get the parent part of the extension
         set nodeExt [string range ${extension} 0 [expr [string last + ${extension}] -1]]
      }
   }

   if { $nodeExt == "-1" } {
      Utils_raiseError $canvas "node listing" [xflow_getErroMsg NO_LOOP_SELECT]
   } else {
      if { $nodeExt != "" } {
         set nodeExt ".${nodeExt}"
      }
      # title is used only for default viewer
      # set winTitle "abort Listing [file tail $node]${nodeExt}.${datestamp}"
      set winTitle "submission Listing [file tail $node]${nodeExt}.${datestamp}"
      regsub -all " " ${winTitle} _ tempfile
      regsub -all "/" ${tempfile} _ tempfile
      set outputfile "${SESSION_TMPDIR}/${tempfile}_[clock seconds]"

      set seqCmd "${submissionListingExec} -n ${seqNode}${nodeExt} -type submission -d ${datestamp}"
      #set s1 [exec ${submissionListingExec} -n ${seqNode}${nodeExt} -type submission -d ${datestamp}]
      #if { [string first "listing not available" $s1 1] > 1 } {
      #   set seqCmd "${submissionListingExec} -n ${seqNode}${nodeExt} -type submission"
      #}
      Sequencer_runCommand ${exp_path} ${datestamp} ${outputfile} ${seqCmd} 1

      if { ${listingViewer} == "default" } {
         TextEditor_createWindow ${winTitle} ${outputfile} top .
      } else {
         set editorCmd "${listingViewer} ${outputfile}"
         TextEditor_goKonsole ${defaultConsole} ${winTitle} ${editorCmd}
      }
   }
}

# this function is called when the user selects an index from the npt or loop
# listbox. It redraws the flow starting from the selected widget
proc xflow_indexedNodeSelectionCallback { exp_path node datestamp canvas combobox_w} {
   ::log::log debug "xflow_indexedNodeSelectionCallback ${exp_path} node:${node} datestamp:${datestamp} canvas:${canvas} $combobox_w"
   set member [${combobox_w} get]

   if { $member != "latest" && [lindex $member 0] != "+" } {
      set member +${member}
   }

   # puts "xflow_indexedNodeSelectionCallback SharedFlowNode_setCurrentExt ${exp_path} ${node} ${datestamp} ${member}"
   SharedFlowNode_setCurrentExt ${exp_path} ${node} ${datestamp} ${member}

   # puts "xflow_indexedNodeSelectionCallback xflow_redrawNodes ${exp_path} ${datestamp} ${node} ${canvas}"
   xflow_redrawNodes ${exp_path} ${datestamp} ${node} ${canvas}
}

# this function is called to expand a node and all of its child nodes
proc xflow_expandAllCallback { exp_path datestamp node canvas caller_menu } {
   SharedFlowNode_uncollapseAll ${exp_path} ${node} ${datestamp}
   destroy $caller_menu
   xflow_drawflow ${exp_path} ${datestamp} $canvas
}

# callback when user click on a box with button 1 to collapse/expand a node
proc xflow_changeCollapsed { exp_path datestamp node canvas } {
   if { [SharedFlowNode_getSubmits ${exp_path} ${node} ${datestamp}] == "" } {
      ::log::log debug "changeCollapse: node has no children"
      return
   }

   set isCollapsed [SharedFlowNode_isCollapsed ${exp_path} ${node} ${datestamp}]
   ::log::log debug "xflow_changeCollapsed ${exp_path} ${node} ${datestamp} isCollapsed:$isCollapsed"
   if { $isCollapsed == 0 || $isCollapsed == 2 } {
      SharedFlowNode_setCollapsed ${exp_path} ${node} ${datestamp} 1
   } else {
      SharedFlowNode_setCollapsed ${exp_path} ${node} ${datestamp} 0
   }

   xflow_drawflow ${exp_path} ${datestamp} $canvas false
   if { [xflow_needBgImageRefresh ${exp_path} ${datestamp} ${canvas}] == true } {
      xflow_addBgImage ${exp_path} ${datestamp} ${canvas} [winfo width ${canvas}] [winfo height ${canvas}]
   }
}

# redraws the flow starting from a node... without having
# to clear all the canvas
proc xflow_redrawNodes { exp_path datestamp node {canvas ""} } {
   global cmdList_${exp_path}_${datestamp}
   ::log::log debug "xflow_redrawNodes exp_path:${exp_path} datestamp:${datestamp} node:$node"
   xflow_setRefreshMode ${exp_path} ${datestamp} true
   set cmdList_${exp_path}_${datestamp} ""
   # update idletasks
   catch {
      if { $canvas == "" } {
         set canvas [xflow_getMainFlowCanvas ${exp_path} ${datestamp}]
      } 

      set cmdList_${exp_path}_${datestamp} {}
      # instead of removing the nodes one by one, I'm collecting all the cmds
      # and run it at once to avoid less flickering on the gui
      ::DrawUtils::clearBranch ${exp_path} ${node} ${datestamp} ${canvas} cmdList_${exp_path}_${datestamp}
      set nodePosition [SharedFlowNode_getSubmitPosition ${exp_path} ${node} ${datestamp}]
      eval [set cmdList_${exp_path}_${datestamp}]
      xflow_drawNode ${exp_path} ${datestamp} ${canvas} ${node} ${nodePosition}
      xflow_resetScrollRegion ${canvas}
      if { [xflow_needBgImageRefresh ${exp_path} ${datestamp} ${canvas}] == true } {
         xflow_addBgImage ${exp_path} ${datestamp} ${canvas} [winfo width ${canvas}] [winfo height ${canvas}]
      }
   }
   xflow_setRefreshMode ${exp_path} ${datestamp} false
}

# redraws the flow for all canvas... if the user has multiple windows open
# on the same experiment
proc xflow_redrawAllFlow { exp_path datestamp } {
   global NODE_DISPLAY_PREF_${exp_path}_${datestamp} NODE_DISPLAY_PREF
   set NODE_DISPLAY_PREF_${exp_path}_${datestamp} ${NODE_DISPLAY_PREF}
   # the active suite could be empty if the redraw is
   # called from the LogReader in overview mode
   set canvas [xflow_getMainFlowCanvas ${exp_path} ${datestamp}]
   xflow_drawflow ${exp_path} ${datestamp} ${canvas} false
}

# user clicks on refresh button in the
# toolbar
# - deletes all nodes
# - rereads flow.xml for each module
# - reread the log file
# - redisplay the flow
proc xflow_refreshFlow { exp_path datestamp  {font false}} {
   global PROGRESS_REPORT_TXT

   #SharedData_readProperties
   #puts "PATH $exp_path $datestamp"
   set PROGRESS_REPORT_TXT "Refreshing experiment ..."
   set progressW [ProgressDlg .pdrefresh -title "Flow Refresh" -parent [xflow_getToplevel ${exp_path} ${datestamp}]  -textvariable PROGRESS_REPORT_TXT]
   # for some reason, I need to call the update for the progress dlg to appear properly
   update idletasks

   set result [ catch {

      global NODE_RESOURCE_DONE_${exp_path}_${datestamp} LOOP_RESOURCES_DONE_${exp_path}_${datestamp}
      set LOOP_RESOURCES_DONE_${exp_path}_${datestamp} false
      set NODE_RESOURCE_DONE_${exp_path}_${datestamp} false
      if {$font == "false" } {
        # SharedFlowNode_clearAllNodes ${exp_path} ${datestamp}
        if { [SharedData_getMiscData OVERVIEW_MODE] == "false" } {
           LogReader_startExpLogReader ${exp_path} ${datestamp} no_overview
        } else {
           set expThreadId [SharedData_getExpThreadId ${exp_path} ${datestamp}]
	   if { ${expThreadId} == "" } {
	     set expThreadId [ThreadPool_getNextThread]
	   }
           thread::send -async ${expThreadId} "LogReader_startExpLogReader ${exp_path} \"${datestamp}\" no_overview false" LogReaderDone
	   vwait LogReaderDone
        }
      }
      xflow_displayFlow ${exp_path} ${datestamp}
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
proc xflow_drawflow { exp_path datestamp canvas {initial_display true} } {
   ::log::log debug "xflow_drawflow() canvas:$canvas"

   if { [SharedFlowNode_isFlowModified ${exp_path} ${datestamp}] == "true" } {
      ::log::log debug "xflow_drawflow() xflow_refreshFlow"
      xflow_refreshFlow ${exp_path} ${datestamp}
      return
   }

   if { [winfo exists ${canvas}] } {
      ::log::log debug "xflow_drawflow() found existing canvas:$canvas"
      # reset the default spacing for drawing flow
      SharedData_resetExpDisplayData ${exp_path} ${datestamp} ${canvas}
      set rootNode [SharedData_getExpRootNode ${exp_path} ${datestamp}]
      xflow_addExpSettingsImg ${exp_path} ${datestamp} ${canvas}
      xflow_clearCanvasFlow ${canvas}
      xflow_drawNode ${exp_path} ${datestamp} $canvas $rootNode 0 true
      xflow_resetScrollRegion ${canvas}
   
      if { $initial_display == true } {
         # $canvas yview moveto 0
         # resize the window depending on size of canvas elements
         xflow_resizeWindow ${exp_path} ${datestamp} ${canvas}
      }

   }
   ::log::log debug "xflow_drawflow() done"
}

# add exp settings icon in flow canvas
proc xflow_addExpSettingsImg { exp_path datestamp canvas } {
   global CHECK_PERMISSION

   set expCfgImage ${canvas}.exp_cfg_image
   image create photo ${expCfgImage} -file [SharedData_getMiscData IMAGE_DIR]/config.png
   set iconStartX [expr [SharedData_getMiscData CANVAS_X_START] - 25]
   set iconY [SharedData_getMiscData CANVAS_Y_START]
  
   if { $CHECK_PERMISSION == false} {
      set read_only "READ-ONLY"
      set textfill black
      set y [expr ${iconY} - 30]
      ${canvas} create text ${iconStartX} ${y} -text ${read_only} -fill $textfill \
         -justify center -anchor w -font [::DrawUtils::getBoxLabelFont ${canvas}] -tag "read_only"
      tooltip::tooltip ${canvas}  -items read_only "User doesn't have permission to write in the experiment."
   } else {
      ${canvas} delete "read_only"
   }
   ${canvas} create image ${iconStartX} ${iconY} -image ${expCfgImage} -tag "ExpSettings"
   ${canvas} bind ExpSettings <Double-1> [list xflow_genericEditorCallback ${exp_path} ${datestamp} ${canvas} ${canvas} ${exp_path}/experiment.cfg]
   ${canvas} bind ExpSettings <Button-3> [list xflow_addExpSettingsMenu ${exp_path} ${datestamp} ${canvas} %X %Y]

   tooltip::tooltip ${canvas}  -items ExpSettings "View/edit experiment settings."

   set lineStartX [expr [SharedData_getMiscData CANVAS_X_START] - 10]
   set lineEndX [expr ${lineStartX} + 18]
   ::DrawUtils::drawline ${canvas} ${lineStartX} ${iconY} ${lineEndX} ${iconY} none \
    [SharedData_getColor FLOW_SUBMIT_ARROW] on [SharedData_getColor SHADOW_COLOR] settings
}

# right click popup menu from exp settings icon
proc xflow_addExpSettingsMenu { exp_path datestamp canvas x y } {
   global SUITE_PERMISSION

   set popMenu .pop_menu
   set ViewMenu $popMenu.viewmenu
   set EditMenu $popMenu.editmenu

   if { [winfo exists ${popMenu}] } {
      destroy ${popMenu}
   }

   set expConfigPath ${exp_path}/experiment.cfg
   set expResourcePath ${exp_path}/resources/resources.def
   set expOptionsPath ${exp_path}/ExpOptions.xml

   menu .pop_menu -title "Exp Settings" -tearoff 0
   ${popMenu} add cascade -label "View" -underline 0 -menu [menu ${ViewMenu}]
   ${popMenu} add cascade -label "Edit" -underline 0 -menu [menu ${EditMenu}]
   
   ${ViewMenu} add command -label "Exp Config" -underline 4 \
      -command [list xflow_genericEditorCallback ${exp_path} ${datestamp} ${canvas} ${popMenu} ${expConfigPath}]
   ${ViewMenu} add command -label "Exp Resource" -underline 4 \
      -command [list xflow_genericEditorCallback ${exp_path} ${datestamp} ${canvas} ${popMenu} ${expResourcePath}]
   ${ViewMenu} add command -label "Exp Options" -underline 4 \
      -command [list xflow_genericEditorCallback ${exp_path} ${datestamp} ${canvas} ${popMenu} ${expOptionsPath}]
   ${EditMenu} add command -label "Exp Config" -underline 4 \
      -command [list xflow_genericEditorCallback ${exp_path} ${datestamp} ${canvas} ${popMenu} ${expConfigPath} "edit"]
   ${EditMenu} add command -label "Exp Resource" -underline 4 \
       -command [list xflow_genericEditorCallback ${exp_path} ${datestamp} ${canvas} ${popMenu} ${expResourcePath} "edit"]
   ${EditMenu} add command -label "Exp Options" -underline 4 \
       -command [list xflow_genericEditorCallback ${exp_path} ${datestamp} ${canvas} ${popMenu} ${expOptionsPath} "edit"]
    
    if {${SUITE_PERMISSION} == false } {
       ${EditMenu}   entryconfigure "Exp Config"   -state disabled
       ${EditMenu}   entryconfigure "Exp Resource" -state disabled
       ${EditMenu}   entryconfigure "Exp Options"  -state disabled      
    } 
   # $popMenu add separator

   tk_popup $popMenu ${x} ${y}
}

# this function resizes the xflow main window depending on the
# items in the canvas
proc xflow_resizeWindow { exp_path datestamp canvas } {
   ::log::log debug "xflow_resizeWindow canvas:${canvas}"

   if { [SharedData_getExpFlowSize ${exp_path} ${datestamp}] != "" } {
      wm geometry [xflow_getToplevel ${exp_path} ${datestamp}] =[SharedData_getExpFlowSize ${exp_path} ${datestamp}]
   } else {
   if { [SharedData_getMiscData FLOW_GEOMETRY] == "" } {
      if { [winfo exists ${canvas}] } {
         set topLevel [winfo toplevel ${canvas}]
         set heightMax [lindex [wm maxsize ${topLevel}] 1]
         set widthMax [lindex [wm maxsize ${topLevel}] 0]
         set canvasMaximX [SharedData_getExpDisplayMaximumX ${exp_path} ${datestamp} ${canvas}]
         set canvasMaximY [SharedData_getExpDisplayMaximumY ${exp_path} ${datestamp} ${canvas}]
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
      wm geometry [xflow_getToplevel ${exp_path} ${datestamp}] =${flowGeometry}
   }
   }
   xflow_MouseWheelCheck ${canvas}

}

proc xflow_resetScrollRegion { _canvas } {
   set delta 5
   foreach { x1 y1 x2 y2 } [${_canvas} bbox flow_element] {
      set x1 [expr ${x1} - ${delta}]
      set y1 [expr ${y1} - ${delta}]
      set x2 [expr ${x2} + ${delta}]
      set y2 [expr ${y2} + ${delta}]
   }
   ${_canvas} configure -scrollregion [list 0 0 ${x2} ${y2}] -yscrollincrement 5 -xscrollincrement 5
   xflow_MouseWheelCheck ${_canvas}
}

# this command is called from a variable trace
# the proc definition requires 3 parameters for variable tracing
# however, defaults to empty strings... no need to pass parameters
# when called manually
proc xflow_nodeResourceCallback { exp_path datestamp {name1 ""} {name2 ""} {op ""} } {
   global NODE_RESOURCE_DONE_${exp_path}_${datestamp}
   global nodeResourceText
   # we only load the resources once
   if { [xflow_isNodePrefResourceRequired ${exp_path} ${datestamp}] == true } {
      if { ! [info exists NODE_RESOURCE_DONE_${exp_path}_${datestamp}] || [set NODE_RESOURCE_DONE_${exp_path}_${datestamp}] == "false" } {
         if { ${exp_path} != "" } {
            set toplevelW [xflow_getToplevel ${exp_path} ${datestamp}]
            set destroyProgressCmd  ""
            if { [wm state ${toplevelW}] == "normal" } {
	       puts "xflow_nodeResourceCallback $exp_path $datestamp  progress bar ..."
               set progressW [ProgressDlg .node_res_pd -parent ${toplevelW} -title "Node Display Preferrences" -textvariable nodeResourceText]
               # Utils_positionWindow ${progressW}
               set destroyProgressCmd  "destroy ${progressW}"
            }

            set nodeResourceText "Loading node resources ..."
            # for some reason, I need to call the update for the progress dlg to appear properly
            update idletasks
            ::log::log debug "xflow_nodeResourceCallback retrieving resources for ${exp_path}"
            set rootNode [SharedData_getExpRootNode ${exp_path} ${datestamp}]
            xflow_getNodeResources ${exp_path} ${rootNode} ${datestamp} 1
            set NODE_RESOURCE_DONE_${exp_path}_${datestamp} true
            eval ${destroyProgressCmd}
            unset nodeResourceText
         }
      }
   }
}

# this function retrives the node resource info by executing
# the maestro-utils nodeinfo. Recursivity can also be enabled using
# is_recursive function parameter.
proc xflow_getNodeResources { exp_path node datestamp {is_recursive 0} } {
   global env
   ::log::log debug "xflow_getNodeResources node:$node"

   set nodeInfoExec "nodeinfo"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]
   set outputFile $env(TMPDIR)/nodeinfo_output_[file tail $node]_[clock seconds]

   # for now we only care about batch resources from tasks
   ::log::log debug "${nodeInfoExec} -n ${seqNode} -f res |  sed -e 's:node.:$node configure -:' -e 's:=: :'"

   # the line below transforms the output of nodeinfo into a call to SharedFlowNode_setGenericAttributef or every attribute
   # i.e. SharedFlowNode_setGenericAttribute ${exp_path} ${node} attr_name attr_value
   set code [catch {set output [exec -ignorestderr ksh -c "export SEQ_EXP_HOME=${exp_path};${nodeInfoExec} -n ${seqNode} -d ${datestamp} -f res |  sed -e 's:node.:SharedFlowNode_setGenericAttribute ${exp_path} ${node} \"${datestamp}\" :' -e 's:=: \":' -e 's/$/\"/'> ${outputFile} 2> /dev/null "]} message]

   if { $code != 0 } {
      Utils_raiseError [xflow_getToplevel ${exp_path} ${datestamp}] "Get Node Resource" $message
      return 0
   }
   if [ catch { eval [exec -ignorestderr cat ${outputFile}] } message ] {
      ::log::log notice "\nERROR: xflow_getNodeResources() exp_path:${exp_path} node:${node} datestamp:${datestamp} $message"
   }

   if { $is_recursive } {
      set submits [SharedFlowNode_getSubmits ${exp_path} ${node} ${datestamp}]
      foreach submitName ${submits} {
         set submitNode ${node}/${submitName}
         xflow_getNodeResources ${exp_path} ${submitNode} ${datestamp} $is_recursive
      }
   }
}

# at startup fetches all the loop node attributes once only to be able to display
# the loop parameters
# NOTE: OBSOLETE PROC...
proc xflow_getAllLoopResourcesCallback { exp_path node datestamp} {
   global LOOP_RESOURCES_DONE_${exp_path}_${datestamp}
   if { ${datestamp} != "" } {
      if { ! [info exists LOOP_RESOURCES_DONE_${exp_path}_${datestamp}] || [set LOOP_RESOURCES_DONE_${exp_path}_${datestamp}] == "false" } {
         ::log::log debug "xflow_getAllLoopResourcesCallback getting resources..."
         xflow_getAllLoopResources ${exp_path} ${node} ${datestamp}
         set LOOP_RESOURCES_DONE_${exp_path}_${datestamp} true
      }
   }
}

# retrieve loop attributes recursively
# NOTE: OBSOLETE PROC...
proc xflow_getAllLoopResources { exp_path node datestamp } {
   if { [SharedFlowNode_getNodeType ${exp_path} ${node} ${datestamp}] == "loop" } {
      xflow_getLoopResources ${node} ${exp_path} ${datestamp}
   } 
   set submits [SharedFlowNode_getSubmits ${exp_path} ${node} ${datestamp}]
   foreach submitName ${submits} {
      set submitNode ${node}/${submitName}
      xflow_getAllLoopResources ${exp_path} ${submitNode} ${datestamp}
   }
}

# now that the loops attributes are stored in the node resource xml file,
# this function calls the nodeinfo to retrieve loop attributes.
# NOTE: OBSOLETE PROC...
proc xflow_getLoopResources { node exp_path datestamp} {
   global env
   ::log::log debug "xflow_getLoopResources node:$node"

   if { [SharedFlowNode_getNodeType ${exp_path} ${node} ${datestamp}] != "loop" } {
      ::log::log debug "xflow_getLoopResources nothing to be done for non-loop node"
      return
   }

   set nodeInfoExec "nodeinfo"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]
   
   set outputFile $env(TMPDIR)/nodeinfo_output_[file tail $node]_[clock seconds]

   # retrieve loop attributes by parsing output of nodeinfo node.specific i.e.
   # node.specific.TYPE=Default
   # node.specific.START=2
   # node.specific.END=10
   # node.specific.STEP=2
   # node.specific.TYPE=Default
   ::log::log debug "xflow_getLoopResources ${nodeInfoExec} -n ${seqNode} -d ${datestamp} | grep node.specific| sed -e 's:node.specific.::' -e 's:=: :'"
   if [ catch { exec -ignorestderr ksh -c "export SEQ_EXP_HOME=${exp_path};${nodeInfoExec} -n ${seqNode} -d ${datestamp} | grep node.specific| sed -e 's:node.specific.::' -e 's:=: :'  > ${outputFile} 2> /dev/null" } message ] {
      if { [SharedData_getMiscData OVERVIEW_MODE] == true } {
         set parentW [xflow_getToplevel ${exp_path} ${datestamp}]
         if { ! [winfo exists ${parentW}] } {
            set parentW [Overview_getToplevel]
         }
      }

      Utils_raiseError [xflow_getToplevel ${exp_path} ${datestamp}] "Get Loop Resources" $message
      return 0
   }

   ::log::log debug "xflow_getLoopResources cat ${outputFile}"
   array set valueList {}
   if [ catch { array set valueList [exec -ignorestderr cat ${outputFile}] } message ] {
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
      EXPRESSION expression
   }

   foreach { name value } [array get valueList] {
      if { [info exists attrMap(${name})] } {
         set attrName $attrMap(${name})
         # ${node} configure -${attrName} ${value}
         # puts "SharedFlowNode_setGenericAttribute ${exp_path} ${node} ${attrName} ${value}"
         SharedFlowNode_setGenericAttribute ${exp_path} ${node} ${datestamp} ${attrName} ${value}
      } else {
         ::log::log debug "xflow_getLoopResources invalid loop attribute token name:$name value:$value"
      }
   }
}

# this function creates an empty canvas in the parent
# container widget if it does not exists.
# Creates canvas with scrollbars and laods bg image
# It returns the new canvas or the existing one.
proc xflow_createFlowCanvas { exp_path datestamp parent } {
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
         catch {
            global CANVAS_DRAG_X CANVAS_DRAG_Y
            %W scan mark %x %y
            set CANVAS_DRAG_X %x
            set CANVAS_DRAG_Y %y
         }
      }

      bind $canvas <B1-Motion> {
         catch {
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
      }

      bind $canvas <Configure> [list xflow_canvasConfigureCallback ${exp_path} ${datestamp} ${canvas} %w %h]
      grid $canvas -row 0 -column 0 -sticky nsew


      # make the canvas expandable to right & bottom
      grid columnconfigure ${drawFrame} 0 -weight 1
      grid rowconfigure ${drawFrame} 0 -weight 1

      # grid ${drawFrame} -row 0 -column 0 -sticky nsew
      grid ${drawFrame} -row 0 -column 1 -sticky nsew
   }
   return $canvas
}

# this is called when a configure event is triggered on a widget to resize, iconified a window.
# I need to redraw the bg image everytime the window is resized... however, this proc can 
# be called about 10-15 times when the user drags the mouse to resize; I don't want
# to redraw the bg 15 times... So let's put a delay and every call cancels the previous one unless the 
# delay is passed; only the last one will live to execute the image redraw.
proc xflow_canvasConfigureCallback { exp_path datestamp canvas width height } {
   global RESIZE_AFTERID
   # cancel the previous event
   catch { after cancel [set RESIZE_AFTERID] }
   # set the event to draw bg
   set RESIZE_AFTERID [after 100 [list xflow_resizeWindowEvent ${exp_path} ${datestamp} ${canvas} ${width} ${height}]]
}

proc xflow_resizeWindowEvent {  exp_path datestamp canvas width height } {
  if { [winfo exists ${canvas}] } {
     xflow_addBgImage ${exp_path} ${datestamp} ${canvas} ${width} ${height}
     set topLevel [winfo toplevel $canvas]
     SharedData_setExpFlowSize ${exp_path} ${datestamp} [winfo width ${topLevel}]x[winfo height ${topLevel}]
     xflow_MouseWheelCheck ${canvas}
   }
}

proc xflow_clearCanvasFlow { _canvas } {
   if { [winfo exists ${_canvas}] } {
      # retrieve all flow elements to delete but not the
      # bg image
      ${_canvas} delete flow_element
   }
   update idletasks
}

# we don't need to redraw the bg image on a node redraw if
# the bg already covers all elements.
proc xflow_needBgImageRefresh { _exp_path _datestamp _canvas } {
   set needRefresh true
   # the current bg already covers all elements if the bbox around all
   # elements is the same as the bbox aroun the bg itself is the same
   if { [${_canvas} bbox all] == [${_canvas} bbox backgroundBitmap] } {
      set needRefresh false
   }
   return ${needRefresh}
}

proc xflow_addBgImage { _exp_path _datestamp _canvas _width _height } {
   global env
   global FLOW_BG_SOURCE_IMG FLOW_TILED_IMG_${_exp_path}_${_datestamp}
   package require img::gif
   set isOverviewMode [SharedData_getMiscData OVERVIEW_MODE]
   set addImg true
   # if overview mode and not monitored exp don't add bg
   # if standalone mode and not original exp don't add  bg
   if [ catch {
      if { (${isOverviewMode} == true && [SharedData_getExpGroupDisplay ${_exp_path}] == "") ||
           (${isOverviewMode} == false && (${_exp_path} != $env(SEQ_EXP_HOME))) } {
	   set addImg false
      }
   } message ] {
      puts stderr "ERROR: xflow_addBgImage ${_exp_path} ${_datestamp} $message"
      set addImg false
   }


   if { ${addImg} == true } {
      if [ catch {
         Utils_busyCursor [winfo toplevel ${_canvas}]

         if { ! [info exists FLOW_BG_SOURCE_IMG] } {
            set FLOW_BG_SOURCE_IMG [image create photo -file [xflow_getImageFile bg_image]]
         }

         if { [info exists  FLOW_TILED_IMG_${_exp_path}_${_datestamp}] } {
            # already has current bg
            image delete [ set FLOW_TILED_IMG_${_exp_path}_${_datestamp} ]
            ${_canvas} delete backgroundBitmap
         }

         set FLOW_TILED_IMG_${_exp_path}_${_datestamp} [image create photo]
         ${_canvas} create image 0 0 \
            -anchor nw \
            -image [set FLOW_TILED_IMG_${_exp_path}_${_datestamp}] \
            -tags backgroundBitmap
         ${_canvas} lower backgroundBitmap
         bind ${_canvas} <Destroy> [list xflow_canvasDestroyCallback ${_exp_path} ${_datestamp}]

         xflow_tileBgImage ${_exp_path} ${_datestamp} ${_canvas} [set FLOW_BG_SOURCE_IMG] [set FLOW_TILED_IMG_${_exp_path}_${_datestamp}] ${_width} ${_height}

         Utils_normalCursor [winfo toplevel ${_canvas}]
      } message ] {
         puts stderr "ERROR: xflow_addBgImage ${_exp_path} ${_datestamp} $message"
         Utils_normalCursor [winfo toplevel ${_canvas}]
      }
   }
}

proc xflow_canvasDestroyCallback { exp_path datestamp } {
   global FLOW_BG_SOURCE_IMG FLOW_TILED_IMG_${exp_path}_${datestamp}
   global XFLOW_BG_WIDTH_${exp_path}_${datestamp} XFLOW_BG_HEIGHT_${exp_path}_${datestamp}
   catch { ::log::log notice "xflow_canvasDestroyCallback deleting image FLOW_TILED_IMG_${exp_path}_${datestamp}" }
   catch { image delete [set FLOW_TILED_IMG_${exp_path}_${datestamp}] }
   catch { unset XFLOW_BG_WIDTH_${exp_path}_${datestamp} }
   catch { unset XFLOW_BG_HEIGHT_${exp_path}_${datestamp} }
   catch { ::log::log notice "xflow_canvasDestroyCallback unset FLOW_TILED_IMG_${exp_path}_${datestamp}" }
   catch { unset FLOW_TILED_IMG_${exp_path}_${datestamp} }
}

proc xflow_tileBgImage { exp_path datestamp canvas sourceImage tiledImage _width _height} {
   global XFLOW_BG_WIDTH_${exp_path}_${datestamp} XFLOW_BG_HEIGHT_${exp_path}_${datestamp}
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

   if { ! [info exists XFLOW_BG_WIDTH_${exp_path}_${datestamp}] } {
      set XFLOW_BG_WIDTH_${exp_path}_${datestamp} ${usedW}
      set XFLOW_BG_HEIGHT_${exp_path}_${datestamp} ${usedH}
   } else {
      set previousWidth [set XFLOW_BG_WIDTH_${exp_path}_${datestamp}]
      set previousHeight [set XFLOW_BG_HEIGHT_${exp_path}_${datestamp}]
      if { ${usedW} > ${previousWidth} || ${usedH} > ${previousHeight} } {
         set XFLOW_BG_WIDTH_${exp_path}_${datestamp} ${usedW}
         set XFLOW_BG_HEIGHT_${exp_path}_${datestamp} ${usedH}
      }
   }
   #::log::log debug "xflow_tileBgImage copy new source img exp_path:$exp_path datestamp:$datestamp"
   # copy from source... sourceImage must be of type photo
   $tiledImage copy $sourceImage -to 0 0 ${usedW} ${usedH}
 }

proc xflow_setErrorMessages {} {
  global ERROR_MSG_LIST
   if { ! [info exists ERROR_MSG_LIST] } {
      set ERROR_MSG_LIST(NO_LOOP_SELECT) "Cannot retrieve loop member for parent loop container! Please select a loop index."
      set ERROR_MSG_LIST(INVALID_NPT_SELECT) "Cannot mix latest selection with index selection!"
      set ERROR_MSG_LIST(NO_INDEX_SELECT) "You must provide a valid index value for this node!"
      set ERROR_MSG_LIST(DATESTAMP_REQUIRED) "Exp datestamp must be set!"
   }
}

proc xflow_getErroMsg { key } {
  global ERROR_MSG_LIST
   return $ERROR_MSG_LIST($key)
}

# this proc should be called when we need to clean the xflow related data
# with respect to a datestamp; should be called when you need to close a flow;
# should be called when you are switching a flow from one datestamp to another.
proc xflow_closeExpDatestamp { exp_path datestamp {from_overview false} } {
   ::log::log notice "xflow_closeExpDatestamp ${exp_path} ${datestamp}"
   set toplevelW [xflow_getToplevel ${exp_path} ${datestamp}]
   destroy ${toplevelW}
   xflow_cleanDatestampVars ${exp_path} ${datestamp}

   # clean images used by this flow
   set images [image names]
   set myImageIndexes [lsearch -all ${images} ${toplevelW}.*]
   foreach myImageIndex ${myImageIndexes} {
      image delete [lindex ${images} ${myImageIndex}]
      ::log::log notice "xflow_closeExpDatestamp ${exp_path} ${datestamp} deleting [lindex ${images} ${myImageIndex}]"
   }

   if { [SharedData_getMiscData OVERVIEW_MODE] == true && ${from_overview} == false } {
      # this procedure can be called twice (from the xflow itself and callback from the overview
      # When called from the overview, the from_overview is set to true so that we don't
      # try to cleanp data twice and to avoid infinite recursion
      set expThreadId [SharedData_getExpThreadId ${exp_path} ${datestamp}]
      if { [Overview_isExpBoxObsolete ${exp_path} ${datestamp}] == true || [SharedData_getExpGroupDisplay ${exp_path}] == "" } {
         ::log::log notice "xflow_closeExpDatestamp ${exp_path} ${datestamp} exp obsolete..."
         Overview_cleanDatestamp ${exp_path} ${datestamp}
         Overview_releaseExpThread ${expThreadId} ${exp_path} ${datestamp}
      } else {
         if { ${datestamp} == "" || [LogMonitor_isLogFileActive ${exp_path} ${datestamp}] == false } {
            ::log::log notice "xflow_closeExpDatestamp ${exp_path} ${datestamp} not obsolete..."
            # notify overview thread to release me
            Overview_releaseExpThread ${expThreadId} ${exp_path} ${datestamp}
         }
      }
   }

   if {  [SharedData_getMiscData OVERVIEW_MODE] == false } {
      LogReader_removeMonitorDatestamp ${exp_path} ${datestamp}
   }

   ::log::log notice "xflow_closeExpDatestamp ${exp_path} ${datestamp} DONE"
}

proc xflow_getXflowInstances { exp_path } {
   set wins [winfo children .]
   set count 0
   foreach win ${wins} {
      if { [string first .xflow_ ${win}] != -1 } {
         incr count
      }
   }
   ::log::log debug "xflow_getXflowInstances count:${count}"
   return ${count}
}

# function called when user quits the application.
# In overview mode, this is also called by the overview for exp thread cleanup
# if required.
proc xflow_quit { exp_path datestamp {from_overview false} } {
   global NODE_DISPLAY_PREF_${exp_path}_${datestamp}
   global SESSION_TMPDIR TITLE_AFTER_ID_${exp_path}_${datestamp} XFLOW_FIND_AFTER_ID_${exp_path}_${datestamp}

   ::log::log debug "xflow_quit exiting Xflow thread id:[thread::id]"
   set isOverviewMode [SharedData_getMiscData OVERVIEW_MODE]

   if { ${isOverviewMode} == "true" } {
      xflow_closeExpDatestamp ${exp_path} ${datestamp} ${from_overview}
   } else {
      # standalone mode
      if { [xflow_getXflowInstances ${exp_path}] > 1 } {
         xflow_closeExpDatestamp ${exp_path} ${datestamp}
      } else {
         exit
      }
   }
}

proc xflow_isWindowActive { exp_path datestamp } {
   set toplevelW [xflow_getToplevel ${exp_path} ${datestamp}]
   if { [winfo exists ${toplevelW}] == "0" } {
      return false
   }

   if { [wm state ${toplevelW}] == "withdrawn" } {
      return false
   }
   return true
}

# this function is only used in xflow standalone mode
# it is called by the msg center thread to notify the xflow
# of new messages available. It will mainly update the msg center
# icon to a new message state.
proc xflow_newMessageCallback { exp_path visible_datestamp has_new_msg } {
   global env
   ::log::log debug "xflow_newMessageCallback has_new_msg:$has_new_msg"
   set datestamps [LogReader_getMonitorDatestamps ${exp_path}]
   # set datestamp [Utils_getRealDatestampValue ${visible_datestamp}]
   foreach datestamp ${datestamps} {
      set msgCenterWidget [xflow_getWidgetName ${exp_path} ${datestamp} msgcenter_button]
      set noNewMsgImage [xflow_getWidgetName ${exp_path} ${datestamp} msg_center_img]
      set hasNewMsgImage [xflow_getWidgetName ${exp_path} ${datestamp} msg_center_new_img]
      if { [winfo exists ${msgCenterWidget}] } {
         set normalBgColor [option get ${msgCenterWidget} background Button]
         set newMsgBgColor  [SharedData_getColor COLOR_MSG_CENTER_MAIN]
         set currentImage [${msgCenterWidget} cget -image]
         if { ${has_new_msg} == "true" && ${currentImage} != ${hasNewMsgImage} } {
            ${msgCenterWidget} configure -image ${hasNewMsgImage} -bg ${newMsgBgColor} -bd 1
         } elseif { ${has_new_msg} == "false" && ${currentImage} != ${noNewMsgImage} } {
            ${msgCenterWidget} configure -image ${noNewMsgImage} -bg ${normalBgColor} -bd 1
         }
      }
   }
}

proc xflow_redrawNodesEvent { exp_path datestamp } {
   ::log::log debug "xflow_redrawNodesEvent ${exp_path} ${datestamp}"
   if { [xflow_isWindowActive ${exp_path} ${datestamp}] == true } {
      set updatedNodes [SharedData_getExpUpdatedNodes ${exp_path} ${datestamp}]
      if { ${updatedNodes} != "" } {
         # update highest node that was affected during this read
         foreach updatedNode ${updatedNodes} {
            ::log::log debug "xflow_redrawNodes ${exp_path} ${datestamp} ${updatedNode}"
            xflow_redrawNodes ${exp_path} ${datestamp} ${updatedNode}
         }
      }
   }
   # update idletasks
   SharedData_setExpUpdatedNodes ${exp_path} ${datestamp} ""
}

# set global variables relative to exp_path and datestamp
proc xflow_setDatestampVars { exp_path datestamp } {
   global NODE_DISPLAY_PREF NODE_DISPLAY_PREF_${exp_path}_${datestamp}
   global FLOW_SCALE_${exp_path}_${datestamp}

   xflow_setRefreshMode ${exp_path} ${datestamp} false

   set NODE_DISPLAY_PREF_${exp_path}_${datestamp} ${NODE_DISPLAY_PREF}
   set FLOW_SCALE_${exp_path}_${datestamp} [SharedData_getMiscData FLOW_SCALE]

   # trace the variable to see if we need to load the resources
   # trace add variable NODE_DISPLAY_PREF_${exp_path}_${datestamp} write "xflow_nodeResourceCallback ${exp_path} \"${datestamp}\""
}

proc xflow_cleanDatestampVars { exp_path datestamp } {
   catch { xflow_canvasDestroyCallback ${exp_path} ${datestamp} }
   trace remove variable NODE_DISPLAY_PREF_${exp_path}_${datestamp} write "xflow_nodeResourceCallback ${exp_path} \"${datestamp}\""
   foreach variableKey { NODE_DISPLAY_PREF FLOW_SCALE TITLE_AFTER_ID \
                         XFLOW_FIND_AFTER_ID LOOP_RESOURCES_DONE \
			 NODE_RESOURCE_DONE FLOW_RESIZED REFRESH_MODE FLOW_RESIZED \
			 cmdList NodeHighLightRestoreCmd } {
      global ${variableKey}_${exp_path}_${datestamp}
      ::log::log debug "xflow_cleanDatestampVars cleaning variable: ${variableKey}_${exp_path}_${datestamp}"
      ::log::log notice "xflow_cleanDatestampVars cleaning variable: ${variableKey}_${exp_path}_${datestamp}"
      catch { unset ${variableKey}_${exp_path}_${datestamp} }
   }
}

# this is the place to validate essential exp
# data for startup
proc xflow_validateExp { startup_exp } {
   puts "xflow_validateExp startup_exp:$startup_exp"
   global env
 
   set myExp ${startup_exp}

   if { ${myExp} == "" && [info exists env(SEQ_EXP_HOME)] } {
      # if exp not defined at startup and seq_exp_home defined use it
      puts "Using SEQ_EXP_HOME at startup: $env(SEQ_EXP_HOME)"
      set myExp $env(SEQ_EXP_HOME)
   }

   if { ${myExp} == "" } {
      set isExpCheckPath [pwd]/EntryModule
      # at last if pwd is an exp, use it
      if { [file exists ${isExpCheckPath}] && [file type ${isExpCheckPath}] == "link" && [file readable ${isExpCheckPath}] } {
         puts "Using current pwd as exp for startup: [pwd]"
         set myExp [pwd]
      }
   }

   if { [SharedData_getMiscData OVERVIEW_MODE] == "false" && ${myExp} != "" && ! [info exists env(SEQ_EXP_HOME)] } {
      set env(SEQ_EXP_HOME) ${myExp}
   }

   if { ${myExp} == "" } {
      Utils_fatalError . "Startup Error" "No exp defined at startup! SEQ_EXP_HOME environment variable not set! Exiting..."
   }

   return ${myExp}
}

# this function is called to create the widgets of the xflow main window
proc xflow_createWidgets { exp_path datestamp {topx ""} {topy ""}} {
   global List_Xflow CHECK_PERMISSION SUITE_PERMISSION

   ::log::log debug "xflow_createWidgets"
   puts "xflow_createWidgets  ${exp_path} ${datestamp}..."
   set toplevelW [xflow_getToplevel ${exp_path} ${datestamp}]
   if { ! [winfo exists ${toplevelW}] } {
      toplevel ${toplevelW}
      if { ${topx} != "" } {
         wm geometry ${toplevelW} +${topx}+${topy}
      }
   }
   puts "xflow_createWidgets  ${exp_path} ${datestamp} setting window delete behavior"
   wm protocol ${toplevelW} WM_DELETE_WINDOW "xflow_quit ${exp_path} \"${datestamp}\""
   wm iconify ${toplevelW}

   set topFrame [frame [xflow_getWidgetName ${exp_path} ${datestamp} top_frame]]
   lappend List_Xflow  [list ${exp_path} ${datestamp} $topFrame]
   puts "xflow_createWidgets  ${exp_path} ${datestamp} creating menus..."
   xflow_addFileMenu ${exp_path} ${datestamp} $topFrame
   xflow_addViewMenu ${exp_path} ${datestamp} $topFrame
   xflow_addHelpMenu ${exp_path} ${datestamp} $topFrame
   puts "xflow_createWidgets  ${exp_path} ${datestamp} menu done..."
 
   # creates exp label right side of menu
   set expLabelFrame [frame [xflow_getWidgetName ${exp_path} ${datestamp}  exp_label_frame]]
   set expLabel [label ${expLabelFrame}.exp_label -font [xflow_getExpLabelFont]]
   grid ${expLabel} -sticky nesw
   pack ${expLabelFrame} -side left -padx {20 0}


   # creates label on the left side of the canvas
   # set expSideLabelFrame [frame [xflow_getWidgetName ${exp_path} ${datestamp}  exp_side_label_frame]]
   set expSideLabelFrame [labelframe [xflow_getWidgetName ${exp_path} ${datestamp}  exp_side_label_frame]]
   set labelValue ""
   if { [DisplayGrp_getWindowsLabel ${exp_path}] != "" } {
      set labelValue "[DisplayGrp_getWindowsLabel]"
   }
   set labelBgColor [SharedData_getMiscData WINDOWS_LABEL_BG]
   if { ${labelBgColor} != "" } {
      set expSideLabel [label ${expSideLabelFrame}.exp_label -text ${labelValue} -justify center -wraplength 1 -font [xflow_getExpLabelFont] -bg [SharedData_getMiscData WINDOWS_LABEL_BG] -anchor center]
   } else {
      set expSideLabel [label ${expSideLabelFrame}.exp_label -text ${labelValue} -justify center -wraplength 1 -font [xflow_getExpLabelFont] -anchor center]
   }
   grid ${expSideLabel} -column 0 -row 1 -sticky ns
   grid ${expSideLabelFrame} -column 0 -row 0 -sticky ns -rowspan 5
   grid rowconfigure ${expSideLabelFrame} 0 -weight 1
   grid rowconfigure ${expSideLabelFrame} 1 -weight 10

   set secondFrame [frame  [xflow_getWidgetName ${exp_path} ${datestamp}  second_frame]]
   set toolbarFrame [xflow_getWidgetName ${exp_path} ${datestamp}  toolbar_frame]
   labelframe ${toolbarFrame} -text Toolbar
   xflow_createToolbar ${exp_path} ${datestamp} ${toolbarFrame}   
   puts "xflow_createWidgets  ${exp_path} ${datestamp} toolbar done..."

   # date bar is the 3nd widget
   set expDateFrame [xflow_getWidgetName ${exp_path} ${datestamp} exp_date_frame]
   xflow_addDatestampWidget ${exp_path} ${datestamp} ${expDateFrame}
   
   # find frame
   set findFrame [frame [xflow_getWidgetName ${exp_path} ${datestamp} find_frame]]
   xflow_createFindWidgets ${exp_path} ${datestamp} ${findFrame}
   set findCloseB [xflow_getWidgetName ${exp_path} ${datestamp} find_close_button]
   ${findCloseB} configure -command [list grid remove ${findFrame}]

   # this displays the widget on the second frame
   grid ${toolbarFrame} -row 0 -column 0 -sticky nsew -padx 2 -ipadx 2
   grid ${expDateFrame} -row 0 -column 2 -sticky nsew -padx 2 -pady 0 -ipadx 2
   xflow_addMsgCenterWidget ${exp_path} ${datestamp}

   # flow_frame is the 3nd widget
   set flowFrame [frame [xflow_getWidgetName ${exp_path} ${datestamp}  flow_frame]]
   set drawFrame [frame ${flowFrame}.draw_frame]

   grid columnconfigure ${flowFrame} 1 -weight 1
   grid rowconfigure ${flowFrame} 0 -weight 1

   # this displays the widgets in the main window layout
   grid $topFrame -row 0 -column 1 -sticky w -padx 2
   grid ${secondFrame} -row 1 -column 1  -sticky nsew -pady 2
   grid ${findFrame} -row 2 -column 1  -sticky nsew -pady 2 -padx 2
   grid remove ${findFrame}
   grid ${flowFrame}  -row 3 -column 1 -columnspan 2 -sticky nsew -padx 2 -pady 2
   grid columnconfigure ${toplevelW} 2 -weight 1
   grid columnconfigure ${toplevelW} 2 -weight 1
   grid rowconfigure ${toplevelW} 3 -weight 2

   set sizeGripW [xflow_getWidgetName ${exp_path}  ${datestamp} main_size_grip]
   ttk::sizegrip ${sizeGripW}

   grid ${sizeGripW} -row 4 -column 2 -sticky se
   
   wm geometry ${toplevelW} =1200x800
}

proc xflow_getExpLabelFont {} {
   set expLabelFont ExpLabelFont
   if { [lsearch [font names] ExpLabelFont] == -1 } {
      # create the font if not exists
      font create ExpLabelFont
      font configure ${expLabelFont} -family [SharedData_getMiscData FONT_LABEL] \
           -size [SharedData_getMiscData XFLOW_EXP_LABEL_SIZE] \
           -weight bold
   } else {
      font configure ${expLabelFont} -family [SharedData_getMiscData FONT_LABEL] \
            -size   [SharedData_getMiscData FONT_LABEL_SIZE] \
            -weight [SharedData_getMiscData FONT_LABEL_STYLE] \
            -slant  [SharedData_getMiscData FONT_LABEL_SLANT] \
            -underline [SharedData_getMiscData FONT_LABEL_UNDERL]
   }
   return ${expLabelFont}
}


# sets the label on the right side of the menus
proc xflow_setExpLabel { _exp_path _displayName _datestamp } {
   ::log::log debug "xflow_setExpLabel _displayName:${_displayName} datestamp:${_datestamp}"
   set expLabelFrame [xflow_getWidgetName ${_exp_path} ${_datestamp} exp_label_frame]
   set displayValue ${_displayName}
   if { ${_datestamp} != "" } {
      set hour [Utils_getHourFromDatestamp ${_datestamp}]
      set displayValue ${_displayName}-${hour}
   }
   ${expLabelFrame}.exp_label configure -text ${displayValue} -font [xflow_getExpLabelFont]
}

# this function is called to create an exp flow.
# 1) in xflow standalone mode, this function is called at startup and when the user views the exp in
# history mode.
# 2) in overview mode, this function is called everytime the user wants to view the exp flow with the latest
# datestamp or in history mode. Note that in overview mode, a thread is created for each exp and another tread is created
# for each exp in history mode.
proc xflow_displayFlow { exp_path datestamp {initial_display false} {focus_node ""} } {
   global env PROGRESS_REPORT_TXT
   global SEQ_DATESTAMP
  
   xflow_checkExpPermission  ${exp_path}

   set SEQ_DATESTAMP $datestamp
   puts "xflow_displayFlow()  exp_path:${exp_path} datestamp:${datestamp} initial_display:${initial_display}"

   ::log::log debug "xflow_displayFlow thread id:[thread::id] datestamp:${datestamp}"
   ::log::log notice "xflow_displayFlow thread id:[thread::id] exp_path:${exp_path} datestamp:${datestamp}"

   set topLevel [xflow_getToplevel ${exp_path} ${datestamp}]

   set topFrame [xflow_getWidgetName ${exp_path} ${datestamp} top_frame]
   if { ! [winfo exists ${topFrame}] } {
      set PROGRESS_REPORT_TXT "Creating widgets..."
      puts "xflow_displayFlow()  exp_path:${exp_path} datestamp:${datestamp} creating widget..."
      xflow_createWidgets ${exp_path} ${datestamp}
      puts "xflow_displayFlow()  exp_path:${exp_path} datestamp:${datestamp} creating widget done..."
      set overview_x ""
      foreach {overview_x overview_y} [SharedData_getMiscData OVERVIEW_MAIN_COORDS] { break }
      if { ${overview_x} != "" } {
         xflow_positionFlowWindow ${topLevel} ${overview_x} ${overview_y}
         ::log::log notice "xflow_displayFlow() xflow_positionFlowWindow ${exp_path} ${topLevel} ${overview_x} ${overview_y}"
      }
   }

   puts "xflow_displayFlow()  exp_path:${exp_path} datestamp:${datestamp} xflow_setDatestampVars() "
   if { ${initial_display} == true } {
      xflow_setDatestampVars ${exp_path} ${datestamp}
   }
   set displayName [ExpOptions_getDisplayName ${exp_path}]
   xflow_setExpLabel ${exp_path} ${displayName} ${datestamp}
   ::log::log debug "xflow_displayFlow exp_path ${exp_path}"
   set rootNode [SharedData_getExpRootNode ${exp_path} ${datestamp}]
   # set PROGRESS_REPORT_TXT "Getting loop node resources ..."
   # xflow_getAllLoopResourcesCallback ${exp_path} ${rootNode} ${datestamp}
   # resource will only be loaded if needed
   # xflow_nodeResourceCallback ${exp_path} ${datestamp}

   puts "xflow_displayFlow()  exp_path:${exp_path} datestamp:${datestamp} xflow_populateDatestamp() "
   xflow_populateDatestamp ${exp_path} ${datestamp} [xflow_getWidgetName ${exp_path} ${datestamp} exp_date_frame]

   xflow_initDatestampEntry ${exp_path} ${datestamp}
   ::log::log notice "xflow_displayFlow ${exp_path} xflow_initDatestampEntry done"

   set drawFrame [xflow_getWidgetName ${exp_path} ${datestamp} flow_frame].draw_frame
   set canvas [xflow_createFlowCanvas ${exp_path} ${datestamp} $drawFrame]
   xflow_drawflow ${exp_path} ${datestamp} $canvas ${initial_display}

   set sizeGripW [xflow_getWidgetName ${exp_path}  ${datestamp} main_size_grip]

   xflow_setTitle ${topFrame} ${exp_path} ${datestamp}
   xflow_toFront [winfo toplevel  ${topFrame}]

   ::log::log notice "xflow_displayFlow ${exp_path} thread id:[thread::id] done datestamp:${datestamp}"
   puts "xflow_displayFlow()  exp_path:${exp_path} datestamp:${datestamp} DONE"

   set node_length [string length ${focus_node}]
   if { ${node_length} > 0 } {
      xflow_findNode ${exp_path} ${datestamp} ${focus_node}
   }
}

# Position the flow windows relative to the main overview window.
# _toplevel is the toplevel of the current flow
# _overview_x is the x coord of the upper left corner of the overview window
# _overview_y is the y coord of the upper left corner of the overview window
proc xflow_positionFlowWindow { _toplevel _overview_x _overview_y} {
   ::log::log debug "xflow_positionFlowWindow _overview_x:$_overview_x _overview_y:$_overview_y"
   # the XFLOW_POS_COUNTER is shared among all exp threads
   if { [SharedData_getMiscData XFLOW_POS_COUNTER] != "" } {
      set counter [SharedData_getMiscData XFLOW_POS_COUNTER]
      incr counter
      if { ${counter} == 20 } {
         set counter 1
      }
   } else {
      set counter 1
   }
   SharedData_setMiscData XFLOW_POS_COUNTER ${counter}
   # I'm using the overview main window x and y and the XFLOW_POS_COUNTER to
   # position a window relative to the main window
   set newx [expr ${_overview_x} + ${counter} * 40]
   set newy [expr ${_overview_y} + 200 + ${counter} * 40]
   wm geometry ${_toplevel} +${newx}+${newy}
   #puts "xflow_positionFlowWindow wm geometry ${_toplevel} +${newx}+${newy}"
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

proc xflow_isNodePrefResourceRequired { exp_path datestamp } {
   set notRequiredList {normal "Execution Time" "Begin Time" "End Time" "Submission Delay" "Delta Time From Start" "Relative Progress" "Relative Execution Time"}
   set currentPref [xflow_getNodeDisplayPref ${exp_path} ${datestamp}]
   set value false
   if { [lsearch -exact ${notRequiredList} ${currentPref}] == -1 } {
      # not found in non required list so yes we need resource
      set value true
   }
   return ${value}
}

proc xflow_getNodeDisplayPref { exp_path datestamp } {
   global NODE_DISPLAY_PREF_${exp_path}_${datestamp}
   if { ! [info exists NODE_DISPLAY_PREF_${exp_path}_${datestamp}] } {
      set NODE_DISPLAY_PREF_${exp_path}_${datestamp} normal
   }
   return [set NODE_DISPLAY_PREF_${exp_path}_${datestamp}]
}

proc xflow_getShawdowStatus {} {
   global SHADOW_STATUS
   if { ! [info exists SHADOW_STATUS] } {
      set SHADOW_STATUS 0
   }
   return $SHADOW_STATUS
}

proc xflow_setTitle { top_w exp_path datestamp } {
   global env TITLE_AFTER_ID_${exp_path}_${datestamp}
   if { [winfo exists ${top_w}] } {
      set current_time [clock format [clock seconds] -format "%H:%M" -gmt 1]
      set shortname [SharedData_getExpData ${exp_path} shortname]
      set hour      [Utils_getHourFromDatestamp ${datestamp}]
      set winTitle "[file tail ${exp_path}] - Xflow - Exp=${exp_path} Datestamp=${datestamp} User=$env(USER) Host=[exec -ignorestderr hostname] Time=${current_time} Shortname=$shortname-$hour"
      wm title [winfo toplevel ${top_w}] ${winTitle}
      # refresh title every minute
      set TITLE_AFTER_ID_${exp_path}_${datestamp} [after 60000 [list xflow_setTitle ${top_w} ${exp_path} ${datestamp}]]
   }
}

proc xflow_getMainFlowCanvas { exp_path datestamp } {
   set flowFrame [xflow_getWidgetName ${exp_path} ${datestamp} flow_frame]
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
   global env argv XFLOW_STANDALONE AUTO_MSG_DISPLAY SUBMIT_POPUP APP_LOGFILE
   set rcFile ""
   set focusNode ""
   set focusLoopArgs ""
   set startupExp ""
   if { [info exists argv] } {
      set options {
         {main ""}
         {date.arg "" "Date for standalone startup"}
         {exp.arg "" "experiment path"}
         {logfile.arg "" "App log file"}
         {debug "Turn debug on"}
         {noautomsg.arg "" "No auto message display"}
         {nosubmitpopup.arg "" "No submit popup"}
         {rc.arg "" "maestrorc preferrence file"}
	 {node.arg "" "Highlight a specific node at startup"}
	 {loop.arg "" "Loop arguments for specific node"}
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
   } else {
      set XFLOW_STANDALONE 0
   }
   # this section is only executed when xflow is run as a standalone application
   if { ${XFLOW_STANDALONE} == 1 } {
      puts "SEQ_XFLOW_BIN=$env(SEQ_XFLOW_BIN)"
      SharedData_init

      if { ! ($params(rc) == "") } {
         puts "xflow using maestrorc file: $params(rc)"
         set rcFile $params(rc)
      }

      SharedData_readProperties ${rcFile}

      if { $params(logfile) != "" } {
         puts "xflow writing to log file: $params(logfile)"
         SharedData_setMiscData APP_LOG_FILE $params(logfile)
         ::log::log notice "xflow Application startup user=$env(USER) host:[exec -ignorestderr hostname]"
      } 

      if { $params(debug) } {
         puts "xflow enabling debug trace"
         SharedData_setMiscData DEBUG_TRACE 1
      } 

      if { $params(noautomsg) != "" } {
         puts "xflow noautomsg flag: $params(noautomsg)"
         if { $params(noautomsg) == 1 } {
            set AUTO_MSG_DISPLAY false
         }
      }

      if { $params(nosubmitpopup) != "" } {
         puts "xflow nosubmitpopup flag: $params(nosubmitpopup)"
         if { $params(nosubmitpopup) == 1 } {
            set SUBMIT_POPUP false
         }
      }

      if { ! ($params(node) == "") } {
         puts "xflow focusing on node: $params(node)"
         set focusNode $params(node)
      }

      if { ! ($params(loop) == "") } {
         puts "xflow got loop iteration: $params(loop)"
         set focusLoopArgs $params(loop)
      }

      if { ! ($params(exp) == "") } {
         puts "Using exp specified at startup: $params(exp)"
         # user specified an exp, use it
         set startupExp $params(exp)
      }

      set expPath [xflow_validateExp ${startupExp}]

      SharedData_setDerivedColors
      SharedData_setPlugins "xflow"

      xflow_init
      ::DrawUtils::initStatusImages

      ExpOptions_read ${expPath}

      if { ($params(date) == "") } {
         set startupDatestamp [LogMonitor_getNewestDatestamp ${expPath}]
      } else {
         set startupDatestamp $params(date)
      }
      SharedData_setExpThreadId ${expPath} ${startupDatestamp} [thread::id]
      LogReader_startExpLogReader ${expPath} ${startupDatestamp} all false

      if { ${focusNode} != "" } {
         set focusFlowNode [SharedData_getExpNodeMapping ${expPath} ${startupDatestamp} ${focusNode}]
         set focusExt [SharedFlowNode_getLoopExtFromLoopArgs ${expPath} ${focusFlowNode} ${startupDatestamp} ${focusLoopArgs}]
         if { ${focusExt} != -1 } {
            set focusNode ${focusNode}${focusExt}
         }
      }

      puts "xflow_displayFlow ${expPath} ${startupDatestamp} true ${focusNode}"
      xflow_displayFlow ${expPath} ${startupDatestamp} true ${focusNode}

      SharedData_setMiscData STARTUP_DONE true
      MsgCenter_startupDone

      puts "LogReader_readMonitorDatestamps..."
      # start monitoring datestamps for new log entries
      LogReader_readMonitorDatestamps


      if { [SharedData_getMiscData XFLOW_NEW_DATESTAMP_LAUNCH] != "" } {
         # monitor for new log datestamps
	 LogMonitor_addOneExpDatestamp ${expPath} ${startupDatestamp}
         LogMonitor_setLastCheckTime ${expPath} [clock seconds]
         LogMonitor_checkOneExpNewLogFiles ${expPath}
      }
   } else {
       # load application-specific plugins
       SharedData_setPlugins "xflow"
   }
}

proc xflow_getImageFile { key } {
   global ImageFiles
   if { ! [info exists ImageFiles] } {
      array set ImageFiles {
         find_close_image_file cancel_small.png
         find_next_image_file next_down.png
         find_previous_image_file previous_up.png
      }
      if { [SharedData_getMiscData BACKGROUND_IMAGE] != "" } {
         set ImageFiles(bg_image) [SharedData_getMiscData BACKGROUND_IMAGE]
      } else {
         set ImageFiles(bg_image) [SharedData_getMiscData IMAGE_DIR]/artist-canvas_2.gif
      }
   }
   set imageFile $ImageFiles(${key})
   return ${imageFile}
}

proc xflow_getWidgetName { exp_path datestamp key } {
   global array XflowWidgetNames
   set value ""
   if { [info exists XflowWidgetNames($key)] } {
      set value $XflowWidgetNames($key)
   } else {
      error "xflow_getWidgetName invalid widget key name:${key}"
   }
   set topLevel [xflow_getToplevel ${exp_path} ${datestamp}]
   return ${topLevel}${value}
}

proc xflow_getToplevel { exp_path {datestamp ""} } {
   set topLevel [regsub -all " " ${exp_path} _]
   set topLevel [regsub -all "/" ${topLevel} _]
   set topLevel [regsub -all {[\.]} ${topLevel} _]
   return .xflow_${topLevel}_${datestamp}
}

# adds the name of widgets in an array. The widget names are
# accessible through the xflow_getWidgetName proc with the use
# of the key. I'm only storing name of widgets that are reference
# more than once in the code... Widgets that are created once and
# not referred, don't care
proc xflow_setWidgetNames {} {
   global array XflowWidgetNames
   if { ! [info exists XflowWidgetNames] } {
      array set XflowWidgetNames {

         exp_side_label_frame .exp_side_label_frame
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
         trash_button   .second_frame.toolbar.button_trash
         dkfont_button .second_frame.toolbar.button_dkfont
         nodelist_button .second_frame.toolbar.button_nodelist
         abortlist_button .second_frame.toolbar.button_nodeabortlist
         dep_button .second_frame.toolbar.button_dep
         legend_button .second_frame.toolbar.button_colorlegend
         close_button .second_frame.toolbar.button_close
         overview_button .second_frame.toolbar.button_overview
         shell_button .second_frame.toolbar.button_shell
         msg_center_img .second_frame.toolbar.msg_center_img
         msg_center_new_img .second_frame.toolbar.msg_center_new_img
	 plugin_frame .second_frame.toolbar.plugintoolbar

         exp_date_frame  .second_frame.date_frame
         exp_date_entry  .second_frame.date_frame.entry
         exp_date_hidden  .second_frame.date_frame.hidden
         exp_date_button_frame .second_frame.date_frame.button_frame
         exp_msg_frame       .second_frame.exp_msg_frame
         exp_msglabel_frame  .second_frame.exp_msg_frame.exp_msg_label

         find_close_button .find_frame.close_button
         find_label .find_frame.entry_label
         find_entry .find_frame.entry_field
         find_next_button .find_frame.next_button
         find_previous_button .find_frame.previous_button
         find_matchcase_check .find_frame.matchcase_check
         find_close_image .find_frame.close_img
         find_next_image .find_frame.next_img
         find_previous_image .find_frame.previous_img

         catchup_toplevel .catchup_top
         evalconfig_toplevel .evaluate_config_top
      }
   }
}

proc xflow_msgCenterThreadReady {} {
   global MSG_CENTER_READY
   set MSG_CENTER_READY 1
}

proc xflow_init { {exp_path ""} } {
   global env DEBUG_TRACE
   global AUTO_MSG_DISPLAY NODE_DISPLAY_PREF SUBMIT_POPUP COLLAPSE_DISABLED_NODES
   global SHADOW_STATUS MSG_CENTER_FOCUS_GRAB
   global SESSION_TMPDIR FLOW_SCALE

   set SHADOW_STATUS 0
   
   # initate array containg name for widgets used in the application

   if { [SharedData_getMiscData OVERVIEW_MODE] == "false" } {
      Utils_createTmpDir
      SharedData_setMiscData XFLOW_THREAD_ID [thread::id]

      set SHADOW_STATUS 
      SharedData_setMiscData IMAGE_DIR $env(SEQ_XFLOW_BIN)/../etc/images
      if { ! [info exists AUTO_MSG_DISPLAY] } {
         set AUTO_MSG_DISPLAY [SharedData_getMiscData AUTO_MSG_DISPLAY]
      } else {
         ::log::log debug "xflow_init SharedData_setMiscData AUTO_MSG_DISPLAY ${AUTO_MSG_DISPLAY}"
         SharedData_setMiscData AUTO_MSG_DISPLAY ${AUTO_MSG_DISPLAY}
      }
      if { ! [info exists SUBMIT_POPUP] } {
         set SUBMIT_POPUP [SharedData_getMiscData SUBMIT_POPUP]
      } else {
         ::log::log debug "xflow_init SharedData_setMiscData SUBMIT_POPUP ${SUBMIT_POPUP}"
         SharedData_setMiscData SUBMIT_POPUP ${SUBMIT_POPUP}
      }

      if { ! [info exists COLLAPSE_DISABLED_NODES] } {
         set COLLAPSE_DISABLED_NODES [SharedData_getMiscData COLLAPSE_DISABLED_NODES]
      } else {
         ::log::log debug "xflow_init SharedData_setMiscData COLLAPSE_DISABLED_NODES ${COLLAPSE_DISABLED_NODES}"
         SharedData_setMiscData COLLAPSE_DISABLED_NODES ${COLLAPSE_DISABLED_NODES}
      }
      xflow_setTkOptions

      set DEBUG_TRACE [SharedData_getMiscData DEBUG_TRACE]
      set NODE_DISPLAY_PREF  [SharedData_getMiscData NODE_DISPLAY_PREF]
      # vwait MSG_CENTER_READY

      puts "xflow_init() Utils_logInit..."
      Utils_logInit
      puts "xflow_init() Utils_logInit done" 

      MsgCenter_init
   }
   if { ! [info exists MSG_CENTER_FOCUS_GRAB] } {
         set  MSG_CENTER_FOCUS_GRAB [SharedData_getMiscData MSG_CENTER_FOCUS_GRAB]
   } else {
      ::log::log debug "xflow_init SharedData_setMiscData MSG_CENTER_FOCUS_GRAB ${MSG_CENTER_FOCUS_GRAB}"
      SharedData_setMiscData MSG_CENTER_FOCUS_GRAB ${MSG_CENTER_FOCUS_GRAB}
   }
   xflow_setWidgetNames 
   xflow_setErrorMessages

   # xflow_createTmpDir
}

proc xflow_setRefreshMode { exp_path datestamp value } {
   global REFRESH_MODE_${exp_path}_${datestamp}
   set REFRESH_MODE_${exp_path}_${datestamp} ${value}
}

proc xflow_isRefreshMode { exp_path datestamp } {
   global REFRESH_MODE_${exp_path}_${datestamp}
   set refreshMode false
   if { [info exists REFRESH_MODE_${exp_path}_${datestamp}] } {
      set refreshMode [set REFRESH_MODE_${exp_path}_${datestamp}]
   }
   return ${refreshMode}
}

proc xflow_getWarningFont {} {
   set fontName WarningFont

   if { [lsearch [font names] ${fontName}] == -1 } {
      font create ${fontName}
      font configure ${fontName} -size 14
   }

   return ${fontName}
}

proc xflow_checkExpPermission { {exp_path ""} } {
   global CHECK_PERMISSION SUITE_PERMISSION

   set CHECK_PERMISSION true
   set SUITE_PERMISSION true

   if { ${exp_path} != "" } {
      if {![file writable ${exp_path}/sequencing]} {
        set CHECK_PERMISSION false
      }
      if {![file writable ${exp_path}/modules]} {
        set SUITE_PERMISSION false
      }
   }
}

if { ! [info exists XFLOW_STANDALONE] || ${XFLOW_STANDALONE} == "1" } {
   if { ! [info exists env(SEQ_XFLOW_BIN) ] } {
      puts "SEQ_XFLOW_BIN must be defined!"
      exit
   }
   set lib_dir $env(SEQ_XFLOW_BIN)/../lib
   puts "lib_dir=$lib_dir"
   set auto_path [linsert $auto_path 0 $lib_dir ]
   package require Tk
   catch { wm withdraw . }
   package require DrawUtils
   ::DrawUtils::init
   xflow_parseCmdOptions
   xflow_checkExpPermission
}
