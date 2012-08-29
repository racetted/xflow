package require textutil::string

# read_type is one of all, no_overview, overview_only, msg_only, refresh_flow
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
   set thisThreadId [thread::id]

   set sendToOverview false
   set sendToFlow false
   set sendToMsgCenter false
   if { ${isOverviewMode} == true && (${read_type} == "all" || ${read_type} == "overview_only") } {
      set sendToOverview true
   }
   if { (${read_type} == "all" || ${read_type} == "no_overview" || ${read_type} == "refresh_flow" ) } {
      set sendToFlow true
   }
   if { (${read_type} == "all" || ${read_type} == "msg_only" || ${read_type} == "no_overview" ) } {
      set sendToMsgCenter true
   }
   
   # first cancel any other waiting read for this suite
   LogReader_cancelAfter $suite_record
   set suitePath [$suite_record cget -suite_path]
   set logfile $suitePath/logs/${datestamp}_nodelog

   if { [file exists $logfile] } {
      set f_logfile [ open $logfile r ]
      flush stdout
      
      if { ${isStartupDone} == "true" } {
         set logFileOffset [SharedData_getExpDatestampOffset ${suitePath} ${datestamp}]
         ::log::log debug "LogReader_readFile suite_record:$suite_record datestamp:${datestamp} read_offset:$logFileOffset"
      } else {
         ::log::log debug "LogReader_readFile suite_record:$suite_record datestamp:${datestamp} reset read_offset"
         set logFileOffset 0
         ${suite_record} configure -exp_log ${logfile}
      }

      # position yourself in the file
      seek $f_logfile $logFileOffset

      while {[gets $f_logfile line] >= 0} {
         if { ${sendToOverview} == true } {
            LogReader_processOverviewLine ${overviewThreadId} $suite_record $datestamp $line
         }
         if { ${sendToFlow} == true || ${sendToMsgCenter} == true} {
            LogReader_processLine $suite_record $datestamp ${sendToFlow} ${sendToMsgCenter} $line
         }
      }
      
      # Need to notify the main thread that this child is done reading
      # the log file for initialization
      if { ${isStartupDone} == "false" && ${isOverviewMode} == "true" } {
            puts "LogReader sending Overview_childInitDone [${suite_record} cget -suite_path] ${datestamp}"
            thread::send -async ${overviewThreadId} \
               "Overview_childInitDone [${suite_record} cget -suite_path] ${datestamp}"
     }

      SharedData_setExpDatestampOffset ${suitePath} ${datestamp} [tell $f_logfile]

      close $f_logfile

   } else {
      if { [file writable $suitePath/logs/] } {
         puts "LogReader_readFile $logfile file does not exists! Creating it..."
         catch { close [open $logfile a] }
      } else {
         puts "LogReader_readFile $logfile file does not exists!"
      }
   
      # Need to notify the main thread that this child is done reading
      # the log file for initialization
      if { ${isStartupDone} == "false" && ${isOverviewMode} == "true" } {
            thread::send -async ${overviewThreadId} \
               "Overview_childInitDone [${suite_record} cget -suite_path] ${datestamp}"
      }
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

# this is meant to be running inside a child thread
proc LogReader_processOverviewLine { overview_thread_id suite_record datestamp line } {  
   ::log::log debug "LogReader_processOverviewLine suite_record:$suite_record line:$line"

   set nodeIndex 28
   set typeIndex [string first "MSGTYPE=" $line $nodeIndex]
   set loopIndex [string first "SEQLOOP=" $line $typeIndex]
   set msgIndex [string first "SEQMSG=" $line $typeIndex]
   set nodeStartIndex [expr $nodeIndex + 8]
   set nodeEndIndex [expr $typeIndex - 2]
   set typeStartIndex [expr $typeIndex + 8]
   if { $loopIndex != -1 } {
      set typeEndIndex [expr $loopIndex -2]
      set loopStartIndex [expr $loopIndex + 8]
   }
   if { $msgIndex == -1 && $loopIndex == -1 } {
      set typeEndIndex end
   }

   if { $typeIndex == -1 } {
      puts "LogReader_processOverviewLine invalid line ignored:$line"   
   } else {
      # TIMESTAMP=20100908.19:19:42
      set timestamp [string range $line 10 [expr $nodeIndex - 2]]
      set node [string range $line $nodeStartIndex $nodeEndIndex]
      set type [string range $line $typeStartIndex $typeEndIndex]
      if { ! ($node == "" || $type == "") } {
         # abortx, endx, beginx type are used for signals we send to the parent containers nodes
         # as a ripple effect... However, in the case of abort messages we don't want these collateral signals
         # to appear in the message center... At this point, we can reset abortx to abort, endx to end and so forth
         if { ${type} != "beginx" } {
            catch { set type $::DrawUtils::rippleStatusMap(${type}) }
         }
         if { ${type} != "info" } {
            if { ${node} == [${suite_record} cget -root_node] } {
               ::log::log debug "LogReader_processOverviewLine time:$timestamp node=$node type=$type"
               thread::send -async ${overview_thread_id} \
                  "Overview_updateExp [thread::id] ${suite_record} ${datestamp} ${type} ${timestamp}"
            }
         }
      }
   }
}

proc LogReader_processLine { suite_record datestamp send_to_flow send_to_msgcenter  line } {
   global MSG_CENTER_THREAD_ID
   set thisThreadId [thread::id]

   ::log::log debug "LogReader_processLine line:$line datestamp:${datestamp} send_to_flow:${send_to_flow} send_to_msgcenter:${send_to_msgcenter}"
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
      puts "LogReader_processLine invalid line ignored:$line datestamp:${datestamp}"   
   } else {
      set timestamp [string range $line 10 26]
      set node [string range $line $nodeStartIndex $nodeEndIndex]
      set flowNode [::SuiteNode::getFlowNodeMapping $suite_record $node]
      set type [string range $line $typeStartIndex $typeEndIndex]
      set msg ""
      ::log::log debug "LogReader_processLine node:$node flowNode:$flowNode"
      if { $type != "" } {
         if { $loopIndex != -1 } {
            set loopExt [string range $line $loopStartIndex $loopEndIndex]
         }
         if { $msgIndex != -1 } {
            set msg [string range $line $msgStartIndex end]
         }
         # send message to message center
         if { ${send_to_msgcenter} == true } {
            if { ${type} == "abort" || ${type} == "info" || ${type} == "event" } {
               if { ${node} == "" } {
                  set msgNode NONE
               } else {
                  set msgNode ${node}
               }
               set expPath [${suite_record} cget -suite_path]
               thread::send -async ${MSG_CENTER_THREAD_ID} \
                  "MsgCenterThread_newMessage ${thisThreadId} \"${datestamp}\" ${timestamp} ${type} ${msgNode}${loopExt} ${expPath} \"${msg}\""
            }
         }
         if { ${send_to_flow} == true } {
                  ::log::log debug "LogReader_processLine here"
            # abortx, endx, beginx type are used for signals we send to the parent containers nodes
            # as a ripple effect... However, in the case of abort messages we don't want these collateral signals
            # to appear in the message center... At this point, we can reset abortx to abort, endx to end and so forth
            set finalCmd ""
            if { $node != "" } {

               if { [info exists ::DrawUtils::rippleStatusMap(${type})] } {
                  set type $::DrawUtils::rippleStatusMap(${type})

                  ::log::log debug "LogReader_processLine node=$node flowNode:$flowNode loopExt:$loopExt type=$type"
                  ::log::log debug "LogReader_processLine message=$msg"
                  if { [info command $flowNode] != "" } {
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
                     # set isThreadStartupDone [SharedData_getMiscData ${thisThreadId}_${datestamp}_STARTUP_DONE]
                     if { [SharedData_getMiscData STARTUP_DONE] == "true" &&
                        [::FlowNodes::isRefreshNeeded ${flowNode} ${loopExt} ] == "true" } {
                        #xflow_redrawNodes ${flowNode}
                        LogReader_updateNodes ${flowNode}
                     }
                  }
               }
            }
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


