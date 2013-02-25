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

   $menuW add command -label "Quit" -underline 0 -command "xflow_quit ${exp_path} ${datestamp}" 

   pack $menuButtonW -side left -pady 2 -padx 2
   tooltip::tooltip $menuW -index "Quit" "test tooltip"
}

proc xflow_addViewMenu { exp_path datestamp parent } {
   global AUTO_MSG_DISPLAY FLOW_SCALE_${exp_path}_${datestamp}
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

   $menuW add checkbutton -label "Show Shadow Status" -variable SHADOW_STATUS \
      -onvalue 1 -offvalue 0 -command [list xflow_redrawAllFlow ${exp_path} ${datestamp}]

   set displayMenu $menuW.displayMenu

   $menuW add cascade -label "Node Display" -underline 5 -menu ${displayMenu}
   menu ${displayMenu} -tearoff 0
   foreach item "normal catchup cpu machine_queue memory mpi wallclock" {
      set value ${item}
      ${displayMenu} add radiobutton -label ${item} -variable NODE_DISPLAY_PREF_${exp_path}_${datestamp} -value ${value} \
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

proc xflow_createToolbar { exp_path datestamp parent } {
   ::log::log debug "xflow_createToolbar ${parent}"
   global MSG_CENTER_THREAD_ID

   set msgCenterW [xflow_getWidgetName ${exp_path} ${datestamp} msgcenter_button]
   set nodeKillW [xflow_getWidgetName ${exp_path} ${datestamp} nodekill_button]
   set catchupW [xflow_getWidgetName ${exp_path} ${datestamp} catchup_button]
   set findW [xflow_getWidgetName ${exp_path} ${datestamp} find_button]
   set refreshW [xflow_getWidgetName ${exp_path} ${datestamp} refresh_button]
   set colorLegendW [xflow_getWidgetName ${exp_path} ${datestamp} legend_button]
   set closeW [xflow_getWidgetName ${exp_path} ${datestamp} close_button]
   #set depW [xflow_getWidgetName dep_button]
   set shellW [xflow_getWidgetName ${exp_path} ${datestamp} shell_button]
   set catchupTopW [xflow_getWidgetName ${exp_path} ${datestamp} catchup_toplevel]

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
   #image create photo ${parent}.ignore_dep_true -file ${imageDir}/dep_on.ppm
   #image create photo ${parent}.ignore_dep_false -file ${imageDir}/dep_off.ppm
   image create photo ${parent}.shell_img -file ${imageDir}/terminal.ppm

   button ${msgCenterW} -padx 0 -pady 0 -image ${noNewMsgImage} -command {
      thread::send -async ${MSG_CENTER_THREAD_ID} "MsgCenterThread_showWindow"
   } -relief flat
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
      grid ${msgCenterW} ${overviewW} ${nodeKillW} ${catchupW} ${shellW} ${findW} ${refreshW} ${colorLegendW} ${closeW} -sticky w -padx 2
   } else {
      grid ${msgCenterW} ${nodeKillW} ${catchupW} ${shellW} ${findW} ${refreshW} ${colorLegendW} ${closeW} -sticky w -padx 2
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

# this function creates the widgets that allows
# the user to set/query the current datestamp
proc xflow_addDatestampWidget { exp_path datestamp parent_widget } {
   set dtFrame ${parent_widget}
   set dateEntryCombo [xflow_getWidgetName ${exp_path} ${datestamp}  exp_date_entry]
   set buttonFrame [xflow_getWidgetName ${exp_path} ${datestamp} exp_date_button_frame]

   labelframe ${dtFrame} -text "Exp Datestamp (yyyymmddhh)"
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

   if { [SharedData_getMiscData OVERVIEW_MODE] == true } {
      set newWindButton [button ${buttonFrame}.new_win_button -relief flat -image ${buttonFrame}.new_win_image \
         -command [list xflow_launchFlowNewWindow ${exp_path} ${datestamp} ]]
      tooltip::tooltip ${newWindButton} "Launch flow in new window."
      pack $setButton $refreshButton ${newWindButton} -side left -pady 2 -padx 2
   } else {
      pack $setButton $refreshButton -side left -pady 2 -padx 2
   }

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
      if { [SharedFlowNode_uncollapseBranch ${_exp_path} ${foundNode} ${_datestamp} ${mainFlowCanvas}] != "" } {
         xflow_drawflow ${_exp_path} ${_datestamp} ${mainFlowCanvas} 0
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

# this function creates the widgets for the node kill window
# that is invoked from the xflow toolbar
proc xflow_nodeKillDisplay { exp_path datestamp parent_w } {

   global env
   set shadowColor [SharedData_getColor SHADOW_COLOR]
   set bgColor [SharedData_getColor CANVAS_COLOR]
   set id [clock seconds]
   set tmpdir $env(TMPDIR)
   set tmpfile "${tmpdir}/test$id"
   set killPath [SharedData_getMiscData SEQ_UTILS_BIN]/nodekill 
   set cmd "export SEQ_EXP_HOME=${exp_path}; $killPath -listall > $tmpfile 2>&1"
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
      -command [list xflow_killNode ${exp_path} ${datestamp} $soloWindow.list ]]
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
proc xflow_killNode { exp_path datestamp list_widget } {

   set indexlist [ $list_widget curselection ]
   ::log::log debug "xflow_killNode list_widget:$list_widget indexlist:$indexlist"
   set listOfNodes ""
   for {set iterator 0} {$iterator < [llength $indexlist]} {incr iterator} {
      set listOfNodes [ linsert $listOfNodes end [ $list_widget get [ lindex $indexlist $iterator ]]]
   }
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
         Sequencer_runCommandLogAndWindow ${exp_path} ${datestamp} [xflow_getToplevel ${exp_path} ${datestamp}] $seqExec "Node Kill [file tail $node]" top -n $node -job_id $nodeID
      } else {
         Utils_raiseError [winfo toplevel ${list_widget}] "Kill Node" "Application Error: Unable to retrieve Task Id."
      }
   }
}

proc xflow_populateDatestamp { exp_path datestamp date_frame } {

   set dateList [LogReader_getAvailableDates ${exp_path}]
   set dateEntryCombo [xflow_getWidgetName ${exp_path} ${datestamp} exp_date_entry]
  
   set values ""
   foreach date $dateList {
      set values "$values [Utils_getVisibleDatestampValue ${date}]"
   }
   ${dateEntryCombo} configure -values $values 
   ${dateEntryCombo} set [Utils_getVisibleDatestampValue ${datestamp}]
}

# Only called in xflow overview mode.
proc xflow_launchFlowNewWindow { exp_path datestamp } {
   set dateEntryCombo [xflow_getWidgetName ${exp_path} ${datestamp} exp_date_entry]
   set hiddenDateWidget [xflow_getWidgetName ${exp_path} ${datestamp} exp_date_hidden]
   set datestampEntryValue [${dateEntryCombo} get]   

   set datestampRealValue [Utils_getRealDatestampValue ${datestampEntryValue}]
   # do nothing if selected value is empty or is already current flow
   if { ${datestampEntryValue} != "" && ${datestampRealValue} != ${datestamp} } {
      Overview_launchExpFlow ${exp_path} ${datestampRealValue}
      # reset to existing value in current flow
      ${dateEntryCombo} set [Utils_getVisibleDatestampValue ${datestamp}]
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
   $dateEntry set [Utils_getVisibleDatestampValue ${datestamp}]
   ${hiddenDate} configure -text [Utils_getVisibleDatestampValue ${datestamp}]
}

# this function is called when the user sets a new datestamp in the
# "Exp Datestamp" field. 
# - Resets flow node status
# - redraw the flow
proc xflow_setDatestampCallback { exp_path datestamp parent_w } {
   global MSG_CENTER_THREAD_ID
   ::log::log debug "xflow_setDatestampCallback exp_path:$exp_path datestamp:$exp_path parent_w:$parent_w"
   set top [winfo toplevel $parent_w]
   set dateEntry [xflow_getWidgetName ${exp_path} ${datestamp} exp_date_entry]

   set newDatestamp [$dateEntry get]

   if { [Utils_validateVisibleDatestamp ${newDatestamp}] == false } {
      tk_messageBox -title "Datestamp Error" -parent ${parent_w} -type ok -icon error \
         -message "Invalid datestamp value: ${newDatestamp}. Format must be yyyymmddhh."
      return
   }

   Utils_busyCursor $top
   # create log file is not exists
   set seqDatestamp [Utils_getRealDatestampValue ${newDatestamp}]
   set logfile ${exp_path}/logs/${seqDatestamp}_nodelog

   set hiddenDate [xflow_getWidgetName ${exp_path} ${datestamp} exp_date_hidden]
   set previousDatestamp [${hiddenDate} cget -text]

   if { ${previousDatestamp} != ${newDatestamp} } {
      # SharedFlowNode_resetNodeStatus ${exp_path} [SharedData_getExpRootNode ${exp_path} ${datestamp}] ${seqDatestamp}

      LogMonitor_createLogFile ${exp_path} ${seqDatestamp}
      SharedData_setExpDatestampOffset ${exp_path} ${seqDatestamp} 0

      ::log::log debug "xflow_setDatestampCallback exp_path:${exp_path} seqDatestamp:${seqDatestamp}"

      ${hiddenDate} configure -text ${newDatestamp}

      if { ${previousDatestamp} != "" } {
         set previousRealDatestamp [Utils_getRealDatestampValue ${previousDatestamp}]
	 # xflow_cleanDatestampVars ${exp_path} ${datestamp}
         SharedData_removeExpThreadId ${exp_path} ${previousRealDatestamp}
      }

      if { [SharedData_getMiscData OVERVIEW_MODE] == true } {
         set expThreadId [ThreadPool_getThread]
         thread::send -async ${expThreadId} "LogReader_startExpLogReader ${exp_path} \"${seqDatestamp}\" no_overview" LogReaderDone
	 vwait LogReaderDone
      } else {
         thread::send -async ${MSG_CENTER_THREAD_ID} "MsgCenterThread_clearAllMessages"
         SharedData_setExpThreadId ${exp_path} ${seqDatestamp} [thread::id]
         SharedData_setMiscData STARTUP_DONE false
         LogReader_startExpLogReader ${exp_path} ${seqDatestamp} no_overview
         SharedData_setMiscData STARTUP_DONE true
      }

      set currentTop [xflow_getToplevel ${exp_path} ${datestamp}]
      set newTop [xflow_getToplevel ${exp_path} ${seqDatestamp}]
      set currentx [winfo x ${currentTop}]
      set currenty [winfo y ${currentTop}]

      xflow_createWidgets ${exp_path} ${seqDatestamp} ${currentx} ${currenty}
      xflow_displayFlow ${exp_path} ${seqDatestamp}
      xflow_closeExpDatestamp ${exp_path} ${datestamp}
   }
   Utils_normalCursor $top
}

# this function returns the resource information that needs to be displayed
# besides the node name. Based on the user preferences View->"Node Display"
proc xflow_getNodeDisplayPrefText { exp_path datestamp node } {
   # puts "xflow_getNodeDisplayPrefText ${exp_path} ${datestamp} ${node}"
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
   if { ${displayPref} != "normal" } {
      if { [string match "*task" [SharedFlowNode_getNodeType ${exp_path} ${node} ${datestamp}]] } {
            set attrValue "[SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} ${attrName}]"
            if { ${displayPref} == "machine_queue" } {
               set queue [SharedFlowNode_getQueue ${exp_path} ${node} ${datestamp}]
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
      if { ${text} != "" } {
         set text "${text}\n(${attrValue})"
      } else {
         set text "(${attrValue})"
      }
   }

   return $text
}

# find a node in the flow and point to it
# the real_node might have an extension attached to
# it example: /a/b/c+12+1
# if multiple indexes are given... the last one can be either a npt or loop index
# the others can only be loop indexes
proc xflow_findNode { exp_path datestamp real_node } {
   ::log::log debug "xflow_findNode exp_path:${exp_path} datestamp:${datestamp} real_node:${real_node}"
   set nodeWithouExt [SharedFlowNode_getNodeFromDisplayFormat ${real_node}]
   set extensionPart [SharedFlowNode_getExtFromDisplayFormat ${real_node}]
   set flowNode [SharedData_getExpNodeMapping ${exp_path} ${datestamp} ${nodeWithouExt}]

   # split the list using + as separator
   set extList [split ${extensionPart} +]
   set extLen [llength ${extList}]
   # start at 1 cause the first element of the extList is a dummy empty value
   set indexCount 1
   set loopList [SharedFlowNode_getLoops ${exp_path} ${flowNode} ${datestamp}]
   set refreshNode ""
   # loop throught the list of indexes
   while { ${indexCount} < ${extLen} } {
      set extValue +[lindex ${extList} ${indexCount}]
      if { [SharedFlowNode_getNodeType ${exp_path} ${flowNode} ${datestamp}] == "npass_task" } {
         SharedFlowNode_setCurrentExt ${exp_path} ${flowNode} $${datestamp} {extValue}
         set refreshNode ${flowNode}
      } else {
         # must be a loop extension
         set loopNode [lindex ${loopList} [expr ${indexCount} - 1]]
         SharedFlowNode_setCurrentExt ${exp_path} ${loopNode} ${datestamp} ${extValue}
      }
      if { ${refreshNode} == "" } {
         set refreshNode ${loopNode}
      }
      incr indexCount
   }
   set collapsedParentNode [SharedFlowNode_uncollapseBranch ${exp_path} ${flowNode} ${datestamp} [xflow_getMainFlowCanvas ${exp_path} ${datestamp}] ]
   if { ${refreshNode} != "" || ${collapsedParentNode} != "" } {
      xflow_drawflow ${exp_path} ${datestamp} [xflow_getMainFlowCanvas ${exp_path} ${datestamp}]
   }
   update idletasks
    ::DrawUtils::pointNode ${exp_path} ${datestamp} ${flowNode}
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
   global FLOW_SCALE_${exp_path}_${datestamp}
   ::log::log debug "xflow_drawNode drawing sub node:$node position:$position "
   set nodeType [SharedFlowNode_getNodeType ${exp_path} ${node} ${datestamp}]
   if { [SharedFlowNode_isParentCollapsed ${exp_path} ${node} ${datestamp} ${canvas}] } {
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
   set deltaY [::DrawUtils::getLineDeltaSpace ${exp_path} ${node} ${datestamp}]
   set drawshadow on
   if { ${flowScale} != "1" } {
      set drawshadow off
   }

   SharedFlowNode_initNodeDatestampCanvas ${exp_path} ${node} ${datestamp} ${canvas}
   set submitter [SharedFlowNode_getSubmitter ${exp_path} ${node} ${datestamp}]
   if { ${submitter} == "" || ${first_node} == "true" } {
      set linex2 [SharedData_getMiscData CANVAS_X_START]
      set liney2 [expr [SharedData_getMiscData CANVAS_Y_START] + ${deltaY}]
      ::log::log debug "xflow_drawNode linex2:$linex2 liney2:$liney2"
   } else {
      SharedFlowNode_initNode ${exp_path} ${submitter} ${datestamp} ${canvas}
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
      foreach { px1 py1 px2 py2 } [SharedFlowNode_getDisplayCoords ${exp_path} ${submitter} ${datestamp} $canvas] { break }

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
            set nextY [SharedFlowNode_getDisplayY ${exp_path} ${node} ${datestamp} ${canvas}]
         } else {
            set nextY [SharedData_getExpDisplayNextY ${exp_path} ${datestamp} $canvas]
         }
         SharedFlowNode_setDisplayY  ${exp_path} ${node} ${datestamp} ${canvas} ${nextY}

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
   set isCollapsed [ SharedFlowNode_isCollapsed ${exp_path} ${node} ${datestamp} ${canvas}]
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
   set extDisplay [SharedFlowNode_getExtDisplay ${exp_path} ${node} ${datestamp} $nodeExtension]
   if { $extDisplay != "" } {
      set text "${text}${extDisplay}"
   }
   if { !((${submits} == "none") ||  (${submits} == "")) && $isCollapsed == 1} {
      set text ${text}+
   }
   set dispPref [xflow_getNodeDisplayPrefText ${exp_path} ${datestamp} ${node}]
   if { $dispPref != "" } {
      set text "${text}\n${dispPref}"
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
         set text "${text}\n[SharedFlowNode_getLoopInfo ${exp_path} ${node} ${datestamp}]"
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
      }
      "outlet" {
         ::DrawUtils::drawOval ${exp_path} ${datestamp} $canvas $tx1 $ty1 $text $text $normalTxtFill $outline $normalFill $node $drawshadow $shadowColor
      }
      default {
         error "Invalid node type:${nodeType} in proc xflow_drawNode()"
      }
   }
   if { ${flowScale} != "1" } { ::tooltip::tooltip $canvas -item ${node} ${text} }
   ::DrawUtils::drawNodeStatus ${exp_path} ${node} ${datestamp} [xflow_getShawdowStatus]
   xflow_MouseWheelCheck ${canvas}
   $canvas bind $node <Double-Button-1> [ list xflow_changeCollapsed ${exp_path} ${datestamp} $canvas $node %X %Y]
   $canvas bind $node <Button-2> [ list xflow_historyCallback ${exp_path} ${datestamp} $node $canvas "" 48] 
   $canvas bind $node <Button-3> [ list xflow_nodeMenu ${exp_path} ${datestamp} $canvas $node %X %Y]

   if { $isCollapsed == 0 } {
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
   eval [set NodeHighLightRestoreCmd_${exp_path}_${datestamp}]
}

# This function is called when user click on a box with button 3
# It will display a popup menu for the current node.
proc xflow_nodeMenu { exp_path datestamp canvas node x y } {
   global ignoreDep 
   ::log::log debug "xflow_nodeMenu() node:$node"

   # highlights the selected node
   ::DrawUtils::highLightNode ${exp_path} ${node} ${datestamp} ${canvas}

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

   menu ${popMenu} -title [SharedFlowNode_getName ${exp_path} ${node} ${datestamp}]

   # when the menu is destroyed, clears the highlighted node
   bind ${popMenu} <Unmap> [list xflow_nodeMenuUnmapCallback ${exp_path} ${datestamp}]

   set historyMenu ${popMenu}.history_menu
   set historyOptions [xflow_getNodeHistoryOptions]
      
   ${popMenu} add cascade -label "History" -underline 0 -menu [menu ${historyMenu}]
   foreach {itemName itemValue} ${historyOptions} {
      ${historyMenu} add command -label ${itemName} -command [list xflow_historyCallback ${exp_path} ${datestamp} $node $canvas $popMenu ${itemValue}]
   }

   ${popMenu} add cascade -label "Info" -underline 0 -menu [menu ${infoMenu}]
   ${popMenu} add cascade -label "Listing" -underline 0 -menu [menu ${listingMenu}]
   ${popMenu} add cascade -label "Submit" -underline 0 -menu [menu ${submitMenu}]
   ${popMenu} add cascade -label "Misc" -underline 0 -menu [menu ${miscMenu}]

   set submits [SharedFlowNode_getSubmits ${exp_path} ${node} ${datestamp} ]
   set isCollapsed [SharedFlowNode_isCollapsed ${exp_path} ${node} ${datestamp} ${canvas}]
   if { ${submits} != "" && ${isCollapsed} } {
      ${popMenu} add command -label "Expand All" -command [list xflow_expandAllCallback ${exp_path} ${datestamp} $node $canvas $popMenu]
   }
   set nodeType [SharedFlowNode_getNodeType ${exp_path} ${node} ${datestamp}]
   if { ${nodeType} == "loop" } {
      xflow_addLoopNodeMenu ${exp_path} ${datestamp} ${popMenu} ${canvas} ${node}
   } elseif { ${nodeType} == "npass_task" } {
      xflow_addNptNodeMenu ${exp_path} ${datestamp} ${popMenu} ${canvas} ${node}
   } else {

      #${infoMenu} add command -label "Node History" -command [list xflow_historyCallback $node $canvas $popMenu 0 ]
      ${infoMenu} add command -label "Node Info" -command [list xflow_nodeInfoCallback ${exp_path} ${datestamp} $node $canvas $popMenu]
      ${infoMenu} add command -label "Node Batch" -command [list xflow_batchCallback ${exp_path} ${datestamp} $node $canvas $popMenu ]

      set currentExtension [SharedFlowNode_getNodeExtension ${exp_path} ${node} ${datestamp}]
      set status [SharedFlowNode_getMemberStatus ${exp_path} ${node} ${datestamp} ${currentExtension}]
      if { ${status} == "begin" } {
          set outputFile [xflow_getOutputFile ${exp_path} ${datestamp} $node]
	  if { [file readable ${outputFile}] } {
	     ${listingMenu} add command -label "Monitor Listing" -command [list xflow_tailfCallback ${exp_path} ${datestamp} $node $canvas ]
          }
      } elseif { ${status} == "abort" || ${status} == "end" } {
          set outputFile [xflow_getOutputFile ${exp_path} ${datestamp} $node]
	  if { [file readable ${outputFile}] } {
	     ${listingMenu} add command -label "Monitor Listing" -command [list xflow_viewOutputFile ${exp_path} ${datestamp} $node ${outputFile}]
          }
      }
      ${listingMenu} add command -label "Node Listing" -command [list xflow_listingCallback ${exp_path} ${datestamp} $node $canvas $popMenu]
      ${listingMenu} add command -label "All Node Listing" -command [list xflow_allListingCallback ${exp_path} ${datestamp} $node $canvas $popMenu success]
      ${listingMenu} add command -label "Node Abort Listing" \
         -command [list xflow_abortListingCallback ${exp_path} ${datestamp} $node $canvas $popMenu] \
         -foreground [::DrawUtils::getBgStatusColor abort]

      ${listingMenu} add command -label "All Node Abort Listing" \
         -command [list xflow_allListingCallback ${exp_path} ${datestamp} $node $canvas $popMenu abort] \
         -foreground [::DrawUtils::getBgStatusColor abort]

      # ${miscMenu} add command -label "New Window" -command [list xflow_newWindowCallback $node $canvas $popMenu]
      ${miscMenu} add command -label "View Workdir" -command [list xflow_launchWorkCallback ${exp_path} ${datestamp} $node $canvas ]
      if { ${nodeType} != "task" } {
         ${submitMenu} add command -label "Submit" -command [list xflow_submitCallback ${exp_path} ${datestamp} $node $canvas $popMenu continue ]
         ${submitMenu} add cascade -label "NO Dependency" -underline 4 -menu [menu ${submitNoDependMenu}]
         ${submitNoDependMenu} add command -label "Submit" \
            -command [list xflow_submitCallback ${exp_path} ${datestamp} $node $canvas $popMenu continue dep_off]
         ${infoMenu} add command -label "Node Config" -command [list xflow_configCallback ${exp_path} ${datestamp} $node $canvas $popMenu ]
         ${infoMenu} add command -label "Evaluated Node Config" -command [list xflow_evalConfigCreateWidgets ${exp_path} ${datestamp} $node $popMenu ]
         ${infoMenu} add command -label "Node Full Config" -command [list xflow_fullConfigCallback ${exp_path} ${datestamp} $node $canvas $popMenu ]
         ${miscMenu} add command -label "Initbranch" -command [list xflow_initbranchCallback ${exp_path} ${datestamp} $node $canvas $popMenu]
      } else {
         ${submitMenu} add command -label "Submit & Continue" -underline 9 -command [list xflow_submitCallback ${exp_path} ${datestamp} $node $canvas $popMenu continue ]
         ${submitMenu} add command -label "Submit & Stop" -underline 9 -command [list xflow_submitCallback ${exp_path} ${datestamp} $node $canvas $popMenu stop ]

         ${submitMenu} add cascade -label "NO Dependency" -underline 4 -menu [menu ${submitNoDependMenu}]
         ${submitNoDependMenu} add command -label "Submit & Continue" -underline 9 \
            -command [list xflow_submitCallback ${exp_path} ${datestamp} $node $canvas $popMenu continue dep_off ]
         ${submitNoDependMenu} add command -label "Submit & Stop" -underline 9 \
            -command [list xflow_submitCallback ${exp_path} ${datestamp} $node $canvas $popMenu stop dep_off ]

         ${infoMenu} add command -label "Node Source" -command [list xflow_sourceCallback ${exp_path} ${datestamp} $node $canvas $popMenu]
         ${infoMenu} add command -label "Node Config" -command [list xflow_configCallback ${exp_path} ${datestamp} $node $canvas $popMenu]
         ${infoMenu} add command -label "Evaluated Node Config" -command [list xflow_evalConfigCreateWidgets ${exp_path} ${datestamp} $node $popMenu]
         ${infoMenu} add command -label "Node Full Config" -command [list xflow_fullConfigCallback ${exp_path} ${datestamp} $node $canvas $popMenu]
         ${miscMenu} add command -label "Initnode" -command [list xflow_initnodeCallback ${exp_path} ${datestamp} $node $canvas $popMenu]
      }
      ${miscMenu} add command -label "End" -command [list xflow_endCallback ${exp_path} ${datestamp} $node $canvas $popMenu]
      ${miscMenu} add command -label "Abort" -command [list xflow_abortCallback ${exp_path} ${datestamp} $node $canvas $popMenu]
      ${infoMenu} add command -label "Node Resource" -command [list xflow_resourceCallback ${exp_path} ${datestamp} $node $canvas $popMenu ]
   }

   ${miscMenu} add command -label "Kill Node" -command [list xflow_killNodeFromDropdown ${exp_path} ${datestamp} $node $canvas $popMenu]

   $popMenu add separator
   $popMenu add command -label "Close"
   
   tk_popup $popMenu $x $y
}

# creates the popup menu for a loop node
proc xflow_addLoopNodeMenu { exp_path datestamp popmenu_w canvas node } {
   ::log::log debug "xflow_addLoopNodeMenu() exp_path:${exp_path} datestamp:${datestamp} node:$node"

   set infoMenu ${popmenu_w}.info_menu
   set listingMenu ${popmenu_w}.listing_menu
   set submitMenu ${popmenu_w}.submit_menu
   set submitNoDependMenu ${popmenu_w}.submit_nodep_menu
   set miscMenu ${popmenu_w}.misc_menu

   ${infoMenu} add command -label "Node History" -command [list xflow_historyCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w}]
   ${infoMenu} add command -label "Node Info" -command [list xflow_nodeInfoCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w}]
   ${infoMenu} add command -label "Node Config" -command [list xflow_configCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w}]
   ${infoMenu} add command -label "Evaluated Node Config" -command [list xflow_evalConfigCreateWidgets ${exp_path} ${datestamp} $node ${popmenu_w}]
   ${infoMenu} add command -label "Node Full Config" -command [list xflow_fullConfigCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w}]
   ${infoMenu} add command -label "Loop Node Batch" -command [list xflow_batchCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w} 1]
   ${infoMenu} add command -label "Member Node Batch" -command [list xflow_batchCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w} 0]
   ${infoMenu} add command -label "Node Resource" -command [list xflow_resourceCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w} ]

   set currentExtension [SharedFlowNode_getNodeExtension ${exp_path} ${node} ${datestamp}]
   set status [SharedFlowNode_getMemberStatus ${exp_path} ${node} ${datestamp} ${currentExtension}]
   puts "currentExtension:$currentExtension"
   if { ${status} == "begin" } {
      set outputFile [xflow_getOutputFile ${exp_path} ${datestamp} $node]
      if { [file readable ${outputFile}] } {
         ${listingMenu} add command -label "Monitor Listing" -command [list xflow_tailfCallback ${exp_path} ${datestamp} $node $canvas ]
      }
   } elseif { ${status} == "abort" || ${status} == "end" } {
      set outputFile [xflow_getOutputFile ${exp_path} ${datestamp} $node]
      if { [file readable ${outputFile}] } {
         ${listingMenu} add command -label "Monitor Listing" -command [list xflow_viewOutputFile ${exp_path} ${datestamp} $node ${outputFile}]
      }
   }

   ${listingMenu} add command -label "Loop Listing" -command [list xflow_listingCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w} 1]
   ${listingMenu} add command -label "Loop Abort Listing" \
      -command [list xflow_abortListingCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w} 1] \
      -foreground [::DrawUtils::getBgStatusColor abort]

   ${listingMenu} add command -label "Member Listing" -command [list xflow_listingCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w}]
   ${listingMenu} add command -label "Member Abort Listing" \
      -command [list xflow_abortListingCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w}] \
      -foreground [::DrawUtils::getBgStatusColor abort]


   ${submitMenu} add command -label "Loop Submit" -command [list xflow_submitLoopCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w} continue ]
   ${submitMenu} add command -label "Member Submit" -command [list xflow_submitCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w} continue ]
   ${submitMenu} add cascade -label "NO Dependency" -underline 4 -menu [menu ${submitNoDependMenu}]
   ${submitNoDependMenu} add command -label "Loop Submit" \
      -command [list xflow_submitLoopCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w} continue dep_off]
   ${submitNoDependMenu} add command -label "Member Submit" \
      -command [list xflow_submitCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w} continue dep_off]

   # ${miscMenu} add command -label "New Window" -command [list xflow_newWindowCallback $node $canvas ${popmenu_w}]
   ${miscMenu} add command -label "View Workdir" -command [list xflow_launchWorkCallback ${exp_path} ${datestamp} $node $canvas ]
   ${miscMenu} add command -label "Loop End" -command [list xflow_endLoopCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w}]
   ${miscMenu} add command -label "Loop Initbranch" -command [list xflow_initbranchLoopCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w}]
   ${miscMenu} add command -label "Member End" -command [list xflow_endCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w}]
   ${miscMenu} add command -label "Member Initbranch" -command [list xflow_initbranchCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w}]
   ${miscMenu} add command -label "Abort" -command [list xflow_abortCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w}]
}

# creates the popup menu for a npt node
proc xflow_addNptNodeMenu { exp_path datestamp popmenu_w canvas node } {


   set infoMenu ${popmenu_w}.info_menu
   set listingMenu ${popmenu_w}.listing_menu
   set submitMenu ${popmenu_w}.submit_menu
   set submitNoDependMenu ${popmenu_w}.submit_nodep_menu
   set miscMenu ${popmenu_w}.misc_menu

   ${infoMenu} add command -label "Node History" -command [list xflow_historyCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w}]
   ${infoMenu} add command -label "Node Info" -command [list xflow_nodeInfoCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w}]
   ${infoMenu} add command -label "Node Batch" -command [list xflow_batchCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w} ]
   ${infoMenu} add command -label "Node Source" -command [list xflow_sourceCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w} ]
   ${infoMenu} add command -label "Node Config" -command [list xflow_configCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w} ]
   ${infoMenu} add command -label "Evaluated Node Config" -command [list xflow_evalConfigCreateWidgets ${exp_path} ${datestamp} $node ${popmenu_w} ]
   ${infoMenu} add command -label "Node Full Config" -command [list xflow_fullConfigCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w}]
   ${infoMenu} add command -label "Node Resource" -command [list xflow_resourceCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w} ]

   set currentExtension [SharedFlowNode_getNodeExtension ${exp_path} ${node} ${datestamp}]
   set status [SharedFlowNode_getMemberStatus ${exp_path} ${node} ${datestamp} ${currentExtension}]
   if { ${status} == "begin" } {
      set outputFile [xflow_getOutputFile ${exp_path} ${datestamp} $node]
      if { [file readable ${outputFile}] } {
         ${listingMenu} add command -label "Monitor Listing" -command [list xflow_tailfCallback ${exp_path} ${datestamp} $node $canvas ]
      }
   } elseif { ${status} == "abort" || ${status} == "end" } {
      set outputFile [xflow_getOutputFile ${exp_path} ${datestamp} $node]
      if { [file readable ${outputFile}] } {
         ${listingMenu} add command -label "Monitor Listing" -command [list xflow_viewOutputFile ${exp_path} ${datestamp} $node ${outputFile}]
      }
   }

   ${listingMenu} add command -label "Node Listing" -command [list xflow_listingCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w}]
   ${listingMenu} add command -label "All Node Listing" -command [list xflow_allListingCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w} success]
   ${listingMenu} add command -label "Node Abort Listing" \
      -command [list xflow_abortListingCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w}] \
      -foreground [::DrawUtils::getBgStatusColor abort]

   ${listingMenu} add command -label "All Node Abort Listing" \
      -command [list xflow_allListingCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w} abort] \
      -foreground [::DrawUtils::getBgStatusColor abort]


   ${submitMenu} add command -label "Submit & Continue" -command [list xflow_submitNpassTaskCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w} continue ]
   ${submitMenu} add command -label "Submit & Stop" -command [list xflow_submitNpassTaskCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w} stop ]
   ${submitMenu} add cascade -label "NO Dependency" -underline 4 -menu [menu ${submitNoDependMenu}]
   ${submitNoDependMenu} add command -label "Submit & Continue" -underline 9 \
      -command [list xflow_submitNpassTaskCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w} continue dep_off ]
   ${submitNoDependMenu} add command -label "Submit & Stop" -underline 9 \
      -command [list xflow_submitNpassTaskCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w} stop dep_off ]

   # ${miscMenu} add command -label "New Window" -command [list xflow_newWindowCallback $node $canvas ${popmenu_w}]
   ${miscMenu} add command -label "View Workdir" -command [list xflow_launchWorkCallback ${exp_path} ${datestamp} $node $canvas ]
   ${miscMenu} add command -label "Initnode" -command [list xflow_initnodeCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w}]
   ${miscMenu} add command -label "End" -command [list xflow_endNpasssTaskCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w}]
   ${miscMenu} add command -label "Abort" -command [list xflow_abortNpasssTaskCallback ${exp_path} ${datestamp} $node $canvas ${popmenu_w}]
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

# this function is called to show the history of a node
# By default, the middle mouse on a node shows the history for the last 48 hours.
# The "Node History" from the Info menu on the node shows only the current datestamp
proc xflow_historyCallback { exp_path datestamp node canvas caller_menu {history 48} {full_loop 0} } {
   ::log::log debug "xflow_historyCallback node:$node canvas:$canvas $full_loop"

   set seqExec [SharedData_getMiscData SEQ_UTILS_BIN]/nodehistory

   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]
   set nodeExt [SharedFlowNode_getListingNodeExtension ${exp_path} ${node} ${datestamp} ${full_loop}]
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
      Sequencer_runCommandWithWindow ${exp_path} ${datestamp} [xflow_getToplevel ${exp_path} ${datestamp}] $seqExec \
         "Node History [file tail $node]$nodeExt -history $history" bottom \
         -n $seqNode$nodeExt ${historyRange}
   }
}

# shows the node information and is invoked from the "Node Info" menu item.
proc xflow_nodeInfoCallback { exp_path datestamp node canvas caller_menu } {
   global env
   set seqExec "[SharedData_getMiscData SEQ_BIN]/nodeinfo"
   set expName [SharedFlowNode_getName ${exp_path} ${node} ${datestamp}]
   set nodeTail [file tail $node]
   set infoWidget [string tolower .${expName}_${nodeTail}_nodeInfo]

   if { [winfo exists $infoWidget] } {
      destroy $infoWidget
   }
   set nodeInfoExec "[SharedData_getMiscData SEQ_BIN]/nodeinfo"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]
   if { [SharedFlowNode_getNodeType ${exp_path} ${node} ${datestamp}] == "npass_task" } {
      set seqLoopArgs [SharedFlowNode_getNptArgs ${exp_path} ${node} ${datestamp}]
      if { ${seqLoopArgs} == "-1" } {
         set seqLoopArgs ""
      }
   } else {
      set seqLoopArgs [SharedFlowNode_getLoopArgs ${exp_path} ${node} ${datestamp}]
   }

   Sequencer_runCommandWithWindow ${exp_path} ${datestamp} [xflow_getToplevel ${exp_path} ${datestamp}] ${nodeInfoExec} "Node Info ${nodeTail}" top -n $seqNode  ${seqLoopArgs}
}

# this command is invoked from the Misc->initbranch menu item
# It sends an initbranch signal to the maestro sequencer for the
# current container node. It deletes all sequencer related node status files for
# the current node and all its child nodes.
proc xflow_initbranchCallback { exp_path datestamp node canvas caller_menu } {
   if { ${datestamp} == "" } {
      Utils_raiseError $canvas "init branch" [xflow_getErroMsg DATESTAMP_REQUIRED]
      return
   }
   set seqExec "[SharedData_getMiscData SEQ_BIN]/maestro"

   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]
   set seqLoopArgs [SharedFlowNode_getLoopArgs ${exp_path} ${node} ${datestamp}]
   if { $seqLoopArgs == "" && [SharedFlowNode_hasLoops ${exp_path} ${node} ${datestamp}] } {
      Utils_raiseError $canvas "initbranch" [xflow_getErroMsg NO_LOOP_SELECT]
   } else {
      Sequencer_runCommandWithWindow ${exp_path} ${datestamp} [xflow_getToplevel ${exp_path} ${datestamp}] $seqExec "initbranch [file tail $node] $seqLoopArgs" top \
         -n $seqNode -s initbranch -f continue $seqLoopArgs
   }
}

# this command is invoked from the Misc->initnode menu item
# It sends an initnode signal to the maestro sequencer for the
# current task node. It deletes all sequencer related node status files for
# the current node.
proc xflow_initnodeCallback { exp_path datestamp node canvas caller_menu } {
   if { ${datestamp} == "" } {
      Utils_raiseError $canvas "node init" [xflow_getErroMsg DATESTAMP_REQUIRED]
      return
   }
   set seqExec "[SharedData_getMiscData SEQ_BIN]/maestro"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]

   set seqLoopArgs [SharedFlowNode_getLoopArgs ${exp_path} ${node} ${datestamp}]
   if { $seqLoopArgs == "" && [SharedFlowNode_hasLoops ${exp_path} ${node} ${datestamp}] } {
      Utils_raiseError $canvas "initnode" [xflow_getErroMsg NO_LOOP_SELECT]
   } else {
      Sequencer_runCommandWithWindow ${exp_path} ${datestamp} [xflow_getToplevel ${exp_path} ${datestamp}] $seqExec "initnode [file tail $node] $seqLoopArgs" top \
         -n $seqNode -s initnode -f continue $seqLoopArgs
      ::log::log notice "${seqExec} -n $seqNode -s initnode -f continue $seqLoopArgs (datestamp=${datestamp})"
   }
}

# this command is invoked from the Misc->initbranch menu item
# It sends an initbranch signal to the maestro sequencer for the
# current loop node. It deletes all sequencer related node status files for
# the current loop node and all its child iteration nodes.
proc xflow_initbranchLoopCallback { exp_path datestamp node canvas caller_menu } {
   if { ${datestamp} == "" } {
      Utils_raiseError $canvas "init branch" [xflow_getErroMsg DATESTAMP_REQUIRED]
      return
   }

   set seqExec "[SharedData_getMiscData SEQ_BIN]/maestro"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]

   set seqLoopArgs [SharedFlowNode_getParentLoopArgs ${exp_path} ${node} ${datestamp}]
   if { $seqLoopArgs == "-1" && [SharedFlowNode_hasLoops ${exp_path} ${node} ${datestamp}] } {
      Utils_raiseError $canvas "initbranch" [xflow_getErroMsg NO_LOOP_SELECT]
   } else {
      Sequencer_runCommandWithWindow ${exp_path} ${datestamp} [xflow_getToplevel ${exp_path} ${datestamp}] $seqExec "initbranch [file tail $node] $seqLoopArgs" top \
         -n $seqNode -s initbranch -f continue $seqLoopArgs
      ::log::log notice "${seqExec} -n $seqNode -s initbranch -f continue $seqLoopArgs (datestamp=${datestamp})"
   }
}

# forces an abort to be sent to maestro sequencer
proc xflow_abortCallback { exp_path datestamp node canvas caller_menu } {
   if { ${datestamp} == "" } {
      Utils_raiseError $canvas "node abort" [xflow_getErroMsg DATESTAMP_REQUIRED]
      return
   }
   set seqExec "[SharedData_getMiscData SEQ_BIN]/maestro"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]

   set seqLoopArgs [SharedFlowNode_getLoopArgs ${exp_path} ${node} ${datestamp}]
   if { $seqLoopArgs == "" && [SharedFlowNode_hasLoops ${exp_path} ${node} ${datestamp}] } {
      Utils_raiseError $canvas "node abort" [xflow_getErroMsg NO_LOOP_SELECT]
   } else {
      Sequencer_runCommandWithWindow ${exp_path} ${datestamp} [xflow_getToplevel ${exp_path} ${datestamp}] $seqExec "abort [file tail $node] $seqLoopArgs" top \
         -n $seqNode -s abort -f continue $seqLoopArgs
      ::log::log notice "${seqExec} -n $seqNode -s abort -f continue $seqLoopArgs (datestamp=${datestamp})"
   }
}

proc xflow_endNpasssTaskCallback { exp_path datestamp node canvas caller_menu } {
   if { ${datestamp} == "" } {
      Utils_raiseError $canvas "node end" [xflow_getErroMsg DATESTAMP_REQUIRED]
      return
   }
   set seqExec "[SharedData_getMiscData SEQ_BIN]/maestro"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]

   set indexListW [::DrawUtils::getIndexWidgetName $node $canvas]
   set indexListValue ""
   if { [winfo exists ${indexListW}] } {
      set indexListValue [${indexListW} get]
      ::log::log debug "xflow_abortNpasssTaskCallback indexListValue:$indexListValue"
   }
   if { ${indexListValue} == "latest" } {
      Utils_raiseError $canvas "Npass_Task end" [xflow_getErroMsg NO_INDEX_SELECT]
   } else {
      set seqNpassTaskArgs [SharedFlowNode_getNptArgs ${exp_path} ${node} ${datestamp} ${indexListValue}]
   
      if { $seqNpassTaskArgs == "-1" } {
         Utils_raiseError $canvas "Npass_Task submit" [xflow_getErroMsg NO_INDEX_SELECT]
      } else {
         ::log::log debug "xflow_abortNpasssTaskCallback $seqNpassTaskArgs"
         Sequencer_runCommandWithWindow ${exp_path} ${datestamp} [xflow_getToplevel ${exp_path} ${datestamp}] $seqExec "end [file tail $node] $seqNpassTaskArgs" top \
            -n $seqNode -s end $seqNpassTaskArgs
         ::log::log debug "xflow_abortNpasssTaskCallback $seqNpassTaskArgs"
         ::log::log notice "${seqExec} -n $seqNode -s end $seqNpassTaskArgs (datestamp=${datestamp})"
      }
   }
}

proc xflow_abortNpasssTaskCallback { exp_path datestamp node canvas caller_menu } {
   if { ${datestamp} == "" } {
      Utils_raiseError $canvas "node abort" [xflow_getErroMsg DATESTAMP_REQUIRED]
      return
   }
   set seqExec "[SharedData_getMiscData SEQ_BIN]/maestro"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]

   set indexListW [::DrawUtils::getIndexWidgetName $node $canvas]
   set indexListValue ""
   if { [winfo exists ${indexListW}] } {
      set indexListValue [${indexListW} get]
      ::log::log debug "xflow_abortNpasssTaskCallback indexListValue:$indexListValue"
   }
   if { ${indexListValue} == "latest" } {
      Utils_raiseError $canvas "Npass_Task submit" [xflow_getErroMsg NO_INDEX_SELECT]
   } else {
      set seqNpassTaskArgs [SharedFlowNode_getNptArgs ${exp_path} ${node} ${datestamp} ${indexListValue}]
   
      if { $seqNpassTaskArgs == "-1" } {
         Utils_raiseError $canvas "Npass_Task submit" [xflow_getErroMsg NO_INDEX_SELECT]
      } else {
         ::log::log debug "xflow_abortNpasssTaskCallback $seqNpassTaskArgs"
         Sequencer_runCommandWithWindow ${exp_path} ${datestamp} [xflow_getToplevel ${exp_path} ${datestamp}] $seqExec "submit [file tail $node] $seqNpassTaskArgs" top \
            -n $seqNode -s abort $seqNpassTaskArgs
         ::log::log debug "xflow_abortNpasssTaskCallback $seqNpassTaskArgs"
         ::log::log notice "${seqExec} -n $seqNode -s abort $seqNpassTaskArgs (datestamp=${datestamp})"
      }
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
   set seqExecWork "[SharedData_getMiscData SEQ_UTILS_BIN]/nodework"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]
   set nodeExt [SharedFlowNode_getListingNodeExtension ${exp_path} ${node} ${datestamp} ${full_loop}]

   if { $nodeExt == "-1" } {
      Utils_raiseError $canvas "node listing" [xflow_getErroMsg NO_LOOP_SELECT]
   } else {
      ::log::log debug "$seqExecWork -n ${seqNode} -ext ${nodeExt}"
      if [ catch { set workpath [split [exec ksh -c "export SEQ_EXP_HOME=${exp_path};export SEQ_DATE=${datestamp}; $seqExecWork -n ${seqNode} -ext ${nodeExt}"] ':'] } message ] {
         Utils_raiseError . "Retrieve node output" $message
         return 0
      }
      set taskBasedir "[lindex $workpath 1]${seqNode}${nodeExt}"
      Utils_launchShell [lindex $workpath 0] ${exp_path} [lindex $workpath 1] "TASK_BASEDIR=[lindex $workpath 1]"
   }
}

# this function is invoked from the "Kill Node" menu item.
# It displays the available jobids of currently running tasks
# for the user to kill.
proc xflow_killNodeFromDropdown { exp_path datestamp node canvas caller_menu } {

   global env
   set shadowColor [SharedData_getColor SHADOW_COLOR]
   set bgColor [SharedData_getColor CANVAS_COLOR]
   set id [clock seconds]
   set tmpdir $env(TMPDIR)
   set tmpfile "${tmpdir}/test$id"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]

   set killPath [SharedData_getMiscData SEQ_UTILS_BIN]/nodekill 
   set cmd "export SEQ_EXP_HOME=${exp_path}; $killPath -n $seqNode -list > $tmpfile 2>&1"
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
      -command [list xflow_killNode ${exp_path} ${datestamp} $soloWindow.list ]]
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
proc xflow_endCallback { exp_path datestamp node canvas caller_menu } {
   if { ${datestamp} == "" } {
      Utils_raiseError $canvas "node end" [xflow_getErroMsg DATESTAMP_REQUIRED]
      return
   }
   set seqExec "[SharedData_getMiscData SEQ_BIN]/maestro"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]

   set seqLoopArgs [SharedFlowNode_getLoopArgs ${exp_path} ${node} ${datestamp}]
   if { $seqLoopArgs == "" && [SharedFlowNode_hasLoops ${exp_path} ${node} ${datestamp}] } {
      Utils_raiseError $canvas "node end" [xflow_getErroMsg NO_LOOP_SELECT]
   } else {
      Sequencer_runCommandWithWindow ${exp_path} ${datestamp} [xflow_getToplevel ${exp_path} ${datestamp}] $seqExec "end [file tail $node] $seqLoopArgs" top \
         -n $seqNode -s end -f continue $seqLoopArgs
      ::log::log notice "$seqExec -n $seqNode -s end -f continue $seqLoopArgs (datestamp=${datestamp})"
   }

}

# forces and end signal to be sent to the maestro sequencer for the current loop node.
proc xflow_endLoopCallback { exp_path datestamp node canvas caller_menu } {
   if { ${datestamp} == "" } {
      Utils_raiseError $canvas "node end" [xflow_getErroMsg DATESTAMP_REQUIRED]
      return
   }
   set seqExec "[SharedData_getMiscData SEQ_BIN]/maestro"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]

   set seqLoopArgs [SharedFlowNode_getParentLoopArgs ${exp_path} ${node} ${datestamp}]
   if { $seqLoopArgs == "-1" && [SharedFlowNode_hasLoops ${exp_path} ${node} ${datestamp}] } {
      Utils_raiseError $canvas "loop end" [xflow_getErroMsg NO_LOOP_SELECT]
   } else {
      Sequencer_runCommandWithWindow ${exp_path} ${datestamp} [xflow_getToplevel ${exp_path} ${datestamp}] $seqExec "end [file tail $node] $seqLoopArgs" top \
         -n $seqNode -s end -f continue $seqLoopArgs
      ::log::log notice "$seqExec -n $seqNode -s end -f continue $seqLoopArgs (datestamp=${datestamp})"
   }
}

# displays the content of a task node (.tsk)
proc xflow_sourceCallback { exp_path datestamp node canvas caller_menu} {
   global SESSION_TMPDIR
   set seqExec "[SharedData_getMiscData SEQ_UTILS_BIN]/nodesource"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]

   set textViewer [SharedData_getMiscData TEXT_VIEWER]
   set defaultConsole [SharedData_getMiscData DEFAULT_CONSOLE]

   set winTitle "Node Source [file tail $node]"
   regsub -all " " ${winTitle} _ tempfile
   set outputfile "${SESSION_TMPDIR}/${tempfile}_[clock seconds]"

   set seqCmd "${seqExec} -n ${seqNode}"
   Sequencer_runCommand ${exp_path} ${datestamp} ${outputfile} ${seqCmd}

   if { ${textViewer} == "default" } {
      create_text_window ${winTitle} ${outputfile} top .
   } else {
      set editorCmd "${textViewer} ${outputfile}"
      ::log::log debug "xflow_sourceCallback running ${defaultConsole} ${editorCmd}"
      TextEditor_goKonsole ${defaultConsole} ${winTitle} ${editorCmd}
   }
}

# displays the content of a config file (.cfg) if it is available.
proc xflow_configCallback { exp_path datestamp node canvas caller_menu} {
   global SESSION_TMPDIR
   set seqExec "[SharedData_getMiscData SEQ_UTILS_BIN]/nodeconfig"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]

   set textViewer [SharedData_getMiscData TEXT_VIEWER]
   set defaultConsole [SharedData_getMiscData DEFAULT_CONSOLE]

   set winTitle "Node Config [file tail $node]"
   regsub -all " " ${winTitle} _ tempfile
   set outputfile "${SESSION_TMPDIR}/${tempfile}_[clock seconds]"

   set seqCmd "${seqExec} -n ${seqNode}"
   Sequencer_runCommand ${exp_path} ${datestamp} ${outputfile} ${seqCmd}

   if { ${textViewer} == "default" } {
      create_text_window ${winTitle} ${outputfile} top .
   } else {
      set editorCmd "${textViewer} ${outputfile}"
      ::log::log debug "xflow_sourceCallback running ${defaultConsole} ${editorCmd}"
      TextEditor_goKonsole ${defaultConsole} ${winTitle} ${editorCmd}
   }
}

proc xflow_evalConfigCreateWidgets { exp_path datestamp node caller_w } {
   global env
   global xflow_EvalConfigFullConfigVar xflow_SubmitHostsVar
   if { ! [info exists xflow_SubmitHostsVar] } {
      set xflow_SubmitHostsVar ""
      set hostsFile $env(SEQ_XFLOW_BIN)/../etc/submit_hosts
      if { [file readable ${hostsFile}] } {
         set xflow_SubmitHostsVar [exec cat ${hostsFile}]
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
   wm title ${topLevelWidget} "Evaluated Config [file tail ${node}] (${node})"
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
   set applyButton [button ${buttonFrame}.apply_button -text Apply -command [list xflow_goEvalConfig ${exp_path} ${datestamp} ${node} ${topLevelWidget}]]

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
}

proc xflow_goEvalConfig { exp_path datestamp node toplevel_w } {
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

   set seqExec "[SharedData_getMiscData SEQ_UTILS_BIN]/evaluate_vars"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]
   set seqLoopArgs [SharedFlowNode_getLoopArgs ${exp_path} ${node} ${datestamp}]

   set textViewer [SharedData_getMiscData TEXT_VIEWER]
   set defaultConsole [SharedData_getMiscData DEFAULT_CONSOLE]

   set winTitle "Evaluated Node Config [file tail $node]"
   regsub -all " " ${winTitle} _ tempfile
   set outputfile "${SESSION_TMPDIR}/${tempfile}_[clock seconds]"
   # set seqCmd "${seqExec} -n ${seqNode} ${seqLoopArgs} -m ${machineValue} -d ${datestamp} -o ${outputfile} ${fullcfg}"
   set seqCmd "${seqExec} -n ${seqNode} ${seqLoopArgs} -m ${machineValue} -d ${datestamp} ${fullcfg}"
   puts $seqCmd
   Utils_busyCursor ${toplevel_w}
   catch {
      Sequencer_runCommand ${exp_path} ${datestamp} ${outputfile} ${seqCmd}
   }
   Utils_normalCursor ${toplevel_w}

   if { ${textViewer} == "default" } {
      create_text_window ${winTitle} ${outputfile} top .
   } else {
      set editorCmd "${textViewer} ${outputfile}"
      ::log::log debug "xflow_goEvalConfig running ${defaultConsole} ${editorCmd}"
      TextEditor_goKonsole ${defaultConsole} ${winTitle} ${editorCmd}
   }
}

proc xflow_fullConfigCallback { exp_path datestamp node canvas caller_menu } {
   global SESSION_TMPDIR
   set seqExec "[SharedData_getMiscData SEQ_UTILS_BIN]/chaindot.py"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]

   set textViewer [SharedData_getMiscData TEXT_VIEWER]
   set defaultConsole [SharedData_getMiscData DEFAULT_CONSOLE]

   set winTitle "Node Full Config [file tail $node]"
   regsub -all " " ${winTitle} _ tempfile
   set outputfile "${SESSION_TMPDIR}/${tempfile}_[clock seconds]"

   set seqCmd "${seqExec} -n ${seqNode} -e ${exp_path} -o ${outputfile}"
   Sequencer_runCommand ${exp_path} ${datestamp} /dev/null ${seqCmd}

   if { ${textViewer} == "default" } {
      create_text_window ${winTitle} ${outputfile} top .
   } else {
      set editorCmd "${textViewer} ${outputfile}"
      ::log::log debug "xflow_sourceCallback running ${defaultConsole} ${editorCmd}"
      TextEditor_goKonsole ${defaultConsole} ${winTitle} ${editorCmd}
   }
}

# displays the resource file (.def) if it is available
proc xflow_resourceCallback { exp_path datestamp node canvas caller_menu } {
   global SESSION_TMPDIR
   set seqExec "[SharedData_getMiscData SEQ_UTILS_BIN]/noderesource"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]

   set textViewer [SharedData_getMiscData TEXT_VIEWER]
   set defaultConsole [SharedData_getMiscData DEFAULT_CONSOLE]

   set winTitle "Node Resource [file tail $node]"
   regsub -all " " ${winTitle} _ tempfile
   set outputfile "${SESSION_TMPDIR}/${tempfile}_[clock seconds]"

   set seqCmd "${seqExec} -n ${seqNode}"
   Sequencer_runCommand ${exp_path} ${datestamp} ${outputfile} ${seqCmd}

   if { ${textViewer} == "default" } {
      create_text_window ${winTitle} ${outputfile} top .
   } else {
      set editorCmd "${textViewer} ${outputfile}"
      ::log::log debug "xflow_resourceCallback running ${defaultConsole} ${editorCmd}"
      TextEditor_goKonsole ${defaultConsole} ${winTitle} ${editorCmd}
   }
}

# displays the latest batch command file generated by maestro
proc xflow_batchCallback { exp_path datestamp node canvas caller_menu {full_loop 0} } {
   global SESSION_TMPDIR
   set seqExec "[SharedData_getMiscData SEQ_UTILS_BIN]/nodebatch"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]

   set nodeExt [SharedFlowNode_getListingNodeExtension ${exp_path} ${node} ${datestamp} ${full_loop}]
   set textViewer [SharedData_getMiscData TEXT_VIEWER]
   set defaultConsole [SharedData_getMiscData DEFAULT_CONSOLE]

   if { $nodeExt == "-1" } {
      Utils_raiseError $canvas "node listing" [xflow_getErroMsg NO_LOOP_SELECT]
   } else {

      if { $nodeExt != "" } {
         set nodeExt ".${nodeExt}"
      }

      set winTitle "Node Batch [file tail ${node}]${nodeExt}"
      regsub -all " " ${winTitle} _ tempfile
      set outputfile "${SESSION_TMPDIR}/${tempfile}_[clock seconds]"
   
      set seqCmd "${seqExec} -n ${seqNode}${nodeExt}"
      Sequencer_runCommand ${exp_path} ${datestamp} ${outputfile} ${seqCmd}
   
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
proc xflow_submitCallback { exp_path datestamp node canvas caller_menu flow {local_ignore_dep dep_on} } {
   global env
   if { ${datestamp} == "" } {
      Utils_raiseError $canvas "node submit" [xflow_getErroMsg DATESTAMP_REQUIRED]
      return
   }

   set ignoreDepFlag ""
   if { ${local_ignore_dep} == "dep_off" } {
      set ignoreDepFlag " -i"
   }

   set seqExec "[SharedData_getMiscData SEQ_BIN]/maestro"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]
   set seqLoopArgs [SharedFlowNode_getLoopArgs ${exp_path} ${node} ${datestamp}]
   if { $seqLoopArgs == "" && [SharedFlowNode_hasLoops ${exp_path} ${node} ${datestamp}] } {
      Utils_raiseError $canvas "node submit" [xflow_getErroMsg NO_LOOP_SELECT]
   } else {
      Sequencer_runCommandLogAndWindow ${exp_path} ${datestamp} [xflow_getToplevel ${exp_path} ${datestamp}] $seqExec "submit [file tail $node] $seqLoopArgs" top \
         -d ${datestamp} -n $seqNode -s submit -f $flow $ignoreDepFlag $seqLoopArgs
   }
}

# same as previous but for loop node
proc xflow_submitLoopCallback { exp_path datestamp node canvas caller_menu flow {local_ignore_dep dep_on}} {
   set ignoreDepFlag ""
   if { ${datestamp} == "" } {
      Utils_raiseError $canvas "node submit" [xflow_getErroMsg DATESTAMP_REQUIRED]
      return
   }
   if { ${local_ignore_dep} == "dep_off" } {
      set ignoreDepFlag " -i"
   }
   set seqExec "[SharedData_getMiscData SEQ_BIN]/maestro"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]
   set seqLoopArgs [SharedFlowNode_getParentLoopArgs ${exp_path} ${node} ${datestamp}]
   if { $seqLoopArgs == "-1" && [SharedFlowNode_hasLoops ${exp_path} ${node} ${datestamp}] } {
      Utils_raiseError $canvas "loop submit" [xflow_getErroMsg NO_LOOP_SELECT]
   } else {
      Sequencer_runCommandLogAndWindow ${exp_path} ${datestamp} [xflow_getToplevel ${exp_path} ${datestamp}] $seqExec "submit [file tail $node] $seqLoopArgs" top \
         -n $seqNode -s submit -f $flow ${ignoreDepFlag} $seqLoopArgs 
   }
}

# same as previous but for npt node
proc xflow_submitNpassTaskCallback { exp_path datestamp node canvas caller_menu flow {local_ignore_dep dep_on} } {

   ::log::log debug "xflow_submitNpassTaskCallback node:$node canvas:$canvas"
   set ignoreDepFlag ""
   if { ${datestamp} == "" } {
      Utils_raiseError $canvas "node submit" [xflow_getErroMsg DATESTAMP_REQUIRED]
      return
   }
   if { ${local_ignore_dep} == "dep_off" } {
      set ignoreDepFlag " -i"
   }
   set seqExec "[SharedData_getMiscData SEQ_BIN]/maestro"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]

   # retrieve index value from widget
   set indexListW [::DrawUtils::getIndexWidgetName $node $canvas]
   set indexListValue ""
   if { [winfo exists ${indexListW}] } {
      set indexListValue [${indexListW} get]
      ::log::log debug "xflow_submitNpassTaskCallback indexListValue:$indexListValue"
   }
   if { ${indexListValue} == "latest" } {
      Utils_raiseError $canvas "Npass_Task submit" [xflow_getErroMsg NO_INDEX_SELECT]
   } else {
      set seqNpassTaskArgs [SharedFlowNode_getNptArgs ${exp_path} ${node} ${datestamp} ${indexListValue}]
   
      if { $seqNpassTaskArgs == "-1" } {
         Utils_raiseError $canvas "Npass_Task submit" [xflow_getErroMsg NO_INDEX_SELECT]
      } else {
         ::log::log debug "xflow_submitNpassTaskCallback $seqNpassTaskArgs"
         Sequencer_runCommandLogAndWindow ${exp_path} ${datestamp} [xflow_getToplevel ${exp_path} ${datestamp}] $seqExec "submit [file tail $node] $seqNpassTaskArgs" top \
            -n $seqNode -s submit -f $flow ${ignoreDepFlag} $seqNpassTaskArgs

      }
   }
}

# this function is invoked to do a 'tail -f' of tha currently-running task
proc xflow_tailfCallback { exp_path datestamp node canvas {full_loop 0} } {
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
      if [ catch { set listPath [exec ksh -c "ls -rt1 ${exp_path}/sequencing/output${seqNode}${nodeExt}.${datestamp}.pgmout* | tail -n 1"] } message ] {
         Utils_raiseError . "Retrieve node output" $message
         return 0
      }
      Utils_launchShell $env(TRUE_HOST) ${exp_path} ${exp_path} "Monitoring=${seqNode}${nodeExt}" "tail -f ${listPath}"
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
   catch { set outputFile [exec ksh -c "ls -rt1 ${exp_path}/sequencing/output${seqNode}${nodeExt}.${datestamp}.pgmout* | tail -n 1"] }
   ::log::log debug "xflow_getOutputFile outputFile:${outputFile}"
   return ${outputFile}
}

proc xflow_viewOutputFile { exp_path datestamp node output_file } {
   set listingViewer [SharedData_getMiscData TEXT_VIEWER]
   set defaultConsole [SharedData_getMiscData DEFAULT_CONSOLE]

   set nodeExt [SharedFlowNode_getListingNodeExtension ${exp_path} ${node} ${datestamp}]
   if { $nodeExt != "" } {
      set nodeExt ".${nodeExt}"
   }
   # title is used only for default viewer
   set winTitle "Node Output [file tail $node]${nodeExt}.${datestamp}"

   if { ${listingViewer} == "default" } {
      create_text_window ${winTitle} ${output_file} top .
   } else {
      set editorCmd "${listingViewer} ${output_file}"
      TextEditor_goKonsole ${defaultConsole} ${winTitle} ${editorCmd}
   }
}

# this funtion is invoked to list all the successfull node listing for this node.
# this means all available listings in different datestamps
proc xflow_allListingCallback { exp_path datestamp node canvas caller_menu type } {
  global env
   #puts "xflow_allListingCallback $exp_path $node $canvas $caller_menu $type"
   set shadowColor [SharedData_getColor SHADOW_COLOR]
   set bgColor [SharedData_getColor CANVAS_COLOR]
   set id [clock seconds]
   set tmpdir $env(TMPDIR)
   set tmpfile "${tmpdir}/test$id"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]

   set listerPath [SharedData_getMiscData SEQ_UTILS_BIN]/nodelister
   set cmd "export SEQ_EXP_HOME=${exp_path}; $listerPath -n ${seqNode} -type $type -list > $tmpfile 2>&1"
   ::log::log debug  "xflow_allListingCallback ksh -c $cmd"
   catch { eval [exec ksh -c $cmd ] }

   if { ${listingViewer} == "default" } {
      create_text_window ${winTitle} ${outputfile} top .
   } else {
      set editorCmd "${listingViewer} ${outputfile}"
      TextEditor_goKonsole ${defaultConsole} ${winTitle} ${editorCmd}
   }
}

# this function is invoked to show the latest succesfull node listing
proc xflow_listingCallback { exp_path datestamp node canvas caller_menu {full_loop 0} } {
   global SESSION_TMPDIR
   ::log::log debug "xflow_listingCallback node:$node canvas:$canvas"
   if { ${datestamp} == "" } {
      Utils_raiseError $canvas "node listing" [xflow_getErroMsg DATESTAMP_REQUIRED]
      return
   }
   set listingExec [SharedData_getMiscData SEQ_UTILS_BIN]/nodelister
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]
   set nodeExt [SharedFlowNode_getListingNodeExtension ${exp_path} ${node} ${datestamp} ${full_loop}]

   set listingViewer [SharedData_getMiscData TEXT_VIEWER]
   set defaultConsole [SharedData_getMiscData DEFAULT_CONSOLE]

   
   if { $nodeExt == "-1" } {
      Utils_raiseError $canvas "node listing" [xflow_getErroMsg NO_LOOP_SELECT]
   } else {
      if { $nodeExt != "" } {
         set nodeExt ".${nodeExt}"
      }
      # title is used only for default viewer
      set winTitle "Node Listing [file tail $node]${nodeExt}.${datestamp}"
      regsub -all " " ${winTitle} _ tempfile
      set outputfile "${SESSION_TMPDIR}/${tempfile}_[clock seconds]"

      set seqCmd "${listingExec} -n ${seqNode}${nodeExt} -d ${datestamp}"
      Sequencer_runCommand ${exp_path} ${datestamp} ${outputfile} ${seqCmd}

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
proc xflow_allListingCallback { exp_path datestamp node canvas caller_menu type } {
  global env
   #puts "xflow_allListingCallback $exp_path $node $canvas $caller_menu $type"
   set shadowColor [SharedData_getColor SHADOW_COLOR]
   set bgColor [SharedData_getColor CANVAS_COLOR]
   set id [clock seconds]
   set tmpdir $env(TMPDIR)
   set tmpfile "${tmpdir}/test$id"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]

   set listerPath [SharedData_getMiscData SEQ_UTILS_BIN]/nodelister
   set cmd "export SEQ_EXP_HOME=${exp_path}; $listerPath -n ${seqNode} -type $type -list > $tmpfile 2>&1"
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
   bind ${listingW}.list <Double-Button-1> [list xflow_showAllListingItem ${exp_path} ${datestamp} ${listingW}.list ${type}]
}

# this function is invoked to display the node listings selected from the
# "All Node Listing" window
proc xflow_showAllListingItem { exp_path datestamp listw list_type} {
   global SESSION_TMPDIR
   ::log::log debug "xflow_showAllListingItem selection: [$listw curselection]"
   set selectedIndexes [$listw curselection]
   set listingExec [SharedData_getMiscData SEQ_UTILS_BIN]/nodelister
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
         Sequencer_runCommand ${exp_path} ${datestamp} ${outputfile} ${seqCmd}
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
proc xflow_abortListingCallback { exp_path datestamp node canvas caller_menu {full_loop 0} } {
   global SESSION_TMPDIR
   ::log::log debug "xflow_abortListingCallback node:$node canvas:$canvas"
   if { ${datestamp} == "" } {
      Utils_raiseError $canvas "node listing" [xflow_getErroMsg DATESTAMP_REQUIRED]
      return
   }
   set abortListingExec [SharedData_getMiscData SEQ_UTILS_BIN]/nodelister
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]

   set nodeExt [SharedFlowNode_getListingNodeExtension ${exp_path} ${node} ${datestamp} ${full_loop}]
   set listingViewer [SharedData_getMiscData TEXT_VIEWER]
   set defaultConsole [SharedData_getMiscData DEFAULT_CONSOLE]

   if { $nodeExt == "-1" } {
      Utils_raiseError $canvas "node listing" [xflow_getErroMsg NO_LOOP_SELECT]
   } else {
      if { $nodeExt != "" } {
         set nodeExt ".${nodeExt}"
      }
      # title is used only for default viewer
      set winTitle "abort Listing [file tail $node]${nodeExt}.${datestamp}"
      regsub -all " " ${winTitle} _ tempfile
      set outputfile "${SESSION_TMPDIR}/${tempfile}_[clock seconds]"

      set seqCmd "${abortListingExec} -n ${seqNode}${nodeExt} -type abort -d ${datestamp}"
      Sequencer_runCommand ${exp_path} ${datestamp} ${outputfile} ${seqCmd}

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
proc xflow_indexedNodeSelectionCallback { exp_path node datestamp canvas combobox_w} {
   ::log::log debug "xflow_indexedNodeSelectionCallback ${exp_path} node:${node} datestamp:${datestamp} canvas:${canvas} $combobox_w"

   set member [${combobox_w} get]

   if { $member != "latest" && [lindex $member 0] != "+" } {
      set member +${member}
   }
   #puts "xflow_indexedNodeSelectionCallback SharedFlowNode_setCurrentExt ${exp_path} ${node} ${datestamp} ${member}"
   SharedFlowNode_setCurrentExt ${exp_path} ${node} ${datestamp} ${member}

   #puts "xflow_indexedNodeSelectionCallback xflow_redrawNodes ${exp_path} ${datestamp} ${node} ${canvas}"
   xflow_redrawNodes ${exp_path} ${datestamp} ${node} ${canvas}
}

# this function is called to expand a node and all of its child nodes
proc xflow_expandAllCallback { exp_path datestamp node canvas caller_menu } {
   SharedFlowNode_uncollapseAll ${exp_path} ${node} ${datestamp} ${canvas}
   destroy $caller_menu
   xflow_drawflow ${exp_path} ${datestamp} $canvas
}

# callback when user click on a box with button 1 to collapse/expand a node
proc xflow_changeCollapsed { exp_path datestamp canvas node x y } {
   
   if { [SharedFlowNode_getSubmits ${exp_path} ${node} ${datestamp}] == "" } {
      ::log::log debug "changeCollapse: node has no children"
      return
   }

   set isCollapsed [SharedFlowNode_isCollapsed ${exp_path} ${node} ${datestamp} ${canvas}]
   if { $isCollapsed == 0 } {
      SharedFlowNode_setCollapsed ${exp_path} ${node} ${datestamp} ${canvas} 1
   } else {
      SharedFlowNode_setCollapsed ${exp_path} ${node} ${datestamp} ${canvas} 0
   }

   xflow_drawflow ${exp_path} ${datestamp} $canvas 0
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
         # get the list of all canvases where the node appears
         set canvasList [SharedFlowNode_getDisplayList ${exp_path} ${node} ${datestamp}]
      } else {
         set canvasList $canvas
      }
      foreach canvas $canvasList {
         set cmdList_${exp_path}_${datestamp} {}
         # instead of removing the nodes one by one, I'm collecting all the cmds
         # and run it at once to avoid less flickering on the gui
         ::DrawUtils::clearBranch ${exp_path} ${node} ${datestamp} ${canvas} cmdList_${exp_path}_${datestamp}
         set nodePosition [SharedFlowNode_getSubmitPosition ${exp_path} ${node} ${datestamp}]
         eval [set cmdList_${exp_path}_${datestamp}]
         xflow_drawNode ${exp_path} ${datestamp} ${canvas} ${node} ${nodePosition}
         xflow_resetScrollRegion ${canvas}
         xflow_addBgImage ${exp_path} ${canvas} [winfo width ${canvas}] [winfo height ${canvas}] true
      }
   }
   xflow_setRefreshMode ${exp_path} ${datestamp} false
}

# redraws the flow for all canvas... if the user has multiple windows open
# on the same experiment
proc xflow_redrawAllFlow { exp_path datestamp } {
   # the active suite could be empty if the redraw is
   # called from the LogReader in overview mode
   set canvasList [SharedData_getExpCanvasList ${exp_path} ${datestamp}]
   foreach canvasW $canvasList {
      xflow_drawflow ${exp_path} ${datestamp} $canvasW 0
   }
}

# user clicks on refresh button in the
# toolbar
# - deletes all nodes
# - rereads flow.xml for each module
# - reread the log file
# - redisplay the flow
proc xflow_refreshFlow { exp_path datestamp } {
   global PROGRESS_REPORT_TXT

   set PROGRESS_REPORT_TXT "Refreshing experiment ..."
   set progressW [ProgressDlg .pdrefresh -title "Flow Refresh" -parent [xflow_getToplevel ${exp_path} ${datestamp}]  -textvariable PROGRESS_REPORT_TXT]
   # for some reason, I need to call the update for the progress dlg to appear properly
   update idletasks

   set result [ catch {

      global NODE_RESOURCE_DONE_${exp_path}_${datestamp} LOOP_RESOURCES_DONE_${exp_path}_${datestamp}
      set LOOP_RESOURCES_DONE_${exp_path}_${datestamp} false
      set NODE_RESOURCE_DONE_${exp_path}_${datestamp} false

      SharedFlowNode_clearAllNodes ${exp_path} ${datestamp}

      SharedData_setExpDatestampOffset ${exp_path} ${datestamp} 0
      if { [SharedData_getMiscData OVERVIEW_MODE] == "false" } {
         LogReader_startExpLogReader ${exp_path} ${datestamp} no_overview
      } else {
         set expThreadId [SharedData_getExpThreadId ${exp_path} ${datestamp}]
	 if { ${expThreadId} == "" } {
	    set expThreadId [ThreadPool_getThread]
	 }
         thread::send -async ${expThreadId} "LogReader_startExpLogReader ${exp_path} \"${datestamp}\" no_overview" LogReaderDone
	 vwait LogReaderDone
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
proc xflow_drawflow { exp_path datestamp canvas {initial_display "1"} } {
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

      xflow_clearCanvasFlow ${canvas}
      xflow_drawNode ${exp_path} ${datestamp} $canvas $rootNode 0 true
      xflow_resetScrollRegion ${canvas}
   
      if { $initial_display == "1" } {
         # $canvas yview moveto 0
         # resize the window depending on size of canvas elements
         xflow_resizeWindow ${exp_path} ${datestamp} ${canvas}
      }

   }
   ::log::log debug "xflow_drawflow() done"
}

# this function resizes the xflow main window depending on the
# items in the canvas
proc xflow_resizeWindow { exp_path datestamp canvas } {
   ::log::log debug "xflow_resizeWindow canvas:${canvas}"

   if { [xflow_isFlowResized ${exp_path} ${datestamp}] == true } {
      ::log::log debug "xflow_resizeWindow FLOW_RESIZED== true returing without resize"
      return
   }

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
   # ${_canvas} configure -scrollregion [list ${x1} ${y1} ${x2} ${y2}] -yscrollincrement 5 -xscrollincrement 5
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
   if { [xflow_getNodeDisplayPref ${exp_path} ${datestamp}] != "normal" } {
      if { ! [info exists NODE_RESOURCE_DONE_${exp_path}_${datestamp}] || [set NODE_RESOURCE_DONE_${exp_path}_${datestamp}] == "false" } {
         if { ${exp_path} != "" } {
            set toplevelW [xflow_getToplevel ${exp_path} ${datestamp}]
            set destroProgessCmd ""
            if { [wm state ${toplevelW}] == "normal" } {
               set progressW [ProgressDlg .node_res_pd -parent ${toplevelW} -title "Node Display Preferrences" -textvariable nodeResourceText]
               # Utils_positionWindow ${progressW}
               set destroProgessCmd "destroy ${progressW}"
            }

            set nodeResourceText "Loading node resources ..."
            # for some reason, I need to call the update for the progress dlg to appear properly
            update idletasks
            ::log::log debug "xflow_nodeResourceCallback retrieving resources for ${exp_path}"
            set rootNode [SharedData_getExpRootNode ${exp_path} ${datestamp}]
            xflow_getNodeResources ${exp_path} ${rootNode} ${datestamp} 1
            set NODE_RESOURCE_DONE_${exp_path}_${datestamp} true
            eval ${destroProgessCmd}
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

   set nodeInfoExec "[SharedData_getMiscData SEQ_BIN]/nodeinfo"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]
   set outputFile $env(TMPDIR)/nodeinfo_output_[file tail $node]_[clock seconds]

   # for now we only care about batch resources from tasks
   ::log::log debug "${nodeInfoExec} -n ${seqNode} -f res |  sed -e 's:node.:$node configure -:' -e 's:=: :'"

   # the line below transforms the output of nodeinfo into a call to SharedFlowNode_setGenericAttributef or every attribute
   # i.e. SharedFlowNode_setGenericAttribute ${exp_path} ${node} attr_name attr_value
   set code [catch {set output [exec ksh -c "export SEQ_EXP_HOME=${exp_path};${nodeInfoExec} -n ${seqNode} -f res |  sed -e 's:node.:SharedFlowNode_setGenericAttribute ${exp_path} ${node} \"${datestamp}\" :' -e 's:=: \":' -e 's/$/\"/'> ${outputFile} 2> /dev/null "]} message]

   if { $code != 0 } {
      Utils_raiseError [xflow_getToplevel ${exp_path} ${datestamp}] "Get Node Resource" $message
      return 0
   }
   if [ catch { eval [exec cat ${outputFile}] } message ] {
      ::log::log notice "\nERROR: xflow_getNodeResources() exp_path:${exp_path} node:${node} datestamp:${datestamp} $message"
   }

   catch { close $fileId }

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
proc xflow_getAllLoopResourcesCallback { exp_path node datestamp} {
   global LOOP_RESOURCES_DONE_${exp_path}_${datestamp}
   if { ! [info exists LOOP_RESOURCES_DONE_${exp_path}_${datestamp}] || [set LOOP_RESOURCES_DONE_${exp_path}_${datestamp}] == "false" } {
      ::log::log debug "xflow_getAllLoopResourcesCallback getting resources..."
      xflow_getAllLoopResources ${exp_path} ${node} ${datestamp}
      set LOOP_RESOURCES_DONE_${exp_path}_${datestamp} true
   }
}

# retrieve loop attributes recursively
proc xflow_getAllLoopResources { exp_path node datestamp} {
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
proc xflow_getLoopResources { node exp_path datestamp} {
   global env
   ::log::log debug "xflow_getLoopResources node:$node"

   if { [SharedFlowNode_getNodeType ${exp_path} ${node} ${datestamp}] != "loop" } {
      ::log::log debug "xflow_getLoopResources nothing to be done for non-loop node"
      return
   }

   set nodeInfoExec "[SharedData_getMiscData SEQ_BIN]/nodeinfo"
   set seqNode [SharedFlowNode_getSequencerNode ${exp_path} ${node} ${datestamp}]
   
   set outputFile $env(TMPDIR)/nodeinfo_output_[file tail $node]_[clock seconds]

   # retrieve loop attributes by parsing output of nodeinfo node.specific i.e.
   # node.specific.TYPE=Default
   # node.specific.START=2
   # node.specific.END=10
   # node.specific.STEP=2
   # node.specific.TYPE=Default
   ::log::log debug "xflow_getLoopResources ${nodeInfoExec} -n ${seqNode} | grep node.specific| sed -e 's:node.specific.::' -e 's:=: :'"
   if [ catch { exec ksh -c "export SEQ_EXP_HOME=${exp_path};${nodeInfoExec} -n ${seqNode} | grep node.specific| sed -e 's:node.specific.::' -e 's:=: :'  > ${outputFile} 2> /dev/null" } message ] {
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

      grid ${drawFrame} -row 0 -column 0 -sticky nsew
   }
   return $canvas
}

proc xflow_canvasConfigureCallback { exp_path datestamp canvas width height} {
   catch {
      xflow_addBgImage ${exp_path} ${datestamp} ${canvas} ${width} ${height} true
   }
   xflow_MouseWheelCheck ${canvas}
}

proc xflow_clearCanvasFlow { _canvas } {
   if { [winfo exists ${_canvas}] } {

      # retrieve all flow elements to delete
      ${_canvas} delete flow_element
   }
   update idletasks
}

proc xflow_addBgImage { _exp_path _datestamp _canvas _width _height {force false} } {
   global FLOW_BG_SOURCE_IMG_${_exp_path}_${_datestamp} FLOW_TILED_IMG_${_exp_path}_${_datestamp}
   package require img::gif

   Utils_busyCursor [winfo toplevel ${_canvas}]

   if { [${_canvas} find withtag backgroundBitmap] == "" } {
      set FLOW_BG_SOURCE_IMG_${_exp_path}_${_datestamp} [image create photo -file [xflow_getImageFile bg_image]]
      set FLOW_TILED_IMG_${_exp_path}_${_datestamp} [image create photo]
      # does not exists, create new one
      ${_canvas} create image 0 0 \
         -anchor nw \
         -image [set FLOW_TILED_IMG_${_exp_path}_${_datestamp}] \
         -tags backgroundBitmap

      ${_canvas} lower backgroundBitmap
      bind ${_canvas} <Destroy> [list xflow_canvasDestroyCallback ${_exp_path} ${_datestamp}]
   }

   xflow_tileBgImage ${_exp_path} ${_datestamp} ${_canvas} [set FLOW_BG_SOURCE_IMG_${_exp_path}_${_datestamp}] [set FLOW_TILED_IMG_${_exp_path}_${_datestamp}] ${_width} ${_height}

   Utils_normalCursor [winfo toplevel ${_canvas}]
}

proc xflow_canvasDestroyCallback { exp_path datestamp } {
   global FLOW_BG_SOURCE_IMG_${exp_path}_${datestamp} FLOW_TILED_IMG_${exp_path}_${datestamp}
   global XFLOW_BG_WIDTH_${exp_path}_${datestamp} XFLOW_BG_HEIGHT_${exp_path}_${datestamp}
   catch { image delete [set FLOW_BG_SOURCE_IMG_${exp_path}_${datestamp}] }
   catch { image delete [set FLOW_TILED_IMG_${exp_path}_${datestamp}] }
   catch { unset XFLOW_BG_WIDTH_${exp_path}_${datestamp} }
   catch { unset XFLOW_BG_HEIGHT_${exp_path}_${datestamp} }
   catch { unset FLOW_BG_SOURCE_IMG_${exp_path}_${datestamp} }
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
      $tiledImage copy $sourceImage -to 0 0 ${usedW} ${usedH}
   } else {
      set previousWidth [set XFLOW_BG_WIDTH_${exp_path}_${datestamp}]
      set previousHeight [set XFLOW_BG_HEIGHT_${exp_path}_${datestamp}]
      if { ${usedW} > ${previousWidth} || ${usedH} > ${previousHeight} } {
         set XFLOW_BG_WIDTH_${exp_path}_${datestamp} ${usedW}
         set XFLOW_BG_HEIGHT_${exp_path}_${datestamp} ${usedH}
         $tiledImage copy $sourceImage -to 0 0 ${usedW} ${usedH}
      }
   }
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

proc xflow_closeExpDatestamp { exp_path datestamp } {
   # puts "xflow_closeExpDatestamp ${exp_path} ${datestamp}"
   set toplevelW [xflow_getToplevel ${exp_path} ${datestamp}]
   destroy ${toplevelW}
}

# function called when user quits the application.
# In overview mode, this is also called by the overview for exp thread cleanup
# if required.
proc xflow_quit { exp_path datestamp {from_overview false} } {
   global XFLOW_STANDALONE NODE_DISPLAY_PREF_${exp_path}_${datestamp}
   global SESSION_TMPDIR TITLE_AFTER_ID_${exp_path}_${datestamp} XFLOW_FIND_AFTER_ID_${exp_path}_${datestamp}

   ::log::log debug "xflow_quit exiting Xflow thread id:[thread::id]"
   set isOverviewMode [SharedData_getMiscData OVERVIEW_MODE]

   if { ${isOverviewMode} == "true" } {
      # we are in overview mode
      set toplevelW [xflow_getToplevel ${exp_path} ${datestamp}]
      destroy ${toplevelW}
      xflow_cleanDatestampVars ${exp_path} ${datestamp}

      if { ${from_overview} == false } {
         if { [Overview_isExpBoxObsolete ${exp_path} ${datestamp}] == true } {
            Overview_cleanDatestamp ${exp_path} ${datestamp}
         } else {
            if { ${datestamp} == "" || [LogMonitor_isLogFileActive ${exp_path} ${datestamp}] == false } {
               set expThreadId [SharedData_getExpThreadId ${exp_path} ${datestamp}]
               # notify overview thread to release me
               Overview_releaseExpThread ${expThreadId} ${exp_path} \"${datestamp}\"
            }
         }
      }

      # clean images used by this flow
      set images [image names]
      set myImageIndexes [lsearch -all ${images} ${toplevelW}*]
      foreach myImageIndex ${myImageIndexes} {
         image delete [lindex ${images} ${myImageIndex}]
      }
   } else {
      # standalone mode
      exit
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
# of new messages available. It will maily update the msg center
# icon to a new message state.
proc xflow_newMessageCallback { exp_path visible_datestamp has_new_msg } {
   global env
   ::log::log debug "xflow_newMessageCallback has_new_msg:$has_new_msg"
   set datestamp [Utils_getRealDatestampValue ${visible_datestamp}]
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
   trace add variable NODE_DISPLAY_PREF_${exp_path}_${datestamp} write "xflow_nodeResourceCallback ${exp_path} \"${datestamp}\""
}

proc xflow_cleanDatestampVars { exp_path datestamp } {
   catch { xflow_canvasDestroyCallback ${exp_path} ${datestamp} }
   foreach variableKey { NODE_DISPLAY_PREF FLOW_SCALE TITLE_AFTER_ID \
                         XFLOW_FIND_AFTER_ID LOOP_RESOURCES_DONE \
			 NODE_RESOURCE_DONE FLOW_RESIZED REFRESH_MODE FLOW_RESIZED \
			 cmdList NodeHighLightRestoreCmd } {
      global ${variableKey}_${exp_path}_${datestamp}
      ::log::log debug "xflow_cleanDatestampVars cleaning variable: ${variableKey}_${exp_path}_${datestamp}"
      catch { unset ${variableKey}_${exp_path}_${datestamp} }
   }
}

# this is the place to validate essential exp
# data for startup
proc xflow_validateExp {} {
   global env
   if { ! [info exists env(SEQ_EXP_HOME)] } {
      Utils_fatalError . "Xflow Startup Error" "SEQ_EXP_HOME environment variable not set! Exiting..."
   }

   set entryModTruePath ""
   set expPath $env(SEQ_EXP_HOME)
   catch { set entryModTruePath [ exec true_path ${expPath}/EntryModule ] }
   if { ${entryModTruePath} == "" } {
      Utils_fatalError . "Xflow Startup Error" "Cannot access ${expPath}/EntryModule. Exiting..."
   }

   return ${expPath}
}

# this function is called to create the widgets of the xflow main window
proc xflow_createWidgets { exp_path datestamp {topx ""} {topy ""}} {
   ::log::log debug "xflow_createWidgets"
   set toplevelW [xflow_getToplevel ${exp_path} ${datestamp}]
   if { ! [winfo exists ${toplevelW}] } {
      puts "xflow_createWidgets creating ${toplevelW}"
      toplevel ${toplevelW}
      if { ${topx} != "" } {
         wm geometry ${toplevelW} +${topx}+${topy}
      }
   }
   wm protocol ${toplevelW} WM_DELETE_WINDOW "xflow_quit ${exp_path} \"${datestamp}\""
   wm iconify ${toplevelW}

   set topFrame [frame [xflow_getWidgetName ${exp_path} ${datestamp} top_frame]]
   xflow_addFileMenu ${exp_path} ${datestamp} $topFrame
   xflow_addViewMenu ${exp_path} ${datestamp} $topFrame
   xflow_addHelpMenu ${exp_path} ${datestamp} $topFrame

   # exp label frame
   set expLabelFrame [frame [xflow_getWidgetName ${exp_path} ${datestamp}  exp_label_frame]]
   set expLabel [label ${expLabelFrame}.exp_label -font [xflow_getExpLabelFont]]

   grid ${expLabel} 
   pack ${expLabelFrame} -side left -padx {20 0}

   set secondFrame [frame  [xflow_getWidgetName ${exp_path} ${datestamp}  second_frame]]
   set toolbarFrame [xflow_getWidgetName ${exp_path} ${datestamp}  toolbar_frame]
   labelframe ${toolbarFrame} -text Toolbar
   xflow_createToolbar ${exp_path} ${datestamp} ${toolbarFrame}   

   # date bar is the 2nd widget
   set expDateFrame [xflow_getWidgetName ${exp_path} ${datestamp} exp_date_frame]
   xflow_addDatestampWidget ${exp_path} ${datestamp} ${expDateFrame}

   # find frame
   set findFrame [frame [xflow_getWidgetName ${exp_path} ${datestamp} find_frame]]
   xflow_createFindWidgets ${exp_path} ${datestamp} ${findFrame}
   set findCloseB [xflow_getWidgetName ${exp_path} ${datestamp} find_close_button]
   ${findCloseB} configure -command [list grid remove ${findFrame}]


   # this displays the widget on the second frame
   grid ${toolbarFrame} -row 0 -column 0 -sticky nsew -padx 2 -ipadx 2
   grid ${expDateFrame} -row 0 -column 1 -sticky nsew -padx 2 -pady 0 -ipadx 2

   # flow_frame is the 3nd widget
   set flowFrame [frame [xflow_getWidgetName ${exp_path} ${datestamp}  flow_frame]]
   set drawFrame [frame ${flowFrame}.draw_frame]

   grid columnconfigure ${flowFrame} 0 -weight 1
   grid rowconfigure ${flowFrame} 0 -weight 1

   # this displays the widgets in the main window layout
   grid $topFrame -row 0 -column 0 -sticky w -padx 2
   grid ${secondFrame} -row 1 -column 0  -sticky nsew -pady 2
   grid ${findFrame} -row 2 -column 0  -sticky nsew -pady 2 -padx 2
   grid remove ${findFrame}
   grid ${flowFrame}  -row 3 -column 0 -columnspan 2 -sticky nsew -padx 2 -pady 2
   grid columnconfigure ${toplevelW} 0 -weight 1
   grid columnconfigure ${toplevelW} 1 -weight 1
   grid rowconfigure ${toplevelW} 3 -weight 2

   set sizeGripW [xflow_getWidgetName ${exp_path}  ${datestamp} main_size_grip]
   ttk::sizegrip ${sizeGripW}
   bind ${sizeGripW} <B1-Motion> [list xflow_B1MotionCallback ${exp_path}  ${datestamp} ${sizeGripW}]

   grid ${sizeGripW} -row 4 -column 1 -sticky se
   
   wm geometry ${toplevelW} =1200x800
}

proc xflow_B1MotionCallback { exp_path datestamp widget } {
   catch {
      ttk::sizegrip::Drag ${widget} [winfo pointerx .] [winfo pointery .]
      xflow_setFlowResized ${exp_path} ${datestamp} true
   }
}

proc xflow_getExpLabelFont {} {
   set expLabelFont ExpLabelFont
   if { [lsearch [font names] ExpLabelFont] == -1 } {
      # create the font if not exists
      font create ExpLabelFont
      font configure ${expLabelFont} -size [SharedData_getMiscData XFLOW_EXP_LABEL_SIZE] -weight bold
   }
   return ${expLabelFont}
}

proc xflow_setExpLabel { _exp_path _displayName _datestamp } {
   # puts "xflow_setExpLabel _displayName:${_displayName} ${_datestamp}"
   set expLabelFrame [xflow_getWidgetName ${_exp_path} ${_datestamp} exp_label_frame]
   set displayValue ${_displayName}
   if { ${_datestamp} != "" } {
      set hour [Utils_getHourFromDatestamp ${_datestamp}]
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
proc xflow_displayFlow { exp_path datestamp {initial_display false} } {
   global env XFLOW_STANDALONE PROGRESS_REPORT_TXT   
   ::log::log debug "xflow_displayFlow thread id:[thread::id] datestamp:${datestamp}"
   ::log::log notice "xflow_displayFlow thread id:[thread::id] exp_path:${exp_path} datestamp:${datestamp}"
   set topLevel [xflow_getToplevel ${exp_path} ${datestamp}]

   xflow_setFlowResized ${exp_path} ${datestamp} false

   set topFrame [xflow_getWidgetName ${exp_path} ${datestamp} top_frame]
   if { ! [winfo exists ${topFrame}] } {
      set PROGRESS_REPORT_TXT "Creating widgets..."
      xflow_createWidgets ${exp_path} ${datestamp}
      set overview_x ""
      foreach {overview_x overview_y} [SharedData_getMiscData OVERVIEW_MAIN_COORDS] { break }
      if { ${overview_x} != "" } {
         xflow_positionFlowWindow ${topLevel} ${overview_x} ${overview_y}
         ::log::log notice "xflow_displayFlow() xflow_positionFlowWindow ${exp_path} ${topLevel} ${overview_x} ${overview_y}"
      }
   }

   xflow_setDatestampVars ${exp_path} ${datestamp}
   set displayName [ExpOptions_getDisplayName ${exp_path}]
   xflow_setExpLabel ${exp_path} ${displayName} ${datestamp}
   ::log::log debug "xflow_displayFlow exp_path ${exp_path}"
   set rootNode [SharedData_getExpRootNode ${exp_path} ${datestamp}]
   set PROGRESS_REPORT_TXT "Getting loop node resources ..."
   xflow_getAllLoopResourcesCallback ${exp_path} ${rootNode} ${datestamp}
   # resource will only be loaded if needed
   xflow_nodeResourceCallback ${exp_path} ${datestamp}

   xflow_populateDatestamp ${exp_path} ${datestamp} [xflow_getWidgetName ${exp_path} ${datestamp} exp_date_frame]

   xflow_initDatestampEntry ${exp_path} ${datestamp}
   ::log::log notice "xflow_displayFlow ${exp_path} xflow_initDatestampEntry done"

   set drawFrame [xflow_getWidgetName ${exp_path} ${datestamp} flow_frame].draw_frame
   set canvas [xflow_createFlowCanvas ${exp_path} ${datestamp} $drawFrame]
   xflow_drawflow ${exp_path} ${datestamp} $canvas ${initial_display}

   xflow_setTitle ${topFrame} ${exp_path} ${datestamp}
   xflow_toFront [winfo toplevel  ${topFrame}]
   ::log::log notice "xflow_displayFlow ${exp_path} thread id:[thread::id] done datestamp:${datestamp}"
   # Console_create
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
      set winTitle "[file tail ${exp_path}] - Xflow - Exp=${exp_path} User=$env(USER) Host=[exec hostname] Time=${current_time}"
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
      set expPath [xflow_validateExp]
      ExpOptions_read ${expPath}

      set newestDatestamp [LogMonitor_getNewestDatestamp ${expPath}]
      SharedData_setExpThreadId ${expPath} ${newestDatestamp} [thread::id]
      LogReader_startExpLogReader ${expPath} ${newestDatestamp} all true
      SharedData_setMiscData STARTUP_DONE true
      xflow_displayFlow ${expPath} ${newestDatestamp}
      thread::send -async ${MSG_CENTER_THREAD_ID} "MsgCenterThread_startupDone"
      # start monitoring datestamps for new log entries
      LogReader_readMonitorDatestamps
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
   return .${topLevel}_${datestamp}
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
         exp_date_hidden  .second_frame.date_frame.hidden
         exp_date_button_frame .second_frame.date_frame.button_frame

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

proc xflow_init { {exp_path ""} } {
   global env DEBUG_TRACE XFLOW_STANDALONE
   global AUTO_MSG_DISPLAY NODE_DISPLAY_PREF
   global SHADOW_STATUS MSG_CENTER_THREAD_ID
   global SESSION_TMPDIR FLOW_SCALE

   set SHADOW_STATUS 0
 
   # initate array containg name for widgets used in the application

   if { ${XFLOW_STANDALONE} == "1" } {
      Utils_createTmpDir
      SharedData_setMiscData XFLOW_THREAD_ID [thread::id]

      set SHADOW_STATUS 0
      SharedData_setMiscData IMAGE_DIR $env(SEQ_XFLOW_BIN)/../etc/images
      if { ! [info exists AUTO_MSG_DISPLAY] } {
         set AUTO_MSG_DISPLAY [SharedData_getMiscData AUTO_MSG_DISPLAY]
      } else {
         ::log::log debug "xflow_init SharedData_setMiscData AUTO_MSG_DISPLAY ${AUTO_MSG_DISPLAY}"
         SharedData_setMiscData AUTO_MSG_DISPLAY ${AUTO_MSG_DISPLAY}
      }
      xflow_setTkOptions
      keynav::enableMnemonics .

      set DEBUG_TRACE [SharedData_getMiscData DEBUG_TRACE]
      set NODE_DISPLAY_PREF  [SharedData_getMiscData NODE_DISPLAY_PREF]
      set MSG_CENTER_THREAD_ID [MsgCenter_getThread]

      Utils_logInit
   }

   xflow_setWidgetNames 

   xflow_setErrorMessages

   keynav::enableMnemonics .

   # xflow_createTmpDir
}

proc xflow_setFlowResized { exp_path datestamp value } {
   global FLOW_RESIZED_${exp_path}_${datestamp}
   set FLOW_RESIZED_${exp_path}_${datestamp} value
}

proc xflow_isFlowResized { exp_path datestamp } {
   global FLOW_RESIZED_${exp_path}_${datestamp}
   set value false
   if { [info exists FLOW_RESIZED_${exp_path}_${datestamp}] } {
      set value [set FLOW_RESIZED_${exp_path}_${datestamp}]
   }
   return ${value}
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

global XFLOW_STANDALONE

if { ! [info exists XFLOW_STANDALONE] || ${XFLOW_STANDALONE} == "1" } {
   if { ! [info exists env(SEQ_XFLOW_BIN) ] } {
      puts "SEQ_XFLOW_BIN must be defined!"
      exit
   }

   set lib_dir $env(SEQ_XFLOW_BIN)/../lib
   puts "lib_dir=$lib_dir"
   set auto_path [linsert $auto_path 0 $lib_dir ]

   package require Tk
   wm withdraw .
   package require DrawUtils
   ::DrawUtils::init
   xflow_parseCmdOptions
}

