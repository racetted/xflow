package require log

# this proc registers a datestamp to be monitored by the current thread
proc LogReader_addMonitorDatestamp { exp_path datestamp } {
   global LogReader_Datestamps
   ::log::log notice "LogReader_addMonitorDatestamp() ${exp_path} ${datestamp} called."

   if { ${exp_path} != "" && ${datestamp} != "" } {
      set key ${exp_path}_${datestamp}
      set LogReader_Datestamps($key) "${exp_path} ${datestamp}"
   }
   ::log::log notice "LogReader_addMonitorDatestamp() ${exp_path} ${datestamp} done."
}

# this proc removes a datestamp from being monitored by the current thread
proc LogReader_removeMonitorDatestamp { exp_path datestamp } {
   global LogReader_Datestamps LOGREADER_UPDATE_NODES_${exp_path}_${datestamp}

   ::log::log notice "Thread:[thread::id] LogReader_removeMonitorDatestamp() ${exp_path} ${datestamp} called."
   set key ${exp_path}_${datestamp}
   array unset LogReader_Datestamps $key
   if { [info exists LOGREADER_UPDATE_NODES_${exp_path}_${datestamp}] } {
      unset LOGREADER_UPDATE_NODES_${exp_path}_${datestamp}
   }
   ::log::log notice "Thread:[thread::id] LogReader_removeMonitorDatestamp() ${exp_path} ${datestamp} done."
}

# once initiated, this proc monitors all the datestamp that  is registered
# every 4 seconds
proc LogReader_readMonitorDatestamps {} {
   # puts "LogReader_readMonitorDatestamps called from thread: [thread::id]"
   global READ_LOG_AFTER_ID LogReader_Datestamps

   catch { after cancel ${READ_LOG_AFTER_ID} }

   if [ catch {

      foreach { key value } [array get LogReader_Datestamps] {
         if [ catch {
            # puts "LogReader_readMonitorDatestamps [thread::id] found key:${key} value:${value}"
            set expPath [lindex ${value} 0]
            set datestamp [lindex ${value} 1]
            # puts "LogReader_readMonitorDatestamps LogReader_readFile ${expPath} ${datestamp}"
            LogReader_readFile ${expPath} ${datestamp} all
            set offset [SharedData_getExpDatestampOffset ${expPath} ${datestamp}]
            if { [SharedData_getMiscData OVERVIEW_MODE] == true && [SharedData_getMiscData STARTUP_DONE] == true } {
              # send heartbeat with the overview
              # It could be that the key was modified while I'm processing this loop so before
	      # I resend the heartbeat I re-check that the key still exists
	      # if { [array get LogReader_Datestamps ${key}] != "" } {
	         # SharedData_setExpHeartbeat ${expPath} ${datestamp} [thread::id] [clock seconds] ${offset}
              # }
           }
         } message ] {
            ::log::log notice "ERROR in LogReader_readMonitorDatestamps: key:${key} ${message}"
            puts "ERROR in LogReader_readMonitorDatestamps: key:${key} ${message}"
         }
      }

   } message ] {
      ::log::log notice "ERROR in LogReader_readMonitorDatestamps: ${message}"
      puts "ERROR in LogReader_readMonitorDatestamps: ${message}"
   }

   set READ_LOG_AFTER_ID [after 4000 LogReader_readMonitorDatestamps]
}

# read_type is one of all, no_overview, overview_only, msg_only, refresh_flow, no_flow
proc LogReader_startExpLogReader { exp_path datestamp read_type {is_startup false} } {
   global MSG_CENTER_THREAD_ID
   ::log::log debug "LogReader_startExpLogReader  $exp_path $datestamp"
   if { ! [info exists MSG_CENTER_THREAD_ID] } {
      if { [SharedData_getMiscData OVERVIEW_MODE] == true } {
         # Utils_logInit
         set MSG_CENTER_THREAD_ID [SharedData_getMiscData OVERVIEW_THREAD_ID]
      } else {
         set MSG_CENTER_THREAD_ID [thread::id]
      }
   }

   if [ catch { 
      FlowXml_parse ${exp_path}/EntryModule/flow.xml ${exp_path} ${datestamp} ""
      ::log::log notice "LogReader_startExpLogReader exp_path=${exp_path} datestamp:${datestamp} read_type:${read_type} DONE."
   } message ] {
      set errMsg "Error Parsing flow.xml file ${exp_path}:\n$message"
      puts "ERROR: LogReader_startExpLogReader Parsing flow.xml file exp_path:${exp_path} datestamp:${datestamp}\n$message"
      ::log::log notice "ERROR: LogReader_startExpLogReader Parsing flow.xml file ${exp_path}:\n$message."
      error ${message}
      return
   }

   if { ${datestamp} != "" } {
      # force reread from beginning
      SharedData_setExpDatestampOffset ${exp_path} ${datestamp} 0

      # first do a full first pass read of the log file
      # LogReader_readFile ${exp_path} ${datestamp} ${read_type} true
      LogReader_readFile ${exp_path} ${datestamp} ${read_type} false
      ::log::log notice "LogReader_startExpLogReader exp_path=${exp_path} datestamp:${datestamp} first pass read DONE."

      if { [SharedData_getMiscData STARTUP_DONE] == false && [SharedData_getMiscData OVERVIEW_MODE] == true } {
         # at application startup, let the overview know that we're done reading the log
         # release the thread to other exp
         thread::send -async [SharedData_getMiscData OVERVIEW_THREAD_ID] "Overview_childInitDone [thread::id] ${exp_path} ${datestamp}"
      }
   
      # register the log to be monitor by this thread
      ::log::log notice "LogReader_startExpLogReader exp_path=${exp_path} datestamp:${datestamp} added to monitor list"
      LogReader_addMonitorDatestamp ${exp_path} ${datestamp}

      # send first heartbeat
      if { [SharedData_getMiscData OVERVIEW_MODE] == true && [SharedData_getMiscData STARTUP_DONE] == true } {
         set offset [SharedData_getExpDatestampOffset ${exp_path} ${datestamp}]
         # thread::send -async [SharedData_getMiscData OVERVIEW_THREAD_ID] "Overview_addHeartbeatDatestamp ${exp_path} ${datestamp}"
	 # SharedData_setExpHeartbeat ${exp_path} ${datestamp} [thread::id] [clock seconds] ${offset}
      }
   }
}

# read_type is one of all, no_overview, overview_only, msg_only, refresh_flow, no_flow
# first_read is true is used when the whole log is read for the first time...
proc LogReader_readFile { exp_path datestamp {read_type no_overview} {first_read false} } {
   global LOGREADER_UPDATE_NODES_${exp_path}_${datestamp}
   ::log::log debug "LogReader_readFile exp_path:${exp_path} datestamp:${datestamp} read_type:${read_type}"
   set LOGREADER_UPDATE_NODES_${exp_path}_${datestamp}  ""
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
   
   if { ${datestamp} != "" } {
      set logfile ${exp_path}/logs/${datestamp}_nodelog

      if { [file exists $logfile] } {
         set f_logfile [ open $logfile r ]
	 # fconfigure ${f_logfile} -buffering line
         flush stdout
         
         if { ${isStartupDone} == "true" } {
            set logFileOffset [SharedData_getExpDatestampOffset ${exp_path} ${datestamp}]
            if { ${logFileOffset} == "" } {
               set logFileOffset 0
               ::log::log notice "INFO: LogReader_readFile exp_path:${exp_path} datestamp:${datestamp} read_offset:$logFileOffset"
            }
            ::log::log debug "LogReader_readFile exp_path:${exp_path} datestamp:${datestamp} read_offset:$logFileOffset"
         } else {
            ::log::log debug "LogReader_readFile exp_path:${exp_path} datestamp:${datestamp} reset read_offset"
            set logFileOffset 0
         }

         # position yourself in the file
         seek $f_logfile $logFileOffset
	 set sameRead false
         while {[gets $f_logfile line] > 0} {
            if [ catch { 
	       if { [LogReader_processLine ${exp_path} ${datestamp} ${line} ${sendToOverview} ${sendToFlow} ${sendToMsgCenter} ${first_read}] != 0 } {
	          # something went wrong reading the line
		  # retry second read in .5 second... once in a while, I get junk when reading from the file... maybe the server is in the processing of
		  # writing to it... a retry seems to do the trick
		  if { ${sameRead} == false } {
		     set sameRead true
		     # go to previous spot in the file
                     seek $f_logfile $logFileOffset
		     after 500
		  } else {
		     # only retry once... after that we log the error
                     ::log::log notice "WARNING: LogReader_readFile() invalid line ignored:${line} exp_path:${exp_path} datestamp:${datestamp} thread_id:[thread::id] file_offset: ${logFileOffset} after 1 retry."
		     break
		  }
	       } else {
	          set sameRead false
	          set logFileOffset [tell ${f_logfile}]
	       }
            } message ] {
	       ::log::log notice "ERROR: LogReader_readFile LogReader_processLine ${exp_path} ${datestamp} ${line} ${sendToOverview} ${sendToFlow} ${sendToMsgCenter} ${first_read}"
	       ::log::log notice "ERROR: message: ${message}"
	       puts "ERROR: LogReader_processLine ${exp_path} ${datestamp} ${line} ${sendToOverview} ${sendToFlow} ${sendToMsgCenter} ${first_read} \nmessage: ${message}"
	    }
         }
	 set offset [tell $f_logfile]
         SharedData_setExpDatestampOffset ${exp_path} ${datestamp} ${offset}
         catch { close $f_logfile }
      } else {
         ::log::log debug "LogReader_readFile $logfile file does not exists!"
      }
   }

   if { ${first_read} == false && [set LOGREADER_UPDATE_NODES_${exp_path}_${datestamp}] != "" } {
      # the gui runs in the overview thread... so set the update nodes list in shared memory
      SharedData_setExpUpdatedNodes ${exp_path} ${datestamp} [set LOGREADER_UPDATE_NODES_${exp_path}_${datestamp}]
      # let gui knows that he needs to redraw the flow
      if { ${isOverviewMode} == true } {
         ::log::log debug "LogReader_readFile xflow_redrawNodesEvent ${exp_path} ${datestamp}"
	 # puts "LogReader_readFile xflow_redrawNodesEvent ${exp_path} ${datestamp}"
         thread::send -async ${overviewThreadId} "xflow_redrawNodesEvent ${exp_path} ${datestamp}" SendDone
	 vwait SendDone
         ::log::log debug "LogReader_readFile xflow_redrawNodesEvent ${exp_path} ${datestamp} DONE"
      } else {
         # in non-overview mode, xflow and LogReader runs within same thread
	 # we are sending the request through the thread messaging  instead of direct call
	 # so that no dependency on the TK is found in this tcl file
         thread::send [thread::id] "xflow_redrawNodesEvent ${exp_path} ${datestamp}"
      }
   }
}

proc LogReader_processLine { _exp_path _datestamp _line _toOverview _ToFlow _toMsgCenter {first_read false} } {
   global MSG_CENTER_THREAD_ID
   if { [string first "TIMESTAMP=" ${_line}] != 0 } {
      return 1
   }

   set nodeIndex 28
   set typeIndex [string first "MSGTYPE=" ${_line} $nodeIndex]
   if { $typeIndex == -1 } {
      puts "LogReader_processLine invalid line ignored:${_line} exp_path:${_exp_path} datestamp:${_datestamp}"
      return 1
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

      if { ${_toMsgCenter} == true } {
         if { ${type} == "abort" || ${type} == "info" || ${type} == "event" } {
            if { ${node} == "" } {
               set msgNode NONE
            } else {
               set msgNode ${node}
            }
	    # send msg variable in between brackets so no expansion is being made
	    # in case it contains dollar signs
            thread::send -async ${MSG_CENTER_THREAD_ID} \
                "MsgCenter_processNewMessage \"${_datestamp}\" ${timestamp} ${type} ${msgNode}${loopExt} ${_exp_path} {${msg}}"
         }
      }

      if { ${_ToFlow} == true } {
         LogReader_processFlowLine ${_exp_path} ${node} ${_datestamp} ${type} ${loopExt} ${timestamp} ${first_read}
      }

      if { ${_toOverview} == true } {
         if { ! ($node == "" || $type == "") } {
            # abortx, endx, beginx type are used for signals we send to the parent containers nodes
            # as a ripple effect... However, in the case of abort messages we don't want these collateral signals
            # to appear in the message center... At this point, we can reset abortx to abort, endx to end and so forth
            if { ${type} != "beginx" } {
               catch { set type [SharedData_getRippleStatusMap ${type}] }
            }
            if { ${type} != "info" } {
               if { ${node} == [SharedData_getExpRootNode ${_exp_path} ${_datestamp}] } {
                  ::log::log debug "LogReader_processLine to overview time:$timestamp node=$node type=$type"
                  ::log::log notice "LogReader_processLine to overview time:$timestamp node=$node datestamp:${_datestamp} type=$type"
		  # puts "LogReader_processLine Overview_updateExp [thread::id] \"${_exp_path}\" \"${_datestamp}\" \"${type}\" \"${timestamp}\""
		  # sends the command in async mode to avoid potential deadlock... however the vwait ensures that it waits for the
		  # command to be finished before going further
                  thread::send -async [SharedData_getMiscData OVERVIEW_THREAD_ID] \
                     "Overview_updateExp [thread::id] \"${_exp_path}\" \"${_datestamp}\" \"${type}\" \"${timestamp}\"" SendDone
		  vwait SendDone
		  # puts "LogReader_processLine Overview_updateExp [thread::id] \"${_exp_path}\" \"${_datestamp}\" \"${type}\" \"${timestamp}\" DONE"
               }
            }
         }
      }
   }
   return 0
}

proc LogReader_processFlowLine { _exp_path _node _datestamp _type _loopExt _timestamp {_firstRead false}} {
  #  puts " LogReader_processFlowLine _exp_path:${_exp_path} node:${_node} _datestamp:${_datestamp} type:${_type} _loopExt:${_loopExt} _firstRead:${_firstRead}"
   # node & signal is mandatory to be processed
   # else the line is ignored
   set loopInfoDisplay ""
   set extDisplay ""
   # abortx, endx, beginx type are used for signals we send to the parent containers nodes
   # as a ripple effect... However, in the case of abort messages we don't want these collateral signals
   # to appear in the message center... At this point, we can reset abortx to abort, endx to end and so forth
   set finalCmd ""
   if { ${_node} != "" } {

      set statusType [SharedData_getRippleStatusMap ${_type}]
      if { ${statusType} != "" } {

         set flowNode [SharedData_getExpNodeMapping ${_exp_path} ${_datestamp} ${_node}]
         ::log::log debug "LogReader_processFlowLine node=${_node} flowNode:$flowNode loopExt:${_loopExt} type=${_type}"
	 if { [SharedFlowNode_isNodeExist ${_exp_path} ${flowNode} ${_datestamp}] == false } {
            puts "WARNING: LogReader_processFlowLine() _exp_path:${_exp_path} node:${_node} _datestamp:${_datestamp} Node might not exists in flow.xml"
            ::log::log notice "WARNING: LogReader_processFlowLine() _exp_path:${_exp_path} node:${_node} _datestamp:${_datestamp} Node might not exists in flow.xml"
	    return
	 }
         if [ catch { set nodeType [SharedFlowNode_getNodeType ${_exp_path} ${flowNode} ${_datestamp}] } message ] {
            puts "ERROR: LogReader_processFlowLine() _exp_path:${_exp_path} node:${_node} flowNode:${flowNode} _datestamp:${_datestamp} type:${_type} _loopExt:${_loopExt} message: ${message}"
            ::log::log notice "ERROR: LogReader_processFlowLine() _exp_path:${_exp_path} node:${_node} flowNode:${flowNode} _datestamp:${_datestamp} type:${_type} _loopExt:${_loopExt} message: ${message}"
            return
         }
            # 1 - first we take care of setting the node status
            if { [string tolower ${_type}] == "init" } {
               if { ${nodeType} == "loop" || ${nodeType} == "npass_task" } {
                  if { ${_loopExt} != "" } {
                     SharedFlowNode_setMemberStatus ${_exp_path} ${flowNode} ${_datestamp} ${_loopExt} ${statusType} ${_type} ${_timestamp} 1
                  } else {
                     # we got an update on the whole loop
                     SharedFlowNode_resetAllStatus ${_exp_path} ${flowNode} ${_datestamp} 1
                  }
               } else { 
                  # current node is not loop
                  if { [SharedFlowNode_getLoops ${_exp_path} ${flowNode} ${_datestamp}] != "" } {
                     # part of parent loop container
                     SharedFlowNode_setMemberStatus ${_exp_path} ${flowNode} ${_datestamp} ${_loopExt} ${statusType} ${_type} ${_timestamp} 1
                  } else {
                     SharedFlowNode_resetNodeStatus ${_exp_path} ${flowNode} ${_datestamp}
                  }
               }
            } else {
               # not init state, any other
               if { ${nodeType} == "loop" || ${nodeType} == "npass_task" } {
                  if { ${_loopExt} != "" } {
                     # we got an update on a loop iteration
                     SharedFlowNode_setMemberStatus ${_exp_path} ${flowNode} ${_datestamp} ${_loopExt} ${statusType} ${_type} ${_timestamp} 0
                  } else {
                     # we got an update on the whole loop
                     SharedFlowNode_setMemberStatus ${_exp_path} ${flowNode} ${_datestamp} all ${statusType} ${_type} ${_timestamp}
                  }
               } else { 
                  # current node is not loop
                  SharedFlowNode_setMemberStatus ${_exp_path} ${flowNode} ${_datestamp} ${_loopExt} ${statusType} ${_type} ${_timestamp}
               }
            }

            # 2 - then we refresh the display... redisplay the node text?
            if { [SharedData_getMiscData STARTUP_DONE] == "true" &&
               [SharedFlowNode_isRefreshNeeded ${_exp_path} ${flowNode} ${_datestamp} ${_loopExt}] == "true" && ${_firstRead} == false } {
               LogReader_updateNodes ${_exp_path} ${_datestamp} ${flowNode}
            }
      }
   }
}

# as many nodes are updated in the same read sequence,
# only update nodes that are in different branches.
# Nodes from the same branch will only get one update on the highest node.
# With this approach, multiple aborts will only be redrawn once at the higher
# level..
proc LogReader_updateNodes { exp_path datestamp node } {
   global LOGREADER_UPDATE_NODES_${exp_path}_${datestamp} 
   ::log::log debug "LogReader_updateNodes exp_path:${exp_path} datestamp:${datestamp} node=${node}"
   if { ! [info exists LOGREADER_UPDATE_NODES_${exp_path}_${datestamp}] } {
      set LOGREADER_UPDATE_NODES_${exp_path}_${datestamp} ${node}
   } else {
      # if one is the parent of another, keep the parent
      # this should take care of one redraw only for aborts where the messages comes in a bunch
      set updatedNodeList [set LOGREADER_UPDATE_NODES_${exp_path}_${datestamp}]
      # if the node is already in the updated list nothing to do
      if { [lsearch  -exact ${updatedNodeList} ${node}] == -1 } {
         # exact node is not in list... search for parent nodes
         # check if the current node is parent of updated nodes
         set childNodes [lsearch  -all ${updatedNodeList} ${node}/*]
         if {  ${childNodes} != "" } {
            # current is parent of updated ones, delete updated ones and add current one
            set childNodes [lreverse ${childNodes}]
            foreach childIndex ${childNodes} {
               set updatedNodeList  [lreplace ${updatedNodeList} ${childIndex} ${childIndex}]
            }
            lappend updatedNodeList ${node}
         } else {
            # current is not parent of udpated ones, 
            # then check if updated ones are already parent of current one
            # break as soon as we find one
            set found false
            foreach updatedNode ${updatedNodeList} {
               if { [string first ${updatedNode}/ ${node}] != -1 } {
                  set found true
                  break
               }
            }
            if { ${found} == "false" } {
               # the node is new, add it
               lappend updatedNodeList ${node}
            }
         }
      }
      set LOGREADER_UPDATE_NODES_${exp_path}_${datestamp} ${updatedNodeList}
      ::log::log debug "LogReader_updateNodes exp_path:${exp_path} datestamp:${datestamp} node=${node} DONE"
   }

}

# the date is sorted in reverse order, the most recent date will appear first
proc LogReader_getAvailableDates { exp_path } {
   set cmd "cd ${exp_path}/logs; ls *_nodelog | sed -e 's,_nodelog,,' | sort -r"
   set expLogs ""
   if [ catch { set expLogs [exec ksh -c $cmd] } message ] {
   }
   ::log::log debug "LogReader_getAvailableDates exp:${exp_path} logs: $expLogs"
   return $expLogs
}

# for xflow using one active datestamp
proc LogReader_getSingleDatestamp { exp_path } {
   global LogReader_Datestamps
   foreach { key value } [array get LogReader_Datestamps] {
      set foundExpPath [lindex ${value} 0]
      if { ${foundExpPath} == ${exp_path} } {
         set datestamp [lindex ${value} 1]
	 return ${datestamp}
      }
   }
   return ""
}

# for standalone xflow using multiple datestamps
# to know when to close the whole app
proc LogReader_isLastDatestamp { exp_path datestamp } {
   global LogReader_Datestamps
   if { [array size LogReader_Datestamps] == 1 } {
      return true
   }
   return false
}

proc LogReader_getMonitorDatestamps { exp_path } {
   global LogReader_Datestamps

   set result {}
   foreach { key value } [array get LogReader_Datestamps] {
      set foundExpPath [lindex ${value} 0]
      set datestamp [lindex ${value} 1]
      if { ${foundExpPath} == ${exp_path} } {
         lappend result ${datestamp}
      }
   }
   return ${result}
}

proc LogReader_printMonitorDatestamps {} {
   global LogReader_Datestamps

   puts "LogReader_printMonitorDatestamps thread_id:[thread::id]..."
   foreach { key value } [array get LogReader_Datestamps] {
      set expPath [lindex ${value} 0]
      set datestamp [lindex ${value} 1]
      puts "thread_id:[thread::id] exp:${expPath} datestamp:${datestamp}"
   }
   puts "LogReader_printMonitorDatestamps thread_id:[thread::id] DONE"
}
