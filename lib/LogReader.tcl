proc LogReader_readFile { suite_record {is_overview 0} {calling_thread_id ""} {is_startup 0} } {

   # first cancel any other waiting read for this suite
   LogReader_cancelAfter $suite_record
   set suitePath [$suite_record cget -suite_path]
   set dateExec "[getGlobalValue SEQ_BIN]/tictac"
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
         if { "${is_overview}" == "0" } {
            thread::send -async ${calling_thread_id} \
            "dateChanged ${suite_record}"
         }
         ${suite_record} configure -read_offset 0 -exp_log ${logfile}
         puts "LogReader_readFile reading new log file $logfile"
      }
   } else {
      # view history mode
      set logfile $suitePath/logs/${monitorLog}_nodelog
   }
   puts "LogReader_readFile calling_thread_id:$calling_thread_id date:[exec date] suite:[$suite_record cget -suite_path] file:[file tail $logfile]"

   if { [file exists $logfile] } {
      set f_logfile [ open $logfile r ]
      flush stdout
      
      set logFileOffset [$suite_record cget -read_offset]

      # position yourself in the file
      seek $f_logfile $logFileOffset
      
      while {[gets $f_logfile line] >= 0} {
         if { $is_overview == "1" && $calling_thread_id != "" } {
            LogReader_processOverviewLine $calling_thread_id $suite_record $line $is_startup
         }
         LogReader_processLine $calling_thread_id $suite_record $line $is_startup
      }
      
      $suite_record configure -read_offset [tell $f_logfile]
      close $f_logfile
   } else {
      puts "LogReader_readFile $logfile file does not exists! Creating it..."
      close [open $logfile a]
   }

   LogReader_readAgain $suite_record $calling_thread_id
}

proc LogReader_readAgain { suite_record calling_thread_id } {
   global ${suite_record}_READ_LOG_IDS
   
   set READ_INTERVAL [$suite_record cget -read_interval]
   catch { set ${suite_record}_READ_LOG_IDS [after $READ_INTERVAL [list LogReader_readFile $suite_record 0 $calling_thread_id]]}
}

proc LogReader_cancelAfter { suite_record } {
   global ${suite_record}_READ_LOG_IDS
   if { [info exists ${suite_record}_READ_LOG_IDS] } {
      after cancel [set ${suite_record}_READ_LOG_IDS]
   }

}

# this is meant to be running inside a child thread
proc LogReader_processOverviewLine { calling_thread_id suite_record line {is_startup 0} } {  
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
      set timestamp [string range $line 0 [expr $nodeIndex - 2]]
      set node [string range $line $nodeStartIndex $nodeEndIndex]
      set type [string range $line $typeStartIndex $typeEndIndex]
      set msg ""
      if { ! ($node == "" || $type == "") } {
         if { $loopIndex != -1 } {
            set loopExt [string range $line $loopStartIndex $loopEndIndex]
         }
         if { $msgIndex != -1 } {
            set msg [string range $line $msgStartIndex end]
         }
         if { "$node" == "/[$suite_record cget -suite_name]" } {
            DEBUG "LogReader_processOverviewLine time:$timestamp node=$node type=$type" 5
            # Overview_updateExp $suite_record $type $timestamp
            thread::send -async ${calling_thread_id} \
               "Overview_updateExp ${suite_record} ${type} ${timestamp} ${is_startup}"
         } 
      }
   }
}

proc LogReader_processLine { calling_thread_id suite_record line {is_startup 0} } {
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
      set node [string range $line $nodeStartIndex $nodeEndIndex]
      set flowNode [::SuiteNode::getFlowNodeMapping $suite_record $node]
      set type [string range $line $typeStartIndex $typeEndIndex]
      set msg ""
      if { ! ($node == "" || $type == "") } {
         if { $loopIndex != -1 } {
            set loopExt [string range $line $loopStartIndex $loopEndIndex]
         }
         if { $msgIndex != -1 } {
            set msg [string range $line $msgStartIndex end]
         }

         DEBUG "node=$node flowNode:$flowNode type=$type" 5
         DEBUG "message=$msg" 5
         switch [string tolower $type] {
            "init" -
            "begin" -
            "submit" -
            "end" -
            "wait" -
            "catchup" -
            "abort" {
               if { [record exists instance $flowNode] } {
                  set textDisplay [$flowNode cget -flow.name]
                  if { [$flowNode cget -flow.type] == "loop" } {
                     set loopInfoDisplay "[::FlowNodes::getLoopInfo $flowNode]"
                     if { $loopExt != "" } {
                        # we got an update on a loop iteration
                        set extDisplay [::FlowNodes::getExtDisplay $flowNode $loopExt ]
                        #set textDisplay "${textDisplay}\n${extDisplay}\n${loopInfoDisplay}"
                        set textDisplay "${textDisplay}${extDisplay}\n${loopInfoDisplay}"
                        if { [string tolower $type] == "init" } {
                           FlowNodes::setMemberStatus $flowNode $loopExt $type 1
                        } else {
                           FlowNodes::setMemberStatus $flowNode $loopExt $type 0
                        }
                     } else {
                        # we got an update on the whole loop
                        #set textDisplay "${textDisplay}\n${loopInfoDisplay}"
                        set textDisplay "${textDisplay}\n${loopInfoDisplay}"
                        if { [string tolower $type] == "init" } {
                           FlowNodes::resetAllStatus $flowNode init 1
                        } else {
                           FlowNodes::setMemberStatus $flowNode all $type
                        }
                     }
                  } else {
                     if { [string tolower $type] == "init" } {
                        if { [$flowNode cget -flow.loops] != "" } {
                           FlowNodes::setMemberStatus $flowNode $loopExt $type 1
                        } else {
                           ::FlowNodes::resetNodeStatus $flowNode 
                        }
                     }
                     FlowNodes::setMemberStatus $flowNode $loopExt $type
                     if { $loopExt != "" } {
                        # we got an update on a loop iteration
                        set extDisplay [::FlowNodes::getExtDisplay $flowNode $loopExt ]
                        #set textDisplay "${textDisplay}\n${extDisplay}"
                        set textDisplay "${textDisplay}${extDisplay}"
                     }
                  }
                  if { [string tolower $type] == "init" && $is_startup == "0"} {
                     #thread::send ${calling_thread_id} \
                     #   "redrawAllFlow ${suite_record}"
                     redrawAllFlow ${suite_record}
                  }
                  # is display refresh required ?
                  if { [::FlowNodes::isDisplayUpdate $flowNode $loopExt] } {
                     ::DrawUtils::drawNodeStatus $flowNode [getShawdowStatus]
                     set dispPref [getNodeDisplayPrefText $flowNode]
                     if { $dispPref != "" } {
                        set textDisplay "${textDisplay}\n${dispPref}"
                     }
                     ::DrawUtils::drawNodeText $flowNode $textDisplay
                  }
               }
            }
            default {
               puts "LogReader_processLine unhandled type:$type"
            }
         }
      }
   }
}

proc LogReader_getAvailableDates { exp_path } {
   set cmd "cd ${exp_path}/logs; ls *_nodelog | sed -e 's,_nodelog,,'"
   set expLogs ""
   if [ catch { set expLogs [exec ksh -c $cmd] } message ] {
   }
   DEBUG "LogReader_getAvailableDates exp logs: $expLogs" 5
   return $expLogs
}
