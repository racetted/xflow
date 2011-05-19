proc LogReader_readFile { suite_record calling_thread_id } {
   global MONITOR_THREAD_ID REDRAW_FLOW
   DEBUG "LogReader_readFile suite_record:$suite_record calling_thread_id:$calling_thread_id"
   set REDRAW_FLOW false
   set isOverviewMode [SharedData_getMiscData OVERVIEW_MODE]
   set isStartupDone [SharedData_getMiscData STARTUP_DONE]
   set thisThreadId [thread::id]
   SharedData_setMiscData ${thisThreadId}_CALLING_THREAD_ID ${calling_thread_id}


   set isThreadStartupDone [SharedData_getMiscData ${thisThreadId}_STARTUP_DONE]
   if { ${isThreadStartupDone} == "true" } {
      set isStartupDone true
   }
   
   # first cancel any other waiting read for this suite
   LogReader_cancelAfter $suite_record
   set suitePath [$suite_record cget -suite_path]
   set dateExec "[SharedData_getMiscData SEQ_BIN]/tictac"
   set expDate ""
   set monitorLog [$suite_record cget -active_log]
   if { $monitorLog == "" } {
      # view latest mode, fetch the exp datestamp
      set cmd "export SEQ_EXP_HOME=$suitePath;$dateExec -f '%Y%M%D%H%Min%S'"
      set expDate ""
      if [ catch { set expDate [exec ksh -c $cmd] } message ] {
         puts "ERROR: $message"
      }

      set logfile $suitePath/logs/${expDate}_nodelog
      set expLog [ ${suite_record} cget -exp_log ]
      if { ${expLog} == "" } {
         ${suite_record} configure -exp_log ${logfile}
      }
      if { ${expLog} != ${logfile} } {
         # new log detected, advise main thread of this event
         if { "${isOverviewMode}" == "false" } {
            # we are in standalone xflow mode
            thread::send -async ${calling_thread_id} \
            "xflow_datestampChanged ${suite_record}"
         } elseif { ${thisThreadId} != ${MONITOR_THREAD_ID} } {
            puts "LogReader_readFile reading new log file $logfile"
            # send event to overview mode
            set overviewThreadId [SharedData_getMiscData OVERVIEW_THREAD_ID]
            thread::send -async ${overviewThreadId} \
            "Overview_ExpDateStampChanged ${suite_record} ${logfile}"
            # send event to own xflow
            thread::send ${thisThreadId} "xflow_datestampChanged ${suite_record}"
         }
         ${suite_record} configure -read_offset 0 -exp_log ${logfile}
         if { ${expLog} != "" } {
            # means that the datestamp changed while we are monitoring a existing one
            # set the exp in startup mode
            SharedData_setMiscData ${thisThreadId}_STARTUP_DONE false
            set isStartupDone false
            # force a redraw at the end of the read
            set REDRAW_FLOW true
            # re-init all nodes
            set rootNode [${suite_record} cget -root_node]
            ::FlowNodes::resetAllStatus ${rootNode} init 1
         }
         puts "LogReader_readFile reading new log file previous:${expLog} new:$logfile"
      }
   } else {
      # view history mode
      set logfile $suitePath/logs/${monitorLog}_nodelog
   }
   DEBUG "LogReader_readFile calling_thread_id:$calling_thread_id date:[exec date] suite:[$suite_record cget -suite_path] file:[file tail $logfile]"

   if { [file exists $logfile] } {
      set f_logfile [ open $logfile r ]
      flush stdout
      
      if { ${isStartupDone} == "true" } {
         set logFileOffset [$suite_record cget -read_offset]
      } else {
         set logFileOffset 0
      }

      # position yourself in the file
      seek $f_logfile $logFileOffset
      
      while {[gets $f_logfile line] >= 0} {
         if { ${isOverviewMode} == "true" && ${thisThreadId} != ${MONITOR_THREAD_ID} } {
            LogReader_processOverviewLine $calling_thread_id $suite_record $line
         }
         LogReader_processLine $calling_thread_id $suite_record $line
      }
      
      # Need to notify the main thread that this child is done reading
      # the log file for initialization
      if { ${isStartupDone} == "false" && ${isOverviewMode} == "true" && ${thisThreadId} != ${MONITOR_THREAD_ID} } {
            thread::send -async ${calling_thread_id} \
               "Overview_childInitDone [${suite_record} cget -suite_path] ${calling_thread_id}"
      }

      $suite_record configure -read_offset [tell $f_logfile]
      close $f_logfile
   } else {
      puts "LogReader_readFile $logfile file does not exists! Creating it..."
      close [open $logfile a]
   }

   if { ${REDRAW_FLOW} == true } {
      SharedData_setMiscData ${thisThreadId}_STARTUP_DONE true
      xflow_redrawAllFlow
   }
   LogReader_readAgain $suite_record $calling_thread_id
}

proc LogReader_readAgain { suite_record calling_thread_id } {
   global ${suite_record}_READ_LOG_IDS
   
   set READ_INTERVAL [$suite_record cget -read_interval]
   catch { set ${suite_record}_READ_LOG_IDS [after $READ_INTERVAL [list LogReader_readFile $suite_record  $calling_thread_id]]}
}

proc LogReader_cancelAfter { suite_record } {
   global ${suite_record}_READ_LOG_IDS
   if { [info exists ${suite_record}_READ_LOG_IDS] } {
      after cancel [set ${suite_record}_READ_LOG_IDS]
   }

}

# this is meant to be running inside a child thread
proc LogReader_processOverviewLine { calling_thread_id suite_record line } {  
   DEBUG "LogReader_processOverviewLine suite_record:$suite_record line:$line" 5

   set nodeIndex [string first "SEQNODE=" $line]
   set typeIndex [string first "MSGTYPE=" $line $nodeIndex]
   set loopIndex [string first "SEQLOOP=" $line $typeIndex]
   set msgIndex [string first "SEQMSG=" $line $typeIndex]
   set nodeStartIndex [expr $nodeIndex + 8]
   set nodeEndIndex [expr $typeIndex - 2]
   set typeStartIndex [expr $typeIndex + 8]
   set loopEndIndex end
   set loopExt ""
   if { $loopIndex != -1 } {
      set typeEndIndex [expr $loopIndex -2]
      set loopStartIndex [expr $loopIndex + 8]
   }
   if { $msgIndex == -1 && $loopIndex == -1 } {
      set typeEndIndex end
   }

   if { $msgIndex != -1 } {
      set loopEndIndex [expr $msgIndex - 2]
      if { $loopIndex == -1 } {
         set typeEndIndex [expr $msgIndex -2]
      }
      set msgStartIndex [expr $msgIndex + 7]
   }

   if { $nodeIndex == -1 || $typeIndex == -1 } {
      puts "LogReader_processOverviewLine invalid line ignored:$line"   
   } else {
      # TIMESTAMP=20100908.19:19:42
      set timestamp [string range $line 10 [expr $nodeIndex - 2]]
      set node [string range $line $nodeStartIndex $nodeEndIndex]
      set type [string range $line $typeStartIndex $typeEndIndex]
      set msg ""
      if { ! ($node == "" || $type == "") } {
         # abortx, endx, beginx type are used for signals we send to the parent containers nodes
         # as a ripple effect... However, in the case of abort messages we don't want these collateral signals
         # to appear in the message center... At this point, we can reset abortx to abort, endx to end and so forth
         if { ${type} != "beginx" } {
            catch { set type $::DrawUtils::rippleStatusMap(${type}) }
         }
         if { $loopIndex != -1 } {
            set loopExt [string range $line $loopStartIndex $loopEndIndex]
         }
         if { $msgIndex != -1 } {
            set msg [string range $line $msgStartIndex end]
         }
         if { ${type} == "init" || ${type} == "begin" || ${type} == "beginx" 
              || ${type} == "abort" || ${type} == "end" 
              || ${type} == "wait" || ${type} == "submit" || ${type} == "catchup" } {
            if { ${node} == [${suite_record} cget -root_node] } {
               set currentDatestamp [::SuiteNode::getActiveDatestamp ${suite_record}]
               DEBUG "LogReader_processOverviewLine time:$timestamp node=$node type=$type" 5
               thread::send -async ${calling_thread_id} \
                  "Overview_updateExp  ${suite_record} ${currentDatestamp} ${type} ${timestamp}"
            }
         }
      }
   }
}

proc LogReader_processLine { calling_thread_id suite_record line } {
   global MSG_CENTER_THREAD_ID
   DEBUG "LogReader_processLine line:$line" 5
   # node & signal is mandatory to be processed
   # else the line is ignored
   set loopInfoDisplay ""
   set extDisplay ""

   set nodeIndex [string first "SEQNODE=" $line]
   set typeIndex [string first "MSGTYPE=" $line $nodeIndex]
   set loopIndex [string first "SEQLOOP=" $line $typeIndex]
   set msgIndex [string first "SEQMSG=" $line $typeIndex]
   set nodeStartIndex [expr $nodeIndex + 8]
   set nodeEndIndex [expr $typeIndex - 2]
   set typeStartIndex [expr $typeIndex + 8]
   set loopEndIndex end
   set loopExt ""
   if { $loopIndex != -1 } {
      set typeEndIndex [expr $loopIndex -2]
      set loopStartIndex [expr $loopIndex + 8]
   }
   if { $msgIndex == -1 && $loopIndex == -1 } {
      set typeEndIndex end
   }

   if { $msgIndex != -1 } {
      set loopEndIndex [expr $msgIndex - 2]
      if { $loopIndex == -1 } {
         set typeEndIndex [expr $msgIndex -2]
      }
      set msgStartIndex [expr $msgIndex + 7]
   }

   if { $nodeIndex == -1 || $typeIndex == -1 } {
      puts "LogReader_processLine invalid line ignored:$line"   
   } else {
      set timestamp [string range $line 10 26]
      set node [string range $line $nodeStartIndex $nodeEndIndex]
      set flowNode [::SuiteNode::getFlowNodeMapping $suite_record $node]
      set type [string range $line $typeStartIndex $typeEndIndex]
      set msg ""
      puts "LogReader_processLine node:$node flowNode:$flowNode"
      if { $type != "" } {
         if { $loopIndex != -1 } {
            set loopExt [string range $line $loopStartIndex $loopEndIndex]
         }
         if { $msgIndex != -1 } {
            set msg [string range $line $msgStartIndex end]
         }
         # send message to message center
         if { ${type} == "abort" || ${type} == "info" || ${type} == "event" } {
            if { ${node} == "" } {
               set msgNode NONE
            } else {
               set msgNode ${node}
            }
            set expPath [${suite_record} cget -suite_path]
            set currentDatestamp [::SuiteNode::getActiveDatestamp ${suite_record}]
            thread::send -async ${MSG_CENTER_THREAD_ID} \
               "MsgCenterThread_newMessage \"${currentDatestamp}\" ${timestamp} ${type} ${msgNode}${loopExt} ${expPath} \"${msg}\""
            # Console_insertMessage "EXP:[${suite_record} cget -suite_path] ${timestamp} ${node} ${type} ${msg}"
         }
         # abortx, endx, beginx type are used for signals we send to the parent containers nodes
         # as a ripple effect... However, in the case of abort messages we don't want these collateral signals
         # to appear in the message center... At this point, we can reset abortx to abort, endx to end and so forth
         set finalCmd ""
         if { $node != "" } {

            if { [info exists ::DrawUtils::rippleStatusMap(${type})] } {
               set type $::DrawUtils::rippleStatusMap(${type})

               DEBUG "LogReader_processLine node=$node flowNode:$flowNode loopExt:$loopExt type=$type" 5
               DEBUG "LogReader_processLine message=$msg" 5
               if { [record exists instance $flowNode] } {
                  # 1 - first we take care of setting the node status
                  if { [string tolower $type] == "init" } {
                     if { [$flowNode cget -flow.type] == "loop" } {
                        if { $loopExt != "" } {
                           
                           FlowNodes::setMemberStatus $flowNode $loopExt $type ${timestamp} 1
                        } else {
                           # we got an update on the whole loop
                           FlowNodes::resetAllStatus $flowNode init 1
                        }
                     } else { 
                        # current node is not loop
                        if { [$flowNode cget -flow.loops] != "" } {
                           # part of parent loop container
                           FlowNodes::setMemberStatus $flowNode $loopExt $type ${timestamp} 1
                        } else {
                           ::FlowNodes::resetNodeStatus $flowNode 
                        }
                     }
                  } else {
                     # not init state, any other
                     if { [$flowNode cget -flow.type] == "loop" || [$flowNode cget -flow.type] == "npass_task" } {
                        if { $loopExt != "" } {
                           # we got an update on a loop iteration
                           FlowNodes::setMemberStatus $flowNode $loopExt $type ${timestamp} 0
                        } else {
                           # we got an update on the whole loop
                           FlowNodes::setMemberStatus $flowNode all $type ${timestamp}
                        }
                     } else { 
                        # current node is not loop
                        FlowNodes::setMemberStatus $flowNode $loopExt $type ${timestamp}
                     }
                  }
      
                  # 2 - then we refresh the display... redisplay the node text?
                  set thisThreadId [thread::id]
                  set isThreadStartupDone [SharedData_getMiscData ${thisThreadId}_STARTUP_DONE]
                  if { [SharedData_getMiscData STARTUP_DONE] == "true" && ${isThreadStartupDone} == "true" &&
                     [::FlowNodes::isRefreshNeeded ${flowNode} ${loopExt} ] == "true" } {
                     xflow_redrawNodes ${flowNode}
                  }
               }
            }
         }
      }
   }
}

# the date is sorted in reverse order, the most recent date will appear first
proc LogReader_getAvailableDates { exp_path } {
   set cmd "cd ${exp_path}/logs; ls *_nodelog | sed -e 's,_nodelog,,' | sort -r"
   set expLogs ""
   if [ catch { set expLogs [exec ksh -c $cmd] } message ] {
   }
   DEBUG "LogReader_getAvailableDates exp logs: $expLogs" 5
   return $expLogs
}


