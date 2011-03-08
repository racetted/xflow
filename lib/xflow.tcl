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
namespace import ::struct::record::*

global env
if { ! [info exists env(SEQ_XFLOW_BIN) ] } {
   puts "SEQ_XFLOW_BIN must be defined!"
   exit
}

puts "SEQ_XFLOW_BIN=$env(SEQ_XFLOW_BIN)"

set lib_dir $env(SEQ_XFLOW_BIN)/../lib
# puts "lib_dir=$lib_dir"
set auto_path [linsert $auto_path 0 $lib_dir ]

::ttk::setTheme classic
package require DrawUtils
package require SuiteNode
package require FlowNodes

::DrawUtils::init

proc xflow_setTkOptions {} {
   option add *activeBackground [SharedData_getColor ACTIVE_BG]
   option add *selectBackground [SharedData_getColor SELECT_BG]

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
}

proc xflow_addViewMenu { parent } {
   global AUTO_MSG_DISPLAY
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

   set labelMenu $menuW.labelmenu

   $menuW add cascade -label "Node Display" -underline 5 -menu $labelMenu
   menu $labelMenu -tearoff 0
   foreach item "normal catchup cpu machine_queue memory mpi wallclock" {
      set value ${item}
      $labelMenu add radiobutton -label ${item} -variable NODE_DISPLAY_PREF -value ${value} \
         -command [list xflow_redrawAllFlow]
   }

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

   pack $menuButtonW -side left -pady 2 -padx 2
   $menuButtonW configure -state disabled
}

proc xflow_createToolbar { parent } {
   DEBUG "xflow_createToolbar ${parent}" 5
   global MSG_CENTER_THREAD_ID
   set msgCenterW ${parent}.button_msgcenter
   set nodeKillW ${parent}.button_nodekill
   set nodeListW ${parent}.button_nodelist
   set nodeAbortListW ${parent}.button_nodeabortlist
   set colorLegendW ${parent}.button_colorlegend

   set closeW ${parent}.button_close
   set depW ${parent}.button_dep

   set imageDir [SharedData_getMiscData IMAGE_DIR]

   image create photo ${parent}.msg_center_img -file ${imageDir}/open_mail_sh.ppm
   image create photo ${parent}.msg_center_new_img -file ${imageDir}/open_mail_new.ppm
   image create photo ${parent}.node_kill_img -file ${imageDir}/node_kill.ppm
   image create photo ${parent}.node_list_img -file ${imageDir}/node_list.ppm
   image create photo ${parent}.node_abort_list_img -file ${imageDir}/node_abort_list.ppm
   image create photo ${parent}.close -file ${imageDir}/cancel.ppm
   image create photo ${parent}.color_legend_img -file ${imageDir}/color_legend.gif
   image create photo ${parent}.ignore_dep_true -file /home/ops/afsi/sul/icons/source/dep_on2.ppm
   image create photo ${parent}.ignore_dep_false -file /home/ops/afsi/sul/icons/source/dep_off2.ppm

   button ${msgCenterW} -padx 0 -pady 0 -image ${parent}.msg_center_img -command {
      thread::send -async ${MSG_CENTER_THREAD_ID} "MsgCenterThread_showWindow"
   }
   ::tooltip::tooltip ${msgCenterW} "Show Message Center."

   button ${nodeKillW} -image ${parent}.node_kill_img -command [list xflow_nodeKillDisplay ${parent} ]
   tooltip::tooltip ${nodeKillW}  "Open job killing dialog"

   button ${nodeListW} -image ${parent}.node_list_img  -state disabled
   tooltip::tooltip ${nodeListW} "Open succesfull node listing dialog -- future feature."

   button ${nodeAbortListW} -image ${parent}.node_abort_list_img -state disabled
   tooltip::tooltip ${nodeAbortListW} "Open abort node listing dialog -- future feature."

   button ${closeW} -image ${parent}.close -command [list xflow_quit]
   ::tooltip::tooltip ${closeW} "Close application."

   button ${colorLegendW} -image ${parent}.color_legend_img -command [list xflow_showColorLegend ${colorLegendW}]
   tooltip::tooltip ${colorLegendW} "Show color legend."


   button ${depW} -image ${parent}.ignore_dep_false -command [list xflow_changeIgnoreDep ${depW} ${parent}.ignore_dep_true ${parent}.ignore_dep_false] -state disabled

   xflow_changeIgnoreDep ${depW} ${parent}.ignore_dep_true ${parent}.ignore_dep_false

   if { [SharedData_getMiscData OVERVIEW_MODE] == "true" } {
      set overviewW ${parent}.button_overview
      image create photo ${parent}.overview -file ${imageDir}/calendar_clock.ppm
      button ${overviewW} -image ${parent}.overview -command {
         set overviewThreadId [SharedData_getMiscData OVERVIEW_THREAD_ID]
         thread::send -async ${overviewThreadId} "Overview_toFront"
      }
      ::tooltip::tooltip ${overviewW} "Show overview window."
      ::tooltip::tooltip ${closeW} "Close window."
      grid ${msgCenterW} ${overviewW} ${nodeKillW} ${depW} ${nodeListW} ${nodeAbortListW} ${colorLegendW} ${closeW} -sticky w -padx 2
   } else {
      grid ${msgCenterW} ${nodeKillW} ${depW} ${nodeListW} ${nodeAbortListW} ${colorLegendW} ${closeW} -sticky w -padx 2
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
proc xflow_addDatestampWidget { parent } {
   if { $parent == "." } {
      set parent ""
   }

   set dtFrame [ labelframe $parent.dt -text "Exp Datestamp (yyyymmddhh)" ]
   bind $dtFrame <Double-Button-1> [list xflow_viewHideDateButtons . .date .date_hidden "" ]
   tooltip::tooltip $dtFrame "Double-click to hide"

   set dateEntry [entry $dtFrame.entry -width 11 ]
   tooltip::tooltip $dateEntry "Enter a value then set the experiment datestamp."

   set buttonFrame [frame ${dtFrame}.button_frame]
   set imageDir [SharedData_getMiscData IMAGE_DIR]
   image create photo ${buttonFrame}.set_image -file ${imageDir}/ok.ppm
   image create photo ${buttonFrame}.refresh_image -file ${imageDir}/refresh.ppm

   set setButton [button ${buttonFrame}.set_button -image ${buttonFrame}.set_image \
      -command [list xflow_setDateStamp $parent]]
   tooltip::tooltip ${setButton} "Sets new datestamp value."

   set refreshButton [button ${buttonFrame}.refresh_button -image ${buttonFrame}.refresh_image \
      -command [list xflow_getDateStamp $parent]]
   tooltip::tooltip $refreshButton "Reloads the current experiment datestamp value."

   pack $setButton $refreshButton -side left -pady 2 -padx 5
   pack $dateEntry -side left -pady 2 -padx 2
   pack $buttonFrame -pady 2 -side left
   pack $dtFrame -side left -pady 2 -padx 2 -fill x -expand 1

}

# this function creates the widgets that allows
# the user to view the exp in history mode
# It retrieves the list of exp dates with $SEQ_EXP_HOME/logs/*_nodelog files
proc xflow_addMonitorDateWidget { parent } {
   if { $parent == "." } {
      set parent ""
   }

   set monitorFrame [ labelframe $parent.monitor_frame -text "Monitoring Datestamp (yyyymmddhh)" ]
   set monitorEntryCombo ${monitorFrame}.entry_combo
   bind $monitorFrame <Double-Button-1> [list xflow_viewHideDateButtons . .date .date_hidden "" ]
   tooltip::tooltip $monitorFrame "Double-click to hide"

   ttk::combobox ${monitorFrame}.entry_combo

   set buttonFrame [frame ${monitorFrame}.button_frame]
   set imageDir [SharedData_getMiscData IMAGE_DIR]
   image create photo ${buttonFrame}.set_image -file ${imageDir}/ok.ppm
   image create photo ${buttonFrame}.refresh_image -file ${imageDir}/refresh.ppm

   set setButton [button ${buttonFrame}.set_button -image ${buttonFrame}.set_image \
      -command [list xflow_setMonitorDate $parent]]
   tooltip::tooltip $setButton "Sets the datestamp value being displayed in the flow."

   set refreshButton [button ${buttonFrame}.refresh_button -image ${buttonFrame}.refresh_image \
      -command [list xflow_populateMonitorDate]]
   tooltip::tooltip $refreshButton "Refresh the datestamp list."

   # by default the monitor widgets are disabled
   xflow_changeMonitorWidgetState disabled

   pack $setButton $refreshButton -side left -pady 2 -padx 5
   pack ${monitorEntryCombo} -side left -pady 2 -padx 2 -fill x
   pack $buttonFrame -pady 2 -side left
   pack $monitorFrame -side left -pady 2 -padx 2 -fill x -expand 1

   tooltip::tooltip ${monitorEntryCombo} "Select value of the date being displayed in the flow."

}


# this function is only called in xflow standalone mode.
# It propagates the Auto Message Display configuration. Alghouh this configuration
# is already global for the xflow thread, it is also used by the message center so it needs to go through the
# SharedData so that the msg center thread can fetch it.
proc xflow_setAutoMsgDisplay {} {
   global AUTO_MSG_DISPLAY
   DEBUG "xflow_setAutoMsgDisplay AUTO_MSG_DISPLAY new value: ${AUTO_MSG_DISPLAY}" 5
   SharedData_setMiscData AUTO_MSG_DISPLAY ${AUTO_MSG_DISPLAY}
}

# generic callback for whoever wants to call the xflow_selectSuiteTab
# it simply redraws the exp flow
proc xflow_selectSuiteCallback { } {
   xflow_selectSuiteTab [xflow_getTabsParentW] [xflow_getActiveSuite]
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
   DEBUG "xflow_changeMonitorWidgetState called ${new_state}"
   set monitorFrame .date.monitor_frame
   set monitorEntryCombo ${monitorFrame}.entry_combo
   set setButton ${monitorFrame}.button_frame.set_button

   $setButton configure -state ${new_state}
   ${monitorEntryCombo} configure -state ${new_state}
   ${monitorEntryCombo} set latest
}

# this function is called when the user changes the
# "Monitoring Latest Logs" configuration,
# enabling or disabling access to select datestamps in history mode
proc xflow_logsMonitorChanged { parent_w } {
   global MONITORING_LATEST
   DEBUG "xflow_logsMonitorChanged called"
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
   grid forget $currentFrame
   if { $height != "" } {
       $replacementFrame configure -height $height
       grid $replacementFrame -row 2 -column 0 -columnspan 2 -sticky nsew -padx 2 -pady 2
   } else {
      grid $replacementFrame -row 2 -column 0 -columnspan 2 -sticky nsew -padx 2 -pady 2
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
   set killPath [getGlobalValue SEQ_UTILS_BIN]/nodekill 
   set cmd "export SEQ_EXP_HOME=$suitePath; $killPath -listall > $tmpfile 2>&1"
   DEBUG "xflow_nodeKillDisplay ksh -c $cmd" 5
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
   DEBUG "xflow_killNode list_widget:$list_widget indexlist:$indexlist" 5
   set listOfNodes ""
   for {set iterator 0} {$iterator < [llength $indexlist]} {incr iterator} {
      set listOfNodes [ linsert $listOfNodes end [ $list_widget get [ lindex $indexlist $iterator ]]]
   }
   set suiteRecord [xflow_getActiveSuite]
   set suitePath [$suiteRecord cget -suite_path]
   set seqExec [getGlobalValue SEQ_UTILS_BIN]/nodekill
   set numOfEntries [llength $listOfNodes]

   for {set iterator 0} {$iterator < $numOfEntries} {incr iterator} {
      set listEntryValue [ split [ lindex $listOfNodes $iterator ] " " ]
      set jobFullPath [lindex $listEntryValue 8]
      if { [string first "/sequencing/jobinfo/" ${jobFullPath}] != -1 } {
         set jobStartIndex [expr [string first "/sequencing/jobinfo/" ${jobFullPath}] + [string length "/sequencing/jobinfo/"] - 1]
         set jobPath [string range ${jobFullPath} ${jobStartIndex} end]
         set nodeID [file tail ${jobPath}]
         set node [file dirname ${jobPath}]/[lindex $listEntryValue end]
         DEBUG "xflow_killNode command: $seqExec  -n $node -job_id $nodeID" 5
         Sequencer_runCommandWithWindow $suitePath $seqExec "Node Kill [file tail $node]" -n $node -job_id $nodeID
      } else {
         Utils_raiseError [winfo toplevel ${list_widget}] "Kill Node" "Application Error: Unable to retrieve Task Id."
      }
   }
}

# this function is called to populate the list of
# available monitor experiment dates in the
# in the Monitoring Datestamp frame
proc xflow_populateMonitorDate {} {

   set suite_record [xflow_getActiveSuite]
   set suitePath [${suite_record} cget -suite_path]
   set dateList [LogReader_getAvailableDates $suitePath]
   set monitorFrame .date.monitor_frame
   set monitorEntryCombo ${monitorFrame}.entry_combo
   
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
   DEBUG "xflow_setMonitorDate called" 5
   set top [winfo toplevel $parent_w]
   Utils_busyCursor $top
   catch {
      set suiteRecord [xflow_getActiveSuite]
      set suitePath [$suiteRecord cget -suite_path]
      set dateList [LogReader_getAvailableDates $suitePath]
   
      set dateEntryCombo .date.monitor_frame.entry_combo
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
         DEBUG "xflow_setMonitorDate ${MONITOR_DATESTAMP}" 5
         set isOverviewMode [SharedData_getMiscData OVERVIEW_MODE]
         if { ${isOverviewMode} == "true" } {
            set monitorThreadId [xflow_getMonitoredThread]
            # in overview mode, the monitor thread takes care of it
            thread::send ${monitorThreadId} "xflowThread_monitorNewDate ${suiteRecord} ${MONITOR_DATESTAMP}"
         } else {
            # in standalone mode
            # point the exp to the history log
            $suiteRecord configure -read_offset 0 -active_log ${MONITOR_DATESTAMP}
            # make sure all nodes are reset
            ::FlowNodes::resetNodeStatus [$suiteRecord cget -root_node]
            xflow_initStartupMode
            # read the log file
            LogReader_readFile $suiteRecord [thread::id]
            xflow_stopStartupMode
            # update the flow
            xflow_redrawAllFlow
         }
      }
   }

   Utils_normalCursor $top
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
   set dateEntryCombo .date.monitor_frame.entry_combo
   set dateValue [xflow_getMonitoringDatestamp]
   $dateEntryCombo set [Utils_getVisibleDatestampValue ${dateValue}]
}

# currently, this is mainly for overview mode...
# there is a single thread created for each exp that takes care of
# displaying flows in history mode so that the currently active datestamp
# coming from $SEQ_EXP_HOME/ExpDate is always displayed
proc xflow_getMonitoredThread {} {
   global MONITOR_THREAD_ID
   if { ${MONITOR_THREAD_ID} == "" } {
      # Creates the singleton thread if it does not exists
      DEBUG "xflow_getMonitoredThread Creating new thread..." 5
      set MONITOR_THREAD_ID [thread::create {
         global env
         set lib_dir $env(SEQ_XFLOW_BIN)/../lib
         set auto_path [linsert $auto_path 0 $lib_dir ]
         package require SuiteNode
         package require Tk

         # this function is meant to be called in overview mode only.
         # when user views exp in history mode from the initial exp flow window,
         # this function is called to create a new window with the history log.
         # For the moment, a single thread is created to handle the history mode for
         # a specific exp.
         proc xflowThread_monitorNewDate { suite_record datestamp } {
            global XFLOW_STANDALONE MONITORING_LATEST MONITOR_DATESTAMP MONITOR_THREAD_ID
            xflow_init
            set XFLOW_STANDALONE 1
            set MONITORING_LATEST 0
            set MONITOR_DATESTAMP ${datestamp}
            set MONITOR_THREAD_ID [thread::id]
            set thisThreadId [thread::id]
            DEBUG "xflowThread_monitorNewDate thread_id:[thread::id] datestamp:${datestamp} overview_mode?  [SharedData_getMiscData OVERVIEW_MODE]" 5
            xflow_displayFlow [thread::id]
            xflow_setMonitorDateWidget
            xflow_viewHideDateButtons . .date_hidden .date ""
            DEBUG "xflowThread_monitorNewDate thread_id:[thread::id] datestamp:${datestamp} DONE" 5
         }

         # enter event loop
         thread::wait
      }]
   }

   DEBUG "xflow_getMonitoredThread returning id: ${MONITOR_THREAD_ID}" 5
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
   if { [winfo toplevel $parent_w]  == "." } {
      set dateEntry .date.dt.entry
   }
   $dateEntry delete 0 end
   $dateEntry insert 0 $shortDatestamp

   if { ${MONITORING_LATEST} == 1 } {
      set MONITOR_DATESTAMP $dateStamp
   }

   DEBUG "xflow_getDateStamp dateStamp:$shortDatestamp" 5
}

# this function is mainly used as a notification from the
# LogReader when it detects that the ${SEQ_EXP_HOME}/ExpDate has changed
# so that the displayed datestamp should be changed in the gui.
proc xflow_datestampChanged { suite_record } {
   set dateFrame .date
   if { [winfo exists $dateFrame] } {
      xflow_getDateStamp $dateFrame ${suite_record}
   }
}

# this function returns the current exp datestamp value as given
# by the maestro tictac command. The format is '%Y%M%D%H%Min%S' i.e. 20110216000000
proc xflow_retrieveDateStamp { parent_w suite_record } {

   set dateExec "[getGlobalValue SEQ_BIN]/tictac"
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
   set dateExec "[getGlobalValue SEQ_BIN]/tictac"
   set suiteRecord [xflow_getActiveSuite]
   set suitePath [$suiteRecord cget -suite_path]
   if { $top  == "." } {
      set dateEntry .date.dt.entry
   }
   Utils_busyCursor $top

   catch {
      set dateStamp [$dateEntry get]
      set cmd "export SEQ_EXP_HOME=$suitePath;$dateExec -s $dateStamp"
      DEBUG "xflow_setDateStamp $cmd" 5
      if [ catch { exec ksh -c $cmd } message ] {
         Utils_raiseError $top "Datestamp" $message
      }
      set MONITOR_DATESTAMP $dateStamp
      $suiteRecord configure -read_offset 0
      ::FlowNodes::resetNodeStatus [$suiteRecord cget -root_node]

      set isOverviewMode [SharedData_getMiscData OVERVIEW_MODE]
      xflow_initStartupMode
      if { ${isOverviewMode} == "true" } {
         set overviewThreadId [SharedData_getMiscData OVERVIEW_THREAD_ID]
         LogReader_readFile $suiteRecord ${overviewThreadId}
      } else {
         LogReader_readFile $suiteRecord [thread::id]
      }
      xflow_stopStartupMode

      xflow_selectSuiteCallback
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
      if { [string match "*task" [$node cget -flow.type] } {
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
   DEBUG "xflow_findNode ${suite_record} ${real_node}" 5
   set nodeWithouExt [::FlowNodes::getNodeFromDisplayFormat ${real_node}]
   set extensionPart [::FlowNodes::getExtFromDisplayFormat ${real_node}]
   set flowNode [::SuiteNode::getFlowNodeMapping ${suite_record} ${nodeWithouExt}]

   # how many indexes do we have
   set numberIndexes [expr [llength [split ${extensionPart} +]] -1 ]
   set refreshNode ""
   if { ${numberIndexes} > 0 } {
      set indexCount 0
      set loopList [${flowNode} cget -flow.loops]
      # we need to select the indexes for loop members and/or npt nodes
      while { ${indexCount} <= [expr ${numberIndexes} -1] } {
         if { ${indexCount} == [expr ${numberIndexes} -1] && [${flowNode} cget -flow.type] == "npass_task" } {
            # the current node is an npt... the last part must be for the npt index
            set leafEx [::FlowNodes::getExtAtIndex ${extensionPart} ${indexCount}]
            ${flowNode} configure -current ${leafEx}
            set refreshNode ${flowNode}
         } else {
            # must be a loop extension
            set loopNode [lindex ${loopList} ${indexCount}]
            set loopExt [::FlowNodes::getExtLeftSlice ${extensionPart} ${indexCount}]
            ${loopNode} configure -current ${loopExt}
         }
         if { ${refreshNode} == "" } {
            set refreshNode ${loopNode}
         }
         incr indexCount
      }
   }
   
   if { ${refreshNode} != "" } {
      xflow_redrawNodes ${refreshNode}
   }

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
   global REFRESH_MODE
   DEBUG "xflow_drawNode drawing sub node:$node position:$position " 5
   set boxW [SharedData_getMiscData CANVAS_BOX_WIDTH]
   set boxH [SharedData_getMiscData CANVAS_BOX_HEIGHT]
   set pady [SharedData_getMiscData CANVAS_PAD_Y]
   set padTx [SharedData_getMiscData CANVAS_PAD_TXT_X]
   set padTy [SharedData_getMiscData CANVAS_PAD_TXT_Y]
   set shadowColor [SharedData_getColor SHADOW_COLOR]
   set deltaY [::DrawUtils::getLineDeltaSpace ${node}]
   set drawshadow on

   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]
   ::FlowNodes::initNode $node $canvas
   set parentNode [${node} cget -flow.parent]
   if { $parentNode == "" || ${first_node} == "true" } {
      set linex2 [SharedData_getMiscData CANVAS_X_START]
      # set liney2 [ SharedData_getMiscData CANVAS_Y_START]
      set liney2 [expr [SharedData_getMiscData CANVAS_Y_START] + ${deltaY}]
      DEBUG "xflow_drawNode linex2:$linex2 liney2:$liney2"
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

      set displayInfo [::FlowNodes::getDisplayCoords $parentNode $canvas]
      DEBUG "xflow_drawNode displayInfo:$displayInfo"
      set px1 [lindex $displayInfo 0]
      set px2 [lindex $displayInfo 2]
      set py1 [lindex $displayInfo 1]
      set py2 [lindex $displayInfo 3]

      # first draw left arrow, the shape depends on the position of the
      # subnode and previous nodes being drawn
      # if position is 0, means first node job so same level as parent node only x coords changes
      set lineTagName ${node}.submit_tag

      if { $position == 0 } {
         set linex1 $px2
         set liney1 [expr $py1 + ($py2 - $py1) / 2 + $deltaY]
         set liney2 $liney1
         set linex2 [expr $linex1 + $boxW/2]
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

         set linex1 [expr $px2 + $boxW/4]
         set linex2 $linex1
         set liney1 [expr $py1 + ($py2 - $py1) / 2 ]
         set liney2 [expr $nextY + ($boxH/4) + $pady + $deltaY]
         ::DrawUtils::$drawline $canvas $linex1 $liney1 $linex2 $liney2 none $lineColor $drawshadow $shadowColor ${lineTagName}
         # then draw hor line with arrow at end
         set linex2 [expr $px2 + $boxW/2]
         set liney1 $liney2
         ::DrawUtils::$drawline $canvas $linex1 $liney1 $linex2 $liney2 last $lineColor  $drawshadow $shadowColor ${lineTagName}
      }
   }
   set normalTxtFill [SharedData_getColor NORMAL_RUN_TEXT]
   set normalFill [::DrawUtils::getBgStatusColor init]
   set outline [SharedData_getColor NORMAL_RUN_OUTLINE]
   # now draw the node
   set tx1 [expr $linex2 + $padTx]
   set ty1 $liney2
   set children [$node cget -flow.children]
   set text [$node cget -flow.name]
   set isCollapsed [::FlowNodes::isCollapsed $node $canvas]
   if { !(($children == "none") ||  ($children == "")) && $isCollapsed == 1} {
      set text ${text}+
   }
   set nodeExtension [::FlowNodes::getNodeExtension $node]
   set extDisplay [::FlowNodes::getExtDisplay $node $nodeExtension]
   if { $extDisplay != "" } {
      set text "${text}${extDisplay}"
   }
   set dispPref [xflow_getNodeDisplayPrefText $node]
   if { $dispPref != "" } {
      set text "${text}\n${dispPref}"
   }
   
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
         bind ${indexListW} <<ComboboxSelected>> [list xflow_indexedNodeSelectionCallback ${node} ${canvas} %W]
      }
      "loop" {
         set text "${text}\n[::FlowNodes::getLoopInfo $node]"
         ::DrawUtils::drawOval $canvas $tx1 $ty1 $text $text $normalTxtFill $outline $normalFill $node $drawshadow $shadowColor
         set indexListW [::DrawUtils::getIndexWidgetName ${node} ${canvas}]
         bind ${indexListW} <<ComboboxSelected>> [list xflow_indexedNodeSelectionCallback ${node} ${canvas} %W]
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
   ::DrawUtils::drawNodeStatus $node [xflow_getShawdowStatus]
   Utils_bindMouseWheel $canvas 2
   $canvas bind $node <Double-Button-1> [ list xflow_changeCollapsed $canvas $node %X %Y]
   $canvas bind $node <Button-2> [ list xflow_historyCallback $node $canvas "" 48] 
   $canvas bind $node <Button-3> [ list xflow_nodeMenu $canvas $node %X %Y]

   if { $isCollapsed == 0 } {
      # get the childs to display
      if { !(($children == "none") ||  ($children == ""))} {
         set nodePosition 0
         foreach child $children {
            #DEBUG "xflow_drawNode drawing subjob:$subjob" 5
            set childNode $node/$child
            xflow_drawNode $canvas $childNode $nodePosition
            incr nodePosition
         }
      }
   }

   DEBUG "xflow_drawNode drawing sub node:$node done" 5
}

# This function is called when user click on a box with button 3
# It will display a popup menu for the current node.
proc xflow_nodeMenu { canvas node x y } {
   global ignoreDep
   DEBUG "xflow_nodeMenu() node:$node" 5

   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]

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

      ${infoMenu} add command -label "Node History" -command [list xflow_historyCallback $node $canvas $popMenu 0 ]
      ${infoMenu} add command -label "Node Info" -command [list xflow_nodeInfoCallback $node $canvas $popMenu]
      ${infoMenu} add command -label "Node Batch" -command [list xflow_batchCallback $node $canvas $popMenu ]

      ${listingMenu} add command -label "Node Listing" -command [list xflow_listingCallback $node $canvas $popMenu]
      ${listingMenu} add command -label "All Node Listing" -command [list xflow_allListingCallback $node $canvas $popMenu success]
      ${listingMenu} add command -label "Node Abort Listing" \
         -command [list xflow_abortListingCallback $node $canvas $popMenu] \
         -foreground [::DrawUtils::getBgStatusColor abort]

      ${listingMenu} add command -label "All Node Abort Listing" \
         -command [list xflow_allListingCallback $node $canvas $popMenu abort] \
         -foreground [::DrawUtils::getBgStatusColor abort]

      ${miscMenu} add command -label "New Window" -command [list xflow_newWindowCallback $node $canvas $popMenu]
      if { [$node cget -flow.type] != "task" } {
         ${submitMenu} add command -label "Submit" -command [list xflow_submitCallback $node $canvas $popMenu continue ]
         ${submitMenu} add cascade -label "NO Dependency" -underline 4 -menu [menu ${submitNoDependMenu}]
         ${submitNoDependMenu} add command -label "Submit" \
            -command [list xflow_submitCallback $node $canvas $popMenu continue dep_off]
         ${infoMenu} add command -label "Node Config" -command [list xflow_configCallback $node $canvas $popMenu ]
         ${miscMenu} add command -label "Initbranch" -command [list xflow_initbranchCallback $node $canvas $popMenu]
      } else {
         ${submitMenu} add command -label "Submit & Continue" -underline 9 -command [list xflow_submitCallback $node $canvas $popMenu continue ]
         ${submitMenu} add command -label "Submit & Stop" -underline 9 -command [list xflow_submitCallback $node $canvas $popMenu stop ]

         ${submitMenu} add cascade -label "NO Dependency" -underline 4 -menu [menu ${submitNoDependMenu}]
         ${submitNoDependMenu} add command -label "Submit & Continue" -underline 9 \
            -command [list xflow_submitCallback $node $canvas $popMenu continue dep_off ]
         ${submitNoDependMenu} add command -label "Submit & Stop" -underline 9 \
            -command [list xflow_submitCallback $node $canvas $popMenu stop dep_off ]

         ${infoMenu} add command -label "Node Source" -command [list xflow_sourceCallback $node $canvas $popMenu ]
         ${infoMenu} add command -label "Node Config" -command [list xflow_configCallback $node $canvas $popMenu ]
         ${miscMenu} add command -label "Initnode" -command [list xflow_initnodeCallback $node $canvas $popMenu]
      }
      ${miscMenu} add command -label "End" -command [list xflow_endCallback $node $canvas $popMenu]
      ${infoMenu} add command -label "Node Resource" -command [list xflow_resourceCallback $node $canvas $popMenu ]
   }

   ${miscMenu} add command -label "Abort" -command [list xflow_abortCallback $node $canvas $popMenu]
   ${miscMenu} add command -label "Kill Node" -command [list xflow_killNodeFromDropdown $node $canvas $popMenu]

   $popMenu add separator
   $popMenu add command -label "Close"
   
   tk_popup $popMenu $x $y
}

# creates the popup menu for a loop node
proc xflow_addLoopNodeMenu { popmenu_w canvas node } {
   DEBUG "xflow_addLoopNodeMenu() node:$node" 5

   set infoMenu ${popmenu_w}.info_menu
   set listingMenu ${popmenu_w}.listing_menu
   set submitMenu ${popmenu_w}.submit_menu
   set submitNoDependMenu ${popmenu_w}.submit_nodep_menu
   set miscMenu ${popmenu_w}.misc_menu

   ${infoMenu} add command -label "Node History" -command [list xflow_historyCallback $node $canvas ${popmenu_w} 0 ]
   ${infoMenu} add command -label "Node Info" -command [list xflow_nodeInfoCallback $node $canvas ${popmenu_w}]
   ${infoMenu} add command -label "Loop Node Batch" -command [list xflow_batchCallback $node $canvas ${popmenu_w} 1]
   ${infoMenu} add command -label "Member Node Batch" -command [list xflow_batchCallback $node $canvas ${popmenu_w} 0]
   ${infoMenu} add command -label "Node Resource" -command [list xflow_resourceCallback $node $canvas ${popmenu_w} ]

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
   ${miscMenu} add command -label "Loop End" -command [list xflow_endLoopCallback $node $canvas ${popmenu_w}]
   ${miscMenu} add command -label "Loop Initbranch" -command [list xflow_initbranchLoopCallback $node $canvas ${popmenu_w}]
   ${miscMenu} add command -label "Member End" -command [list xflow_endCallback $node $canvas ${popmenu_w}]
   ${miscMenu} add command -label "Member Initbranch" -command [list xflow_initbranchCallback $node $canvas ${popmenu_w}]
}

# creates the popup menu for a npt node
proc xflow_addNptNodeMenu { popmenu_w canvas node } {

   set infoMenu ${popmenu_w}.info_menu
   set listingMenu ${popmenu_w}.listing_menu
   set submitMenu ${popmenu_w}.submit_menu
   set submitNoDependMenu ${popmenu_w}.submit_nodep_menu
   set miscMenu ${popmenu_w}.misc_menu

   ${infoMenu} add command -label "Node History" -command [list xflow_historyCallback $node $canvas ${popmenu_w} 0 ]
   ${infoMenu} add command -label "Node Info" -command [list xflow_nodeInfoCallback $node $canvas ${popmenu_w}]
   ${infoMenu} add command -label "Node Batch" -command [list xflow_batchCallback $node $canvas ${popmenu_w} ]
   ${infoMenu} add command -label "Node Source" -command [list xflow_sourceCallback $node $canvas ${popmenu_w} ]
   ${infoMenu} add command -label "Node Config" -command [list xflow_configCallback $node $canvas ${popmenu_w} ]
   ${infoMenu} add command -label "Node Resource" -command [list xflow_resourceCallback $node $canvas ${popmenu_w} ]

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
      -command [list xflow_submitCallback $node $canvas ${popmenu_w} continue dep_off ]
   ${submitNoDependMenu} add command -label "Submit & Stop" -underline 9 \
      -command [list xflow_submitCallback $node $canvas ${popmenu_w} stop dep_off ]

   ${miscMenu} add command -label "New Window" -command [list xflow_newWindowCallback $node $canvas ${popmenu_w}]
   ${miscMenu} add command -label "Initnode" -command [list xflow_initnodeCallback $node $canvas ${popmenu_w}]
   ${miscMenu} add command -label "End" -command [list xflow_endCallback $node $canvas ${popmenu_w}]

}

# this menu is called when the user request a new partial flow window to be launched
# starting from a selected node
proc xflow_newWindowCallback { node canvas caller_menu } {
   DEBUG "xflow_newWindowCallback node:$node canvas:$canvas" 5
   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]
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

   set suiteRecord [::SuiteNode::getSuiteRecord $newCanvas]
   ::SuiteNode::setDisplayRoot $suiteRecord $newCanvas $displayNode

   # post process when window closes
   wm protocol $topWidget WM_DELETE_WINDOW [list xflow_closeSpawnedWindow $suiteRecord $newCanvas $topWidget ]
   xflow_drawflow $newCanvas

   # expand the view by default
   xflow_expandAllCallback $displayNode $newCanvas ""
}

# this function is called to show the history of a node
# By default, the middle mouse on a node shows the history for the last 48 hours.
# The "Node History" from the Info menu on the node shows only the current datestamp
proc xflow_historyCallback { node canvas caller_menu history {full_loop 0} } {
   DEBUG "xflow_historyCallback node:$node canvas:$canvas $full_loop" 5

   set seqExec [getGlobalValue SEQ_UTILS_BIN]/nodehistory
   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]

   set seqNode [::FlowNodes::getSequencerNode $node]
   set nodeExt [::FlowNodes::getListingNodeExtension $node $full_loop]
   DEBUG "xflow_historyCallback nodeExt:$nodeExt" 5
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
         "Node History [file tail $node]$nodeExt -history $history" \
         -n $seqNode$nodeExt -history $history -edate $dateStamp 
   }
}

# shows the node information and is invoked from the "Node Info" menu item.
proc xflow_nodeInfoCallback { node canvas caller_menu } {
   global env
   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]
   set suiteName [$suiteRecord cget -suite_name]
   set nodeTail [file tail $node]
   set infoWidget [string tolower .${suiteName}_${nodeTail}_nodeInfo]

   if { [winfo exists $infoWidget] } {
      destroy $infoWidget
   }
   toplevel $infoWidget
   Utils_positionWindow $infoWidget $canvas
   wm title $infoWidget "Node Info ${nodeTail}"
   set textWidget [text $infoWidget.txt]
   set outputFile $env(TMPDIR)/nodeinfo_output_${nodeTail}_[clock seconds]
   set seqExpHome [$suiteRecord cget -suite_path]
   set nodeInfoExec "[getGlobalValue SEQ_BIN]/nodeinfo"
   set seqNode [::FlowNodes::getSequencerNode $node]
   if { [$node cget -flow.type] == "npass_task" } {
      set seqLoopArgs [::FlowNodes::getNptArgs ${node} ]
      if { ${seqLoopArgs} == "-1" } {
         set seqLoopArgs ""
      }
   } else {
      set seqLoopArgs [::FlowNodes::getLoopArgs $node]
   }

   DEBUG "xflow_nodeInfoCallback export SEQ_EXP_HOME=${seqExpHome};${nodeInfoExec} -n $seqNode  ${seqLoopArgs}" 5
   set code [catch {eval [exec ksh -c "export SEQ_EXP_HOME=${seqExpHome};${nodeInfoExec} -n $seqNode  ${seqLoopArgs} > ${outputFile} 2> /dev/null"]} message]

   if { $code != 0 } {
      DEBUG "xflow_newWindowCallback ERROR:${message}" 5
      return
   }

   if [catch {open "$outputFile" "r"} fileId] {
      puts stderr "Cannot open $outputFile: $outputFile"
      return 0
   } else {
    while {[gets $fileId line] >= 0} {
      $textWidget insert end "${line}\n"
    }
   }
   catch { close $fileId }
   #$textWidget configure -height [$textWidget count -lines 0.0 end]
   grid $textWidget -column 0 -row 0 -sticky nsew -padx 2 -pady 2
   grid columnconfigure $infoWidget 0 -weight 1
   grid rowconfigure $infoWidget 0 -weight 1
}

# this command is invoked from the Misc->initbranch menu item
# It sends an initbranch signal to the maestro sequencer for the
# current container node. It deletes all sequencer related node status files for
# the current node and all its child nodes.
proc xflow_initbranchCallback { node canvas caller_menu } {
   set seqExec "[getGlobalValue SEQ_BIN]/maestro"
   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]
   set seqNode [::FlowNodes::getSequencerNode $node]
   set seqLoopArgs [::FlowNodes::getLoopArgs $node]
   if { $seqLoopArgs == "" && [::FlowNodes::hasLoops $node] } {
      Utils_raiseError $canvas "initbranch" [getErrorMsg NO_LOOP_SELECT]
   } else {
      Sequencer_runCommandWithWindow [$suiteRecord cget -suite_path] $seqExec "initbranch [file tail $node] $seqLoopArgs" -n $seqNode -s initbranch -f continue $seqLoopArgs
   }
   #$node configure -flow.status initialize
   #::DrawUtils::drawNodeStatus $node
}

# this command is invoked from the Misc->initnode menu item
# It sends an initnode signal to the maestro sequencer for the
# current task node. It deletes all sequencer related node status files for
# the current node.
proc xflow_initnodeCallback { node canvas caller_menu } {
   set seqExec "[getGlobalValue SEQ_BIN]/maestro"
   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]
   set seqNode [::FlowNodes::getSequencerNode $node]
   set seqLoopArgs [::FlowNodes::getLoopArgs $node]
   if { $seqLoopArgs == "" && [::FlowNodes::hasLoops $node] } {
      Utils_raiseError $canvas "initnode" [getErrorMsg NO_LOOP_SELECT]
   } else {
      Sequencer_runCommandWithWindow [$suiteRecord cget -suite_path] $seqExec "initnode [file tail $node] $seqLoopArgs" -n $seqNode -s initnode -f continue $seqLoopArgs
   }
}

# this command is invoked from the Misc->initbranch menu item
# It sends an initbranch signal to the maestro sequencer for the
# current loop node. It deletes all sequencer related node status files for
# the current loop node and all its child iteration nodes.
proc xflow_initbranchLoopCallback { node canvas caller_menu } {
   set seqExec "[getGlobalValue SEQ_BIN]/maestro"
   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]
   set seqNode [::FlowNodes::getSequencerNode $node]
   set seqLoopArgs [::FlowNodes::getParentLoopArgs $node]
   if { $seqLoopArgs == "-1" && [::FlowNodes::hasLoops $node] } {
      Utils_raiseError $canvas "initbranch" [getErrorMsg NO_LOOP_SELECT]
   } else {
      Sequencer_runCommandWithWindow [$suiteRecord cget -suite_path] $seqExec "initbranch [file tail $node] $seqLoopArgs" -n $seqNode -s initbranch -f continue $seqLoopArgs
   }
}

# forces an abort to be sent to maestro sequencer
proc xflow_abortCallback { node canvas caller_menu } {
   set seqExec "[getGlobalValue SEQ_BIN]/maestro"
   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]
   set seqNode [::FlowNodes::getSequencerNode $node]
   set seqLoopArgs [::FlowNodes::getLoopArgs $node]
   if { $seqLoopArgs == "" && [::FlowNodes::hasLoops $node] } {
      Utils_raiseError $canvas "node abort" [getErrorMsg NO_LOOP_SELECT]
   } else {
      Sequencer_runCommandWithWindow [$suiteRecord cget -suite_path] $seqExec "abort [file tail $node] $seqLoopArgs" -n $seqNode -s abort -f continue $seqLoopArgs
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
   set killPath [getGlobalValue SEQ_UTILS_BIN]/nodekill 
   set cmd "export SEQ_EXP_HOME=$suitePath; $killPath -n $seqNode -list > $tmpfile 2>&1"
   DEBUG "xflow_killNodeFromDropdown ksh -c $cmd" 5
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
   set seqExec "[getGlobalValue SEQ_BIN]/maestro"

   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]

   set seqNode [::FlowNodes::getSequencerNode $node]
   set seqLoopArgs [::FlowNodes::getLoopArgs $node]
   if { $seqLoopArgs == "" && [::FlowNodes::hasLoops $node] } {
      Utils_raiseError $canvas "node end" [getErrorMsg NO_LOOP_SELECT]
   } else {
      Sequencer_runCommandWithWindow [$suiteRecord cget -suite_path] $seqExec "end [file tail $node] $seqLoopArgs" -n $seqNode -s end -f continue $seqLoopArgs
   }

}

# forces and end signal to be sent to the maestro sequencer for the current loop node.
proc xflow_endLoopCallback { node canvas caller_menu } {
   set seqExec "[getGlobalValue SEQ_BIN]/maestro"

   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]

   set seqNode [::FlowNodes::getSequencerNode $node]
   set seqLoopArgs [::FlowNodes::getParentLoopArgs $node]
   if { $seqLoopArgs == "-1" && [::FlowNodes::hasLoops $node] } {
      Utils_raiseError $canvas "loop end" [getErrorMsg NO_LOOP_SELECT]
   } else {
      Sequencer_runCommandWithWindow [$suiteRecord cget -suite_path] $seqExec "end [file tail $node] $seqLoopArgs" -n $seqNode -s end -f continue $seqLoopArgs
   }
}

# displays the content of a task node (.tsk)
proc xflow_sourceCallback { node canvas caller_menu} {
   global SESSION_TMPDIR
   set seqExec "[getGlobalValue SEQ_UTILS_BIN]/nodesource"
   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]
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
      DEBUG "xflow_sourceCallback running ${defaultConsole} ${editorCmd}" 5
      TextEditor_goKonsole ${defaultConsole} ${winTitle} ${editorCmd}
   }
}

# displays the content of a config file (.cfg) if it is available.
proc xflow_configCallback { node canvas caller_menu} {
   global SESSION_TMPDIR
   set seqExec "[getGlobalValue SEQ_UTILS_BIN]/nodeconfig"
   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]
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
      DEBUG "xflow_sourceCallback running ${defaultConsole} ${editorCmd}" 5
      TextEditor_goKonsole ${defaultConsole} ${winTitle} ${editorCmd}
   }
}

# displays the resource file (.def) if it is available
proc xflow_resourceCallback { node canvas caller_menu } {
   global SESSION_TMPDIR
   set seqExec "[getGlobalValue SEQ_UTILS_BIN]/noderesource"
   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]
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
      DEBUG "xflow_resourceCallback running ${defaultConsole} ${editorCmd}" 5
      TextEditor_goKonsole ${defaultConsole} ${winTitle} ${editorCmd}
   }
}

# displays the latest batch command file generated by maestro
proc xflow_batchCallback { node canvas caller_menu {full_loop 0} } {
   global SESSION_TMPDIR
   set seqExec "[getGlobalValue SEQ_UTILS_BIN]/nodebatch"
   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]
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
      # Sequencer_runCommandWithWindow [$suiteRecord cget -suite_path] $seqExec "batch file [file tail $node]$nodeExt " -n $seqNode$nodeExt 

      set winTitle "Node Batch [file tail ${node}]${nodeExt}"
      regsub -all " " ${winTitle} _ tempfile
      set outputfile "${SESSION_TMPDIR}/${tempfile}_[clock seconds]"
   
      set seqCmd "${seqExec} -n ${seqNode}${nodeExt}"
      Sequencer_runCommand [$suiteRecord cget -suite_path] ${outputfile} ${seqCmd}
   
      if { ${textViewer} == "default" } {
         create_text_window ${winTitle} ${outputfile} top .
      } else {
         set editorCmd "${textViewer} ${outputfile}"
         DEBUG "xflow_sourceCallback running ${defaultConsole} ${editorCmd}" 5
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
   # global ignoreDep
   set test_flag ""
   if { ${local_ignore_dep} == "dep_off" } {
      set test_flag " -i"
   }

   set seqExec "[getGlobalValue SEQ_BIN]/maestro"

   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]
   set seqNode [::FlowNodes::getSequencerNode $node]
   set seqLoopArgs [::FlowNodes::getLoopArgs $node]
   if { $seqLoopArgs == "" && [::FlowNodes::hasLoops $node] } {
      Utils_raiseError $canvas "node submit" [getErrorMsg NO_LOOP_SELECT]
   } else {
      Sequencer_runCommandWithWindow [$suiteRecord cget -suite_path] $seqExec "submit [file tail $node] $seqLoopArgs" -n $seqNode -s submit -f $flow $test_flag $seqLoopArgs

   }
}

# same as previous but for loop node
proc xflow_submitLoopCallback { node canvas caller_menu flow} {
   set seqExec "[getGlobalValue SEQ_BIN]/maestro"

   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]

   set seqNode [::FlowNodes::getSequencerNode $node]
   set seqLoopArgs [::FlowNodes::getParentLoopArgs $node]
   if { $seqLoopArgs == "-1" && [::FlowNodes::hasLoops $node] } {
      Utils_raiseError $canvas "loop submit" [getErrorMsg NO_LOOP_SELECT]
   } else {
      Sequencer_runCommandWithWindow [$suiteRecord cget -suite_path] $seqExec "submit [file tail $node] $seqLoopArgs" -n $seqNode -s submit -f $flow $seqLoopArgs   
   }
}

# same as previous but for npt node
proc xflow_submitNpassTaskCallback { node canvas caller_menu flow} {
   global ignoreDep

   DEBUG "xflow_submitNpassTaskCallback node:$node canvas:$canvas" 5
   set seqExec "[getGlobalValue SEQ_BIN]/maestro"

   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]

   set seqNode [::FlowNodes::getSequencerNode $node]
   # retrieve index value from widget
   set indexListW "${canvas}.[${node} cget flow.name]"
   set indexListValue ""
   if { [winfo exists ${indexListW}] } {
      set indexListValue [${indexListW} get]
      DEBUG "xflow_submitNpassTaskCallback indexListValue:$indexListValue" 5
   }
   if { ${indexListValue} == "latest" } {
      Utils_raiseError $canvas "Npass_Task submit" [getErrorMsg NO_INDEX_SELECT]
   } else {
      set seqNpassTaskArgs [::FlowNodes::getNptArgs ${node} ${indexListValue}]
   
      if { $seqNpassTaskArgs == "-1" } {
         Utils_raiseError $canvas "Npass_Task submit" [getErrorMsg NO_INDEX_SELECT]
      } else {
         DEBUG "xflow_submitNpassTaskCallback $seqNpassTaskArgs" 5
         Sequencer_runCommandWithWindow [$suiteRecord cget -suite_path] $seqExec "submit [file tail $node] $seqNpassTaskArgs" -n $seqNode -s submit -f $flow $ignoreDep $seqNpassTaskArgs

      }
   }
}

# this funtion is invoked to show the latest succesfull node listing
proc xflow_listingCallback { node canvas caller_menu {full_loop 0} } {
   global SESSION_TMPDIR
   DEBUG "xflow_allListingCallback node:$node canvas:$canvas" 5
   set listingExec [getGlobalValue SEQ_UTILS_BIN]/nodelister
   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]

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
   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]
   set seqNode [::FlowNodes::getSequencerNode $node]
   #set nodeExt [::FlowNodes::getListingNodeExtension $node 0]
   set suitePath [$suiteRecord cget -suite_path]
   set listerPath [getGlobalValue SEQ_UTILS_BIN]/nodelister
   #if { $nodeExt == "-1" } {
   #   Utils_raiseError $canvas "node listing" [getErrorMsg NO_LOOP_SELECT]
   #   return
   #}
   #if { $nodeExt != "" } {
   #   set nodeExt ".${nodeExt}"
   #}
   set cmd "export SEQ_EXP_HOME=$suitePath; $listerPath -n ${seqNode} -type $type -list > $tmpfile 2>&1"
   DEBUG "xflow_allListingCallback ksh -c $cmd" 5
   catch { eval [exec ksh -c $cmd ] }

   ##set fullList [list showAllListings $node $type $canvas $canvas.list]
   set listingW .listing_${type}_${node}
   if { [winfo exists ${listingW}] } {
      destroy ${listingW}
   }
   toplevel ${listingW}
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
         ${listingW}.list insert end $line 
   }

   catch {[exec rm -f $tmpfile]}
   bind ${listingW}.list <Double-Button-1> [list xflow_showAllListingItem ${suiteRecord} ${listingW}.list ${type}]
}

# this function is invoked to display the node listings selected from the
# "All Node Listing" window
proc xflow_showAllListingItem { suite_record listw list_type} {
   global SESSION_TMPDIR
   DEBUG "xflow_showAllListingItem selection: [$listw curselection]" 5
   set selectedIndexes [$listw curselection]
   set listingExec [getGlobalValue SEQ_UTILS_BIN]/nodelister
   set suitePath [${suite_record} cget -suite_path]
   set listingViewer [SharedData_getMiscData TEXT_VIEWER]
   set defaultConsole [SharedData_getMiscData DEFAULT_CONSOLE]

   foreach selectIndex $selectedIndexes {
      set selectedValue [$listw get $selectIndex]
      if { [string first "On " $selectedValue] != 0 } {
         set splittedArgs [split $selectedValue]
         set listingFile [lindex $splittedArgs end]
         set splittedFile [split [file tail $listingFile] .]

         set winTitle "${list_type} Listing [file tail ${listingFile}]"
         regsub -all " " ${winTitle} _ tempfile
         set outputfile "${SESSION_TMPDIR}/${tempfile}_[clock seconds]"

         set seqCmd "${listingExec} -f $listingFile"
         Sequencer_runCommand ${suitePath} ${outputfile} ${seqCmd}
         # Sequencer_runCommandWithWindow $suitePath $listingExec "${list_type} listing ${wTitle}" -f $listingFile
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
   DEBUG "xflow_abortListingCallback node:$node canvas:$canvas" 5
   set abortListingExec [getGlobalValue SEQ_UTILS_BIN]/nodelister
   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]
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
   DEBUG "npassTaskSelectionCallback node:$node $combobox_w" 5

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
   DEBUG "xflow_closeSpawnedWindow suite:$suite canvas:$canvas toplevel_win:$toplevel_win" 5
   set rootNode [::SuiteNode::getDisplayRoot $suite $canvas]
   # recursively remove the display from all nodes in the canvas
   ::FlowNodes::removeDisplayFromNode $rootNode $canvas 1

   # remove the canvas from the suite
   ::SuiteNode::removeDisplayFromSuite $suite $canvas
   destroy $toplevel_win
}

# callback when user click on a box with button 1 to collapse/expand a node
proc xflow_changeCollapsed { canvas binder x y } {
   #DEBUG "xflow_changeCollapsed called canvas:$canvas binder:$binder x:$x y:$y" 4
   if { [${binder} cget -flow.children] == "" } {
      DEBUG "changeCollapse: node has no children" 4
      return
   }

   set isCollapsed [::FlowNodes::isCollapsed $binder $canvas]
   if { $isCollapsed == 0 } {
      ::FlowNodes::setCollapsed $binder $canvas 1
   } else {
      ::FlowNodes::setCollapsed $binder $canvas 0
   }

   #DEBUG "xflow_changeCollapsed: new collapse value:[${binder} cget -flow.display.collapse]" 4
   xflow_drawflow $canvas
}

# redraws the flow starting from a node... without having
# to clear all the canvas
proc xflow_redrawNodes { node {canvas ""} } {
   global REFRESH_MODE
   DEBUG "xflow_redrawNodes node:$node" 5
   set REFRESH_MODE true
   catch {
      if { $canvas == "" } {
         # get the list of all canvases where the node appears
         set canvasList [::FlowNodes::getDisplayList $node]
      } else {
         set canvasList $canvas
      }
   
      foreach canvas $canvasList {
         ::DrawUtils::clearBranch ${canvas} ${node}
         set nodePosition [::FlowNodes::getPosition ${node}]
         xflow_drawNode ${canvas} ${node} ${nodePosition}
         #xflow_resizeWindow ${canvas}
      }
   }
   set REFRESH_MODE false
}

# redraws the flow for all canvas... if the user has multiple windows open
# on the same experiment
proc xflow_redrawAllFlow {} {
   set suiteRecord [xflow_getActiveSuite]
   set canvasList [::SuiteNode::getCanvasList ${suiteRecord}]
   foreach canvasW $canvasList {
      xflow_drawflow $canvasW 0
   }
}

# draws the experiment flow
proc xflow_drawflow { canvas {initial_display "1"} } {
   DEBUG "xflow_drawflow() canvas:$canvas" 5
   if { [winfo exists ${canvas}] } {
      DEBUG "xflow_drawflow() found existing canvas:$canvas" 5
      ::DrawUtils::clearCanvas $canvas

      set suiteRecord [::SuiteNode::getSuiteRecord $canvas]
      # reset the default spacing for drawing flow
      ::SuiteNode::resetDisplayData ${suiteRecord} ${canvas}
      set rootNode [::SuiteNode::getDisplayRoot $suiteRecord $canvas]

      set callback xflow_changeCollapsed
      xflow_drawNode $canvas $rootNode 0 true
      set canvasArea [$canvas bbox all]
      $canvas  configure -scrollregion $canvasArea -yscrollincrement 5 -xscrollincrement 5
      # resize the window depending on size of canvas elements
      xflow_resizeWindow ${canvas}

      if { $initial_display == "1" } {
         $canvas yview moveto 0
      }
      xflow_AddCanvasBg ${canvas}
   }
   DEBUG "xflow_drawflow() done" 5

}

# this function resizes the xflow main window depending on the
# items in the canvas
proc xflow_resizeWindow { canvas } {
   DEBUG "xflow_resizeWindow canvas:${canvas}" 5

   if { [winfo exists ${canvas}] } {
      set topLevel [winfo toplevel ${canvas}]
      set suiteRecord [::SuiteNode::getSuiteRecord $canvas]
      set heightMax [winfo screenheight [winfo toplevel ${canvas}]]
      set widthMax [winfo screenwidth [winfo toplevel ${canvas}]]
      set canvasMaximX [::SuiteNode::getDisplayMaximumX ${suiteRecord} ${canvas}]
      set canvasMaximY [::SuiteNode::getDisplayMaximumY ${suiteRecord} ${canvas}]
      set windowW [expr ${canvasMaximX} + 50]
      set windowH [expr ${canvasMaximY} + 135]
      if { [expr ${windowH} > ${heightMax}] } {
         DEBUG "xflow_resizeWindow height ${windowH} > ${heightMax} (default)" 5
         set windowH ${heightMax}
      }
      if { [expr ${windowW} > ${widthMax}] } {
         DEBUG "xflow_resizeWindow width ${windowW} > ${widthMax} (default)" 5
         set windowW ${widthMax}
      }
      wm geometry ${topLevel} =${windowW}x${windowH}
   }
}

# this function is a leftover when xflow was supporting multipe exps.
# It is still use yet only to parse the exp flow.xml file.
proc xflow_createTabs { parent suiteList bind_cmd {page_h 1} {page_w 1}} {
   global env
   DEBUG "xflow_createTabs parent:$parent suiteList:$suiteList bind_cmd:$bind_cmd "
   set tabsetWidget $parent

   set count 0
   foreach suitePath $suiteList {
      set suiteName [file tail $suitePath]
      set drawFrame $parent.[::SuiteNode::formatName $suitePath]
      frame $drawFrame

      grid columnconfigure $parent 0 -weight 1
      grid rowconfigure $parent 0 -weight 1

      # get the leaf part of the entry module, that will give us the
      # root node of the experiment
      set entryMod $suitePath
      set entryModTruePath [exec true_path $env(SEQ_EXP_HOME)/EntryModule]
      set entryMod [file tail $entryModTruePath]

      readMasterfile ${suitePath}/EntryModule/flow.xml $suitePath "" ""
      set suiteRecord [::SuiteNode::formatSuiteRecord $suitePath]
      set rootNode [${suiteRecord} cget -root_node]
      xflow_getNodeResources ${rootNode} $suitePath 1
      incr count
   }
}

# this function retrives the node resource info by executing
# the maestro-utils nodeinfo. Recursivity can also be enabled using
# is_recursive function parameter.
proc xflow_getNodeResources { node suite_path {is_recursive 0} } {
   global env
   DEBUG "xflow_getNodeResources node:$node"
   set nodeInfoExec "[getGlobalValue SEQ_BIN]/nodeinfo"
   set seqNode [::FlowNodes::getSequencerNode $node]
   set outputFile $env(TMPDIR)/nodeinfo_output_[file tail $node]_[clock seconds]

   # for now we only care about batch resources from tasks
   if { [string match "*Task" [$node cget -flow.type] ] } {
      # the next command runs nodeinfo and converts each line of the output
      # into a tcl command
      set code [catch {set output [exec ksh -c "export SEQ_EXP_HOME=${suite_path};${nodeInfoExec} -n ${seqNode} -f res |  sed -e 's:node.:$node configure -:' -e 's:=: :' > ${outputFile} 2> /dev/null "]} message]
   
      if { $code != 0 } {
         Utils_raiseError . "Get Node Resource" $message
         return 0
      }
      if [ catch { eval [exec cat ${outputFile}] } message ] {
         puts "\n$message"
      }

      catch { close $fileId }
   } elseif { [$node cget -flow.type] == "loop" } {
      xflow_getLoopResources ${node} ${suite_path}
   } 

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

# now that the loops attributes are stored in the node resource xml file,
# this function calls the nodeinfo to retrieve loop attributes.
proc xflow_getLoopResources { node suite_path } {
   global env
   DEBUG "xflow_getLoopResources node:$node"

   if { [$node cget -flow.type] != "loop" } {
      DEBUG "xflow_getLoopResources nothing to be done for non-loop node"
      return
   }

   set nodeInfoExec "[getGlobalValue SEQ_BIN]/nodeinfo"
   set seqNode [::FlowNodes::getSequencerNode $node]
   set outputFile $env(TMPDIR)/nodeinfo_output_[file tail $node]_[clock seconds]

   # retrieve loop attributes by parsing output of nodeinfo node.specific i.e.
   # node.specific.TYPE=Default
   # node.specific.START=2
   # node.specific.END=10
   # node.specific.STEP=2
   # node.specific.TYPE=Default
   DEBUG "xflow_getLoopResources ${nodeInfoExec} -n ${seqNode} | grep node.specific| sed -e 's:node.specific.::' -e 's:=: :'"
   if [ catch { exec ksh -c "${nodeInfoExec} -n ${seqNode} | grep node.specific| sed -e 's:node.specific.::' -e 's:=: :'  > ${outputFile} 2> /dev/null" } message ] {
      Utils_raiseError . "Get Loop Resources" $message
      return 0
   }

   DEBUG "xflow_getLoopResources cat ${outputFile}"
   array set valueList {}
   if [ catch { array set valueList [exec cat ${outputFile}] } message ] {
      puts "\n$message"
   }

   # maps the node.specific attribute name to the
   # node record attribute name
   array set attrMap { 
      TYPE loop_type
      START start
      STEP step
      END end
      SET sets
   }

   foreach { name value } [array get valueList] {
      if { [info exists attrMap(${name})] } {
         set attrName $attrMap(${name})
         ${node} configure -${attrName} ${value}
      } else {
         DEBUG "xflow_getLoopResources invalid loop attribute token name:$name value:$value"
      }
   }
}

# this is leftover code when the xflow was able to display multiple exps
# using tabs. This function is still used to refresh the content of an exp flow,
# however xflow supports only one exp now.
proc xflow_selectSuiteTab { parent suite_record } {

   DEBUG "xflow_selectSuiteTab parent:$parent suite_record:${suite_record}"

   set title "xflow experiment path = [${suite_record} cget -suite_path]"
   wm title . $title

   xflow_setActiveSuite ${suite_record}
   set formattedName [::SuiteNode::formatName [${suite_record} cget -suite_path]]
   set drawFrame ${parent}.${formattedName}
   set canvas [xflow_createFlowCanvas $drawFrame]
   xflow_getDateStamp $parent ${suite_record}

   catch {
      xflow_drawflow $canvas
   }
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
   DEBUG "xflow_createFlowCanvas parent:$parent " 5
   set canvasBgImageWidth 3000
   set canvasBgImageHeight 1500
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

         grid ${drawFrame}.pad -row 0 -column 0 -in ${drawFrame}.xframe -sticky es
         grid ${drawFrame}.xscroll -row 0 -column 1 -sticky ew -in ${drawFrame}.xframe
   
         grid columnconfigure ${drawFrame}.xframe 1 -weight 1
         grid rowconfigure ${drawFrame}.xframe 1 -weight 1
   
         # only show the scrollbars if required
         ::autoscroll::autoscroll ${drawFrame}.yscroll
         ::autoscroll::autoscroll ${drawFrame}.xscroll
      }
      canvas $canvas -yscrollcommand [list ${drawFrame}.yscroll set] \
         -xscrollcommand [list ${drawFrame}.xscroll set] -relief raised -bg $canvasColor

      # add bg image
      set imageDir [SharedData_getMiscData IMAGE_DIR]
      image create photo ${canvas}.bg_image -width ${canvasBgImageWidth} -height \
         ${canvasBgImageHeight} -file ${imageDir}/artist-canvas_2.gif

      grid $canvas -row 0 -column 0 -sticky nsew


      # make the canvas expandable to right & bottom
      grid columnconfigure ${drawFrame} 0 -weight 1
      grid rowconfigure ${drawFrame} 0 -weight 1

      grid ${drawFrame} -row 0 -column 0 -sticky nsew
   }
   return $canvas
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
      return ""
   }
}

# function called when user quits the application.
# In overview mode, this is also called by the overview for exp thread cleanup
# if required.
proc xflow_quit {} {
   global XFLOW_STANDALONE MONITOR_THREAD_ID
   global SESSION_TMPDIR

   DEBUG "xflow_quit exiting Xflow thread id:[thread::id]" 5
   set suiteRecord [xflow_getActiveSuite]
   set isOverviewMode [SharedData_getMiscData OVERVIEW_MODE]
   if { [info exists SESSION_TMPDIR] } {
      DEBUG "xflow_quit deleting tmp dir ${SESSION_TMPDIR}"
      catch { file delete -force ${SESSION_TMPDIR} }
      set SESSION_TMPDIR ""
   }
   if { ${isOverviewMode} == "true" } {
      # we are in overview mode
      set childWidgets [winfo children .]
      foreach childW ${childWidgets} {
         destroy ${childW}
      }
      wm withdraw .
   } else {
      LogReader_cancelAfter $suiteRecord
      exit
   }
}

# not used for now
proc xflow_resizeCallback { source_widget } {
   DEBUG "xflow_resizeCallback source_widget:$source_widget" 5
   set suiteRecord [xflow_getActiveSuite]
   set thisTop [winfo toplevel ${source_widget}]
   set canvasList [::SuiteNode::getCanvasList ${suiteRecord}]
   foreach canvasWidget ${canvasList} {
      set canvasWidgetTop [winfo toplevel ${canvasWidget}]
      if { ${thisTop} == ${canvasWidgetTop} } {
         set canvasH [winfo height ${canvasWidget}]
         set canvasW [expr [winfo width ${canvasWidget} ] + 20]
         DEBUG "xflow_resizeCallback found canvas:${canvasWidget} height:${canvasH} width:${canvasW}" 5
         xflow_AddCanvasBg ${canvasWidget}
      }
   }
}

# this function is only used in xflow standalone mode
# it is called by the msg center thread to notify the xflow
# of new messages available. It will maily update the msg center
# icon to a new message state.
proc xflow_newMessageCallback { has_new_msg } {
   DEBUG "xflow_newMessageCallback has_new_msg:$has_new_msg" 5
   set msgCenterWidget .toolbar.button_msgcenter
   set noNewMsgImage .toolbar.msg_center_img
   set hasNewMsgImage .toolbar.msg_center_new_img
   set normalBgColor [option get ${msgCenterWidget} background Button]
   set newMsgBgColor  [SharedData_getColor MSG_CENTER_ABORT_BG]
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
   global env
   if { ! [info exists env(SEQ_EXP_HOME)] } {
      Utils_fatalError . "Xflow Startup Error" "SEQ_EXP_HOME environment variable not set! Exiting..."
   }

   set entryModTruePath ""
   catch { set entryModTruePath [exec true_path $env(SEQ_EXP_HOME)/EntryModule] }
   if { ${entryModTruePath} == "" } {
      Utils_fatalError . "Xflow Startup Error" "Cannot access $env(SEQ_EXP_HOME)/EntryModule. Exiting..."
   }
}

# this function is called to create the widgets of the xflow main window
proc xflow_createWidgets {} {
   global env
   DEBUG "xflow_createWidgets" 5
   wm iconify .
   set topFrame .top   
   # .top is the first widget
   frame $topFrame
   xflow_addFileMenu $topFrame
   xflow_addViewMenu $topFrame
   xflow_addHelpMenu $topFrame
   grid $topFrame -row 0 -column 0 -sticky w -padx 2

   set toolbarFrame .toolbar
   frame ${toolbarFrame}
   xflow_createToolbar ${toolbarFrame}
   grid ${toolbarFrame} -row 1 -column 0 -sticky w -padx 2

   # date bar is the 2nd widget
   set dateFrame .date
   set dateFrameHidden .date_hidden
   frame $dateFrame
   tooltip::tooltip $dateFrame "Double-click to hide"
   labelframe $dateFrameHidden -text "Hidden Date Controls"
   tooltip::tooltip $dateFrameHidden "Double-click to expand"
   xflow_addDatestampWidget $dateFrame
   # monitor date
   xflow_addMonitorDateWidget $dateFrame
   bind $dateFrame <Double-Button-1> [list xflow_viewHideDateButtons . $dateFrame $dateFrameHidden 20 ]
   bind $dateFrameHidden <Double-Button-1> [list xflow_viewHideDateButtons . $dateFrameHidden $dateFrame "" ]
   grid $dateFrame -row 2 -column 0 -sticky nsew -padx 0 -pady 0 -columnspan 2

   # start in hidden mode
   xflow_viewHideDateButtons . $dateFrame $dateFrameHidden 20

   #add list buttons
   set openListButtonsFrame .list_buttons
   labelframe $openListButtonsFrame  -text "Listing buttons"
   tooltip::tooltip $openListButtonsFrame "Double-click to hide"

   # .tabs is the 3nd widget
   set tabFrame .tabs
   frame .tabs
   xflow_createTabs .tabs $env(SEQ_EXP_HOME) "xflow_selectSuiteCallback"
   
   grid .tabs  -row 3 -column 0 -columnspan 2 -sticky nsew -padx 2 -pady 2
   grid columnconfigure . 0 -weight 1
   grid columnconfigure . 1 -weight 1
   grid rowconfigure . 3 -weight 2

   ttk::sizegrip .sizeGrip
   grid .sizeGrip -row 3 -column 1 -sticky se
   
   wm geometry . =1200x800
}

# this function is called to create an exp flow.
# 1) in xflow standalone mode, this function is called at startup and when the user views the exp in
# history mode.
# 2) in overview mode, this function is called everytime the user wants to view the exp flow with the latest
# datestamp or in history mode. Note that in overview mode, a thread is created for each exp and another tread is created
# for each exp in history mode.
proc xflow_displayFlow { calling_thread_id } {
   global env XFLOW_STANDALONE 
   global MONITORING_LATEST MONITOR_DATESTAMP

   DEBUG "xflow_displayFlow thread id:[thread::id]" 5

   set topFrame .top

   xflow_createTmpDir
   xflow_validateSuite

   if { ! [winfo exists ${topFrame}] } {
      xflow_createWidgets
   }

   # the SuiteNode record is only created after xflow_createWidgets
   set activeSuite $env(SEQ_EXP_HOME)
   set activeSuiteRecord [SuiteNode::getSuiteRecordFromPath $activeSuite]
   xflow_setActiveSuite $activeSuiteRecord

   # initial monitor dates
   xflow_populateMonitorDate

   if { ${MONITORING_LATEST} == "1" } {
      # the thread id associated to an exp path is mainly used by
      # the xflow_overview... The overview needs it to send signals
      # to the thread that is used to monitor the active exp log.
      # NOT set if in exp history mode
      SharedData_setSuiteData $env(SEQ_EXP_HOME) THREAD_ID [thread::id]
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
        LogReader_readFile $activeSuiteRecord $calling_thread_id
        xflow_stopStartupMode
      }
      xflow_selectSuiteCallback
   }

   xflow_toFront .
   # Console_create
}

proc xflow_toFront { toplevel_w } {
   switch [wm state ${toplevel_w}] {
      "iconic" {
         wm deiconify ${toplevel_w}
      }
      "withdrawn" {
         wm withdraw ${toplevel_w} ; wm deiconify ${toplevel_w}
      }
   }
}

proc xflow_getMonitoringDatestamp {} {
   global MONITOR_DATESTAMP
   return $MONITOR_DATESTAMP
}

proc xflow_getTabsParentW {} {
   return .tabs
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
   global argv XFLOW_STANDALONE AUTO_MSG_DISPLAY
   if { [info exists argv] } {
      set options {
         {main ""}
         {noautomsg ""}
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
}

proc xflow_init {} {
   global env DEBUG_TRACE DEBUG_LEVEL
   global NODE_DISPLAY_PREF AUTO_MSG_DISPLAY
   global SHADOW_STATUS MONITORING_LATEST
   global MSG_CENTER_THREAD_ID MONITOR_THREAD_ID
   global REFRESH_MODE SESSION_TMPDIR
   set REFRESH_MODE false
   set MONITOR_THREAD_ID ""
   set SHADOW_STATUS 0
   set MONITORING_LATEST 1

   SharedData_setMiscData SEQ_BIN [Sequencer_getPath]
   SharedData_setMiscData SEQ_UTILS_BIN [Sequencer_getUtilsPath]
   SharedData_setMiscData IMAGE_DIR $env(SEQ_XFLOW_BIN)/../etc/images

   set DEBUG_TRACE [SharedData_getMiscData DEBUG_TRACE]
   set DEBUG_LEVEL [SharedData_getMiscData DEBUG_LEVEL]
   set NODE_DISPLAY_PREF  [SharedData_getMiscData NODE_DISPLAY_PREF]
   set MSG_CENTER_THREAD_ID [MsgCenter_getThread]
   SharedData_setMiscData XFLOW_THREAD_ID [thread::id]
   if { ! [info exists AUTO_MSG_DISPLAY] } {
      set AUTO_MSG_DISPLAY [SharedData_getMiscData AUTO_MSG_DISPLAY]
   } else {
      DEBUG "xflow_init SharedData_setMiscData AUTO_MSG_DISPLAY ${AUTO_MSG_DISPLAY}" 5
      SharedData_setMiscData AUTO_MSG_DISPLAY ${AUTO_MSG_DISPLAY}
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
      DEBUG "xflow_createTmpDir deleting ${myTmpDir}" 5
      file delete -force ${myTmpDir}
   }
   DEBUG "xflow_createTmpDir creating ${myTmpDir}" 5
   file mkdir ${myTmpDir}
   set SESSION_TMPDIR ${myTmpDir}
}

global XFLOW_STANDALONE

xflow_parseCmdOptions
# this section is only executed when xflow is run as a standalone application
if { ${XFLOW_STANDALONE} == 1 } {
   SharedData_init
   xflow_init
   xflow_displayFlow [thread::id]
   SharedData_setMiscData STARTUP_DONE true
   SharedData_setMiscData [thread::id]_STARTUP_DONE true
   thread::send -async ${MSG_CENTER_THREAD_ID} "MsgCenterThread_startupDone"
}
