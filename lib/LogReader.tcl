package require log
package require textutil

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
proc LogReader_readMonitorDatestamps { {start_delay -1} } {
   ::log::log debug "LogReader_readMonitorDatestamps called from thread: [thread::id] start_delay:${start_delay}"
   global READ_LOG_AFTER_ID LogReader_Datestamps

   if { ${start_delay} != -1 } {
      after ${start_delay}
   }

   if [ catch {
  
      catch { after cancel ${READ_LOG_AFTER_ID} }


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
            puts stderr "ERROR in LogReader_readMonitorDatestamps: key:${key} ${message}"
         }
      }

   } message ] {
      ::log::log notice "ERROR in LogReader_readMonitorDatestamps: ${message}"
      puts stderr "ERROR in LogReader_readMonitorDatestamps: ${message}"
   }

   set READ_DELAY [SharedData_getMiscData LOG_READ_DELAY]
   if { ${READ_DELAY} == "" } {
      set READ_DELAY 4000
   }
   puts "LogReader_readMonitorDatestamps READ_DELAY:$READ_DELAY"
   set READ_LOG_AFTER_ID [after ${READ_DELAY} LogReader_readMonitorDatestamps]
}

# read_type is one of all, no_overview, refresh_flow
#    all: message entries sent to xflow, overview and msg_center when applicable
#         this is the default under normal monitoring usage
#    no_overview: message entries sent to xflow and msg_center when applicable
#                 you would use this for example, when the user chooses an old datestamp through xflow, the overview does not not to be updated
#
#    refresh_flow: message entries only sent to xflow
#                 You would use this for example, when the flow is refreshed by the user, you don't want the overview to be flickering with
#		  any update status from an already processed log file
# 
# read_toplog: is used to read ${datestamp}_toplog file instead of ${datestamp}_nodelog file for performance purpose
#              usually set to true by overview ; for now, the reading of toplog is only done at overview startup.
#              after startup, it reverts to nodelog for any further updates.
#
# use_log_cache: is used to tell logreader to start reading at a certain point in the log file as opposed to reading from start
# 
proc LogReader_startExpLogReader { exp_path datestamp read_type {read_toplog false} {use_log_cache false} } {
   global MSG_CENTER_THREAD_ID CREADER_FIELD_SEPARATOR
   ::log::log debug "LogReader_startExpLogReader  exp_path:$exp_path datestamp:$datestamp read_type:${read_type} read_toplog:${read_toplog} use_log_cache:${use_log_cache}"
   if [ catch {

   if { ! [info exists CREADER_FIELD_SEPARATOR] } {
      set CREADER_FIELD_SEPARATOR "!~!"
   }

   if { ! [info exists MSG_CENTER_THREAD_ID] } {
      if { [SharedData_getMiscData OVERVIEW_MODE] == true } {
         # Utils_logInit
         set MSG_CENTER_THREAD_ID [SharedData_getMiscData OVERVIEW_THREAD_ID]
      } else {
         set MSG_CENTER_THREAD_ID [thread::id]
      }
   }

   if [ catch { 
      if { ${use_log_cache} == false } {
         FlowXml_parse ${exp_path}/EntryModule/flow.xml ${exp_path} ${datestamp} ""
         ::log::log notice "LogReader_startExpLogReader exp_path=${exp_path} datestamp:${datestamp} read_type:${read_type} DONE."

         TsvInfo_loadData $exp_path $datestamp

      }
   } message ] {
      set errMsg "Error Parsing flow.xml file ${exp_path}:\n$message\nInfo: $::errorInfo"
      puts stderr "ERROR: LogReader_startExpLogReader Parsing flow.xml file exp_path:${exp_path} datestamp:${datestamp}\n$message\n$::errorInfo"
      ::log::log notice "ERROR: LogReader_startExpLogReader Parsing flow.xml file ${exp_path}:\n$message$::errorInfo."
      error ${message} $::errorInfo
      return 
   }

   if { ${datestamp} != "" } {
      if { ${use_log_cache} == false } {
         # force reread from beginning
         SharedData_setExpDatestampOffset ${exp_path} ${datestamp} 0
      }

      # first do a full first pass read of the log file
      if {${read_type} == "refresh_flow" || ${read_type} == "no_overview" || [SharedData_getMiscData OVERVIEW_MODE] == false} {
         LogReader_readTsv ${exp_path} ${datestamp}
      } else {
         LogReader_readFile ${exp_path} ${datestamp} ${read_type} ${read_toplog}
      }

      ::log::log notice "LogReader_startExpLogReader exp_path=${exp_path} datestamp:${datestamp} first pass read DONE."

      if { [SharedData_getMiscData STARTUP_DONE] == false && [SharedData_getMiscData OVERVIEW_MODE] == true } {
         # at application startup, let the overview know that we're done reading the log
         # release the thread to other exp
         thread::send -async [SharedData_getMiscData OVERVIEW_THREAD_ID] "Overview_childInitDone [thread::id] ${exp_path} ${datestamp}"
      }
  
      set isOverviewMode [SharedData_getMiscData OVERVIEW_MODE]
      # register the log to be monitor by this thread
      ::log::log notice "LogReader_startExpLogReader exp_path=${exp_path} datestamp:${datestamp} added to monitor list"
      LogReader_addMonitorDatestamp ${exp_path} ${datestamp}

      # send first heartbeat
      if { [SharedData_getMiscData OVERVIEW_MODE] == true && [SharedData_getMiscData STARTUP_DONE] == true } {
         set offset [SharedData_getExpDatestampOffset ${exp_path} ${datestamp}]
         # thread::send -async [SharedData_getMiscData OVERVIEW_THREAD_ID] "Overview_addHeartbeatDatestamp ${exp_path} ${datestamp}"
         # SharedData_setExpHeartbeat ${exp_path} ${datestamp} [thread::id] [clock seconds] ${offset}
      }

      # SharedData_setExpNodeLogCache ${exp_path} ${datestamp} true
   }

   } message ] {
      puts stderr "ERROR: LogReader_startExpLogReader exp_path:${exp_path} datestamp:${datestamp}\n$message\n$::errorInfo"
      ::log::log notice "ERROR: LogReader_startExpLogReader ${exp_path}:\n$message.\n$::errorInfo"
      error ${message}
      return
   }
}

# used at xflow startup to retrieve statuses in logs: 
# executes C logreader that outputs tsv elements
# then set the tsv structures in the environment
#
# The returned output from logreader contains 3 lines
# line1 contains a list of node names with statuses and stats; the nodes must have entries in the log file to appear here
#       each nodename, statuses, stats keyword are separated by a backslash character
# line2 contains a list of all node names and avg; even nodes that do not have entries in the log file (i.e. have not executed yet)
#       each nodename, avg keyword are separated by a backslash character
# line 3 contains the read offset of the last line read by logreader
#
proc LogReader_readTsv { exp_path datestamp } {
   ::log::log debug "LogReader_readTsv execution on ${exp_path}/logs/${datestamp}_nodelog"
   if { ![file exists ${exp_path}/logs/${datestamp}_nodelog] } {
      puts "${exp_path}/logs/${datestamp}_nodelog does not exist"
      return
   }

   # initialize read offset to 0
   SharedData_setExpDatestampOffset ${exp_path} ${datestamp} 0
   set statsVar "SharedFlowNode_${exp_path}_${datestamp}_stats"
   set pair 0
   set cmd ""
   set lines [exec -ignorestderr logreader -e ${exp_path} -d ${datestamp}]
   set last_read_offset [LogReader_getEndOffset ${exp_path} ${datestamp} nodelog]
   set lineCount 0
   foreach line [split $lines "\n"] {
      switch ${lineCount} {
      0 {
	 ::log::log debug "LogReader_readTsv Got Statuses Line--------------------------"
         # node_name2\statuses...\stats...
         set tsvlist [split [string trim $line] "\\"]
         foreach tsvel $tsvlist { 
            ::log::log debug "LogReader_readTsv statuses tsvel:$tsvel pair:$pair"
            if { $pair == 0 && $tsvel != "" } {
               # the first element of the list contains the node name
               set tmpnode $tsvel
               set flowNode [SharedData_getExpNodeMapping ${exp_path} ${datestamp} ${tmpnode}]
               set pair 1
               # puts "LogReader_readTsv statuses tsvel:$tsvel set pair:$pair"
            } elseif { $pair == 1 } {
               # the second element of the list contains the node statuses
	       # example:
	       # statuses {+1 {end 20160317.18:53:33} +2 {end 20160317.18:53:49} +3 {end 20160317.18:53:58} +4^last {end 20160317.18:53:39} all {end 20160317.18:53:58} }
	       #
               set runtimeVar "SharedFlowNode_${exp_path}_${datestamp}_runtime"
               set cmd "tsv::keylset ${runtimeVar} ${flowNode} ${tsvel}"
	       ::log::log debug "LogReaderTsv setting statuses cmd:$cmd"
	       eval ${cmd}
               # post process statuses mainly to know latest members for loops & nptask
               processTsvStatuses ${exp_path} ${datestamp} ${flowNode}
               set pair 2
            } elseif { $pair == 2 } {
               # the third element of the list contains the node stats
               set cmd "tsv::keylset ${statsVar} ${flowNode} ${tsvel}"
	       ::log::log debug "LogReaderTsv setting stats cmd:$cmd"
	       eval ${cmd}
               set pair 0
	       set flowNode ""
            }	    
         }
      }

      1 {
	 ::log::log debug "LogReader_readTsv Got Avg Line----------------------"
	 # node_name2\avg...\node_name3\avg...\node_name4\avg
         set tsvlist [split [string trim $line] "\\"]
         foreach tsvel $tsvlist { 
            ::log::log debug "LogReader_readTsv avg tsvel:$tsvel pair:$pair"
            if { $pair == 0 && $tsvel != "" } {
               # the first element of the list contains the node name
               set tmpnode $tsvel
               set flowNode [SharedData_getExpNodeMapping ${exp_path} ${datestamp} ${tmpnode}]
               set pair 1
               # puts "LogReader_readTsv statuses tsvel:$tsvel set pair:$pair"
            } elseif { $pair == 1 } {
               # the second element of the list contains the node avg values
	       # example:
	       # avg {+1 { exectime 00:00:11 submitdelay 00:00:15 begin 20:13:05 end 20:13:16 deltafromstart 00:00:49 }+2 { exectime 00:00:11 submitdelay 00:00:16 begin 20:13:09 end 20:13:20 deltafromstart 00:00:53 } }
               set cmd "tsv::keylset ${statsVar} ${flowNode} ${tsvel}"
	       ::log::log debug "LogReaderTsv setting avg cmd:$cmd"
	       eval ${cmd}
               set pair 0
	       set flowNode ""
            }
         }
      }

      2 {
         # The last line has the read offset value of the log file in bytes format: last_read_offset 890984
	 ::log::log debug "LogReader_readTsv Got read offset line:$line"
	 eval set ${line}
         SharedData_setExpDatestampOffset ${exp_path} ${datestamp} ${last_read_offset}
	 ::log::log debug "LogReader_readTsv SharedData_getExpDatestampOffset: [SharedData_getExpDatestampOffset ${exp_path} ${datestamp}]"
      }

      }
      # enf of switch
      incr lineCount
   }

   # the returned output from logreader is ordered in the following format splitted by a backslash :
   # node_name1\statuses...\stats...
   if { [SharedData_getMiscData OVERVIEW_MODE] == false } {
      LogReader_readFile ${exp_path} ${datestamp} "msg_center" true
   }
}

# this proc is called by LogReader_readTsv mainly to calculate the
# latest updated values for nodes that have iterations loop, npass_task
proc processTsvStatuses { exp_path datestamp flownode } {

   set runtimeVar "SharedFlowNode_${exp_path}_${datestamp}_runtime"
   set displayInfoVar "SharedFlowNode_${exp_path}_${datestamp}_gui_runtime"

   set nodeType [SharedFlowNode_getGenericAttribute ${exp_path} ${flownode} ${datestamp} type]
   array set statuses {}
   catch { array set statuses [tsv::keylget ${runtimeVar} ${flownode} statuses] }
   if { ${nodeType} == "npass_task" || ${nodeType} == "loop" } {
      foreach { stored_member status } [array get statuses] {
         set currentMax [SharedFlowNode_getMaxExtValue ${exp_path} ${flownode} ${datestamp}]
         set newMax [string length [lindex [split ${stored_member} +] end ] ]
         if { ${newMax} > ${currentMax} } {
            SharedFlowNode_setMaxExtValue  ${exp_path} ${flownode} ${datestamp} ${newMax}
         }
         if { $stored_member == "null" } {
            set statuses(all) $status
            unset statuses($stored_member)
            tsv::keylset ${runtimeVar} ${flownode} statuses "[array get statuses]"
         }
      }
   }
   if { ${nodeType} == "npass_task" } {
      tsv::keylset ${displayInfoVar} ${flownode} latest_member ""
      # how many parent loops do I have
      set nofParentLoops [llength [SharedFlowNode_getGenericAttribute ${exp_path} ${flownode} ${datestamp} loops]]
      if { ${nofParentLoops} != "" } {
         foreach { stored_member status } [array get statuses] {
            # how many index separator do I have from the given member
            set nofSeparators [expr [llength [split ${stored_member} +]] - 1]
            if { [expr ${nofSeparators} > ${nofParentLoops}] } {
               set baseExt [SharedFlowNode_getExtBasePart ${stored_member}]
               if { ${baseExt} != "" } {
                  set latestMemberKey latest_member_${baseExt}
                  if { [tsv::keylget ${displayInfoVar} ${flownode} ${latestMemberKey} {}] == 0 || [tsv::keylget ${displayInfoVar} ${flownode} ${latestMemberKey}] == "" } {
                     tsv::keylset ${displayInfoVar} ${flownode} ${latestMemberKey} $stored_member
                     tsv::keylset ${displayInfoVar} ${flownode} ${latestMemberKey}_timestamp [lindex $status 1]
                  } elseif { [tsv::keylget ${displayInfoVar} ${flownode} ${latestMemberKey}_timestamp {}] != 0 } {
                     set oldtime [tsv::keylget ${displayInfoVar} ${flownode} ${latestMemberKey}_timestamp]
                     set newtime [lindex $status 1]
                     if { [SharedFlowNode_isTimestampOlder $newtime $oldtime] == 1 } {
                        tsv::keylset ${displayInfoVar} ${flownode} ${latestMemberKey} $stored_member
                        tsv::keylset ${displayInfoVar} ${flownode} ${latestMemberKey}_timestamp [lindex $status 1]
                     }
                  }
               }
            } elseif { [expr ${nofSeparators} < ${nofParentLoops}] || [expr ${nofSeparators} == ${nofParentLoops}] } {
               unset statuses($stored_member)
            }
         }
         tsv::keylset ${runtimeVar} ${flownode} statuses "[array get statuses]"
      }
   }

   if { ${nodeType} == "loop" } {
      tsv::keylset ${displayInfoVar} ${flownode} latest_member ""
      set nofParentLoops [llength [SharedFlowNode_getGenericAttribute ${exp_path} ${flownode} ${datestamp} loops]]
      if { ${nofParentLoops} > 1 } {
         foreach { stored_member status } [array get statuses] {
            set nofSeparators [expr [llength [split ${stored_member} +]] - 1]
            if { [expr ${nofParentLoops} - 1] == ${nofSeparators} } {
               if { [tsv::keylget ${displayInfoVar} ${flownode} latest_member {}] == 0 || [tsv::keylget ${displayInfoVar} ${flownode} latest_member] == "" } {
                  tsv::keylset ${displayInfoVar} ${flownode} latest_member $stored_member
                  tsv::keylset ${displayInfoVar} ${flownode} ${stored_member}_timestamp [lindex $status 1]
               } else {
                  set tmp_latest_member [tsv::keylget ${displayInfoVar} ${flownode} latest_member]
                  if { [tsv::keylget ${displayInfoVar} ${flownode} ${tmp_latest_member}_timestamp {}] != 0 } {
                     set oldtime [tsv::keylget ${displayInfoVar} ${flownode} ${tmp_latest_member}_timestamp]
                     set newtime [lindex $status 1]
                     if { [SharedFlowNode_isTimestampOlder $newtime $oldtime] == 1 } {
                        tsv::keylset ${displayInfoVar} ${flownode} latest_member $stored_member
                        tsv::keylset ${displayInfoVar} ${flownode} ${stored_member}_timestamp [lindex $status 1]
                     }
                  }
               }
            }
         }
      }
   } else {
      foreach { stored_member status } [array get statuses] {
         # puts "flownode:$flownode stored_member:$stored_member status:$status"
         if { $stored_member != "null" && $stored_member != "all" } {
            if { [tsv::keylget ${displayInfoVar} ${flownode} latest_member {}] == 0 || [tsv::keylget ${displayInfoVar} ${flownode} latest_member] == "" } {
               tsv::keylset ${displayInfoVar} ${flownode} latest_member $stored_member
               tsv::keylset ${displayInfoVar} ${flownode} ${stored_member}_timestamp [lindex $status 1]
	       # puts "saving tmp_latest_member:$stored_member ${stored_member}_timestamp [lindex $status 1] " 
            } else {
               set tmp_latest_member [tsv::keylget ${displayInfoVar} ${flownode} latest_member]
	       # puts "tmp_latest_member:$tmp_latest_member"
               if { [tsv::keylget ${displayInfoVar} ${flownode} ${tmp_latest_member}_timestamp {}] != 0 } {
                  set oldtime [tsv::keylget ${displayInfoVar} ${flownode} ${tmp_latest_member}_timestamp]
                  set newtime [lindex $status 1]
	          # puts "tmp_latest_member:$tmp_latest_member oldtime:$oldtime newtime:$newtime"
                  if { [SharedFlowNode_isTimestampOlder $newtime $oldtime] == 1 } {
                     tsv::keylset ${displayInfoVar} ${flownode} latest_member $stored_member
                     tsv::keylset ${displayInfoVar} ${flownode} ${stored_member}_timestamp [lindex $status 1]
                  }
               }
            }
         }
      }
   }
}

# read_type is one of all, no_overview, refresh_flow, msg_center
# see LogReader_startExpLogReader for more info
#
proc LogReader_readFile { exp_path datestamp {read_type no_overview} {read_toplog false} } {
   global LOGREADER_UPDATE_NODES_${exp_path}_${datestamp} env
   # ::log::log debug "LogReader_readFile exp_path:${exp_path} datestamp:${datestamp} read_type:${read_type}"
   ::log::log debug "LogReader_readFile exp_path:${exp_path} datestamp:${datestamp} read_type:${read_type} read_toplog:${read_toplog}"
   set LOGREADER_UPDATE_NODES_${exp_path}_${datestamp}  ""
   set isOverviewMode [SharedData_getMiscData OVERVIEW_MODE]
   if { ${isOverviewMode} == true } {
      set overviewThreadId [SharedData_getMiscData OVERVIEW_THREAD_ID]
   }
   set isStartupDone [SharedData_getMiscData STARTUP_DONE]
   ::log::log debug "LogReader_readFile exp_path:${exp_path} datestamp:${datestamp} isStartupDone:${isStartupDone}"
   set sendToOverview false
   set sendToFlow false
   set sendToMsgCenter false
   if { ${isOverviewMode} == true && ${read_type} == "all" } {
      set sendToOverview true
   }
   if { (${read_type} == "all" || ${read_type} == "no_overview" || ${read_type} == "refresh_flow" ) } {
      set sendToFlow true
   }
   if { (${read_type} == "all" || ${read_type} == "no_overview" || ${read_type} == "msg_center" ) } {
      set sendToMsgCenter true
      if { (${isOverviewMode} == true && [SharedData_getExpGroupDisplay ${exp_path}] == "") ||
      	   (${isOverviewMode} == false && (${exp_path} != $env(SEQ_EXP_HOME))) } {
         # in overview mode and the exp is not monitored, we don't send messages up
         set sendToMsgCenter false
      }
   }
   
   set isTopLogRead false
   if { ${datestamp} != "" } {
      set logfile ${exp_path}/logs/${datestamp}_nodelog
      if { ${read_toplog} == true && [file exists ${exp_path}/logs/${datestamp}_toplog] } {
         # read_toplog is only used for overview startup
         # To avoid reading the same entries twice at startup, we need to set the
         # offset of the nodelog to the end of the file at startup
         set logfile ${exp_path}/logs/${datestamp}_toplog
	 set isTopLogRead true
      }
   
      ::log::log debug "LogReader_readFile exp_path:${exp_path} datestamp:${datestamp} logfile:${logfile}"
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
         while {[gets $f_logfile line] >= 0} {
	    if { ${line} != "" } {
               if [ catch { 
	          if { [LogReader_processLine ${exp_path} ${datestamp} ${line} ${sendToOverview} ${sendToFlow} ${sendToMsgCenter}] != 0 } {
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
	          ::log::log notice "ERROR: LogReader_readFile LogReader_processLine ${exp_path} ${datestamp} ${line} ${sendToOverview} ${sendToFlow} ${sendToMsgCenter}"
	          ::log::log notice "ERROR: message: ${message}\n$::errorInfo"
	          puts stderr "ERROR: LogReader_processLine ${exp_path} ${datestamp} ${line} ${sendToOverview} ${sendToFlow} ${sendToMsgCenter} \nmessage: ${message}\n$::errorInfo"
	       }
            }
         }
	 if { ${isTopLogRead} == false } {
	    set logFileOffset [tell ${f_logfile}]
         } else {
            # reset offset to end of nodelog file
	    # after reading toplog
	    set logFileOffset [LogReader_getEndOffset ${exp_path} ${datestamp} nodelog]
	 }

         SharedData_setExpDatestampOffset ${exp_path} ${datestamp} ${logFileOffset}
         catch { close $f_logfile }
      } else {
         ::log::log debug "LogReader_readFile $logfile file does not exists!"
      }
   }

   if { [set LOGREADER_UPDATE_NODES_${exp_path}_${datestamp}] != "" } {
      # the gui runs in the overview thread... so set the update nodes list in shared memory
      SharedData_setExpUpdatedNodes ${exp_path} ${datestamp} [set LOGREADER_UPDATE_NODES_${exp_path}_${datestamp}]
      # let gui knows that he needs to redraw the flow
      if { ${isOverviewMode} == true } {
         # ::log::log notice "LogReader_readFile xflow_redrawNodesEvent ${exp_path} ${datestamp}"
         ::log::log debug "LogReader_readFile xflow_redrawNodesEvent ${exp_path} ${datestamp}"
         # puts "LogReader_readFile xflow_redrawNodesEvent ${exp_path} ${datestamp}"
         thread::send -async ${overviewThreadId} "xflow_redrawNodesEvent ${exp_path} ${datestamp}" SendDone
         vwait SendDone
         ::log::log debug "LogReader_readFile xflow_redrawNodesEvent ${exp_path} ${datestamp} DONE"
         # ::log::log notice "LogReader_readFile xflow_redrawNodesEvent ${exp_path} ${datestamp} DONE"
      } else {
         # in non-overview mode, xflow and LogReader runs within same thread
         # we are sending the request through the thread messaging  instead of direct call
         # so that no dependency on the TK is found in this tcl file
         thread::send [thread::id] "xflow_redrawNodesEvent ${exp_path} ${datestamp}"
      }
   }
}

# process line output from the logreader C, which is a bit different than the regular log file
# for performance improvement
# NOTE: this is not used for now
proc LogReader_processCreaderLine { _exp_path _datestamp _line _toOverview _ToFlow _toMsgCenter } {
   global CREADER_FIELD_SEPARATOR MSG_CENTER_THREAD_ID
   # puts "LogReader_processCreaderLine _line:$_line CREADER_FIELD_SEPARATOR:$CREADER_FIELD_SEPARATOR"
   # split the data for the line based on the separator !~!
   set dataList [textutil::splitx ${_line} ${CREADER_FIELD_SEPARATOR}]
   # assign each value with the respective order
   lassign $dataList timestamp node msgtype loopExt msg

   if { ${_toMsgCenter} == true } {
      if { ${msgtype} == "abort" || ${msgtype} == "info" || ${msgtype} == "event" } {
         if { ${node} == "" } {
            set msgNode NONE
         } else {
            set msgNode ${node}
         }
         # send msg variable in between brackets so no expansion is being made
         # in case it contains dollar signs
         thread::send -async ${MSG_CENTER_THREAD_ID} \
            "MsgCenter_processNewMessage \"${_datestamp}\" ${timestamp} ${msgtype} ${msgNode}${loopExt} {${msg}} ${_exp_path}"
      }
   }

   if { ${_ToFlow} == true } {
      LogReader_processFlowLine ${_exp_path} ${node} ${_datestamp} ${msgtype} ${loopExt} ${timestamp} true
   }

   if { ${_toOverview} == true } {
      if { ![string match "info*" ${msgtype}] && ${msgtype} != "event" } {
         # abortx, endx, beginx type are used for signals we send to the parent containers nodes
         # as a ripple effect... However, in the case of abort messages we don't want these collateral signals
         # to appear in the message center... At this point, we can reset abortx to abort, endx to end and so forth
         if { ${msgtype} != "beginx" } {
            catch { set msgtype [SharedData_getRippleStatusMap ${msgtype}] }
         }
         if { ${node} == [SharedData_getExpRootNode ${_exp_path} ${_datestamp}] } {
            ::log::log debug "LogReader_processCreaderLine to overview time:$timestamp node=$node msgtype=$msgtype"
            ::log::log notice "LogReader_processCreaderLine to overview time:$timestamp node=$node datestamp:${_datestamp} msgtype=$msgtype"
            # puts "LogReader_processLine Overview_updateExp [thread::id] \"${_exp_path}\" \"${_datestamp}\" \"${msgtype}\" \"${timestamp}\""
            # sends the command in async mode to avoid potential deadlock... however the vwait ensures that it waits for the
            # command to be finished before going further
            thread::send -async [SharedData_getMiscData OVERVIEW_THREAD_ID] \
               "Overview_updateExp [thread::id] \"${_exp_path}\" \"${_datestamp}\" \"${msgtype}\" \"${timestamp}\"" SendDone
            vwait SendDone
            # puts "LogReader_processLine Overview_updateExp [thread::id] \"${_exp_path}\" \"${_datestamp}\" \"${msgtype}\" \"${timestamp}\" DONE"
         }
      }
   }

}

proc LogReader_processLine { _exp_path _datestamp _line _toOverview _ToFlow _toMsgCenter } {
   global MSG_CENTER_THREAD_ID env

   if { [string first "TIMESTAMP=" ${_line}] != 0 } {
      return 1
   }

   set tmpline $_line
      if { $tmpline == "" } {
         continue
      }

      set nodeIndex [string first "SEQNODE=" ${tmpline}]
      set node [string range ${tmpline} [expr $nodeIndex + 8] [expr [string first ":MSGTYPE=" ${tmpline} ${nodeIndex}] - 1]]
   
      set typeIndex [string first "MSGTYPE=" ${tmpline}]
      if { $typeIndex == -1 } {
         continue
      }

      set loopIndex [string first "SEQLOOP=" ${tmpline} $typeIndex]
      set msgIndex [string first "SEQMSG=" ${tmpline} $typeIndex]
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

      set timestamp [string range ${tmpline} [expr [string first "TIMESTAMP=" ${tmpline} 0] + 10] [expr $nodeIndex - 2]]
      if { [string length $timestamp] > 18 || [string length $timestamp] < 17} {
         continue
      }
      set type [string range ${tmpline} $typeStartIndex $typeEndIndex]
      if { $type != "" } {
         if { $loopIndex != -1 } {
            set loopExt [string range ${tmpline} $loopStartIndex $loopEndIndex]
         }
         if { $msgIndex != -1 } {
            set msg [string range ${tmpline} $msgStartIndex end]
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
                "MsgCenter_processNewMessage \"${_datestamp}\" ${timestamp} ${type} ${msgNode}${loopExt} {${msg}} ${_exp_path}"
            }
         }

         if { ${_ToFlow} == true } {
	    if { ${type} != "wait" } {
               LogReader_processFlowLine ${_exp_path} ${node} ${_datestamp} ${type} ${loopExt} ${timestamp}
	    } else {
               LogReader_processFlowLine ${_exp_path} ${node} ${_datestamp} ${type} ${loopExt} ${timestamp} ${msg}
	    }
         }

         if { ${_toOverview} == true } {
            if { ![string match "info*" ${type}] && ${type} != "event" } {
               # abortx, endx, beginx type are used for signals we send to the parent containers nodes
               # as a ripple effect... However, in the case of abort messages we don't want these collateral signals
               # to appear in the message center... At this point, we can reset abortx to abort, endx to end and so forth
               if { ${type} != "beginx" } {
                  catch { set type [SharedData_getRippleStatusMap ${type}] }
               }
               if { ${node} == [SharedData_getExpRootNode ${_exp_path} ${_datestamp}] } {
                  ::log::log debug "LogReader_processLine to overview time:$timestamp node=$node type=$type"
                  # ::log::log notice "LogReader_processLine to overview time:$timestamp node=$node datestamp:${_datestamp} type=$type"
                  # puts "LogReader_processLine Overview_updateExp [thread::id] \"${_exp_path}\" \"${_datestamp}\" \"${type}\" \"${timestamp}\""
                  # sends the command in async mode to avoid potential deadlock... however the vwait ensures that it waits for the
                  # command to be finished before going further
                  thread::send -async [SharedData_getMiscData OVERVIEW_THREAD_ID] \
                  "Overview_updateExp [thread::id] \"${_exp_path}\" \"${_datestamp}\" \"${type}\" \"${timestamp}\"" SendDone
                  vwait SendDone
                  # ::log::log notice "LogReader_processLine to overview time:$timestamp node=$node datestamp:${_datestamp} type=$type DONE"
                  # puts "LogReader_processLine Overview_updateExp [thread::id] \"${_exp_path}\" \"${_datestamp}\" \"${type}\" \"${timestamp}\" DONE"
               }
            }
         }
      }
   return 0
}

proc LogReader_processFlowLine { _exp_path _node _datestamp _type _loopExt _timestamp {_msg ""} } {
  #  puts " LogReader_processFlowLine _exp_path:${_exp_path} node:${_node} _datestamp:${_datestamp} type:${_type} _loopExt:${_loopExt}" 
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
            puts stderr "ERROR: LogReader_processFlowLine() _exp_path:${_exp_path} node:${_node} flowNode:${flowNode} _datestamp:${_datestamp} type:${_type} _loopExt:${_loopExt} message: ${message}"
            ::log::log notice "ERROR: LogReader_processFlowLine() _exp_path:${_exp_path} node:${_node} flowNode:${flowNode} _datestamp:${_datestamp} type:${_type} _loopExt:${_loopExt} message: ${message}"
            return
         }
            # 1 - first we take care of setting the node status
            if { ${_type} == "init" } {
               if { ${nodeType} == "loop" || ${nodeType} == "npass_task" } {
                  if { ${_loopExt} != "" } {
                     SharedFlowNode_setMemberStatus ${_exp_path} ${flowNode} ${_datestamp} ${_loopExt} ${statusType} ${_type} ${_timestamp} "" 1
                  } else {
                     # we got an update on the whole loop
                     SharedFlowNode_resetAllStatus ${_exp_path} ${flowNode} ${_datestamp} 1
                  }
               } else { 
                  # current node is not loop
                  if { [SharedFlowNode_getLoops ${_exp_path} ${flowNode} ${_datestamp}] != "" } {
                     # part of parent loop container
                     SharedFlowNode_setMemberStatus ${_exp_path} ${flowNode} ${_datestamp} ${_loopExt} ${statusType} ${_type} ${_timestamp} "" 1
                  } else {
                     SharedFlowNode_resetNodeStatus ${_exp_path} ${flowNode} ${_datestamp}
                  }
               }
            } else {

               # not init state, any other
               if { ${nodeType} == "loop" || ${nodeType} == "npass_task" } {
                  if { ${_loopExt} != "" } {
                     # we got an update on a loop iteration
                     SharedFlowNode_setMemberStatus ${_exp_path} ${flowNode} ${_datestamp} ${_loopExt} ${statusType} ${_type} ${_timestamp} ${_msg}
                  } else {
                     # we got an update on the whole loop
                     SharedFlowNode_setMemberStatus ${_exp_path} ${flowNode} ${_datestamp} all ${statusType} ${_type} ${_timestamp} ${_msg}
                  }
               } else { 
                  # current node is not loop
                  SharedFlowNode_setMemberStatus ${_exp_path} ${flowNode} ${_datestamp} ${_loopExt} ${statusType} ${_type} ${_timestamp} ${_msg}
               }
            }

            # 2 - then we refresh the display... redisplay the node text?
            if { [SharedData_getMiscData STARTUP_DONE] == "true" && [SharedFlowNode_isRefreshNeeded ${_exp_path} ${flowNode} ${_datestamp} ${_loopExt}] == "true" } {
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
   if [ catch { set expLogs [exec -ignorestderr ksh -c $cmd] } message ] {
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

# returns the offset that would point to the end of the log file
# "which_log_file" is either nodelog or toplog
proc LogReader_getEndOffset { exp_path datestamp {which_log_file nodelog} } {
   set endOffset 0
   set logfile ${exp_path}/logs/${datestamp}_${which_log_file}
   set f_logfile [ open $logfile r ]
   seek $f_logfile 0 end
   set endOffset [tell ${f_logfile}]
   catch { close $f_logfile }
   return ${endOffset}
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

