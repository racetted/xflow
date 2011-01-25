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

#source testdata.tcl
::DrawUtils::init

proc setTkOptions {} {
   option add *activeBackground [SharedData_getColor ACTIVE_BG]
   option add *selectBackground [SharedData_getColor SELECT_BG]

   # ttk::style configure Xflow.Menu -background cornsilk4
}

proc addFileMenu { parent } {
   if { $parent == "." } {
      set parent ""
   }
   set menuButtonW ${parent}.menub
   set menuW $menuButtonW.menu

   menubutton $menuButtonW -text File -underline 0 -menu $menuW \
      -relief [SharedData_getMiscData MENU_RELIEF]
   menu $menuW -tearoff 0

   $menuW add command -label "Quit" -underline 0 -command "quitXflow" 

   pack $menuButtonW -side left -pady 2 -padx 2
}

proc addViewMenu { parent } {
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
      -onvalue 1 -offvalue 0 -command [ list logsMonitorChanged $parent ]

   $menuW add checkbutton -label "Show Shadow Status" -variable SHADOW_STATUS \
      -onvalue 1 -offvalue 0 -command selectSuiteCallback

   set labelMenu $menuW.labelmenu

   $menuW add cascade -label "Node Display" -underline 5 -menu $labelMenu
   menu $labelMenu -tearoff 0
   foreach item "normal catchup cpu machine_queue memory mpi wallclock" {
      set value ${item}
      $labelMenu add radiobutton -label ${item} -variable NODE_DISPLAY_PREF -value ${value} \
         -command [list redrawAllFlow]
   }
   proc out {} {
   $labelMenu add radiobutton -label "normal" -variable NODE_DISPLAY_PREF -value "normal" \
      -command selectSuiteCallback
   $labelMenu add radiobutton -label "catchup" -variable NODE_DISPLAY_PREF -value 2 \
      -command selectSuiteCallback
   $labelMenu add radiobutton -label "cpu" -variable NODE_DISPLAY_PREF -value 3 \
      -command selectSuiteCallback
   $labelMenu add radiobutton -label "machine_queue" -variable NODE_DISPLAY_PREF -value 4 \
      -command selectSuiteCallback
   $labelMenu add radiobutton -label "memory" -variable NODE_DISPLAY_PREF -value 5 \
      -command selectSuiteCallback
   $labelMenu add radiobutton -label "mpi" -variable NODE_DISPLAY_PREF -value 6 \
      -command selectSuiteCallback
   $labelMenu add radiobutton -label "wallclock" -variable NODE_DISPLAY_PREF -value 7 \
      -command selectSuiteCallback
   }

   pack $menuButtonW -side left -pady 2 -padx 2
}

proc xflow_setAutoMsgDisplay {} {
   global AUTO_MSG_DISPLAY
   DEBUG "xflow_setAutoMsgDisplay AUTO_MSG_DISPLAY new value: ${AUTO_MSG_DISPLAY}" 5
   SharedData_setMiscData AUTO_MSG_DISPLAY ${AUTO_MSG_DISPLAY}
}

# generic callback for whoever wants to call the selectSuiteTab
proc selectSuiteCallback { } {
   selectSuiteTab [getTabsParentW] [getActiveSuite]
}

proc addHelpMenu { parent } {
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

proc xflow_AddCanvasBg { canvas } {
   # image already created at canvas creaton time
   set imageBg ${canvas}.bg_image
   set imageTagName ${canvas}_bg_image

   ${canvas} delete ${imageTagName}
   ${canvas} create image 0 0 -anchor nw -image ${imageBg} -tags ${imageTagName}
   ${canvas} lower ${imageTagName}
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

   button ${nodeKillW} -image ${parent}.node_kill_img -command [list nodeKillDisplay ${parent} ]
   tooltip::tooltip ${nodeKillW}  "Open job killing dialog"

   button ${nodeListW} -image ${parent}.node_list_img  -state disabled
   tooltip::tooltip ${nodeListW} "Open succesfull node listing dialog -- future feature."

   button ${nodeAbortListW} -image ${parent}.node_abort_list_img -state disabled
   tooltip::tooltip ${nodeAbortListW} "Open abort node listing dialog -- future feature."

   button ${closeW} -image ${parent}.close -command [list quitXflow]
   ::tooltip::tooltip ${closeW} "Close application."

   button ${colorLegendW} -image ${parent}.color_legend_img -command [list showColorLegend ${colorLegendW}]
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

proc showColorLegend { caller_w } {
   set topW .color_legend
   if { [winfo exists ${topW}] } {
      wm withdraw ${topW} ; wm deiconify ${topW}
   } else {
      toplevel ${topW}
      positionWindow ${topW} ${caller_w}
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

proc addDatestampWidget { parent } {
   if { $parent == "." } {
      set parent ""
   }

   set dtFrame [ labelframe $parent.dt -text "Exp Datestamp (yyyymmddhh)" ]
   bind $dtFrame <Double-Button-1> [list viewHideDateButtons . .date .date_hidden "" ]
   tooltip::tooltip $dtFrame "Double-click to hide"

   set dateEntry [entry $dtFrame.entry -width 11 ]
   tooltip::tooltip $dateEntry "Enter a value then set the experiment datestamp."

   set buttonFrame [frame ${dtFrame}.button_frame]
   set imageDir [SharedData_getMiscData IMAGE_DIR]
   image create photo ${buttonFrame}.set_image -file ${imageDir}/ok.ppm
   image create photo ${buttonFrame}.refresh_image -file ${imageDir}/refresh.ppm

   set setButton [button ${buttonFrame}.set_button -image ${buttonFrame}.set_image \
      -command [list setDateStamp $parent]]
   tooltip::tooltip ${setButton} "Sets new datestamp value."

   set refreshButton [button ${buttonFrame}.refresh_button -image ${buttonFrame}.refresh_image \
      -command [list getDateStamp $parent]]
   tooltip::tooltip $refreshButton "Reloads the current experiment datestamp value."

   pack $setButton $refreshButton -side left -pady 2 -padx 5
   pack $dateEntry -side left -pady 2 -padx 2
   pack $buttonFrame -pady 2 -side left
   pack $dtFrame -side left -pady 2 -padx 2 -fill x -expand 1

}

proc logsMonitorChanged { parent_w } {
   global MONITORING_LATEST
   DEBUG "logsMonitorChanged called"
   if { $parent_w == "." } {
      set parent_w ""
   }
   set monitorFrame .date.monitor_frame
   set monitorEntryCombo ${monitorFrame}.entry_combo
   set setButton ${monitorFrame}.button_frame.set_button
   if { $MONITORING_LATEST == 0 } {
      set status normal
   } else {
      set status disabled
   }
   set suiteRecord [getActiveSuite]
   set topNode "/[$suiteRecord cget -suite_name]"
   $suiteRecord configure -active_log ""
   $setButton configure -state $status
   ${monitorEntryCombo} configure -state $status
   ${monitorEntryCombo} set latest

   set top [winfo toplevel $parent_w]
   busyCursor $top
   catch {
      if { $MONITORING_LATEST == 1 } {
         $suiteRecord configure -read_offset 0
         ::FlowNodes::resetNodeStatus $topNode
         selectSuiteTab [getTabsParentW] $suiteRecord
         set isOverviewMode [SharedData_getMiscData OVERVIEW_MODE]
         if { ${isOverviewMode} == "true" } {
            set overviewThreadId [SharedData_getMiscData OVERVIEW_THREAD_ID]
            LogReader_readFile $suiteRecord ${overviewThreadId}
         } else {
            LogReader_readFile $suiteRecord [thread::id]
         }
      }
   }

   normalCursor $top
}

proc addMonitorDateWidget { parent } {
   if { $parent == "." } {
      set parent ""
   }

   set monitorFrame [ labelframe $parent.monitor_frame -text "Monitoring Datestamp (yyyymmddhh)" ]
   set monitorEntryCombo ${monitorFrame}.entry_combo
   bind $monitorFrame <Double-Button-1> [list viewHideDateButtons . .date .date_hidden "" ]
   tooltip::tooltip $monitorFrame "Double-click to hide"

   ttk::combobox ${monitorFrame}.entry_combo

   set buttonFrame [frame ${monitorFrame}.button_frame]
   set imageDir [SharedData_getMiscData IMAGE_DIR]
   image create photo ${buttonFrame}.set_image -file ${imageDir}/ok.ppm
   image create photo ${buttonFrame}.refresh_image -file ${imageDir}/refresh.ppm

   set setButton [button ${buttonFrame}.set_button -image ${buttonFrame}.set_image \
      -command [list setMonitorDate $parent]]
   tooltip::tooltip $setButton "Sets the datestamp value being displayed in the flow."

   set refreshButton [button ${buttonFrame}.refresh_button -image ${buttonFrame}.refresh_image \
      -command [list populateMonitorDate $parent]]
   tooltip::tooltip $refreshButton "Refresh the datestamp list."

   pack $setButton $refreshButton -side left -pady 2 -padx 5
   pack ${monitorEntryCombo} -side left -pady 2 -padx 2 -fill x
   pack $buttonFrame -pady 2 -side left
   pack $monitorFrame -side left -pady 2 -padx 2 -fill x -expand 1

   tooltip::tooltip ${monitorEntryCombo} "Select value of the date being displayed in the flow."

}

# this function is called when the user click on the arrows to
# close or open the control bar in a run window

proc viewHideListButtons { parent currentFrame replacementFrame height } {
   grid forget $currentFrame
   if { $height != "" } {
       $replacementFrame configure -height $height
       grid $replacementFrame -row 3 -column 0 -columnspan 2 -sticky nsew -padx 2 -pady 2
   } else {
       grid $replacementFrame -row 3 -column 0 -columnspan 2 -sticky nsew -padx 2 -pady 2
   }
}

proc viewHideDateButtons { parent currentFrame replacementFrame height } {
   grid forget $currentFrame
   if { $height != "" } {
       $replacementFrame configure -height $height
       grid $replacementFrame -row 2 -column 0 -columnspan 2 -sticky nsew -padx 2 -pady 2
   } else {
      grid $replacementFrame -row 2 -column 0 -columnspan 2 -sticky nsew -padx 2 -pady 2
   }
}


proc addListButtonsWidget { monitorFrame } {

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
      -command [list nodeKillDisplay $monitorFrame ] ]
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

proc nodeKillDisplay { parent_w } {

   global env
   set shadowColor [SharedData_getColor SHADOW_COLOR]
   set bgColor [SharedData_getColor CANVAS_COLOR]
   set id [clock seconds]
   set tmpdir $env(TMPDIR)
   set tmpfile "${tmpdir}/test$id"
   set suiteRecord [getActiveSuite]
   set suitePath [$suiteRecord cget -suite_path]
   set killPath [getGlobalValue SEQ_UTILS_BIN]/nodekill 
   set cmd "export SEQ_EXP_HOME=$suitePath; $killPath -listall > $tmpfile 2>&1"
   DEBUG "nodeKillDisplay ksh -c $cmd" 5
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
      -command [list killNode $soloWindow.list ]]
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

proc killNode { list_widget } {

   set indexlist [ $list_widget curselection ]
   DEBUG "killNode list_widget:$list_widget indexlist:$indexlist" 5
   set listOfNodes ""
   for {set iterator 0} {$iterator < [llength $indexlist]} {incr iterator} {
      set listOfNodes [ linsert $listOfNodes end [ $list_widget get [ lindex $indexlist $iterator ]]]
   }
   set suiteRecord [getActiveSuite]
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
         DEBUG "killNode command: $seqExec  -n $node -job_id $nodeID" 5
         Sequencer_runCommandWithWindow $suitePath $seqExec "Node Kill [file tail $node]" -n $node -job_id $nodeID
      } else {
         raiseError [winfo toplevel ${list_widget}] "Kill Node" "Application Error: Unable to retrieve Task Id."
      }
   }
}

proc getMonitorDate { parent_w { suite_record "" } } {
   global MONITOR_DATESTAMP MONITORING_LATEST
   if { ${suite_record} == "" } {
      set suite_record [getActiveSuite]
   }
   set suitePath [${suite_record} cget -suite_path]
   set dateList [LogReader_getAvailableDates $suitePath]

   set monitorFrame .date.monitor_frame
   set monitorEntryCombo ${monitorFrame}.entry_combo
   set setButton ${monitorFrame}.button_frame.set_button
   
   # flush the current list
   ${monitorEntryCombo} configure -values ""
   set values ""
   foreach date ${dateList} {
      set values "$values [Utils_getVisibleDatestampValue ${date}]"
   }
   ${monitorEntryCombo} configure -values $values
   DEBUG "getMonitorDate MONITOR_DATESTAMP:$MONITOR_DATESTAMP -active_log? [${suite_record} cget -active_log]" 5
   if { ${MONITORING_LATEST} == 0 && ${MONITOR_DATESTAMP} != "" } {
      ${suite_record} configure -active_log ${MONITOR_DATESTAMP} -read_offset 0
      ${monitorEntryCombo} set ${MONITOR_DATESTAMP}
   } else {
      if { [${suite_record} cget -active_log] == "" } {
         ${monitorEntryCombo} configure -state disabled
         ${setButton} configure -state disabled
         ${monitorEntryCombo} set latest
      } else {
         ${monitorEntryCombo} set [Utils_getVisibleDatestampValue [${suite_record} cget -active_log]]
         set MONITOR_DATESTAMP [${suite_record} cget -active_log]
      }
   }
   DEBUG "getMonitorDate 2 MONITOR_DATESTAMP:$MONITOR_DATESTAMP" 5
}

proc populateMonitorDate { parent_w {suite_record ""} } {
   if { ${suite_record} == "" } {
      set suite_record [getActiveSuite]
   }
   set suitePath [${suite_record} cget -suite_path]
   set dateList [LogReader_getAvailableDates $suitePath]
   set monitorFrame .date.monitor_frame
   set monitorEntryCombo ${monitorFrame}.entry_combo
   
   # flush the current list
   ${monitorEntryCombo} configure -values ""
   set values ""
   foreach date $dateList {
      set values "$values [Utils_getVisibleDatestampValue ${date}]"
   }
   ${monitorEntryCombo} configure -values $values
}

proc setMonitorDate { parent_w } {
   global MONITOR_DATESTAMP
   DEBUG "setMonitorDate called" 5
   set top [winfo toplevel $parent_w]
   busyCursor $top
   catch {
      set suiteRecord [getActiveSuite]
      set suitePath [$suiteRecord cget -suite_path]
      set suiteName [$suiteRecord cget -suite_name]
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
         raiseError [winfo toplevel $parent_w] "Datestamp" "Selected date does not exists!\nPlease choose another date."
      } else {
         set MONITOR_DATESTAMP [Utils_getRealDatestampValue ${dateValue}]
         DEBUG "setMonitorDate ${MONITOR_DATESTAMP}" 5
         set isOverviewMode [SharedData_getMiscData OVERVIEW_MODE]
         if { ${isOverviewMode} == "true" } {
            set monitorThreadId [xflow_getMonitoredThread]
            thread::send ${monitorThreadId} "xflowThread_monitorNewDate ${MONITOR_DATESTAMP}"
         } else {
            $suiteRecord configure -read_offset 0 -active_log ${MONITOR_DATESTAMP}
            set topNode "/${suiteName}"
            ::FlowNodes::resetNodeStatus $topNode
            selectSuiteTab [getTabsParentW] $suiteRecord
            SharedData_setMiscData STARTUP_DONE false
            LogReader_readFile $suiteRecord [thread::id]
            SharedData_setMiscData STARTUP_DONE true
            redrawAllFlow
         }

      }
   }

   normalCursor $top
}

proc setMonitorDateWidget {} {
   set dateEntryCombo .date.monitor_frame.entry_combo
   set dateValue [getMonitoringDatestamp]
   $dateEntryCombo set [Utils_getVisibleDatestampValue ${dateValue}]
}

proc xflow_getMonitoredThread {} {
   global MONITOR_THREAD_ID
   if { ${MONITOR_THREAD_ID} == "" } {
      DEBUG "xflow_getMonitoredThread Creating new thread..." 5
      set MONITOR_THREAD_ID [thread::create {
         global env
         set lib_dir $env(SEQ_XFLOW_BIN)/../lib
         set auto_path [linsert $auto_path 0 $lib_dir ]
         package require SuiteNode
         package require Tk

         proc xflowThread_monitorNewDate { datestamp } {
            global XFLOW_STANDALONE MONITORING_LATEST MONITOR_DATESTAMP MONITOR_THREAD_ID
            xflow_init
            set XFLOW_STANDALONE 1
            set MONITORING_LATEST 0
            set MONITOR_DATESTAMP ${datestamp}
            set MONITOR_THREAD_ID [thread::id]
            DEBUG "xflowThread_monitorNewDate thread_id:[thread::id] datestamp:${datestamp} overview_mode? [SharedData_getMiscData OVERVIEW_MODE]" 5
            launchXflow [thread::id]
            setMonitorDateWidget
            viewHideDateButtons . .date_hidden .date ""
         }

         # enter event loop
         thread::wait
      }]
   }

   DEBUG "xflow_getMonitoredThread returning id: ${MONITOR_THREAD_ID}" 5
   return ${MONITOR_THREAD_ID}
}

proc getDateStamp { parent_w {suite_record ""} } {
   global MONITOR_DATESTAMP MONITORING_LATEST
   if { ${suite_record} == "" } {
      set suite_record [getActiveSuite]
   }
   set dateStamp [retrieveDateStamp $parent_w ${suite_record}]
   set shortDatestamp [Utils_getVisibleDatestampValue ${dateStamp}]
   if { [winfo toplevel $parent_w]  == "." } {
      set dateEntry .date.dt.entry
   }
   $dateEntry delete 0 end
   $dateEntry insert 0 $shortDatestamp

   if { ${MONITORING_LATEST} == 1 } {
      set MONITOR_DATESTAMP $dateStamp
   }

   DEBUG "getDateStamp dateStamp:$shortDatestamp" 5
}

proc retrieveDateStamp { parent_w suite_record } {

   set dateExec "[getGlobalValue SEQ_BIN]/tictac"
   set suitePath [${suite_record} cget -suite_path]
   set cmd "export SEQ_EXP_HOME=$suitePath;$dateExec -f '%Y%M%D%H%Min%S'"
   set dateStamp ""
   if [ catch { set dateStamp [exec ksh -c $cmd] } message ] {
      raiseError [winfo toplevel $parent_w] "Datestamp" $message
   }
   return $dateStamp
}

proc setDateStamp { parent_w } {
   global MONITOR_DATESTAMP
   set top [winfo toplevel $parent_w]
   set dateExec "[getGlobalValue SEQ_BIN]/tictac"
   set suiteRecord [getActiveSuite]
   set suiteName [$suiteRecord cget -suite_name]
   set suitePath [$suiteRecord cget -suite_path]
   if { $top  == "." } {
      set dateEntry .date.dt.entry
   }
   busyCursor $top

   catch {
      set dateStamp [$dateEntry get]
      set cmd "export SEQ_EXP_HOME=$suitePath;$dateExec -s $dateStamp"
      DEBUG "setDateStamp $cmd" 5
      if [ catch { exec ksh -c $cmd } message ] {
         raiseError $top "Datestamp" $message
      }
      set MONITOR_DATESTAMP $dateStamp
      $suiteRecord configure -read_offset 0
      set topNode "/${suiteName}"
      ::FlowNodes::resetNodeStatus $topNode
      selectSuiteTab [getTabsParentW] $suiteRecord

      set isOverviewMode [SharedData_getMiscData OVERVIEW_MODE]
      if { ${isOverviewMode} == "true" } {
         set overviewThreadId [SharedData_getMiscData OVERVIEW_THREAD_ID]
         LogReader_readFile $suiteRecord ${overviewThreadId}
      } else {
         SharedData_setMiscData STARTUP_DONE false
         LogReader_readFile $suiteRecord [thread::id]
         SharedData_setMiscData STARTUP_DONE true
      }
   }

   normalCursor $top
}

proc getMonitoringDatestamp {} {
   global MONITOR_DATESTAMP
   return $MONITOR_DATESTAMP
}

# parent is where the user has clicked
proc positionWindow { top {parent ""} } {
   if { $parent != "" } {
      set POSITION_X [winfo pointerx $parent]
      set POSITION_Y [winfo pointery $parent]
   } else {
      set POSITION_X [expr [winfo screenwidth .]/4]
      set POSITION_Y [expr [winfo screenheight .]/8]
   }
   wm geometry $top +${POSITION_X}+${POSITION_Y}
}

proc DEBUG { output {level 2} } {
   set debugOn [getGlobalValue "DEBUG_TRACE"]
   set debugLevel [getGlobalValue "DEBUG_LEVEL"]
   if { $debugOn && $debugLevel >= $level} {
      puts "$output"
      flush stdout
   }
}

proc getTabsParentW {} {
   return .tabs
}

proc getNodeDisplayPrefText { node } {
   set text ""
   set displayPref [getNodeDisplayPref]
   set attrName ${displayPref}
   set attrValue ""

   if { ${displayPref} == "machine_queue" } {
      set attrName "machine"
   }
   if { ${displayPref} != "normal" } {
      if { [$node cget -flow.type] == "task" || [$node cget -flow.type] == "npass_task"  } {
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

proc getNodeDisplayPref {} {
   global NODE_DISPLAY_PREF
   if { ! [info exists NODE_DISPLAY_PREF] } {
      set NODE_DISPLAY_PREF normal
   }
   return $NODE_DISPLAY_PREF
}

proc getShawdowStatus {} {
   global SHADOW_STATUS
   if { ! [info exists SHADOW_STATUS] } {
      set SHADOW_STATUS 0
   }
   return $SHADOW_STATUS
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
            # the current node ian npt... the last part must be for the npt index
            set leafEx [::FlowNodes::getExtAtIndex ${extensionPart} ${indexCount}]
            ${flowNode} configure -current ${leafEx}
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

proc drawNode { canvas node position callback {first_node false} } {
   global REFRESH_MODE
   DEBUG "drawNode drawing sub node:$node position:$position" 5
   set boxW [SharedData_getMiscData CANVAS_BOX_WIDTH]
   set boxH [SharedData_getMiscData CANVAS_BOX_HEIGHT]
   set pady [SharedData_getMiscData CANVAS_PAD_Y]
   set padTx [SharedData_getMiscData CANVAS_PAD_TXT_X]
   set padTy [SharedData_getMiscData CANVAS_PAD_TXT_Y]
   set shadowColor [SharedData_getColor SHADOW_COLOR]
   set drawshadow on

   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]
   ::FlowNodes::initNode $node $canvas
   set parentNode [${node} cget -flow.parent]
   if { $parentNode == "" || ${first_node} == "true" } {
      set linex2 [SharedData_getMiscData CANVAS_X_START]
      set liney2 [SharedData_getMiscData CANVAS_Y_START]
      DEBUG "drawNode linex2:$linex2 liney2:$liney2"
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
      DEBUG "drawNode displayInfo:$displayInfo"
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
         set liney1 [expr $py1 + ($py2 - $py1) / 2 ]
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
         set liney2 [expr $nextY + ($boxH/4) + $pady]
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
   set dispPref [getNodeDisplayPrefText $node]
   if { $dispPref != "" } {
      set text "${text}\n${dispPref}"
   }
   
   switch [$node cget -flow.type] {
      "family" {
         ::DrawUtils::drawBoxSansOutline $canvas $tx1 $ty1 $text $text $normalTxtFill $outline $normalFill $callback $node $drawshadow $shadowColor
         ::FlowNodes::addToFamilyList $node
      }
      "module" {
	 ::DrawUtils::drawBoxSansOutline $canvas $tx1 $ty1 $text $text $normalTxtFill $outline $normalFill $callback $node $drawshadow $shadowColor
      }
      "task" {
         ::DrawUtils::drawBox $canvas $tx1 $ty1 $text $text $normalTxtFill $outline $normalFill $callback $node $drawshadow $shadowColor
      }

      "npass_task" {
         ::DrawUtils::drawBox $canvas $tx1 $ty1 $text $text $normalTxtFill $outline $normalFill $callback $node $drawshadow $shadowColor
      }
      "loop" {
         set text "${text}\n[::FlowNodes::getLoopInfo $node]"
         ::DrawUtils::drawOval $canvas $tx1 $ty1 $text $text $normalTxtFill $outline $normalFill $callback $node $drawshadow $shadowColor
      }
      "case" {
         ::DrawUtils::drawLosange $canvas $tx1 $ty1 $text $normalTxtFill $outline $normalFill $callback $node $drawshadow $shadowColor
      }
      "outlet" {
         ::DrawUtils::drawOval $canvas $tx1 $ty1 $text $text $normalTxtFill $outline $normalFill $callback $node $drawshadow $shadowColor
      }
      default {
         error "Invalid node type:[$node cget -flow.type] in proc drawNode()"
      }
   }
   ::DrawUtils::drawNodeStatus $node [getShawdowStatus]
   xflow_bindMouseWheel $canvas
   $canvas bind $node <Double-Button-1> [ list $callback $canvas $node %X %Y]
   $canvas bind $node <Button-2> [ list historyCallback $node $canvas "" 48] 
   $canvas bind $node <Button-3> [ list nodeMenu $canvas $node %X %Y]

   if { $isCollapsed == 0 } {
      # get the childs to display
      if { !(($children == "none") ||  ($children == ""))} {
         set nodePosition 0
         foreach child $children {
            #DEBUG "drawNode drawing subjob:$subjob" 5
            set childNode $node/$child
            drawNode $canvas $childNode $nodePosition $callback
            incr nodePosition
         }
      }
   }
   
   DEBUG "drawNode drawing sub node:$node done" 5
}

proc xflow_bindMouseWheel { widget_ } {
   bind ${widget_} <4> {
      %W yview scroll -2 units
   }
   bind ${widget_} <5> {
      %W yview scroll 2 units
   }
}

# callback when user click on a box with button 3
proc nodeMenu { canvas node x y } {
   global ignoreDep
   DEBUG "nodeMenu() node:$node" 5

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

   #menu $popMenu -bg "#d1d1d1"
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
      ${popMenu} add command -label "Expand All" -command [list expandAllCallback $node $canvas $popMenu]
   }
   if { [$node cget -flow.type] == "loop" } {
      addLoopNodeMenu ${popMenu} ${canvas} ${node}
   } elseif { [$node cget -flow.type] == "npass_task" } {
      addNptNodeMenu ${popMenu} ${canvas} ${node}
   } else {

      ${infoMenu} add command -label "Node History" -command [list historyCallback $node $canvas $popMenu 0 ]
      ${infoMenu} add command -label "Node Info" -command [list nodeInfoCallback $node $canvas $popMenu]
      ${infoMenu} add command -label "Node Batch" -command [list batchCallback $node $canvas $popMenu ]

      ${listingMenu} add command -label "Node Listing" -command [list listingCallback $node $canvas $popMenu]
      ${listingMenu} add command -label "All Node Listing" -command [list allListingCallback $node $canvas $popMenu success]
      ${listingMenu} add command -label "Node Abort Listing" \
         -command [list abortListingCallback $node $canvas $popMenu] \
         -foreground [::DrawUtils::getBgStatusColor abort]

      ${listingMenu} add command -label "All Node Abort Listing" \
         -command [list allListingCallback $node $canvas $popMenu abort] \
         -foreground [::DrawUtils::getBgStatusColor abort]

      ${miscMenu} add command -label "New Window" -command [list newWindowCallback $node $canvas $popMenu]
      #$popMenu add checkbutton -label "Ignore Dependency" -onvalue " -i" -offvalue "" -variable ignoreDep
      if { [xflow_isIgnoreDepTrue] == "true" } {
         ${submitMenu} add checkbutton -label "Ignore Dependency" -onvalue " -i" -offvalue "" -variable ignoreDep -state disabled
      }
      if { [$node cget -flow.type] != "task" } {
         ${submitMenu} add command -label "Submit" -command [list submitCallback $node $canvas $popMenu continue ]
         ${submitMenu} add cascade -label "NO Dependency" -underline 4 -menu [menu ${submitNoDependMenu}]
         ${submitNoDependMenu} add command -label "Submit" \
            -command [list submitCallback $node $canvas $popMenu continue dep_off]
         ${infoMenu} add command -label "Node Config" -command [list configCallback $node $canvas $popMenu ]
         ${miscMenu} add command -label "Initbranch" -command [list initbranchCallback $node $canvas $popMenu]
      } else {
         ${submitMenu} add command -label "Submit & Continue" -underline 9 -command [list submitCallback $node $canvas $popMenu continue ]
         ${submitMenu} add command -label "Submit & Stop" -underline 9 -command [list submitCallback $node $canvas $popMenu stop ]

         # ${submitMenu} add cascade -label "Submit & Continue" -underline 11 -menu [menu ${submitDependMenu}]
         ${submitMenu} add cascade -label "NO Dependency" -underline 4 -menu [menu ${submitNoDependMenu}]
         #${submitDependMenu} add command -label "With Dependency" \
         #   -command [list submitCallback $node $canvas $popMenu continue dep_on ]
         #${submitDependMenu} add command -label "W/O Dependency" \
         #   -command [list submitCallback $node $canvas $popMenu continue dep_off ]
         #${submitMenu} add cascade -label "Submit & Stop" -underline 11 -menu [menu ${submitNoDependMenu}]
         ${submitNoDependMenu} add command -label "Submit & Continue" -underline 9 \
            -command [list submitCallback $node $canvas $popMenu continue dep_off ]
         ${submitNoDependMenu} add command -label "Submit & Stop" -underline 9 \
            -command [list submitCallback $node $canvas $popMenu stop dep_off ]

         ${infoMenu} add command -label "Node Source" -command [list sourceCallback $node $canvas $popMenu ]
         ${infoMenu} add command -label "Node Config" -command [list configCallback $node $canvas $popMenu ]
         ${miscMenu} add command -label "Initnode" -command [list initnodeCallback $node $canvas $popMenu]
      }
      ${miscMenu} add command -label "End" -command [list endCallback $node $canvas $popMenu]
      ${infoMenu} add command -label "Node Resource" -command [list resourceCallback $node $canvas $popMenu ]
   }

   #$popMenu add command -label "Bound Family" -command [list boundFamilyCallback $node $canvas $popMenu]
   ${miscMenu} add command -label "Abort" -command [list abortCallback $node $canvas $popMenu]
   ${miscMenu} add command -label "Kill Node" -command [list killNodeFromDropdown $node $canvas $popMenu]
   ${miscMenu} add command -label "Clean Log" -command [list cleanLogCallback $canvas $popMenu]
   $popMenu add separator
   $popMenu add command -label "Close"
   
   tk_popup $popMenu $x $y
}

proc nodeMenu_backup { canvas node x y } {
   global ignoreDep
   DEBUG "nodeMenu() node:$node" 5
   set popMenu .popupMenu
   if { [winfo exists $popMenu] } {
      destroy $popMenu
   }
   #menu $popMenu -bg [SharedData_getColor CANVAS_COLOR]
   menu $popMenu -bg "#d1d1d1"
   set children [$node cget -flow.children]
   set isCollapsed [::FlowNodes::isCollapsed $node $canvas]
   if { $children != "" && $isCollapsed } {
      $popMenu add command -label "Expand All" -command [list expandAllCallback $node $canvas $popMenu]
   }
   if { [$node cget -flow.type] == "loop" } {
      addLoopNodeMenu ${popMenu} ${canvas} ${node}
   } elseif { [$node cget -flow.type] == "npass_task" } {
      addNptNodeMenu ${popMenu} ${canvas} ${node}
   } else {
      $popMenu add command -label "Node History" -command [list historyCallback $node $canvas $popMenu 0 ]
      $popMenu add command -label "Node Info" -command [list nodeInfoCallback $node $canvas $popMenu]
      $popMenu add command -label "Node Listing" -command [list listingCallback $node $canvas $popMenu]
      $popMenu add command -label "All Node Listing" -command [list allListingCallback $node $canvas $popMenu success]
      $popMenu add command -label "Node Abort Listing" \
         -command [list abortListingCallback $node $canvas $popMenu] \
         -foreground [::DrawUtils::getBgStatusColor abort]
      $popMenu add command -label "All Node Abort Listing" \
         -command [list allListingCallback $node $canvas $popMenu abort] \
         -foreground [::DrawUtils::getBgStatusColor abort]
      $popMenu add command -label "Node Batch" -command [list batchCallback $node $canvas $popMenu ]
      $popMenu add command -label "New Window" -command [list newWindowCallback $node $canvas $popMenu]
      $popMenu add separator
      #$popMenu add checkbutton -label "Ignore Dependency" -onvalue " -i" -offvalue "" -variable ignoreDep
      if { [xflow_isIgnoreDepTrue] == "true" } {
         $popMenu add checkbutton -label "Ignore Dependency" -onvalue " -i" -offvalue "" -variable ignoreDep -state disabled
      }
      if { [$node cget -flow.type] != "task" } {
         $popMenu add command -label "Submit" -command [list submitCallback $node $canvas $popMenu continue ]
         $popMenu add command -label "Node Config" -command [list configCallback $node $canvas $popMenu ]
         $popMenu add separator
         $popMenu add command -label "Initbranch" -command [list initbranchCallback $node $canvas $popMenu]
      } else {
         $popMenu add command -label "Submit & Continue" -command [list submitCallback $node $canvas $popMenu continue ]
         $popMenu add command -label "Submit & Stop" -command [list submitCallback $node $canvas $popMenu stop ]
         $popMenu add command -label "Node Source" -command [list sourceCallback $node $canvas $popMenu ]
         $popMenu add command -label "Node Config" -command [list configCallback $node $canvas $popMenu ]
         $popMenu add separator
         $popMenu add command -label "Initnode" -command [list initnodeCallback $node $canvas $popMenu]
      }
      $popMenu add command -label "End" -command [list endCallback $node $canvas $popMenu]
   }

   #$popMenu add command -label "Bound Family" -command [list boundFamilyCallback $node $canvas $popMenu]
   $popMenu add command -label "Abort" -command [list abortCallback $node $canvas $popMenu]
   $popMenu add command -label "Kill Node" -command [list killNodeFromDropdown $node $canvas $popMenu]
   $popMenu add command -label "Clean Log" -command [list cleanLogCallback $canvas $popMenu]
   $popMenu add separator
   $popMenu add command -label "Close" -command { destroy .popupMenu }
   
   tk_popup $popMenu $x $y
}

proc addLoopNodeMenu { popmenu_w canvas node } {
   DEBUG "addLoopNodeMenu() node:$node" 5

   set infoMenu ${popmenu_w}.info_menu
   set listingMenu ${popmenu_w}.listing_menu
   set submitMenu ${popmenu_w}.submit_menu
   set miscMenu ${popmenu_w}.misc_menu

   ${infoMenu} add command -label "Node History" -command [list historyCallback $node $canvas ${popmenu_w} 0 ]
   ${infoMenu} add command -label "Node Info" -command [list nodeInfoCallback $node $canvas ${popmenu_w}]
   ${infoMenu} add command -label "Loop Node Batch" -command [list batchCallback $node $canvas ${popmenu_w} 1]
   ${infoMenu} add command -label "Member Node Batch" -command [list batchCallback $node $canvas ${popmenu_w} 0]
   ${infoMenu} add command -label "Node Resource" -command [list resourceCallback $node $canvas ${popmenu_w} ]

   ${listingMenu} add command -label "Loop Listing" -command [list listingCallback $node $canvas ${popmenu_w} 1]
   ${listingMenu} add command -label "Loop Abort Listing" \
      -command [list abortListingCallback $node $canvas ${popmenu_w} 1] \
      -foreground [::DrawUtils::getBgStatusColor abort]

   ${listingMenu} add command -label "Member Listing" -command [list listingCallback $node $canvas ${popmenu_w}]
   ${listingMenu} add command -label "Member Abort Listing" \
      -command [list abortListingCallback $node $canvas ${popmenu_w}] \
      -foreground [::DrawUtils::getBgStatusColor abort]


   if { [xflow_isIgnoreDepTrue] == "true" } {
      ${submitMenu} add checkbutton -label "Ignore Dependency" -onvalue " -i" -offvalue "" -variable ignoreDep -state disabled
   }
   ${submitMenu} add command -label "Loop Submit" -command [list submitLoopCallback $node $canvas ${popmenu_w} continue ]
   ${submitMenu} add command -label "Member Submit" -command [list submitCallback $node $canvas ${popmenu_w} continue ]

   ${miscMenu} add command -label "New Window" -command [list newWindowCallback $node $canvas ${popmenu_w}]
   ${miscMenu} add command -label "Loop End" -command [list endLoopCallback $node $canvas ${popmenu_w}]
   ${miscMenu} add command -label "Loop Initbranch" -command [list initbranchLoopCallback $node $canvas ${popmenu_w}]
   ${miscMenu} add command -label "Member End" -command [list endCallback $node $canvas ${popmenu_w}]
   ${miscMenu} add command -label "Member Initbranch" -command [list initbranchCallback $node $canvas ${popmenu_w}]
}

proc addNptNodeMenu { popmenu_w canvas node } {

   set infoMenu ${popmenu_w}.info_menu
   set listingMenu ${popmenu_w}.listing_menu
   set submitMenu ${popmenu_w}.submit_menu
   set miscMenu ${popmenu_w}.misc_menu

   ${infoMenu} add command -label "Node History" -command [list historyCallback $node $canvas ${popmenu_w} 0 ]
   ${infoMenu} add command -label "Node Info" -command [list nodeInfoCallback $node $canvas ${popmenu_w}]
   ${infoMenu} add command -label "Node Batch" -command [list batchCallback $node $canvas ${popmenu_w} ]
   ${infoMenu} add command -label "Node Source" -command [list sourceCallback $node $canvas ${popmenu_w} ]
   ${infoMenu} add command -label "Node Config" -command [list configCallback $node $canvas ${popmenu_w} ]
   ${infoMenu} add command -label "Node Resource" -command [list resourceCallback $node $canvas ${popmenu_w} ]

   ${listingMenu} add command -label "Node Listing" -command [list listingCallback $node $canvas ${popmenu_w}]
   ${listingMenu} add command -label "All Node Listing" -command [list allListingCallback $node $canvas ${popmenu_w} success]
   ${listingMenu} add command -label "Node Abort Listing" \
      -command [list abortListingCallback $node $canvas ${popmenu_w}] \
      -foreground [::DrawUtils::getBgStatusColor abort]

   ${listingMenu} add command -label "All Node Abort Listing" \
      -command [list allListingCallback $node $canvas ${popmenu_w} abort] \
      -foreground [::DrawUtils::getBgStatusColor abort]


   if { [xflow_isIgnoreDepTrue] == "true" } {
      ${submitMenu} add checkbutton -label "Ignore Dependency" -onvalue " -i" -offvalue "" -variable ignoreDep -state disabled
   }
   ${submitMenu} add command -label "Submit & Continue" -command [list submitNpassTaskCallback $node $canvas ${popmenu_w} continue ]
   ${submitMenu} add command -label "Submit & Stop" -command [list submitNpassTaskCallback $node $canvas ${popmenu_w} stop ]

   ${miscMenu} add command -label "New Window" -command [list newWindowCallback $node $canvas ${popmenu_w}]
   ${miscMenu} add command -label "Initnode" -command [list initnodeCallback $node $canvas ${popmenu_w}]
   ${miscMenu} add command -label "End" -command [list endCallback $node $canvas ${popmenu_w}]

}

proc newWindowCallback { node canvas caller_menu } {
   DEBUG "newWindowCallback node:$node canvas:$canvas" 5
   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]
   set suiteName [$suiteRecord cget -suite_name]
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

   positionWindow $topWidget $canvas
   wm title $topWidget "Root=$displayNode"

   set formattedName [::SuiteNode::formatName [$suiteRecord cget -suite_path]]
   set drawFrame ${topWidget}.${formattedName}

   frame $drawFrame
   set newCanvas [createFlowCanvas $drawFrame]
   grid $drawFrame -sticky nsew

   set sizeGripWidget [ttk::sizegrip $topWidget.sizeGrip]
   grid ${sizeGripWidget} -sticky se

   # make the drawing expand x y directions
   grid rowconfigure $topWidget 0 -weight 1
   grid columnconfigure $topWidget 0 -weight 1

   set suiteRecord [::SuiteNode::getSuiteRecord $newCanvas]
   ::SuiteNode::setDisplayRoot $suiteRecord $newCanvas $displayNode

   # post process when window closes
   wm protocol $topWidget WM_DELETE_WINDOW [list closeSpawnedWindow $suiteRecord $newCanvas $topWidget ]
   drawflow $newCanvas

   # expand the view by default
   expandAllCallback $displayNode $newCanvas ""
}

proc historyCallback { node canvas caller_menu history {full_loop 0} } {
   DEBUG "historyCallback node:$node canvas:$canvas $full_loop" 5

   set seqExec [getGlobalValue SEQ_UTILS_BIN]/nodehistory
   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]

   set seqNode [::FlowNodes::getSequencerNode $node]
   set nodeExt [::FlowNodes::getListingNodeExtension $node $full_loop]
   DEBUG "historyCallback nodeExt:$nodeExt" 5
   if { $nodeExt == "-1" } {
      raiseError $canvas "node listing" [getErrorMsg NO_LOOP_SELECT]
   } else {
      if { $nodeExt != "" } {
         set nodeExt ".${nodeExt}"
      }

      # set datestamp for history to monitoring date if different from latest, else take datestamp from experiment.
      #set dateStamp [$suiteRecord cget -active_log]
      set dateStamp [getMonitoringDatestamp]
      if { $dateStamp == "" } {
          set dateStamp [retrieveDateStamp $canvas $suiteRecord]
      }

      Sequencer_runCommandWithWindow [$suiteRecord cget -suite_path] $seqExec \
         "Node History [file tail $node]$nodeExt -history $history" \
         -n $seqNode$nodeExt -history $history -edate $dateStamp 
   }
}

proc nodeInfoCallback { node canvas caller_menu } {
   global env
   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]
   set suiteName [$suiteRecord cget -suite_name]
   set nodeTail [file tail $node]
   set infoWidget [string tolower .${suiteName}_${nodeTail}_nodeInfo]

   if { [winfo exists $infoWidget] } {
      destroy $infoWidget
   }
   toplevel $infoWidget
   positionWindow $infoWidget $canvas
   wm title $infoWidget "Node Info ${nodeTail}"
   set textWidget [text $infoWidget.txt]
   set outputFile $env(TMPDIR)/nodeinfo_output_${nodeTail}
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

   DEBUG "nodeInfoCallback export SEQ_EXP_HOME=${seqExpHome};${nodeInfoExec} -n $seqNode  ${seqLoopArgs}" 5
   set code [catch {eval [exec ksh -c "export SEQ_EXP_HOME=${seqExpHome};${nodeInfoExec} -n $seqNode  ${seqLoopArgs} > ${outputFile} 2> /dev/null"]} message]

   if { $code != 0 } {
      DEBUG "newWindowCallback ERROR:${message}" 5
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

proc boundFamilyCallback { node canvas caller_menu } {
   ::DrawUtils::drawFamily $node $canvas
   destroy $caller_menu
}

proc initbranchCallback { node canvas caller_menu } {
   set seqExec "[getGlobalValue SEQ_BIN]/maestro"
   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]
   set seqNode [::FlowNodes::getSequencerNode $node]
   set seqLoopArgs [::FlowNodes::getLoopArgs $node]
   if { $seqLoopArgs == "" && [::FlowNodes::hasLoops $node] } {
      raiseError $canvas "initbranch" [getErrorMsg NO_LOOP_SELECT]
   } else {
      Sequencer_runCommandWithWindow [$suiteRecord cget -suite_path] $seqExec "initbranch [file tail $node] $seqLoopArgs" -n $seqNode -s initbranch -f continue $seqLoopArgs
   }
   #$node configure -flow.status initialize
   #::DrawUtils::drawNodeStatus $node
}

proc initnodeCallback { node canvas caller_menu } {
   set seqExec "[getGlobalValue SEQ_BIN]/maestro"
   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]
   set seqNode [::FlowNodes::getSequencerNode $node]
   set seqLoopArgs [::FlowNodes::getLoopArgs $node]
   if { $seqLoopArgs == "" && [::FlowNodes::hasLoops $node] } {
      raiseError $canvas "initnode" [getErrorMsg NO_LOOP_SELECT]
   } else {
      Sequencer_runCommandWithWindow [$suiteRecord cget -suite_path] $seqExec "initnode [file tail $node] $seqLoopArgs" -n $seqNode -s initnode -f continue $seqLoopArgs
   }
}

proc initbranchLoopCallback { node canvas caller_menu } {
   set seqExec "[getGlobalValue SEQ_BIN]/maestro"
   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]
   set seqNode [::FlowNodes::getSequencerNode $node]
   set seqLoopArgs [::FlowNodes::getParentLoopArgs $node]
   if { $seqLoopArgs == "-1" && [::FlowNodes::hasLoops $node] } {
      raiseError $canvas "initbranch" [getErrorMsg NO_LOOP_SELECT]
   } else {
      Sequencer_runCommandWithWindow [$suiteRecord cget -suite_path] $seqExec "initbranch [file tail $node] $seqLoopArgs" -n $seqNode -s initbranch -f continue $seqLoopArgs
   }
}

proc abortCallback { node canvas caller_menu } {
   set seqExec "[getGlobalValue SEQ_BIN]/maestro"
   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]
   set seqNode [::FlowNodes::getSequencerNode $node]
   set seqLoopArgs [::FlowNodes::getLoopArgs $node]
   if { $seqLoopArgs == "" && [::FlowNodes::hasLoops $node] } {
      raiseError $canvas "node abort" [getErrorMsg NO_LOOP_SELECT]
   } else {
      Sequencer_runCommandWithWindow [$suiteRecord cget -suite_path] $seqExec "abort [file tail $node] $seqLoopArgs" -n $seqNode -s abort -f continue $seqLoopArgs
   }
}

proc killNodeFromDropdown { node canvas caller_menu } {

   global env
   set shadowColor [SharedData_getColor SHADOW_COLOR]
   set bgColor [SharedData_getColor CANVAS_COLOR]
   set id [clock seconds]
   set tmpdir $env(TMPDIR)
   set tmpfile "${tmpdir}/test$id"
   set suiteRecord [getActiveSuite]
   set suitePath [$suiteRecord cget -suite_path]
   set seqNode [::FlowNodes::getSequencerNode $node]
   set killPath [getGlobalValue SEQ_UTILS_BIN]/nodekill 
   set cmd "export SEQ_EXP_HOME=$suitePath; $killPath -n $seqNode -list > $tmpfile 2>&1"
   DEBUG "killNodeFromDropdown ksh -c $cmd" 5
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
      -command [list killNode $soloWindow.list ]]
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

proc endCallback { node canvas caller_menu } {
   set seqExec "[getGlobalValue SEQ_BIN]/maestro"

   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]

   set seqNode [::FlowNodes::getSequencerNode $node]
   set seqLoopArgs [::FlowNodes::getLoopArgs $node]
   if { $seqLoopArgs == "" && [::FlowNodes::hasLoops $node] } {
      raiseError $canvas "node end" [getErrorMsg NO_LOOP_SELECT]
   } else {
      Sequencer_runCommandWithWindow [$suiteRecord cget -suite_path] $seqExec "end [file tail $node] $seqLoopArgs" -n $seqNode -s end -f continue $seqLoopArgs
   }

}

proc endLoopCallback { node canvas caller_menu } {
   set seqExec "[getGlobalValue SEQ_BIN]/maestro"

   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]

   set seqNode [::FlowNodes::getSequencerNode $node]
   set seqLoopArgs [::FlowNodes::getParentLoopArgs $node]
   if { $seqLoopArgs == "-1" && [::FlowNodes::hasLoops $node] } {
      raiseError $canvas "loop end" [getErrorMsg NO_LOOP_SELECT]
   } else {
      Sequencer_runCommandWithWindow [$suiteRecord cget -suite_path] $seqExec "end [file tail $node] $seqLoopArgs" -n $seqNode -s end -f continue $seqLoopArgs
   }
}

proc sourceCallback { node canvas caller_menu} {
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
      DEBUG "sourceCallback running ${defaultConsole} ${editorCmd}" 5
      TextEditor_goKonsole ${defaultConsole} ${winTitle} ${editorCmd}
   }
}


proc configCallback { node canvas caller_menu} {
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
      DEBUG "sourceCallback running ${defaultConsole} ${editorCmd}" 5
      TextEditor_goKonsole ${defaultConsole} ${winTitle} ${editorCmd}
   }
}

proc resourceCallback { node canvas caller_menu } {
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
      DEBUG "resourceCallback running ${defaultConsole} ${editorCmd}" 5
      TextEditor_goKonsole ${defaultConsole} ${winTitle} ${editorCmd}
   }
}

proc batchCallback { node canvas caller_menu {full_loop 0} } {
   global SESSION_TMPDIR
   set seqExec "[getGlobalValue SEQ_UTILS_BIN]/nodebatch"
   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]
   set seqNode [::FlowNodes::getSequencerNode $node]
   set nodeExt [::FlowNodes::getListingNodeExtension $node $full_loop]
   set textViewer [SharedData_getMiscData TEXT_VIEWER]
   set defaultConsole [SharedData_getMiscData DEFAULT_CONSOLE]

   if { $nodeExt == "-1" } {
      raiseError $canvas "node listing" [getErrorMsg NO_LOOP_SELECT]
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
         DEBUG "sourceCallback running ${defaultConsole} ${editorCmd}" 5
         TextEditor_goKonsole ${defaultConsole} ${winTitle} ${editorCmd}
      }
   }
}

proc submitCallback { node canvas caller_menu flow {local_ignore_dep dep_on} } {
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
      raiseError $canvas "node submit" [getErrorMsg NO_LOOP_SELECT]
   } else {
      Sequencer_runCommandWithWindow [$suiteRecord cget -suite_path] $seqExec "submit [file tail $node] $seqLoopArgs" -n $seqNode -s submit -f $flow $test_flag $seqLoopArgs

   }

}

proc submitLoopCallback { node canvas caller_menu flow} {
   set seqExec "[getGlobalValue SEQ_BIN]/maestro"

   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]

   set seqNode [::FlowNodes::getSequencerNode $node]
   set seqLoopArgs [::FlowNodes::getParentLoopArgs $node]
   if { $seqLoopArgs == "-1" && [::FlowNodes::hasLoops $node] } {
      raiseError $canvas "loop submit" [getErrorMsg NO_LOOP_SELECT]
   } else {
      Sequencer_runCommandWithWindow [$suiteRecord cget -suite_path] $seqExec "submit [file tail $node] $seqLoopArgs" -n $seqNode -s submit -f $flow $seqLoopArgs   
   }
}

proc submitNpassTaskCallback { node canvas caller_menu flow} {
   global ignoreDep

   DEBUG "submitNpassTaskCallback node:$node canvas:$canvas" 5
   set seqExec "[getGlobalValue SEQ_BIN]/maestro"

   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]

   set seqNode [::FlowNodes::getSequencerNode $node]
   # retrieve index value from widget
   set indexListW "${canvas}.[${node} cget flow.name]"
   set indexListValue ""
   if { [winfo exists ${indexListW}] } {
      set indexListValue [${indexListW} get]
      DEBUG "submitNpassTaskCallback indexListValue:$indexListValue" 5
   }
   if { ${indexListValue} == "latest" } {
      raiseError $canvas "Npass_Task submit" [getErrorMsg NO_INDEX_SELECT]
   } else {
      set seqNpassTaskArgs [::FlowNodes::getNptArgs ${node} ${indexListValue}]
   
      if { $seqNpassTaskArgs == "-1" } {
         raiseError $canvas "Npass_Task submit" [getErrorMsg NO_INDEX_SELECT]
      } else {
         DEBUG "submitNpassTaskCallback $seqNpassTaskArgs" 5
         Sequencer_runCommandWithWindow [$suiteRecord cget -suite_path] $seqExec "submit [file tail $node] $seqNpassTaskArgs" -n $seqNode -s submit -f $flow $ignoreDep $seqNpassTaskArgs

      }
   }
}

proc listingCallback { node canvas caller_menu {full_loop 0} } {
   global SESSION_TMPDIR
   DEBUG "listingCallback node:$node canvas:$canvas" 5
   set listingExec [getGlobalValue SEQ_UTILS_BIN]/nodelister
   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]

   set seqNode [::FlowNodes::getSequencerNode $node]
   set nodeExt [::FlowNodes::getListingNodeExtension $node $full_loop]
   set datestamp [getMonitoringDatestamp]
   set listingViewer [SharedData_getMiscData TEXT_VIEWER]
   set defaultConsole [SharedData_getMiscData DEFAULT_CONSOLE]

   if { $nodeExt == "-1" } {
      raiseError $canvas "node listing" [getErrorMsg NO_LOOP_SELECT]
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

proc allListingCallback { node canvas caller_menu type } {
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
   #   raiseError $canvas "node listing" [getErrorMsg NO_LOOP_SELECT]
   #   return
   #}
   #if { $nodeExt != "" } {
   #   set nodeExt ".${nodeExt}"
   #}
   set cmd "export SEQ_EXP_HOME=$suitePath; $listerPath -n ${seqNode} -type $type -list > $tmpfile 2>&1"
   DEBUG "allListingCallback ksh -c $cmd" 5
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
   bind ${listingW}.list <Double-Button-1> [list showAllListingItem ${suiteRecord} ${listingW}.list ${type}]
}

proc showAllListingItem { suite_record listw list_type} {
   global SESSION_TMPDIR
   DEBUG "showAllListingItem selection: [$listw curselection]" 5
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

proc abortListingCallback { node canvas caller_menu {full_loop 0} } {
   global SESSION_TMPDIR
   DEBUG "abortListingCallback node:$node canvas:$canvas" 5
   set abortListingExec [getGlobalValue SEQ_UTILS_BIN]/nodelister
   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]
   set seqNode [::FlowNodes::getSequencerNode $node]
   set nodeExt [::FlowNodes::getListingNodeExtension $node $full_loop]
   set datestamp [getMonitoringDatestamp]
   set listingViewer [SharedData_getMiscData TEXT_VIEWER]
   set defaultConsole [SharedData_getMiscData DEFAULT_CONSOLE]

   if { $nodeExt == "-1" } {
      raiseError $canvas "node listing" [getErrorMsg NO_LOOP_SELECT]
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

proc cleanLogCallback { canvas caller_menu } {
   DEBUG "cleanLogCallback canvas:$canvas" 5
   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]
   set suitePath [$suiteRecord cget -suite_path]
   set logfile $suitePath/logs/firsin
   Sequencer_runCommandWithWindow [$suiteRecord cget -suite_path] cp "Clean Log $logfile" /dev/null $logfile
   destroy $caller_menu
   puts "**************************************************************************************"
   puts [ $suiteRecord cget -read_offset ]
   $suiteRecord configure -read_offset 0
   puts "**************************************************************************************"
   puts [ $suiteRecord cget -read_offset ]
   # LogReader_readFile $suiteRecord

   drawflow $canvas
}


proc indexedNodeSelectionCallback { node canvas combobox_w} {
   DEBUG "npassTaskSelectionCallback node:$node $combobox_w" 5

   set member [${combobox_w} get]

   if { $member != "latest" && [lindex $member 0] != "+" } {
      set member +${member}
   }
   $node configure -current $member

   xflow_redrawNodes ${node} ${canvas}
}

proc expandAllCallback { node canvas caller_menu } {
   ::FlowNodes::uncollapseAll $node $canvas
   destroy $caller_menu
   drawflow $canvas
}

# this should only be called for flow windows that
# are spawned using the "new window" callback
proc closeSpawnedWindow { suite canvas toplevel_win} {
   DEBUG "closeSpawnedWindow suite:$suite canvas:$canvas toplevel_win:$toplevel_win" 5
   set rootNode [::SuiteNode::getDisplayRoot $suite $canvas]
   # recursively remove the display from all nodes in the canvas
   ::FlowNodes::removeDisplayFromNode $rootNode $canvas 1

   # remove the canvas from the suite
   ::SuiteNode::removeDisplayFromSuite $suite $canvas
   destroy $toplevel_win
}

# callback when user click on a box with button 1
proc changeCollapsed { canvas binder x y } {
   #DEBUG "changeCollapsed called canvas:$canvas binder:$binder x:$x y:$y" 4
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

   #DEBUG "changeCollapsed: new collapse value:[${binder} cget -flow.display.collapse]" 4
   drawflow $canvas
}

proc redrawAllFlow {} {
   set suiteRecord [getActiveSuite]
   set canvasList [::SuiteNode::getCanvasList ${suiteRecord}]
   foreach canvasW $canvasList {
      drawflow $canvasW 0
   }
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
         drawNode ${canvas} ${node} ${nodePosition} changeCollapsed
         #xflow_resizeWindow ${canvas}
      }
   }
   set REFRESH_MODE false
}

proc drawflow { canvas {initial_display "1"} } {
   DEBUG "drawflow() canvas:$canvas" 5
   if { [winfo exists ${canvas}] } {
      ::DrawUtils::clearCanvas $canvas

      set suiteRecord [::SuiteNode::getSuiteRecord $canvas]
      # reset the default spacing for drawing flow
      # ::SuiteNode::resetDisplayNextY $suiteRecord $canvas
      ::SuiteNode::resetDisplayData ${suiteRecord} ${canvas}
      set rootNode [::SuiteNode::getDisplayRoot $suiteRecord $canvas]
   
      set callback changeCollapsed
      drawNode $canvas $rootNode 0 $callback true
      set canvasArea [$canvas bbox all]
      $canvas  configure -scrollregion $canvasArea -yscrollincrement 5 -xscrollincrement 5
   
      # resize the window depending on size of canvas elements
      xflow_resizeWindow ${canvas}

      if { $initial_display == "1" } {
         $canvas yview moveto 0
      }
      xflow_AddCanvasBg ${canvas}
   }
   DEBUG "drawflow() done" 5

}

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

proc createTabs { parent suiteList bind_cmd {page_h 1} {page_w 1}} {
   global env
   DEBUG "createTabs parent:$parent suiteList:$suiteList bind_cmd:$bind_cmd "
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
      getNodeResources ${rootNode} $suitePath 1
      incr count
   }
}

proc getNodeResources { node suite_path {is_recursive 0} } {
   global env
   DEBUG "getNodeResources node:$node"
   set nodeInfoExec "[getGlobalValue SEQ_BIN]/nodeinfo"
   set seqNode [::FlowNodes::getSequencerNode $node]
   set outputFile $env(TMPDIR)/nodeinfo_output_[file tail $node]

   # for now we only care about resources from tasks
   if { [$node cget -record_type] == "FlowTask" || [$node cget -record_type] == "FlowNpassTask" } {
      # the next command runs nodeinfo and converts each line of the output
      # into a tcl command
      set code [catch {set output [exec ksh -c "export SEQ_EXP_HOME=${suite_path};${nodeInfoExec} -n ${seqNode} -f res |  sed -e 's:node.:$node configure -:' -e 's:=: :' > ${outputFile} 2> /dev/null "]} message]
   
      if { $code != 0 } {
         raiseError . "Get Node Resource" $message
         return 0
      }
      if [ catch { eval [exec cat ${outputFile}] } message ] {
         puts "\n$message"
      }

      catch { close $fileId }
   }

   if { $is_recursive } {
      set childList [$node cget -flow.children]
      if { $childList != "" } {
         foreach childName $childList {
            set childNode $node/$childName
            getNodeResources $childNode $suite_path $is_recursive
         }
      }
   }
}

proc selectSuiteTab { parent suite_record } {

   DEBUG "selectSuiteTab parent:$parent suite_record:${suite_record}"

   set title "xflow experiment path = [${suite_record} cget -suite_path]"
   wm title . $title

   setActiveSuite ${suite_record}
   set formattedName [::SuiteNode::formatName [${suite_record} cget -suite_path]]
   set drawFrame ${parent}.${formattedName}
   set canvas [createFlowCanvas $drawFrame]
   getDateStamp $parent ${suite_record}
   getMonitorDate $parent ${suite_record}

   catch {
      drawflow $canvas
   }
}

proc xflow_isIgnoreDepTrue {} {
   global ignoreDep
   if { ${ignoreDep} == "" } {
      return false
   }
   return true
}

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

proc createFlowCanvas { parent } {
   DEBUG "createFlowCanvas parent:$parent " 5
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

proc createMainMenus { _top } {
   if { $_top == "." } {
      set top ""
   } else {
      set top $_top
   }

   button ${top}.msgCenter -text "Message Center"
   pack ${top}.msgCenter -padx 1m -side left -fill x -expand 1
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

proc setActiveSuite { suite } {
   global ACTIVE_SUITE

   set ACTIVE_SUITE $suite
}

proc getActiveSuite {} {
   global ACTIVE_SUITE

   if { [info exists ACTIVE_SUITE] } {
      return $ACTIVE_SUITE
   } else {
      return ""
   }
}

proc listToString { inputList } {

    set resultString "" 
    for { set i 0 } { $i < [llength $inputList] } { incr i } {
        set resultString "$resultString [lindex $inputList $i]"
    }
    return $resultString 

}

proc quitXflow {} {
   global XFLOW_STANDALONE MONITOR_THREAD_ID
   global SESSION_TMPDIR

   DEBUG "quitXflow exiting Xflow thread id:[thread::id]" 5
   set suiteRecord [getActiveSuite]
   set isOverviewMode [SharedData_getMiscData OVERVIEW_MODE]
   if { [info exists SESSION_TMPDIR] } {
      DEBUG "quitXflow deleting tmp dir ${SESSION_TMPDIR}"
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
   set suiteRecord [getActiveSuite]
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
      FatalError . "Xflow Startup Error" "SEQ_EXP_HOME environment variable not set! Exiting..."
   }

   set entryModTruePath ""
   catch { set entryModTruePath [exec true_path $env(SEQ_EXP_HOME)/EntryModule] }
   if { ${entryModTruePath} == "" } {
      FatalError . "Xflow Startup Error" "Cannot access $env(SEQ_EXP_HOME)/EntryModule. Exiting..."
   }
}

proc launchXflow { calling_thread_id } {
   global env XFLOW_STANDALONE 
   global MONITORING_LATEST MONITOR_DATESTAMP

   DEBUG "launchXflow thread id:[thread::id]" 5

   set topFrame .top

   xflow_createTmpDir

   xflow_validateSuite

   if { ! [winfo exists ${topFrame}] } {
      set suiteList {}
      if { [info exists env(SEQ_EXP_HOME)] } {
         set activeSuite $env(SEQ_EXP_HOME)
         set suiteList [linsert $suiteList 0 $env(SEQ_EXP_HOME)] 
         if { ${MONITORING_LATEST} == "1" } {
            SharedData_setSuiteData $env(SEQ_EXP_HOME) THREAD_ID [thread::id]
         }
      }
      proc out {} {
         set suitesFile $env(HOME)/.suites/.xflow.suites.xml
         if { [file exists $suitesFile] } {
            # old stuff to show all user's exp
            ExpXmlReader_readExperiments $suitesFile
            set suiteList [ExpXmlReader_getExpList]
            DEBUG "suiteList: $suiteList"
            set activeSuite [lindex $suiteList 0]
         }
      }   
      wm iconify .
      
      # .top is the first widget
      frame $topFrame
      addFileMenu $topFrame
      addViewMenu $topFrame
      addHelpMenu $topFrame
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
      addDatestampWidget $dateFrame
      # monitor date
      addMonitorDateWidget $dateFrame
      bind $dateFrame <Double-Button-1> [list viewHideDateButtons . $dateFrame $dateFrameHidden 20 ]
      bind $dateFrameHidden <Double-Button-1> [list viewHideDateButtons . $dateFrameHidden $dateFrame "" ]
      grid $dateFrame -row 2 -column 0 -sticky nsew -padx 0 -pady 0 -columnspan 2

      # start in hidden mode
      viewHideDateButtons . $dateFrame $dateFrameHidden 20

      #add list buttons
      set openListButtonsFrame .list_buttons
      #set hiddenListButtonsFrame .list_buttons_hidden
      labelframe $openListButtonsFrame  -text "Listing buttons"
      tooltip::tooltip $openListButtonsFrame "Double-click to hide"
   
      # .tabs is the 3nd widget
      set tabFrame .tabs
      frame .tabs
      createTabs .tabs $suiteList "selectSuiteCallback"
      
      grid .tabs  -row 3 -column 0 -columnspan 2 -sticky nsew -padx 2 -pady 2
      grid columnconfigure . 0 -weight 1
      grid columnconfigure . 1 -weight 1
      grid rowconfigure . 3 -weight 2
   
      ttk::sizegrip .sizeGrip
      grid .sizeGrip -row 3 -column 1 -sticky se
      
      wm geometry . =1200x800
      
      set activeSuiteRecord [SuiteNode::getSuiteRecordFromPath $activeSuite]
      #puts "startup:: activeSuite:$activeSuite activeSuiteRecord:$activeSuiteRecord"
      setActiveSuite $activeSuiteRecord
      
      set suiteRecordList [record show instances SuiteInfo]
      DEBUG "suiteRecordList :$suiteRecordList"

      if { ${XFLOW_STANDALONE} == "1" } {
         LogReader_readFile $activeSuiteRecord $calling_thread_id
      }
      selectSuiteTab .tabs $activeSuiteRecord 
      set activeSuiteName [$activeSuiteRecord cget -suite_name]
      set activeSuitePath [$activeSuiteRecord cget -suite_path]
      set topNode "/${activeSuiteName}"
      expandAllCallback $topNode .tabs.[::SuiteNode::formatName ${activeSuitePath}].canvas ""
   
      wm deiconify .
   } else {
      xflow_toFront
   }
   # Console_create
}

proc xflow_toFront {} {
   wm withdraw . ; wm deiconify .
}

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

proc parseCmdOptions {} {
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
      # set AUTO_MSG_DISPLAY true
      if { $params(noautomsg) } {
         set AUTO_MSG_DISPLAY false
      }
   } else {
      set XFLOW_STANDALONE 0
   }
}

proc xflow_datestampChanged { suite_record } {
   set dateFrame .date
   if { [winfo exists $dateFrame] } {
      getDateStamp $dateFrame ${suite_record}
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
   #set NODE_DISPLAY_PREF normal
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

   setTkOptions

   keynav::enableMnemonics .
   wm protocol . WM_DELETE_WINDOW quitXflow

   xflow_createTmpDir
}

# creates a tmp dir for listings, text files
proc xflow_createTmpDir {} {
   global env SESSION_TMPDIR

   set thisPid [thread::id]
   set userTmpDir [SharedData_getMiscData USER_TMP_DIR]
   if { ${userTmpDir} != "default" } {
      if { ! [file isdirectory ${userTmpDir}] } {
         FatalError . "Xflow Startup Error" "Invalid user configuration in .maestrorc file. Directory ${userTmpDir} does not exists!"
      }
      set rootTmpDir ${userTmpDir}
   } else {
      if { ! [info exists env(TMPDIR)] } {
         FatalError . "Xflow Startup Error" "TMPDIR environment variable does not exists!"
      }
      set rootTmpDir $env(TMPDIR)
   }
   set id [clock seconds]
   set myTmpDir ${rootTmpDir}/maestro_${thisPid}_${id}
   if { [file exists ${myTmpDir}] } {
      puts "xflow_createTmpDir deleting ${myTmpDir}"
      file delete -force ${myTmpDir}
   }
   puts "xflow_createTmpDir creating ${myTmpDir}"
   file mkdir ${myTmpDir}
   set SESSION_TMPDIR ${myTmpDir}
}

global XFLOW_STANDALONE

parseCmdOptions
if { ${XFLOW_STANDALONE} == 1 } {

   SharedData_init
   xflow_init
   launchXflow [thread::id]
   SharedData_setMiscData STARTUP_DONE true
   thread::send -async ${MSG_CENTER_THREAD_ID} "MsgCenterThread_startupDone"
}
