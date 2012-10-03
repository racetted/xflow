package require textutil::string

# read_type is one of all, no_overview, overview_only, msg_only, refresh_flow, no_flow
proc LogReader_readFile { suite_record datestamp {read_type no_overview} } {
   global REDRAW_FLOW LOGREADER_UPDATE_NODES
   ::log::log debug "LogReader_readFile suite_record:$suite_record datestamp:${datestamp} read_type:${read_type}"
   set REDRAW_FLOW false
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
   LogReader_cancelAfter $suite_record
   set expPath [$suite_record cget -suite_path]
   if { ${datestamp} != "" } {
      set logfile ${expPath}/logs/${datestamp}_nodelog

      if { [file exists $logfile] } {
         set f_logfile [ open $logfile r ]
         flush stdout
         
         if { ${isStartupDone} == "true" } {
            set logFileOffset [SharedData_getExpDatestampOffset ${expPath} ${datestamp}]
            ::log::log debug "LogReader_readFile suite_record:$suite_record datestamp:${datestamp} read_offset:$logFileOffset"
         } else {
            ::log::log debug "LogReader_readFile suite_record:$suite_record datestamp:${datestamp} reset read_offset"
            set logFileOffset 0
         }

         # position yourself in the file
         seek $f_logfile $logFileOffset

         while {[gets $f_logfile line] >= 0} {
            LogReader_processLine ${suite_record} ${expPath} ${datestamp} ${line} ${sendToOverview} ${sendToFlow} ${sendToMsgCenter}
         }
         SharedData_setExpDatestampOffset ${expPath} ${datestamp} [tell $f_logfile]
         SharedData_setExpStartupDone ${expPath} ${datestamp} true
         close $f_logfile

      } else {
         if { [file writable ${expPath}/logs/] } {
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
      thread::send -async ${overviewThreadId} "Overview_childInitDone ${expPath} ${datestamp}"
   }

   if { ${REDRAW_FLOW} == true } {
      xflow_redrawAllFlow
   } elseif { ${LOGREADER_UPDATE_NODES} != "" } {
      # update highest node that was affected during this read
      foreach updatedNode  ${LOGREADER_UPDATE_NODES} {
         xflow_redrawNodes ${updatedNode}
      }
   }
   # special case for flow refresh
   if { ${read_type} == "refresh_flow" } {
      set read_type "all"
   }
   LogReader_readAgain $suite_record ${datestamp} ${read_type}
}

proc LogReader_readAgain { suite_record datestamp read_type } {
   global ${suite_record}_READ_LOG_IDS
   
   catch { set ${suite_record}_READ_LOG_IDS [after 4000 [list LogReader_readFile $suite_record ${datestamp} ${read_type}]]}
}

proc LogReader_cancelAfter { suite_record } {
   global ${suite_record}_READ_LOG_IDS
   if { [info exists ${suite_record}_READ_LOG_IDS] } {
      after cancel [set ${suite_record}_READ_LOG_IDS]
   }

}

proc LogReader_processLine { _suite_record _exp_path _datestamp _line _toOverview _ToFlow _toMsgCenter } {
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
                     "Overview_updateExp [thread::id] ${_suite_record} ${_datestamp} ${type} ${timestamp}"
               }
            }
         }
      }

      if { ${_ToFlow} == true } {
         LogReader_processFlowLine ${_suite_record} ${node} ${_datestamp} ${type} ${loopExt} ${timestamp}
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

proc LogReader_processFlowLine { _suite_record _node _datestamp _type _loopExt _timestamp} {

   # node & signal is mandatory to be processed
   # else the line is ignored
   set loopInfoDisplay ""
   set extDisplay ""
   set expPath [${_suite_record} cget -suite_path]
   # abortx, endx, beginx type are used for signals we send to the parent containers nodes
   # as a ripple effect... However, in the case of abort messages we don't want these collateral signals
   # to appear in the message center... At this point, we can reset abortx to abort, endx to end and so forth
   set finalCmd ""
   if { ${_node} != "" } {
      set flowNode [::SuiteNode::getFlowNodeMapping ${_suite_record} ${_node}]

      if { [info exists ::DrawUtils::rippleStatusMap(${_type})] } {
         set type $::DrawUtils::rippleStatusMap(${_type})

         ::log::log debug "LogReader_processFlowLine node=${_node} flowNode:$flowNode loopExt:${_loopExt} type=${_type}"
         set nodeType [SharedFlowNode_getNodeType ${expPath} ${flowNode}]
         # puts "LogReader_processFlowLine nodeType:${nodeType} node=${_node} flowNode:$flowNode loopExt:${_loopExt} type=${_type}"
            # 1 - first we take care of setting the node status
            if { [string tolower ${_type}] == "init" } {
               if { ${nodeType} == "loop" } {
                  if { ${_loopExt} != "" } {
                     SharedFlowNode_setMemberStatus ${expPath} ${flowNode} ${_datestamp} ${_loopExt} ${_type} ${_timestamp} 1
                  } else {
                     # we got an update on the whole loop
                     SharedFlowNode_resetAllStatus ${expPath} ${flowNode} ${_datestamp} 1
                  }
               } else { 
                  # current node is not loop
                  if { [SharedFlowNode_getLoops ${expPath} ${flowNode}] != "" } {
                     # part of parent loop container
                     SharedFlowNode_setMemberStatus ${expPath} ${flowNode} ${_datestamp} ${_loopExt} ${_type} ${_timestamp} 1
                  } else {
                     SharedFlowNode_resetNodeStatus ${expPath} ${flowNode} ${_datestamp}
                  }
               }
            } else {
               # not init state, any other
               if { ${nodeType} == "loop" || ${nodeType} == "npass_task" } {
                  if { ${_loopExt} != "" } {
                     # we got an update on a loop iteration
                     SharedFlowNode_setMemberStatus ${expPath} ${flowNode} ${_datestamp} ${_loopExt} ${_type} ${_timestamp} 0
                  } else {
                     # we got an update on the whole loop
                     SharedFlowNode_setMemberStatus ${expPath} ${flowNode} ${_datestamp} all ${_type} ${_timestamp}
                  }
               } else { 
                  # current node is not loop
                  # puts  "SharedFlowNode_setMemberStatus ${expPath} ${flowNode} ${_datestamp} ${_loopExt} ${_type} ${_timestamp}"
                  SharedFlowNode_setMemberStatus ${expPath} ${flowNode} ${_datestamp} ${_loopExt} ${_type} ${_timestamp}
               }
            }

            # 2 - then we refresh the display... redisplay the node text?
            if { [SharedData_getMiscData STARTUP_DONE] == "true" &&
               [SharedFlowNode_isRefreshNeeded ${expPath} ${flowNode} ${_datestamp} ${_loopExt}] == "true" } {
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


