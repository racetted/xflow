package require textutil::string
package require log

proc LogReader_startExpLogReader { exp_path datestamp {is_startup false} } {
   # puts "LogReader_startExpLogReader exp_path:$exp_path datestamp:$datestamp is_startup:$is_startup"
   global env this_id
   ::log::log debug "LogReader_startExpLogReader"

   global env DEBUG_TRACE
   global MSG_CENTER_THREAD_ID

   set DEBUG_TRACE [SharedData_getMiscData DEBUG_TRACE]
   set MSG_CENTER_THREAD_ID [SharedData_getMsgCenterThreadId]
   # SharedData_setMiscData XFLOW_THREAD_ID [thread::id]

   SharedData_setExpThreadId ${exp_path} "${datestamp}" [thread::id]

   ::log::log debug "LogReader_startExpLogReader exp_path=${exp_path} datestamp:${datestamp}"
   # puts "LogReader_startExpLogReader xflow_readFlowXml"

   if [ catch { 
      readMasterfile ${exp_path}/EntryModule/flow.xml ${exp_path} "" ""
   } message ] {
      set errMsg "Error Parsing flow.xml file ${exp_path}:\n$message"
      puts "${errMsg}"
      # tk_messageBox -title "Application Error!" -type ok -icon error \
      #   -message ${errMsg}
   }

   # puts "LogReader_startExpLogReader LogReader_readFile"
   if { ${is_startup} == true } {
      if { [LogMonitor_isLogFileActive ${exp_path} ${datestamp}] == false } {
         # inactive log
         # only send to overview and msg center, don't send to flow
         LogReader_readFile ${exp_path} ${datestamp} no_flow
         # release exp thread
         thread::send -async [SharedData_getMiscData OVERVIEW_THREAD_ID] "Overview_releaseExpThread [thread::id] ${exp_path} ${datestamp}"
      } else {
         # active log, we read the log files, send updates to overview, to msg center and to flow thread as well
         LogReader_readFile ${exp_path} ${datestamp} all
      }
   } else {
      # this is usually called when the user launches a flow from the overview,
      # at that point we don't care about sending updates to overview or msg center cause it's already done
      # just launch the flow
      LogReader_readFile ${exp_path} ${datestamp} refresh_flow
   }
}

# read_type is one of all, no_overview, overview_only, msg_only, refresh_flow, no_flow
proc LogReader_readFile { exp_path datestamp {read_type no_overview} } {
   global LOGREADER_UPDATE_NODES REDRAW_NODES_EVENT
   ::log::log debug "LogReader_readFile exp_path:${exp_path} datestamp:${datestamp} read_type:${read_type}"
   set LOGREADER_UPDATE_NODES ""
   set isOverviewMode [SharedData_getMiscData OVERVIEW_MODE]
   if { ${isOverviewMode} == true } {
         set overviewThreadId [SharedData_getMiscData OVERVIEW_THREAD_ID]
   }
   set isStartupDone [SharedData_getMiscData STARTUP_DONE]

   set sendToOverview false
   set sendToFlow false
   set sendToMsgCenter false
   if { ${isOverviewMode} == true && (${read_type} == "all" || ${read_type} == "overview_only" || ${read_type} == "no_flow") } {
      set sendToOverview true
   }
   if { (${read_type} == "all" || ${read_type} == "no_overview" || ${read_type} == "refresh_flow" ) } {
      set sendToFlow true
   }
   if { (${read_type} == "all" || ${read_type} == "msg_only" || ${read_type} == "no_overview" || ${read_type} == "no_flow") } {
      set sendToMsgCenter true
   }
   
   # first cancel any other waiting read for this suite
   LogReader_cancelAfter ${exp_path}
   if { ${datestamp} != "" } {
      set logfile ${exp_path}/logs/${datestamp}_nodelog

      if { [file exists $logfile] } {
         set f_logfile [ open $logfile r ]
         flush stdout
         
         if { ${isStartupDone} == "true" } {
            set logFileOffset [SharedData_getExpDatestampOffset ${exp_path} ${datestamp}]
            ::log::log debug "LogReader_readFile exp_path:${exp_path} datestamp:${datestamp} read_offset:$logFileOffset"
         } else {
            ::log::log debug "LogReader_readFile exp_path:${exp_path} datestamp:${datestamp} reset read_offset"
            set logFileOffset 0
         }

         # position yourself in the file
         seek $f_logfile $logFileOffset

         while {[gets $f_logfile line] >= 0} {
            LogReader_processLine ${exp_path} ${datestamp} ${line} ${sendToOverview} ${sendToFlow} ${sendToMsgCenter}
         }
         SharedData_setExpDatestampOffset ${exp_path} ${datestamp} [tell $f_logfile]
         SharedData_setExpStartupDone ${exp_path} ${datestamp} true
         close $f_logfile

      } else {
         if { [file writable ${exp_path}/logs/] } {
            puts "LogReader_readFile $logfile file does not exists! Creating it..."
            catch { close [open $logfile a] }
         } else {
            puts "LogReader_readFile $logfile file does not exists!"
         }
      }
   }

   # Need to notify the main thread that this child is done reading
   # the log file for initialization
   if { ${isStartupDone} == "false" && ${isOverviewMode} == "true" } {
      thread::send -async ${overviewThreadId} "Overview_childInitDone ${exp_path} ${datestamp}"
   }

   if { ${LOGREADER_UPDATE_NODES} != "" } {
      # let gui knows that he needs to redraw using the LOGREADER_UPDATE_NODES
      set REDRAW_NODES_EVENT true

      # update highest node that was affected during this read
      # foreach updatedNode  ${LOGREADER_UPDATE_NODES} {
      #   xflow_redrawNodes ${updatedNode}
      # }
   }
   # special case for flow refresh
   if { ${read_type} == "refresh_flow" } {
      set read_type "all"
   }
   LogReader_readAgain ${exp_path} ${datestamp} ${read_type}
}

proc LogReader_readAgain { exp_path datestamp read_type } {
   global ${exp_path}_READ_LOG_IDS
   
   catch { set ${exp_path}_READ_LOG_IDS [after 4000 [list LogReader_readFile ${exp_path} ${datestamp} ${read_type}]]}
}

proc LogReader_cancelAfter { exp_path } {
   global ${exp_path}_READ_LOG_IDS
   if { [info exists ${exp_path}_READ_LOG_IDS] } {
      after cancel [set ${exp_path}_READ_LOG_IDS]
   }

}

proc LogReader_processLine { _exp_path _datestamp _line _toOverview _ToFlow _toMsgCenter } {
   global MSG_CENTER_THREAD_ID

   set nodeIndex 28
   set typeIndex [string first "MSGTYPE=" ${_line} $nodeIndex]
   if { $typeIndex == -1 } {
      puts "LogReader_processLine invalid line ignored:${_line} _exp_path:${_exp_path} ${_datestamp}"
      return
   }
   set loopIndex [string first "SEQLOOP=" ${_line} $typeIndex]
   set msgIndex [string first "SEQMSG=" ${_line} $typeIndex]
   set nodeStartIndex [expr $nodeIndex + 8]
   set nodeEndIndex [expr $typeIndex - 2]
   set typeStartIndex [expr $typeIndex + 8]
   set loopEndIndex end
   if { $loopIndex != -1 } {
      set typeEndIndex [expr $loopIndex -2]
      set loopStartIndex [expr $loopIndex + 8]
   }
   if { $msgIndex == -1 && $loopIndex == -1 } {
      set typeEndIndex end
   } else {
       set loopEndIndex [expr $msgIndex - 2]
      if { $loopIndex == -1 } {
         set typeEndIndex [expr $msgIndex -2]
      }
      set msgStartIndex [expr $msgIndex + 7]
 }

   set timestamp [string range ${_line} 10 [expr $nodeIndex - 2]]
   set node [string range ${_line} $nodeStartIndex $nodeEndIndex]
   set type [string range ${_line} $typeStartIndex $typeEndIndex]
   if { $type != "" } {
      if { $loopIndex != -1 } {
         set loopExt [string range ${_line} $loopStartIndex $loopEndIndex]
      }
      if { $msgIndex != -1 } {
         set msg [string range ${_line} $msgStartIndex end]
      }

      if { ${_toOverview} == true } {
         if { ! ($node == "" || $type == "") } {
            # abortx, endx, beginx type are used for signals we send to the parent containers nodes
            # as a ripple effect... However, in the case of abort messages we don't want these collateral signals
            # to appear in the message center... At this point, we can reset abortx to abort, endx to end and so forth
            if { ${type} != "beginx" } {
               catch { set type $::DrawUtils::rippleStatusMap(${type}) }
            }
            if { ${type} != "info" } {
               if { ${node} == [SharedData_getExpRootNode ${_exp_path}] } {
                  ::log::log debug "LogReader_processLine to overview time:$timestamp node=$node type=$type"
                  thread::send -async [SharedData_getMiscData OVERVIEW_THREAD_ID] \
                     "Overview_updateExp [thread::id] ${_exp_path} ${_datestamp} ${type} ${timestamp}"
               }
            }
         }
      }

      if { ${_ToFlow} == true } {
         LogReader_processFlowLine ${_exp_path} ${node} ${_datestamp} ${type} ${loopExt} ${timestamp}
      }

      if { ${_toMsgCenter} == true } {
         if { ${type} == "abort" || ${type} == "info" || ${type} == "event" } {
            if { ${node} == "" } {
               set msgNode NONE
            } else {
               set msgNode ${node}
            }
            thread::send -async ${MSG_CENTER_THREAD_ID} \
               "MsgCenterThread_newMessage [thread::id] \"${_datestamp}\" ${timestamp} ${type} ${msgNode}${loopExt} ${_exp_path} \"${msg}\""
         }
      }

   }
}

proc LogReader_processFlowLine { _exp_path _node _datestamp _type _loopExt _timestamp} {

   # node & signal is mandatory to be processed
   # else the line is ignored
   set loopInfoDisplay ""
   set extDisplay ""
   # abortx, endx, beginx type are used for signals we send to the parent containers nodes
   # as a ripple effect... However, in the case of abort messages we don't want these collateral signals
   # to appear in the message center... At this point, we can reset abortx to abort, endx to end and so forth
   set finalCmd ""
   if { ${_node} != "" } {
      # set flowNode [::SuiteNode::getFlowNodeMapping ${_suite_record} ${_node}]
      set flowNode [SharedData_getExpNodeMapping ${_exp_path} ${_node}]

      if { [info exists ::DrawUtils::rippleStatusMap(${_type})] } {
         set type $::DrawUtils::rippleStatusMap(${_type})

         ::log::log debug "LogReader_processFlowLine node=${_node} flowNode:$flowNode loopExt:${_loopExt} type=${_type}"
         set nodeType [SharedFlowNode_getNodeType ${_exp_path} ${flowNode}]
         # puts "LogReader_processFlowLine nodeType:${nodeType} node=${_node} flowNode:$flowNode loopExt:${_loopExt} type=${_type}"
            # 1 - first we take care of setting the node status
            if { [string tolower ${_type}] == "init" } {
               if { ${nodeType} == "loop" } {
                  if { ${_loopExt} != "" } {
                     SharedFlowNode_setMemberStatus ${_exp_path} ${flowNode} ${_datestamp} ${_loopExt} ${_type} ${_timestamp} 1
                  } else {
                     # we got an update on the whole loop
                     SharedFlowNode_resetAllStatus ${_exp_path} ${flowNode} ${_datestamp} 1
                  }
               } else { 
                  # current node is not loop
                  if { [SharedFlowNode_getLoops ${_exp_path} ${flowNode}] != "" } {
                     # part of parent loop container
                     SharedFlowNode_setMemberStatus ${_exp_path} ${flowNode} ${_datestamp} ${_loopExt} ${_type} ${_timestamp} 1
                  } else {
                     SharedFlowNode_resetNodeStatus ${_exp_path} ${flowNode} ${_datestamp}
                  }
               }
            } else {
               # not init state, any other
               if { ${nodeType} == "loop" || ${nodeType} == "npass_task" } {
                  if { ${_loopExt} != "" } {
                     # we got an update on a loop iteration
                     SharedFlowNode_setMemberStatus ${_exp_path} ${flowNode} ${_datestamp} ${_loopExt} ${_type} ${_timestamp} 0
                  } else {
                     # we got an update on the whole loop
                     SharedFlowNode_setMemberStatus ${_exp_path} ${flowNode} ${_datestamp} all ${_type} ${_timestamp}
                  }
               } else { 
                  # current node is not loop
                  # puts  "SharedFlowNode_setMemberStatus ${_exp_path} ${flowNode} ${_datestamp} ${_loopExt} ${_type} ${_timestamp}"
                  SharedFlowNode_setMemberStatus ${_exp_path} ${flowNode} ${_datestamp} ${_loopExt} ${_type} ${_timestamp}
               }
            }

            # 2 - then we refresh the display... redisplay the node text?
            if { [SharedData_getMiscData STARTUP_DONE] == "true" &&
               [SharedFlowNode_isRefreshNeeded ${_exp_path} ${flowNode} ${_datestamp} ${_loopExt}] == "true" } {
               #xflow_redrawNodes ${flowNode}
               LogReader_updateNodes ${flowNode}
            }
      }
   }
}

# as many nodes are updated in the same read sequence,
# only update nodes that are in different branches.
# Nodes from the same branch will only get one update on the highest node.
# With this approach, multiple aborts will only be redrawn once at the higher
# level..
proc LogReader_updateNodes { node } {
   global LOGREADER_UPDATE_NODES

   if { ${LOGREADER_UPDATE_NODES} == "" } {
      set LOGREADER_UPDATE_NODES ${node}
   } else {
      # if one is the parent of another, keep the parent
      # this should take care of one redraw only for aborts where the messages comes in a bunch

      # if the node is already in the updated list nothing to do
      if { [lsearch  -exact ${LOGREADER_UPDATE_NODES} ${node}] == -1 } {
         # exact node is not in list... search for parent nodes
         # check if the current node is parent of updated nodes
         set childNodes [lsearch  -all ${LOGREADER_UPDATE_NODES} ${node}*]
         if {  ${childNodes} != "" } {
            # current is parent of updated ones, delete updated ones and add current one
            set childNodes [lreverse ${childNodes}]
            foreach childIndex ${childNodes} {
               set LOGREADER_UPDATE_NODES [lreplace ${LOGREADER_UPDATE_NODES} ${childIndex} ${childIndex}]
            }
            lappend LOGREADER_UPDATE_NODES ${node}
         } else {
            # current is not parent of udpated ones, 
            # then check if updated ones are already parent of current one
            # break as soon as we find one
            set found false
            foreach updatedNode ${LOGREADER_UPDATE_NODES} {
               if { [string first ${updatedNode} ${node}] != -1 } {
                  set found true
                  break
               }
            }
            if { ${found} == "false" } {
               # the node is new, add it
               lappend LOGREADER_UPDATE_NODES ${node}
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
   ::log::log debug "LogReader_getAvailableDates exp logs: $expLogs"
   return $expLogs
}


