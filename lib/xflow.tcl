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
puts "lib_dir=$lib_dir"
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
   $labelMenu add radiobutton -label "normal" -variable NODE_DISPLAY_PREF -value 1 \
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

proc xflow_testAddCanvasBg { canvas height width } {
   puts "xflow_testAddCanvasBg ${canvas}"
   # image already created at canvas creaton time
   set imageBg ${canvas}.bg_image
   set imageTagName ${canvas}_bg_image

   ${canvas} delete ${imageTagName}
   ${canvas} create image 0 0 -anchor nw -image ${imageBg} -tags ${imageTagName}
   ${canvas} lower ${imageTagName}
   puts "xflow_testAddCanvasBg ${canvas} done"
}

proc xflow_createToolbar { parent } {
   puts "xflow_createToolbar ${parent}"
   global MSG_CENTER_THREAD_ID
   set msgCenterW ${parent}.button_msgcenter
   set nodeKillW ${parent}.button_nodekill
   set nodeListW ${parent}.button_nodelist
   set nodeAbortListW ${parent}.button_nodeabortlist

   set closeW ${parent}.button_close

   set imageDir [SharedData_getMiscData IMAGE_DIR]

   image create photo ${parent}.msg_center_img -file ${imageDir}/open_mail_sh.ppm
   image create photo ${parent}.msg_center_new_img -file ${imageDir}/open_mail_new.ppm
   image create photo ${parent}.node_kill_img -file ${imageDir}/node_kill.ppm
   image create photo ${parent}.node_list_img -file ${imageDir}/node_list.ppm
   image create photo ${parent}.node_abort_list_img -file ${imageDir}/node_abort_list.ppm
   image create photo ${parent}.close -file ${imageDir}/cancel.ppm

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

   if { [SharedData_getMiscData OVERVIEW_MODE] == "true" } {
      set overviewW ${parent}.button_overview
      image create photo ${parent}.overview -file ${imageDir}/calendar_clock.ppm
      button ${overviewW} -image ${parent}.overview -command {
         set overviewThreadId [SharedData_getMiscData OVERVIEW_THREAD_ID]
         thread::send -async ${overviewThreadId} "Overview_toFront"
      }
      ::tooltip::tooltip ${overviewW} "Show overview window."
      ::tooltip::tooltip ${closeW} "Close window."
      grid ${msgCenterW} ${overviewW} ${nodeKillW} ${nodeListW}  ${nodeAbortListW} ${closeW} -sticky w -padx 2
   } else {
      grid ${msgCenterW} ${nodeKillW} ${nodeListW} ${nodeAbortListW} ${closeW} -sticky w -padx 2
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
      set jobPath [string range [lindex $listEntryValue 8] [string length $suitePath/sequencing/jobinfo] end]
      set nodeID [file tail ${jobPath}]
      set node [file dirname ${jobPath}]/[lindex $listEntryValue end]
      Sequencer_runCommand $suitePath $seqExec "Node Kill [file tail $node]" -n $node -job_id $nodeID
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
      set values "$values [string range $date 0 9]"
   }
   ${monitorEntryCombo} configure -values $values
   puts "getMonitorDate MONITOR_DATESTAMP:$MONITOR_DATESTAMP -active_log? [${suite_record} cget -active_log]"
   if { ${MONITORING_LATEST} == 0 && ${MONITOR_DATESTAMP} != "" } {
      ${suite_record} configure -active_log ${MONITOR_DATESTAMP} -read_offset 0
      ${monitorEntryCombo} set ${MONITOR_DATESTAMP}
   } else {
      if { [${suite_record} cget -active_log] == "" } {
         ${monitorEntryCombo} configure -state disabled
         ${setButton} configure -state disabled
         ${monitorEntryCombo} set latest
      } else {
         ${monitorEntryCombo} set [string range [${suite_record} cget -active_log] 0 9]
         set MONITOR_DATESTAMP [${suite_record} cget -active_log]
      }
   }
   puts "getMonitorDate 2 MONITOR_DATESTAMP:$MONITOR_DATESTAMP"
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
      set values "$values [string range $date 0 9]"
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
         if { [string match ${dateValue}0000 $date] } {
            set found 1
            break
         }
      }
      if { $found == 0 } {
         raiseError [winfo toplevel $parent_w] "Datestamp" "Selected date does not exists!\nPlease choose another date."
      } else {
         DEBUG "setMonitorDate ${dateValue}0000" 5
         set MONITOR_DATESTAMP ${dateValue}0000
         proc out {} {
            $suiteRecord configure -read_offset 0 -active_log ${dateValue}0000
            set topNode "/${suiteName}"
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
         set isOverviewMode [SharedData_getMiscData OVERVIEW_MODE]
         if { ${isOverviewMode} == "true" } {
            set monitorThreadId [xflow_getMonitoredThread]
            #thread::send -async ${monitorThreadId} \
            #   "xflowThread_monitorNewDate ${MONITOR_DATESTAMP}"
            thread::send ${monitorThreadId} "xflowThread_monitorNewDate ${MONITOR_DATESTAMP}"
         } else {
            $suiteRecord configure -read_offset 0 -active_log ${MONITOR_DATESTAMP}
            set topNode "/${suiteName}"
            ::FlowNodes::resetNodeStatus $topNode
            selectSuiteTab [getTabsParentW] $suiteRecord
            LogReader_readFile $suiteRecord [thread::id]
         }

      }
   }

   normalCursor $top
}

proc newMonitorDate { suite_record datestamp } {
}

proc xflow_getMonitoredThread {} {
   global MONITOR_THREAD_ID
   if { ${MONITOR_THREAD_ID} == "" } {
      DEBUG "xflow_getMonitoredThread Creating new thread..." 5
      set MONITOR_THREAD_ID [thread::create {
         global env
         set lib_dir $env(SEQ_XFLOW_BIN)/../lib
         set auto_path [linsert $auto_path 0 $lib_dir ]

         proc xflowThread_monitorNewDate { datestamp } {
            global XFLOW_STANDALONE MONITORING_LATEST MONITOR_DATESTAMP MONITOR_THREAD_ID
            xflow_init
            set XFLOW_STANDALONE 1
            set MONITORING_LATEST 0
            set MONITOR_DATESTAMP ${datestamp}
            set MONITOR_THREAD_ID [thread::id]
            DEBUG "xflowThread_monitorNewDate thread_id:[thread::id] datestamp:${datestamp} overview_mode? [SharedData_getMiscData OVERVIEW_MODE]" 5
            launchXflow [thread::id]
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
   set shortDatestamp [string range $dateStamp 0 9]
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
         LogReader_readFile $suiteRecord [thread::id]
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

proc initGlobals {} {
   global NODE_DISPLAY_PREF
   global SHADOW_STATUS MONITORING_LATEST

   set NODE_DISPLAY_PREF 1
   set SHADOW_STATUS 0
   set MONITORING_LATEST 1
}

proc getNodeDisplayPrefText { node } {
   set text ""
   if { [$node cget -flow.type] == "task" || [$node cget -flow.type] == "npass_task"  } {
      switch [getNodeDisplayPref] {
         2 {
            set text "([$node cget -catchup])"
         }
         3 {
            set text "([$node cget -cpu])"
         }
         4 {
            set text "([$node cget -machine])"
         }
         5 {
            set text "([$node cget -memory])"
         }
         6 {
            set text "([$node cget -mpi])"
         }
         7 {
            set text "([$node cget -wallclock])"
         }
         default {
         }
      }
   }
   return $text
}

proc getNodeDisplayPref {} {
   global NODE_DISPLAY_PREF
   if { ! [info exists NODE_DISPLAY_PREF] } {
      set NODE_DISPLAY_PREF 0
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

proc xflow_findNode { suite_record real_node } {
   set flowNode [::SuiteNode::getFlowNodeMapping ${suite_record} ${real_node}]
   ::DrawUtils::pointNode ${suite_record} ${flowNode}
}

# parent_node is the previous_node in the flow that is submitting this node
proc drawNode { canvas node parent_node position run_catchup {callback test} } {
   DEBUG "drawNode drawing sub node:$node parent_node:$parent_node position:$position" 5
   set boxW [SharedData_getMiscData CANVAS_BOX_WIDTH]
   set boxH [SharedData_getMiscData CANVAS_BOX_HEIGHT]
   set pady [SharedData_getMiscData CANVAS_PAD_Y]
   set padTx [SharedData_getMiscData CANVAS_PAD_TXT_X]
   set padTy [SharedData_getMiscData CANVAS_PAD_TXT_Y]
   set shadowColor [SharedData_getColor SHADOW_COLOR]
   set drawshadow on

   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]
   ::FlowNodes::initNode $node $canvas
   if { $parent_node == "" } {
      set linex2 20
      set liney2 20
      DEBUG "drawNode linex2:$linex2 liney2:$liney2"
   } else {
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

      set displayInfo [::FlowNodes::getDisplayCoords $parent_node $canvas]
      DEBUG "drawNode displayInfo:$displayInfo"
      set px1 [lindex $displayInfo 0]
      set px2 [lindex $displayInfo 2]
      set py1 [lindex $displayInfo 1]
      set py2 [lindex $displayInfo 3]
      # first draw left arrow, the shape depends on the position of the
      # subnode and previous nodes being drawn
      # if position is 0, means first node job so same level as parent node only x coords changes
      if { $position == 0 } {
         set linex1 $px2
         set liney1 [expr $py1 + ($py2 - $py1) / 2 ]
         set liney2 $liney1
         set linex2 [expr $linex1 + $boxW/2]
         ::DrawUtils::$drawline $canvas $linex1 $liney1 $linex2 $liney2 last $lineColor $drawshadow $shadowColor
      } else {
         # draw L-shape arrow
         # first draw vertical line
         set nextY [::SuiteNode::getDisplayNextY $suiteRecord $canvas]
         set linex1 [expr $px2 + $boxW/4]
         set linex2 $linex1
         set liney1 [expr $py1 + ($py2 - $py1) / 2 ]
         set liney2 [expr $nextY + ($boxH/4) + $pady]
         ::DrawUtils::$drawline $canvas $linex1 $liney1 $linex2 $liney2 none $lineColor $drawshadow $shadowColor
         # then draw hor line with arrow at end
         set linex2 [expr $px2 + $boxW/2]
         set liney1 $liney2
         ::DrawUtils::$drawline $canvas $linex1 $liney1 $linex2 $liney2 last $lineColor  $drawshadow $shadowColor
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
   set maxExtDisplay "${text}[::FlowNodes::getExtDisplayWidth $node]"
   if { $extDisplay != "" } {
      set text "${text}${extDisplay}"
   }
   set dispPref [getNodeDisplayPrefText $node]
   if { $dispPref != "" } {
      set maxExtDisplay "${maxExtDisplay}\n${dispPref}"
      set text "${text}\n${dispPref}"
   }
   
   switch [$node cget -flow.type] {
      "family" {
         ::DrawUtils::drawBoxSansOutline $canvas $tx1 $ty1 $text $maxExtDisplay $normalTxtFill $outline $normalFill $callback $node $drawshadow $shadowColor
         ::FlowNodes::addToFamilyList $node
      }
      "module" {
	 ::DrawUtils::drawBoxSansOutline $canvas $tx1 $ty1 $text $maxExtDisplay $normalTxtFill $outline $normalFill $callback $node $drawshadow $shadowColor
      }
      "task" {
         ::DrawUtils::drawBox $canvas $tx1 $ty1 $text $maxExtDisplay $normalTxtFill $outline $normalFill $callback $node $drawshadow $shadowColor
      }

      "npass_task" {
         ::DrawUtils::drawBox $canvas $tx1 $ty1 $text $maxExtDisplay $normalTxtFill $outline $normalFill $callback $node $drawshadow $shadowColor
      }
      "loop" {
         set text "${text}\n[::FlowNodes::getLoopInfo $node]"
         ::DrawUtils::drawOval $canvas $tx1 $ty1 $text $maxExtDisplay $normalTxtFill $outline $normalFill $callback $node $drawshadow $shadowColor
      }
      "case" {
         ::DrawUtils::drawLosange $canvas $tx1 $ty1 $text $normalTxtFill $outline $normalFill $callback $node $drawshadow $shadowColor
      }
      "outlet" {
         ::DrawUtils::drawOval $canvas $tx1 $ty1 $text $maxExtDisplay $normalTxtFill $outline $normalFill $callback $node $drawshadow $shadowColor
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

   #::FlowNodes::setDisplayLimits $node $canvas
   if { $isCollapsed == 0 } {
      # get the childs to display
      if { !(($children == "none") ||  ($children == ""))} {
         set nodePosition 0
         foreach child $children {
            #DEBUG "drawNode drawing subjob:$subjob" 5
            set childNode $node/$child
            drawNode $canvas $childNode $node $nodePosition $run_catchup $callback
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
   $popMenu add command -label "Node History" -command [list historyCallback $node $canvas $popMenu 0 ]
   $popMenu add command -label "Node Info" -command [list nodeInfoCallback $node $canvas $popMenu]
   if { [$node cget -flow.type] == "loop" } {
      $popMenu add command -label "Loop Listing" -command [list listingCallback $node $canvas $popMenu 1]
      $popMenu add command -label "Loop Abort Listing" -command [list abortListingCallback $node $canvas $popMenu 1]
      $popMenu add command -label "Loop Node Batch" -command [list batchCallback $node $canvas $popMenu 1]
      $popMenu add command -label "Member Listing" -command [list listingCallback $node $canvas $popMenu]
      $popMenu add command -label "Member Abort Listing" -command [list abortListingCallback $node $canvas $popMenu]
      $popMenu add command -label "Member Node Batch" -command [list batchCallback $node $canvas $popMenu 0]
      $popMenu add command -label "New Window" -command [list newWindowCallback $node $canvas $popMenu]
      $popMenu add separator
      $popMenu add checkbutton -label "Ignore Dependency" -onvalue " -i" -offvalue "" -variable ignoreDep 
      $popMenu add command -label "Loop Submit" -command [list submitLoopCallback $node $canvas $popMenu continue ]
      $popMenu add command -label "Member Submit" -command [list submitCallback $node $canvas $popMenu continue ]
      $popMenu add separator
      $popMenu add command -label "Loop End" -command [list endLoopCallback $node $canvas $popMenu]
      $popMenu add command -label "Loop Initbranch" -command [list initbranchLoopCallback $node $canvas $popMenu]
      $popMenu add command -label "Member End" -command [list endCallback $node $canvas $popMenu]
      $popMenu add command -label "Member Initbranch" -command [list initbranchCallback $node $canvas $popMenu]
   } else {
      $popMenu add command -label "Node Listing" -command [list listingCallback $node $canvas $popMenu]
      $popMenu add command -label "All Node Listing" -command [list allListingCallback $node $canvas $popMenu success]
      $popMenu add command -label "Node Abort Listing" -command [list abortListingCallback $node $canvas $popMenu]
      $popMenu add command -label "All Node Abort Listing" -command [list allListingCallback $node $canvas $popMenu abort]
      $popMenu add command -label "Node Batch" -command [list batchCallback $node $canvas $popMenu ]
      $popMenu add command -label "New Window" -command [list newWindowCallback $node $canvas $popMenu]
      $popMenu add separator
      $popMenu add checkbutton -label "Ignore Dependency" -onvalue " -i" -offvalue "" -variable ignoreDep 
      if { [$node cget -flow.type] != "task" && [$node cget -flow.type] != "npass_task"} {
         $popMenu add command -label "Submit" -command [list submitCallback $node $canvas $popMenu continue ]
      } else {
         if { [$node cget -flow.type] == "npass_task"} {
            $popMenu add command -label "Submit & Continue" -command [list submitNpassTaskCallback $node $canvas $popMenu continue ]
            $popMenu add command -label "Submit & Stop" -command [list submitNpassTaskCallback $node $canvas $popMenu stop ]
            $popMenu add command -label "Node Source" -command [list sourceCallback $node $canvas $popMenu ]
         } else {
            $popMenu add command -label "Submit & Continue" -command [list submitCallback $node $canvas $popMenu continue ]
            $popMenu add command -label "Submit & Stop" -command [list submitCallback $node $canvas $popMenu stop ]
            $popMenu add command -label "Node Source" -command [list sourceCallback $node $canvas $popMenu ]
         }
      }
      $popMenu add command -label "Node Config" -command [list configCallback $node $canvas $popMenu ]
      $popMenu add separator
      if { [$node cget -flow.type] != "task" && [$node cget -flow.type] != "npass_task"} {
         $popMenu add command -label "Initbranch" -command [list initbranchCallback $node $canvas $popMenu]
      } else {
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
      set dateStamp [$suiteRecord cget -active_log]
      if { $dateStamp == "" } {
          set dateStamp [retrieveDateStamp $canvas $suiteRecord]
      }

      Sequencer_runCommand [$suiteRecord cget -suite_path] $seqExec \
         "Node History [file tail $node]$nodeExt -history $history" \
         -n $seqNode$nodeExt -history $history -edate $dateStamp 
   }
}

proc nodeInfoCallback { node canvas caller_menu } {
   global env
   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]
   set suiteName [$suiteRecord cget -suite_name]
   set nodeTail [file tail $node]
   set infoWidget .${suiteName}_${nodeTail}_nodeInfo

   set depAttrMap { "Dep Hour" "Dep Type" "Dep Status" "Dep Suite" "Dep User" }
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
   set seqLoopArgs [::FlowNodes::getLoopArgs $node]
   set code [catch {eval [exec ksh -c "export SEQ_EXP_HOME=${seqExpHome};${nodeInfoExec} -n $seqNode  ${seqLoopArgs} > ${outputFile}"]} message]

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
      Sequencer_runCommand [$suiteRecord cget -suite_path] $seqExec "initbranch [file tail $node] $seqLoopArgs" -n $seqNode -s initbranch -f continue $seqLoopArgs
   }
   #$node configure -flow.status initialize
   #::DrawUtils::drawNodeStatus $node
   destroy $caller_menu
}

proc initnodeCallback { node canvas caller_menu } {
   set seqExec "[getGlobalValue SEQ_BIN]/maestro"
   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]
   set seqNode [::FlowNodes::getSequencerNode $node]
   set seqLoopArgs [::FlowNodes::getLoopArgs $node]
   if { $seqLoopArgs == "" && [::FlowNodes::hasLoops $node] } {
      raiseError $canvas "initnode" [getErrorMsg NO_LOOP_SELECT]
   } else {
      Sequencer_runCommand [$suiteRecord cget -suite_path] $seqExec "initnode [file tail $node] $seqLoopArgs" -n $seqNode -s initnode -f continue $seqLoopArgs
   }
   destroy $caller_menu
}

proc initbranchLoopCallback { node canvas caller_menu } {
   set seqExec "[getGlobalValue SEQ_BIN]/maestro"
   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]
   set seqNode [::FlowNodes::getSequencerNode $node]
   set seqLoopArgs [::FlowNodes::getParentLoopArgs $node]
   if { $seqLoopArgs == "-1" && [::FlowNodes::hasLoops $node] } {
      raiseError $canvas "initbranch" [getErrorMsg NO_LOOP_SELECT]
   } else {
      Sequencer_runCommand [$suiteRecord cget -suite_path] $seqExec "initbranch [file tail $node] $seqLoopArgs" -n $seqNode -s initbranch -f continue $seqLoopArgs
   }
   destroy $caller_menu
}

proc abortCallback { node canvas caller_menu } {
   set seqExec "[getGlobalValue SEQ_BIN]/maestro"
   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]
   set seqNode [::FlowNodes::getSequencerNode $node]
   set seqLoopArgs [::FlowNodes::getLoopArgs $node]
   if { $seqLoopArgs == "" && [::FlowNodes::hasLoops $node] } {
      raiseError $canvas "node abort" [getErrorMsg NO_LOOP_SELECT]
   } else {
      Sequencer_runCommand [$suiteRecord cget -suite_path] $seqExec "abort [file tail $node] $seqLoopArgs" -n $seqNode -s abort -f continue $seqLoopArgs
   }
   destroy $caller_menu
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
   destroy $caller_menu
}

proc endCallback { node canvas caller_menu } {
   set seqExec "[getGlobalValue SEQ_BIN]/maestro"

   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]

   set seqNode [::FlowNodes::getSequencerNode $node]
   set seqLoopArgs [::FlowNodes::getLoopArgs $node]
   if { $seqLoopArgs == "" && [::FlowNodes::hasLoops $node] } {
      raiseError $canvas "node end" [getErrorMsg NO_LOOP_SELECT]
   } else {
      Sequencer_runCommand [$suiteRecord cget -suite_path] $seqExec "end [file tail $node] $seqLoopArgs" -n $seqNode -s end -f continue $seqLoopArgs
   }

   destroy $caller_menu
}

proc endLoopCallback { node canvas caller_menu } {
   set seqExec "[getGlobalValue SEQ_BIN]/maestro"

   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]

   set seqNode [::FlowNodes::getSequencerNode $node]
   set seqLoopArgs [::FlowNodes::getParentLoopArgs $node]
   if { $seqLoopArgs == "-1" && [::FlowNodes::hasLoops $node] } {
      raiseError $canvas "loop end" [getErrorMsg NO_LOOP_SELECT]
   } else {
      Sequencer_runCommand [$suiteRecord cget -suite_path] $seqExec "end [file tail $node] $seqLoopArgs" -n $seqNode -s end -f continue $seqLoopArgs
   }
   destroy $caller_menu
}

proc sourceCallback { node canvas caller_menu} {
   set seqExec "[getGlobalValue SEQ_UTILS_BIN]/nodesource"
   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]
   set seqNode [::FlowNodes::getSequencerNode $node]
   Sequencer_runCommand [$suiteRecord cget -suite_path] $seqExec "Node Source [file tail $node]" -n $seqNode
   destroy $caller_menu
}

proc configCallback { node canvas caller_menu} {
   set seqExec "[getGlobalValue SEQ_UTILS_BIN]/nodeconfig"
   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]
   set seqNode [::FlowNodes::getSequencerNode $node]
   Sequencer_runCommand [$suiteRecord cget -suite_path] $seqExec "Node Config [file tail $node]" -n $seqNode
   destroy $caller_menu
}

proc batchCallback { node canvas caller_menu {full_loop 0} } {
   set seqExec "[getGlobalValue SEQ_UTILS_BIN]/nodebatch"
   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]

   set seqNode [::FlowNodes::getSequencerNode $node]
   set nodeExt [::FlowNodes::getListingNodeExtension $node $full_loop]
   if { $nodeExt == "-1" } {
      raiseError $canvas "node listing" [getErrorMsg NO_LOOP_SELECT]
   } else {
      if { $nodeExt != "" } {
         set nodeExt ".${nodeExt}"
      }
      Sequencer_runCommand [$suiteRecord cget -suite_path] $seqExec "batch file [file tail $node]$nodeExt " -n $seqNode$nodeExt 
   }
   destroy $caller_menu
}

proc submitCallback { node canvas caller_menu flow } {
   global ignoreDep

   set seqExec "[getGlobalValue SEQ_BIN]/maestro"

   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]

   set seqNode [::FlowNodes::getSequencerNode $node]
   set seqLoopArgs [::FlowNodes::getLoopArgs $node]
   if { $seqLoopArgs == "" && [::FlowNodes::hasLoops $node] } {
      raiseError $canvas "node submit" [getErrorMsg NO_LOOP_SELECT]
   } else {
      Sequencer_runCommand [$suiteRecord cget -suite_path] $seqExec "submit [file tail $node] $seqLoopArgs" -n $seqNode -s submit -f $flow $ignoreDep $seqLoopArgs
   }

   destroy $caller_menu
}

proc submitLoopCallback { node canvas caller_menu flow} {
   set seqExec "[getGlobalValue SEQ_BIN]/maestro"

   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]

   set seqNode [::FlowNodes::getSequencerNode $node]
   set seqLoopArgs [::FlowNodes::getParentLoopArgs $node]
   if { $seqLoopArgs == "-1" && [::FlowNodes::hasLoops $node] } {
      raiseError $canvas "loop submit" [getErrorMsg NO_LOOP_SELECT]
   } else {
      Sequencer_runCommand [$suiteRecord cget -suite_path] $seqExec "submit [file tail $node] $seqLoopArgs" -n $seqNode -s submit -f $flow $seqLoopArgs   
   }
   destroy $caller_menu
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
      set seqNpassTaskArgs [::FlowNodes::getNpassTaskArgs ${node} ${indexListValue}]
   
      if { $seqNpassTaskArgs == "-1" } {
         raiseError $canvas "Npass_Task submit" [getErrorMsg NO_INDEX_SELECT]
      } else {
         Sequencer_runCommand [$suiteRecord cget -suite_path] $seqExec "submit [file tail $node] $seqNpassTaskArgs" -n $seqNode -s submit -f $flow $ignoreDep $seqNpassTaskArgs   
      }
   }
   destroy $caller_menu
}

proc listingCallback { node canvas caller_menu {full_loop 0} } {
   DEBUG "listingCallback node:$node canvas:$canvas" 5
   set listingExec [getGlobalValue SEQ_UTILS_BIN]/nodelister
   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]

   set seqNode [::FlowNodes::getSequencerNode $node]
   set nodeExt [::FlowNodes::getListingNodeExtension $node $full_loop]
   set datestamp [getMonitoringDatestamp]
   if { $nodeExt == "-1" } {
      raiseError $canvas "node listing" [getErrorMsg NO_LOOP_SELECT]
   } else {
      if { $nodeExt != "" } {
         set nodeExt ".${nodeExt}"
      }
      Sequencer_runCommand [$suiteRecord cget -suite_path] $listingExec "listing [file tail $node]${nodeExt}.$datestamp " -n $seqNode$nodeExt -d $datestamp
   }
   destroy $caller_menu
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

   destroy $caller_menu

}

proc showAllListingItem { suite_record listw list_type} {
   DEBUG "showAllListingItem selection: [$listw curselection]" 5
   set selectedIndexes [$listw curselection]
   set listingExec [getGlobalValue SEQ_UTILS_BIN]/nodelister
   set suitePath [${suite_record} cget -suite_path]

   foreach selectIndex $selectedIndexes {
      set selectedValue [$listw get $selectIndex]
      if { [string first "On " $selectedValue] != 0 } {
         set splittedArgs [split $selectedValue]
         set listingFile [lindex $splittedArgs end]
         set splittedFile [split [file tail $listingFile] .]
         if { [llength $splittedFile] == 6 } {
            set wTitle "[lindex $splittedFile 0].[lindex $splittedFile 1].[lindex $splittedFile 4].[lindex $splittedFile 5]"
         } else {
            set wTitle "[lindex $splittedFile 0].[lindex $splittedFile 3].[lindex $splittedFile 4]"
         }
         Sequencer_runCommand $suitePath $listingExec "${list_type} listing ${wTitle}" -f $listingFile
      }
   }
}

proc abortListingCallback { node canvas caller_menu {full_loop 0} } {
   DEBUG "abortListingCallback node:$node canvas:$canvas" 5
   set abortListingExec [getGlobalValue SEQ_UTILS_BIN]/nodelister
   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]
   set seqNode [::FlowNodes::getSequencerNode $node]
   set nodeExt [::FlowNodes::getListingNodeExtension $node $full_loop]
   set datestamp [getMonitoringDatestamp]
   if { $nodeExt == "-1" } {
      raiseError $canvas "node abort listing" [getErrorMsg NO_LOOP_SELECT]
   } else {
      if { $nodeExt != "" } {
         set nodeExt ".${nodeExt}"
      }
      Sequencer_runCommand [$suiteRecord cget -suite_path] $abortListingExec "abort listing [file tail $node]${nodeExt}.${datestamp}" -n $seqNode$nodeExt -type abort -d $datestamp
   }
   destroy $caller_menu
}


proc cleanLogCallback { canvas caller_menu } {
   DEBUG "cleanLogCallback canvas:$canvas" 5
   set suiteRecord [::SuiteNode::getSuiteRecord $canvas]
   set suitePath [$suiteRecord cget -suite_path]
   set logfile $suitePath/logs/firsin
   Sequencer_runCommand [$suiteRecord cget -suite_path] cp "Clean Log $logfile" /dev/null $logfile
   destroy $caller_menu
   puts "**************************************************************************************"
   puts [ $suiteRecord cget -read_offset ]
   $suiteRecord configure -read_offset 0
   puts "**************************************************************************************"
   puts [ $suiteRecord cget -read_offset ]
   # LogReader_readFile $suiteRecord

   drawflow $canvas
}


proc npassTaskSelectionCallback { node canvas combobox_w} {
   DEBUG "npassTaskSelectionCallback node:$node $combobox_w" 5

   set member [${combobox_w} get]

   if { $member != "latest" && [lindex $member 0] != "+" } {
      set member +${member}
   }
   $node configure -current $member
   drawflow $canvas
}

proc loopSelectionCallback { node canvas combobox_w} {
   DEBUG "loopSelectionCallback node:$node $combobox_w" 5

   set member [${combobox_w} get]

   if { $member != "latest" && [lindex $member 0] != "+" } {
      set member +${member}
   }
   $node configure -current $member
   drawflow $canvas
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

proc redrawAllFlow { suite_record } {
   set canvasList [::SuiteNode::getCanvasList ${suite_record}]
   foreach canvasW $canvasList {
      drawflow $canvasW 0
   }
}

proc drawflow { canvas {initial_display "1"} } {
   DEBUG "drawflow() canvas:$canvas" 5
   if { [winfo exists ${canvas}] } {
      ::DrawUtils::clearCanvas $canvas

      set suiteRecord [::SuiteNode::getSuiteRecord $canvas]
      # reset the default spacing for drawing flow
      ::SuiteNode::resetDisplayNextY $suiteRecord $canvas
      set rootNode [::SuiteNode::getDisplayRoot $suiteRecord $canvas]
   
      set callback changeCollapsed
      drawNode $canvas $rootNode "" 0 5 $callback
      set canvasArea [$canvas bbox all]
      $canvas  configure -scrollregion $canvasArea -yscrollincrement 5 -xscrollincrement 5
   
      # resize the window depending on size of canvas elements
      set boxCoords [${canvas} bbox all]
      set heightMax 800
      set widthMax 1200
      set canvasH [expr [lindex ${boxCoords} 3] - [lindex ${boxCoords} 1]]
      set canvasW [expr [lindex ${boxCoords} 2] - [lindex ${boxCoords} 0]]
      set windowH [expr ${canvasH} + 135]
      set windowW [expr ${canvasW} + 50]
      if { [expr ${windowH} > ${heightMax}] } {
         set windowH ${heightMax}
      }
      if { [expr ${windowW} > ${widthMax}] } {
         set windowW ${widthMax}
      }
      wm geometry . =${windowW}x${windowH}
   
      if { $initial_display == "1" } {
         $canvas yview moveto 0
      }
      xflow_testAddCanvasBg ${canvas} ${canvasH} ${canvasW}
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
   if { [$node cget -record_type] == "FlowTask" } {
      # the next command runs nodeinfo and converts each line of the output
      # into a tcl command
      set code [catch {set output [exec ksh -c "export SEQ_EXP_HOME=${suite_path};${nodeInfoExec} -n ${seqNode} -f res |  sed -e 's:node.:$node configure -:' -e 's:=: :' > ${outputFile}"]} message]
   
      if { $code != 0 } {
         raiseError . "Get Node Resource" $message
         return 0
      }
      if [ catch { eval eval [exec cat ${outputFile}] } message ] {
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
      image create photo ${canvas}.bg_image -width ${canvasBgImageWidth} -height ${canvasBgImageHeight} -file ${imageDir}/Sheet_Music_6.ppm

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
  set ERROR_MSG_LIST(NO_INDEX_SELECT) "You must provide an index value for this node!"
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

   DEBUG "exiting Xflow ..." 5
   set suiteRecord [getActiveSuite]
   set isOverviewMode [SharedData_getMiscData OVERVIEW_MODE]

   if { ${isOverviewMode} == "true" } {
      # we are in overview mode
      set childWidgets [winfo children .]
      foreach childW ${childWidgets} {
         destroy ${childW}
      }
      set overviewThreadId [SharedData_getMiscData OVERVIEW_THREAD_ID]
      thread::send -async ${overviewThreadId} "Overview_childQuit ${suiteRecord} [thread::id]"
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
         xflow_testAddCanvasBg ${canvasWidget} ${canvasH} ${canvasW}
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

proc launchXflow { calling_thread_id } {
   global env XFLOW_STANDALONE

   set topFrame .top
   if { ! [winfo exists ${topFrame}] } { 
      DEBUG "launchXflow ${calling_thread_id}" 5
      
      set suiteList {}
      set suitesFile $env(HOME)/.suites/.xflow.suites.xml
      if { [info exists env(SEQ_EXP_HOME)] } {
         set activeSuite $env(SEQ_EXP_HOME)
         set suiteList [linsert $suiteList 0 $env(SEQ_EXP_HOME)] 
         SharedData_setSuiteData $env(SEQ_EXP_HOME) THREAD_ID [thread::id]
      } elseif { [file exists $suitesFile] } {
         ExpXmlReader_readExperiments $suitesFile
         set suiteList [ExpXmlReader_getExpList]
         DEBUG "suiteList: $suiteList"
         set activeSuite [lindex $suiteList 0]
      } else {
         FatalError . "Xflow Startup Error" "\${HOME}/.suites/.xflow.suites.xml configuration file does not exists & SEQ_EXP_HOME not set! Exiting..."
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
      set AUTO_MSG_DISPLAY true
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
   global env DEBUG_ON DEBUG_LEVEL
   global NODE_DISPLAY_PREF AUTO_MSG_DISPLAY
   global SHADOW_STATUS MONITORING_LATEST
   global MSG_CENTER_THREAD_ID MONITOR_THREAD_ID

   set MONITOR_THREAD_ID ""
   set NODE_DISPLAY_PREF 1
   set SHADOW_STATUS 0
   set MONITORING_LATEST 1

   SharedData_setMiscData SEQ_BIN [Sequencer_getPath]
   SharedData_setMiscData SEQ_UTILS_BIN [Sequencer_getUtilsPath]
   SharedData_setMiscData IMAGE_DIR $env(SEQ_XFLOW_BIN)/../etc/images

   set DEBUG_ON [SharedData_getMiscData DEBUG_TRACE]
   set DEBUG_LEVEL [SharedData_getMiscData DEBUG_LEVEL]
   set MSG_CENTER_THREAD_ID [MsgCenter_getThread]
   SharedData_setMiscData XFLOW_THREAD_ID [thread::id]
   if { ! [info exists AUTO_MSG_DISPLAY] } {
      set AUTO_MSG_DISPLAY [SharedData_getMiscData AUTO_MSG_DISPLAY]
   } else {
      puts "xflow_init SharedData_setMiscData AUTO_MSG_DISPLAY ${AUTO_MSG_DISPLAY}"
      SharedData_setMiscData AUTO_MSG_DISPLAY ${AUTO_MSG_DISPLAY}
   }

   setErrorMessages

   setTkOptions

   # initGlobals

   keynav::enableMnemonics .
   wm protocol . WM_DELETE_WINDOW quitXflow
}

global XFLOW_STANDALONE

parseCmdOptions
if { ${XFLOW_STANDALONE} == 1 } {

   SharedData_init
   xflow_init
   launchXflow [thread::id]
   SharedData_setMiscData STARTUP_DONE true
}
