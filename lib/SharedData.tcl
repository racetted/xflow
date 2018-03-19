package require Thread

# This is a generic to store data for a specific experiment in
# a shared memory structure... This data can be retrieved from
# all threads within the application i.e. overview thread, msg center and experiment threads
#

# exp_path is the full path of the experiment i.e. SEQ_EXP_HOME
# key is the key for the specific value
proc SharedData_setExpData { exp_path key value } {
   if { [tsv::names SharedData_${exp_path}] == "" } {
      # does not exists... create it
      set initValues [list ${key} ${value}]
      tsv::array set SharedData_${exp_path} ${initValues}
   } else {
      array set values [tsv::array get SharedData_${exp_path}]
      set values(${key}) ${value}
      tsv::array set SharedData_${exp_path} [array get values]
   }
}

# retrieve experiment data based on the exp_path and the key
proc SharedData_getExpData { exp_path key } {
   set returnedValue ""
   if { [tsv::exists SharedData_${exp_path} ${key}] } {
      array set values [tsv::array get SharedData_${exp_path} ${key}]      
      set returnedValue $values(${key})
   }
   return ${returnedValue}
}

# removes experiment data based on the exp_path and the key
proc SharedData_unsetExpData { exp_path key } {
   if { [tsv::exists SharedData_${exp_path} ${key}] } {
      array set values [tsv::array get SharedData_${exp_path}]
      array unset values ${key}
      tsv::array reset SharedData_${exp_path} [array get values]
   }
}

proc SharedData_getExpDatestampMutex { exp_path datestamp } {
   # puts "SharedData_getExpDatestampMutex ${exp_path}_${datestamp} called"
   set mutexValue ""
   foreach { key mutexValue } [tsv::array get SharedData_ExpMutex ${exp_path}_${datestamp}] {}
   if { ${mutexValue} == "" } {
       thread::mutex lock [SharedData_getMiscData COMMON_MUTEX]
       # set mutexValue [thread::mutex create -recursive]
       set mutexValue [thread::mutex create]
       tsv::array set SharedData_ExpMutex ${exp_path}_${datestamp} ${mutexValue}
       thread::mutex unlock [SharedData_getMiscData COMMON_MUTEX]
   }
   # puts "SharedData_getExpDatestampMutex ${exp_path}_${datestamp} DONE"
   return ${mutexValue}
}

proc SharedData_removeExpDatestampMutex { exp_path datestamp } {
   catch { tsv::unset SharedData_ExpMutex ${exp_path}_${datestamp} }
}

proc SharedData_setExpDatestampData { exp_path datestamp key value } {
   # puts "SharedData_setExpDatestampData ${exp_path}_${datestamp} called"
   set expDatestampMutex [SharedData_getExpDatestampMutex ${exp_path} ${datestamp}]
   thread::mutex lock ${expDatestampMutex}
   # puts "SharedData_setExpDatestampData ${expDatestampMutex} locked"

      tsv::keylset SharedData_${exp_path}_${datestamp} data ${key} ${value}

   thread::mutex unlock ${expDatestampMutex}
   # puts "SharedData_setExpDatestampData exp_path:${exp_path} datestamp:$datestamp key:$key value:$value DONE"
}

proc SharedData_removeExpDatestampData { exp_path datestamp } {
   ::log::log notice "SharedData_removeExpDatestampData() exp_path:${exp_path} datestamp:${datestamp}"
   # puts "SharedData_removeExpDatestampData() exp_path:${exp_path} datestamp:${datestamp}"
   catch { after cancel [SharedData_getExpOverviewUpdateAfterId ${exp_path} ${datestamp}] }
   # ::log::log notice "SharedData_removeExpDatestampData() exp_path:${exp_path} datestamp:${datestamp} reset done"

   ::log::log notice "SharedData_removeExpDatestampData() exp_path:${exp_path} datestamp:${datestamp} getting lock"
   set expDatestampMutex [SharedData_getExpDatestampMutex ${exp_path} ${datestamp}]
   # puts "SharedData_removeExpDatestampData ${expDatestampMutex} locked"
   thread::mutex lock ${expDatestampMutex}

   ::log::log notice "SharedData_removeExpDatestampData() exp_path:${exp_path} datestamp:${datestamp} unset "
   # puts "SharedData_removeExpDatestampData() unset exp_path:${exp_path} datestamp:${datestamp}"
   catch { tsv::unset SharedData_${exp_path}_${datestamp} }

   ::log::log notice "SharedData_removeExpDatestampData() exp_path:${exp_path} datestamp:${datestamp} unlock"
   # puts "SharedData_removeExpDatestampData() exp_path:${exp_path} datestamp:${datestamp} unlocking..."
   thread::mutex unlock ${expDatestampMutex}
   ::log::log notice "SharedData_removeExpDatestampData() exp_path:${exp_path} datestamp:${datestamp} unset done"
   # puts "SharedData_removeExpDatestampData() exp_path:${exp_path} datestamp:${datestamp} unset done"
   # puts "SharedData_removeExpDatestampData() exp_path:${exp_path} datestamp:${datestamp} DONE"
}

# retrieve experiment data based on the exp_path and the key
proc SharedData_getExpDatestampData { exp_path datestamp key } {
   # puts "SharedData_getExpDatestampData() exp_path:${exp_path} datestamp:${datestamp} key:$key"
   set returnedValue ""
   set keys ""
   catch { set keys [tsv::keylkeys SharedData_${exp_path}_${datestamp} data] }
   if { [lsearch ${keys} ${key}] != -1 } {
      # puts "SharedData_getExpDatestampData() exp_path:${exp_path} datestamp:${datestamp} key:$key"
      set returnedValue [tsv::keylget SharedData_${exp_path}_${datestamp} data ${key}]
   }
   # puts "SharedData_getExpDatestampData() exp_path:${exp_path} datestamp:${datestamp} key:$key DONE"
   return ${returnedValue}
}

# removes experiment data based on the exp_path and the key
proc SharedData_unsetExpDatestampData { exp_path datestamp key } {
   # puts "SharedData_unsetExpDatestampData() exp_path:${exp_path} datestamp:${datestamp}"
   catch { tsv::keyldel SharedData_${exp_path}_${datestamp} data ${key} }
   # puts "SharedData_unsetExpDatestampData() exp_path:${exp_path} datestamp:${datestamp} DONE"
}

# retrieves the experiment thread id
# There is usually a thread associated with an experiment and a datestamp in the
# following cases:
# 1) The flow is currently viewed by the user
# 2) The flow is currently active (log file modified within the last hour)
# 3) The flow is being read at application startup
proc SharedData_getExpThreadId { _exp_path _datestamp } {
   set threadId ""
   catch {
      set threadId [SharedData_getExpDatestampData ${_exp_path} ${_datestamp} thread_id]
   }
   return ${threadId}
}

# removes the thread id associated with the experiment datestamp
proc SharedData_removeExpThreadId { _exp_path _datestamp } {
   SharedData_unsetExpDatestampData ${_exp_path} ${_datestamp} thread_id
}

# sets the thread id associated with the experiment datestamp 
proc SharedData_setExpThreadId { _exp_path _datestamp  _thread_id } { 
   SharedData_setExpDatestampData ${_exp_path} ${_datestamp} thread_id ${_thread_id}
}

# sets the log file offset associated with the experiment datestamp
# the offset is used by the LogReader to know where to read the log file between
# reads.
proc SharedData_setExpDatestampOffset { exp_path datestamp {offset 0} } {
   SharedData_setExpDatestampData ${exp_path} ${datestamp} offset ${offset}
}

# retrieves the log file offset associated with the experiment datestamp
proc SharedData_getExpDatestampOffset { _exp_path _datestamp } {
   set offset 0
   catch {
      set offset [SharedData_getExpDatestampData ${_exp_path} ${_datestamp} offset]
   }
   return ${offset}
}

proc SharedData_setExpOverviewUpdateAfterId { _exp_path _datestamp _afterid } {
   SharedData_setExpDatestampData ${_exp_path} ${_datestamp} update_afterid ${_afterid}
}

proc SharedData_getExpOverviewUpdateAfterId { _exp_path _datestamp } {
   SharedData_getExpDatestampData ${_exp_path} ${_datestamp} update_afterid
}

proc SharedData_setExpGroupDisplay { _exp_path _groupDisplay } {
   SharedData_setExpData ${_exp_path} groupdisplay ${_groupDisplay}
}

proc SharedData_setExpRootNode { _exp_path _datestamp _rootNode } {
   SharedData_setExpDatestampData ${_exp_path} ${_datestamp} rootnode ${_rootNode}
}

proc SharedData_getExpRootNode { _exp_path _datestamp } {
   set rootNode [SharedData_getExpDatestampData ${_exp_path} ${_datestamp} rootnode]
   return ${rootNode}
}

proc SharedData_setExpNodeLogCache { _exp_path _datestamp _cached } {
   SharedData_setExpDatestampData ${_exp_path} ${_datestamp} nodelogcache ${_cached}
}

proc SharedData_getExpNodeLogCache { _exp_path _datestamp } {
   set cached false
   catch {
      set cached [SharedData_getExpDatestampData ${_exp_path} ${_datestamp} nodelogcache]
   }
   if { ${cached} == "" } {
      set cached false
   }
   return ${cached}
}

proc SharedData_setExpHeartbeat { _exp_path _datestamp _threadId _timeSeconds _offset } {
   SharedData_setExpDatestampData ${_exp_path} ${_datestamp} heartbeat "${_threadId} ${_timeSeconds} ${_offset}"
}

proc SharedData_getExpHeartbeat { _exp_path _datestamp } {
   set heartbeatData [SharedData_getExpDatestampData ${_exp_path} ${_datestamp} heartbeat]
   return ${heartbeatData}
}

proc SharedData_getExpGroupDisplay { _exp_path } {
   set groupDisplay [SharedData_getExpData ${_exp_path} groupdisplay]
   return ${groupDisplay}
}

proc SharedData_setExpDisplayName { _exp_path _displayName } {
   SharedData_setExpData ${_exp_path} displayname ${_displayName}
}

proc SharedData_getExpDisplayName { _exp_path } {
   set displayName [SharedData_getExpData ${_exp_path} displayname]
   return ${displayName}
}

proc SharedData_setExpTimings { _exp_path _timings } {
   SharedData_setExpData ${_exp_path} ref_timings ${_timings}
}

proc SharedData_getExpTimings { _exp_path } {
   set timings [SharedData_getExpData ${_exp_path} ref_timings]
   return ${timings}
}

# _timings is a list of the following format
# {ref_level1 ref_level2}
# {00:10:00 00:15:00}
proc SharedData_setExpTimingProgress { _exp_path _timings } {
   SharedData_setExpData ${_exp_path} ref_timings_progres ${_timings}
}

# returns a list of the following format
# {ref_level1 ref_level2}
# {00:10:00 00:15:00}
# returns empty string if no value defined for the exp
proc SharedData_getExpTimingProgress { _exp_path } {
   set timingProgress [SharedData_getExpData ${_exp_path} ref_timings_progres]
   return ${timingProgress}
}

proc SharedData_getTimingProgressLevel1 { _exp_path } {
   set timingProgressLevel1 ""
   set timingProgress [SharedData_getExpData ${_exp_path} ref_timings_progres]
   if { ${timingProgress} != "" } {
      set timingProgressLevel1 [lindex ${timingProgress} 0]
   } else {
      set timingProgressLevel1 [SharedData_getMiscData TIMING_PROGRESS_REF_LEVEL1]
   }

   return ${timingProgressLevel1}
}

proc SharedData_getTimingProgressLevel2 { _exp_path } {
   set timingProgressLevel2 ""
   set timingProgress [SharedData_getExpData ${_exp_path} ref_timings_progres]
   if { ${timingProgress} != "" } {
      set timingProgressLevel2 [lindex ${timingProgress} 1]
   } else {
      set timingProgressLevel2 [SharedData_getMiscData TIMING_PROGRESS_REF_LEVEL2]
   }
   return ${timingProgressLevel2}
}

# if _exp_path null, validates only the default values
# if _exp_path not null, validates values from ExpOptions.xml if any
proc SharedData_validateTimingProgress { {_exp_path ""} } {
   # format is 00:10:00 00:15:00
   set progressTimingLevel1 [SharedData_getMiscData TIMING_PROGRESS_REF_LEVEL1]
   set progressTimingLevel2 [SharedData_getMiscData TIMING_PROGRESS_REF_LEVEL2]
   set timeFormat {%H:%M:%S}

   if { [catch { clock scan ${progressTimingLevel1} -format {%H:%M:%S} } ] } {
      error "ERROR: Invalid timing_progress_ref_level1 definition in maestrorc; format must be HH:MM:SS"
      Utils_fatalError . "Startup Error" "Invalid timing_progress_ref_level1 definition in maestrorc; format must be HH:MM:SS exp=${_exp_path}"
   }

   if { [catch { clock scan ${progressTimingLevel2} -format {%H:%M:%S} } ] } {
      Utils_fatalError . "Startup Error" "Invalid timing_progress_ref_level2 definition in maestrorc; format must be HH:MM:SS exp=${_exp_path}"
   }

   if { ${_exp_path} != "" } {
      set expTimingProgress [SharedData_getExpData ${_exp_path} ref_timings_progres]
      if { ${expTimingProgress} != "" } {
         set expTimingProgressLevel1 [lindex ${expTimingProgress} 0]
         set expTimingProgressLevel2 [lindex ${expTimingProgress} 1]
         if { [catch { clock scan ${expTimingProgressLevel1} -format {%H:%M:%S} } ] } {
	    Utils_fatalError . "Startup Error" "Invalid TimingProgres ref_level1 definition in ExpOptions.xml; format must be HH:MM:SS exp=${_exp_path}"
         }
         if { [catch { clock scan ${expTimingProgressLevel2} -format {%H:%M:%S} } ] } {
	    Utils_fatalError . "Startup Error" "Invalid TimingProgres ref_level2 definition in ExpOptions.xml; format must be HH:MM:SS exp=${_exp_path}"
         }
      }
   }
}

proc SharedData_setExpHeartbeat { _exp_path _datestamp _threadId _timeSeconds _offset } {
   SharedData_setExpDatestampData ${_exp_path} ${_datestamp} heartbeat "${_threadId} ${_timeSeconds} ${_offset}"
}

proc SharedData_getExpHeartbeat { _exp_path _datestamp } {
   set heartbeatData [SharedData_getExpDatestampData ${_exp_path} ${_datestamp} heartbeat]
   return ${heartbeatData}
}

proc SharedData_getExpGroupDisplay { _exp_path } {
   set groupDisplay [SharedData_getExpData ${_exp_path} groupdisplay]
   return ${groupDisplay}
}

proc SharedData_setExpDisplayName { _exp_path _displayName } {
   SharedData_setExpData ${_exp_path} displayname ${_displayName}
}

proc SharedData_getExpDisplayName { _exp_path } {
   set displayName [SharedData_getExpData ${_exp_path} displayname]
   return ${displayName}
}

proc SharedData_setExpTimings { _exp_path _timings } {
   SharedData_setExpData ${_exp_path} ref_timings ${_timings}
}

proc SharedData_getExpTimings { _exp_path } {
   set timings [SharedData_getExpData ${_exp_path} ref_timings]
   return ${timings}
}

proc SharedData_setExpSupportInfo { _exp_path _supportInfo } {
   SharedData_setExpData ${_exp_path} supportinfo ${_supportInfo}
}

proc SharedData_getExpSupportInfo { _exp_path } {
   set info [SharedData_getExpData ${_exp_path} supportinfo]
   return ${info}
}

proc SharedData_setExpShortName { _exp_path _shortName } {
   SharedData_setExpData ${_exp_path} shortname ${_shortName}
}

proc SharedData_getExpShortName { _exp_path } {
   set info [SharedData_getExpData ${_exp_path} shortname]
   return ${info}
}

# true | false
proc SharedData_setExpAutoLaunch { _exp_path _autoLaunch} {
   SharedData_setExpData ${_exp_path} autolaunch ${_autoLaunch}
}

proc SharedData_getExpAutoLaunch { _exp_path } {
   set autoLaunchValue [SharedData_getExpData ${_exp_path} autolaunch]
   if { ${autoLaunchValue} == "" } {
      set autoLaunchValue true
   }
   return ${autoLaunchValue}
}

# sets the check idle flag for the exp, this value comes from the ExpOptions.xml
proc SharedData_setExpCheckIdle { _exp_path _checkIdle } {
   SharedData_setExpData ${_exp_path} checkidle ${_checkIdle}
}

# gets the check idle flag for the exp, this value comes from the ExpOptions.xml
proc SharedData_getExpCheckIdle { _exp_path } {
   set checkIdleValue [SharedData_getExpData ${_exp_path} checkidle ]
   if { ${checkIdleValue} == "" } {
      set checkIdleValue true
   }
   return ${checkIdleValue}
}

# sets exp log idle threshold value in minutes
proc SharedData_setExpIdleThreshold { _exp_path _idle_threshold } {
   SharedData_setExpData ${_exp_path} idle_threshold ${_idle_threshold}
}

# exp log idle threshold value in minutes
# try to read value from exp if it has a value (ExpOptions.xml)
# if not, read from global value
proc SharedData_getExpIdleThreshold { _exp_path } {
   set idleThresholdValue [SharedData_getExpData ${_exp_path} idle_threshold ]
   if { ${idleThresholdValue} == "" } {
      set idleThresholdValue [SharedData_getMiscData OVERVIEW_EXP_IDLE_THRESHOLD]
   }
   return ${idleThresholdValue}
}

# sets exp log idle threshold value in minutes
proc SharedData_setExpSubmitLateThreshold { _exp_path _submit_late_threshold } {
   SharedData_setExpData ${_exp_path} submit_late_threshold ${_submit_late_threshold}
}

# exp check submission late threshold value in minutes
# try to read value from exp if it has a value (ExpOptions.xml)
# if not, read from global value
proc SharedData_getExpSubmitLateThreshold { _exp_path } {
   set submitLateThresholdValue [SharedData_getExpData ${_exp_path} submit_late_threshold ]
   if { ${submitLateThresholdValue} == "" } {
      set submitLateThresholdValue [SharedData_getMiscData OVERVIEW_EXP_SUBMIT_LATE_THRESHOLD]
   }
   return ${submitLateThresholdValue}
}

# true | false
proc SharedData_setExpShowExp { _exp_path _showExp } {
   SharedData_setExpData ${_exp_path} showexp ${_showExp}
}

proc SharedData_getExpShowExp { _exp_path } {
   set showExpValue [SharedData_getExpData ${_exp_path} showexp]
   if { ${showExpValue} == "" } {
      set showExpValue true
   }
   return ${showExpValue}
}

proc SharedData_setExpScheduleType { _exp_path _schedType } {
   SharedData_setExpData ${_exp_path} sched_type ${_schedType}
}

proc SharedData_getExpScheduleType { _exp_path } {
   set info [SharedData_getExpData ${_exp_path} sched_type]
   return ${info}
}

proc SharedData_setExpScheduleValue { _exp_path _schedValue } {
   SharedData_setExpData ${_exp_path} sched_value ${_schedValue}
}

proc SharedData_getExpScheduleValue { _exp_path } {
   set info [SharedData_getExpData ${_exp_path} sched_value]
   return ${info}
}

proc SharedData_setExpIsDailyDatestamp { _exp_path _isDaily } {
   SharedData_setExpData ${_exp_path} daily_datestamp ${_isDaily}
}

proc SharedData_getExpIsDailyDatestamp { _exp_path } {
   set info [SharedData_getExpData ${_exp_path} daily_datestamp]
   return ${info}
}

# true | false
proc SharedData_setExpModules { _exp_path _datestamp _modules } {
   SharedData_setExpDatestampData ${_exp_path} ${_datestamp} modules ${_modules}
}

proc SharedData_addExpModule { _exp_path _datestamp _module } {
   set modules [SharedData_getExpDatestampData ${_exp_path} ${_datestamp} modules]
   if { [lsearch ${modules} ${_module}] == -1 } {
      lappend modules ${_module}
      SharedData_setExpModules ${_exp_path} ${_datestamp} ${modules}
   }
}

proc SharedData_getExpModules { _exp_path _datestamp } {
   set modules [SharedData_getExpDatestampData ${_exp_path} ${_datestamp} modules]
   return ${modules}
}

proc SharedData_setExpUpdatedNodes { _exp_path _datestamp _nodeList } {
   SharedData_setExpDatestampData ${_exp_path} ${_datestamp} updated_nodes ${_nodeList}
}

proc SharedData_getExpUpdatedNodes { _exp_path _datestamp} {
   set nodeList [SharedData_getExpDatestampData ${_exp_path} ${_datestamp} updated_nodes]
   return ${nodeList}
}

# value of _checkIdleFlag is 1 or 0 to indicate user has
# does not want more warnings for exp idle
# 0 is the default value when not set i.e. means want warnings
# 1 means no more warnings
# This value is for each run datesamp as the user can change the value
proc SharedData_setExpStopCheckIdle { _exp_path _datestamp _checkIdleFlag } {
   SharedData_setExpDatestampData ${_exp_path} ${_datestamp} stop_check_idle ${_checkIdleFlag}
}

proc SharedData_getExpStopCheckIdle { _exp_path _datestamp} {
   set checkIdleFlag 0
   catch { set checkIdleFlag [SharedData_getExpDatestampData ${_exp_path} ${_datestamp} stop_check_idle] }
   if { ${checkIdleFlag} == "" } {
      set checkIdleFlag 0
   }
   return ${checkIdleFlag}
}

# value of _checkSubmitLateFlag is 1 or 0 to indicate user has
# does not want more warnings for submit late
# 0 is the default value when not set i.e. means want warnings
# 1 means no more warnings
proc SharedData_setExpStopCheckSubmitLate { _exp_path _datestamp _checkSubmitLateFlag } {
   SharedData_setExpDatestampData ${_exp_path} ${_datestamp} stop_check_submit_late ${_checkSubmitLateFlag}
}

proc SharedData_getExpStopCheckSubmitLate { _exp_path _datestamp} {
   set checkSubmitLateFlag 0
   catch { set checkSubmitLateFlag [SharedData_getExpDatestampData ${_exp_path} ${_datestamp} stop_check_submit_late] }
   if { ${checkSubmitLateFlag} == "" } {
      set checkSubmitLateFlag 0
   }
   return ${checkSubmitLateFlag}
}

proc SharedData_setExpFlowSize { _exp_path _datestamp _flow_size } {
   SharedData_setExpDatestampData ${_exp_path} ${_datestamp} flow_size ${_flow_size}
}

proc SharedData_getExpFlowSize { _exp_path _datestamp} {
   set flow_size [SharedData_getExpDatestampData ${_exp_path} ${_datestamp} flow_size]
   return ${flow_size}
}

proc SharedData_addExpNodeMapping { _exp_path _datestamp _real_node _flow_node } {
 #  puts "SharedData_addExpNodeMapping exp_path:${_exp_path} datestamp:${_datestamp} real_node:${_real_node} flow_node:${_flow_node}"
   # ::log::log notice "SharedData_addExpNodeMapping()  exp_path:${_exp_path} datestamp:${_datestamp} real_node:${_real_node} flow_node:${_flow_node}"

   array set nodeMappings [SharedData_getExpDatestampData ${_exp_path} ${_datestamp} node_mappings]
   set nodeMappings(${_real_node}) ${_flow_node}

   SharedData_setExpDatestampData ${_exp_path} ${_datestamp} node_mappings [array get nodeMappings]
}

proc SharedData_getExpNodeMapping { _exp_path _datestamp _real_node } {
   # puts "SharedData_getExpNodeMapping exp_path:${_exp_path} datestamp:${_datestamp} real_node:${_real_node}"
   set flowNode ${_real_node}
      array set nodeMapping [SharedData_getExpDatestampData ${_exp_path} ${_datestamp} node_mappings]
      if { [info exists nodeMapping(${_real_node})] } {
         set flowNode $nodeMapping(${_real_node})
      }

   # puts "SharedData_getExpNodeMapping exp_path:${_exp_path} datestamp:${_datestamp} real_node;${_real_node} flowNode:${flowNode}"
   return ${flowNode}
}

proc SharedData_isExpNodeMappingExists { _exp_path _datestamp } {
  set isExist false
   catch {
      if { [SharedData_getExpDatestampData ${_exp_path} ${_datestamp} node_mappings] != "" } {
         set isExist true
      }
   }
   return ${isExist}
}

proc SharedData_resetExpDisplayData { _exp_path _datestamp _canvas } {
   array set canvasList [SharedData_getExpDatestampData ${_exp_path} ${_datestamp} canvases]

   if { [info exists canvasList(${_canvas})] } {
      set canvasList(${_canvas}) [list 40 "/[file tail ${_exp_path}]" 40 40]
      SharedData_setExpDatestampData ${_exp_path} ${_datestamp} canvases [array get canvasList]
   }
}

proc SharedData_initExpDisplayData { _exp_path _datestamp _canvas } {
   array set canvasList [SharedData_getExpDatestampData ${_exp_path} ${_datestamp} canvases]
   if { ! [info exists canvasList(${_canvas})] } {
      set canvasList(${_canvas}) [list 40 "/[file tail ${_exp_path}]" 40 40]
      SharedData_setExpDatestampData ${_exp_path} ${_datestamp} canvases [array get canvasList]
   }
}

proc SharedData_setExpDisplayData { _exp_path _datestamp _canvas next_y max_x max_y } {
   array set canvasList [SharedData_getExpDatestampData ${_exp_path} ${_datestamp} canvases]
   if { ! [info exists canvasList(${_canvas})] } {
      SharedData_initExpDisplayData ${_exp_path} ${_datestamp} ${_canvas}
      array set canvasList [SharedData_getExpDatestampData ${_exp_path} ${_datestamp} canvases]
   }

   set canvasInfo $canvasList(${_canvas})

   if { [expr ${next_y} > [lindex $canvasInfo 0]] } {
      set canvasInfo [lreplace $canvasInfo 0 0 $next_y]
   }

   if { [expr ${max_x} > [lindex $canvasInfo 2]] } {
      set canvasInfo [lreplace $canvasInfo 2 2 $max_x]
   }

   if { [expr ${max_y} > [lindex $canvasInfo 3]] } {
      set canvasInfo [lreplace $canvasInfo 3 3 $max_y]
   }

   set canvasList(${_canvas}) ${canvasInfo}
   SharedData_setExpDatestampData ${_exp_path} ${_datestamp} canvases [array get canvasList]
}

proc SharedData_setExpDisplayNextY { _exp_path _datestamp _canvas _value } {
   array set canvasList [SharedData_getExpDatestampData ${_exp_path} ${_datestamp} canvases]
   if { ! [info exists canvasList(${_canvas})] } {
      SharedData_initExpDisplayData ${_exp_path} ${_datestamp} ${_canvas}
      array set canvasList [SharedData_getExpDatestampData ${_exp_path} ${_datestamp} canvases]
   }
   set canvasInfo $canvasList(${_canvas})
   set canvasList($_canvas) [lreplace $canvasInfo 0 0 $_value]
   SharedData_setExpDatestampData ${_exp_path} ${_datestamp} canvases [array get canvasList]
}

proc SharedData_setExpDisplayRoot { _exp_path _datestamp _canvas _value } {
   array set canvasList [SharedData_getExpDatestampData ${_exp_path} ${_datestamp} canvases]
   if { ! [info exists canvasList(${_canvas})] } {
      SharedData_initExpDisplayData ${_exp_path} ${_datestamp} ${_canvas}
      array set canvasList [SharedData_getExpDatestampData ${_exp_path} ${_datestamp} canvases]
   }
   set canvasInfo $canvasList(${_canvas})
   set canvasList($_canvas) [lreplace $canvasInfo 1 1 $_value]
   SharedData_setExpDatestampData ${_exp_path} ${_datestamp} canvases [array get canvasList]
}

proc SharedData_getExpDisplayNextY { _exp_path _datestamp _canvas } {
   array set canvasList [SharedData_getExpDatestampData ${_exp_path} ${_datestamp} canvases]
   if { ! [info exists canvasList(${_canvas})] } {
      SharedData_initExpDisplayData ${_exp_path} ${_datestamp} ${_canvas}
      array set canvasList [SharedData_getExpDatestampData ${_exp_path} ${_datestamp} canvases]
   }
   set canvasInfo $canvasList(${_canvas})
   return [lindex ${canvasInfo} 0]
}

proc SharedData_getExpDisplayMaximumX { _exp_path _datestamp _canvas } {
   array set canvasList [SharedData_getExpDatestampData ${_exp_path} ${_datestamp} canvases]
   if { ! [info exists canvasList(${_canvas})] } {
      SharedData_initExpDisplayData ${_exp_path} ${_datestamp} ${_canvas}
      array set canvasList [SharedData_getExpDatestampData ${_exp_path} ${_datestamp} canvases]
   }
   set canvasInfo $canvasList(${_canvas})
   return [lindex $canvasInfo 2]
}

proc SharedData_getExpDisplayMaximumY { _exp_path _datestamp _canvas } {
   array set canvasList [SharedData_getExpDatestampData ${_exp_path} ${_datestamp} canvases]
   if { ! [info exists canvasList(${_canvas})] } {
      SharedData_initExpDisplayData ${_exp_path} ${_datestamp} ${_canvas}
      array set canvasList [SharedData_getExpDatestampData ${_exp_path} ${_datestamp} canvases]
   }
   set canvasInfo $canvasList(${_canvas})
   return [lindex $canvasInfo 3]
}

proc SharedData_getExpDisplayRoot { _exp_path _datestamp _canvas } {
   array set canvasList [SharedData_getExpDatestampData ${_exp_path} ${_datestamp} canvases]
   if { ! [info exists canvasList(${_canvas})] } {
      SharedData_initExpDisplayData ${_exp_path} ${_datestamp} ${_canvas}
      array set canvasList [SharedData_getExpDatestampData ${_exp_path} ${_datestamp} canvases]
   }
   set canvasInfo $canvasList(${_canvas})
   return [lindex $canvasInfo 1]
}

proc SharedData_getExpCanvasList { _exp_path _datestamp } {
   set resultList {}

   array set canvasList [SharedData_getExpDatestampData ${_exp_path} ${_datestamp} canvases]
   foreach {canvas info} [array get canvasList] {
      lappend resultList $canvas
   }

   return ${resultList}
}

proc SharedData_removeExpDisplayData { _exp_path _datestamp _canvas } {
   array set canvasList [SharedData_getExpDatestampData ${_exp_path} ${_datestamp} canvases]
   array unset canvasList ${_canvas}
   SharedData_setExpDatestampData ${_exp_path} ${_datestamp} canvases [array get canvasList]
}

proc SharedData_printNodeMapping { _exp_path _datestamp } {
   array set nodeMapping [SharedData_getExpDatestampData ${_exp_path} ${_datestamp} node_mappings]
   foreach { real_node flow_node } [array get nodeMapping] {
      puts "${_exp_path} ${_datestamp} real_node:${real_node} flow_node:${flow_node}"
   }
}

proc SharedData_setMiscData { key_ value_ } {
   tsv::set misc ${key_} ${value_}
}

proc SharedData_getMiscData { key_ } {
   set value ""
   if { [tsv::exists misc ${key_}] } {
      set value [tsv::set misc ${key_}]
   }
   return ${value}
}

proc SharedData_getColor { key_ } {
   set value ""
   if { [tsv::exists misc ${key_}] } {
     set value [tsv::set misc ${key_}]
   }
   return ${value}
}

proc SharedData_setColor { key_ color_ } {
   tsv::set misc ${key_} ${color_}
}

proc SharedData_initColors {} {
   if { ! [tsv::exists misc CANVAS_COLOR] } {

      SharedData_setColor FLOW_SUBMIT_ARROW "#787878"
      SharedData_setColor FLOW_SUBMIT_ARROW "#787878"

      SharedData_setColor FLOW_FIND_SELECT "#ffe600"
      SharedData_setColor CANVAS_COLOR "#ececec"
      SharedData_setColor SHADOW_COLOR "#676559"
      SharedData_setColor NORMAL_RUN_OUTLINE black
      SharedData_setColor NORMAL_RUN_FILL "#6D7886"
      SharedData_setColor NORMAL_RUN_TEXT black
      SharedData_setColor ACTIVE_BG "#509df4"
      SharedData_setColor SELECT_BG "#509df4"
      #SharedData_setColor SELECT_BG "#3875d7"
      SharedData_setColor DEFAULT_BG "#ececec"
      SharedData_setColor DEFAULT_HEADER_BG "#ececec"
      SharedData_setColor DEFAULT_HEADER_FG "#FFF8DC"
      SharedData_setColor DEFAULT_ROW_FG "#FFF8DC"
      SharedData_setColor DEFAULT_ROW_BG "#ececec"

      SharedData_setColor COLOR_MSG_CENTER_MAIN "#8B1012"
      SharedData_setColor MSG_CENTER_NORMAL_FG "black"
      SharedData_setColor COLOR_MSG_CENTER_ALT "black"
      SharedData_setColor MSG_CENTER_ABORT_FG "white"
      SharedData_setColor MSG_CENTER_STRIPE_BG "grey95"
      SharedData_setColor MSG_CENTER_NORMAL_BG "grey90"

      # the key is the status
      # first color is fg, second color is bg, 3rd is overview box outline
      SharedData_setColor COLOR_STATUS_BEGIN "white #016e11 #016e11"
      SharedData_setColor COLOR_STATUS_INIT "black #ececec black"
      SharedData_setColor COLOR_STATUS_SUBMIT "white #b8bdc3 #b8bdc3"
      SharedData_setColor COLOR_STATUS_ABORT "white #8B1012 #8B1012"
      SharedData_setColor COLOR_STATUS_END "white DodgerBlue3 DodgerBlue3"
      SharedData_setColor COLOR_STATUS_CATCHUP "white #913b9c #913b9c"
      SharedData_setColor COLOR_STATUS_WAIT "black #e7ce69 #e7ce69"
      SharedData_setColor COLOR_STATUS_DISCRET "white #913b9c #913b9c"
      SharedData_setColor COLOR_STATUS_UNKNOWN "white black black"

      # storing original values so I can detect which ones are different
      foreach status [list BEGIN INIT SUBMIT ABORT END CATCHUP WAIT DISCRET] {
         SharedData_setColor ORIG_COLOR_STATUS_${status} [SharedData_getColor COLOR_STATUS_${status}]
      }

      SharedData_setColor STATUS_SHADOW "white black black"
   }
}

# force_check=false return ${status} if not found in mapping
# force_check=true return "" if not found in mapping
proc SharedData_getRippleStatusMap { status {force_check true} } {
   global RIPPLE_STATUS_MAP
   if { ! [info exists RIPPLE_STATUS_MAP] } {
      array set RIPPLE_STATUS_MAP {
         abortx abort
         abort  abort
         end    end
         endx   end
         begin  begin
         beginx begin
         init   init
         submit submit
         wait   wait
         catchup catchup
         discret discret
      }
   }

   if { ${force_check} == true } {
      set foundStatus ""
   } else {
      set foundStatus ${status}
   }

   if { [info exists RIPPLE_STATUS_MAP(${status})] } {
      set foundStatus $RIPPLE_STATUS_MAP(${status})
   }

   return ${foundStatus}
}

# colors that are derived from others
# this proc needs to be called after the maestrorc has been read... caused
# some of the source colors could be defined by the user
proc SharedData_setDerivedColors {} {
   SharedData_setColor COLOR_MSG_CENTER_MAIN [lindex [SharedData_getColor COLOR_STATUS_ABORT] 1]
}

# plugin information file processing
# this proc needs to be called after the maestrorc file has been read because
# the plugin list is provided there
proc SharedData_setPlugins { parent } {
    set pluginList [string toupper ${parent}_plugin_list]
    set pluginFileList [split [SharedData_getMiscData ${pluginList}] ":"]
    set pluginInfo [SharedData_getMiscData PLUGINS]
    foreach fname $pluginFileList {
	set thisPlugin [dict create script "" icon "" helptext "" menuitem "" terminal 1 file ${fname} parent ${parent}]
	set errorMsg ""
	if { [file exists ${fname}] } {
	    set pluginContent [open ${fname} r]
	    while {[gets ${pluginContent} line] >= 0 && ${errorMsg} == "" } {
		#puts "SharedData_readProperties processing line: ${line}"
		if { [string index ${line} 0] != "#" && [string length ${line}] > 0 } {
		    #puts "SharedData_readProperties found data line: ${line}"
		    # the = sign is used to separate between the key and the value.
		    # spaces around the values are trimmed
		    set splittedList [split ${line} =]
		    
		    # if the list does not contain 2 elements, something's not right
		    # output the error message
		    if { [llength ${splittedList}] != 2 } {
			# error "ERROR: While reading ${fileName}\nInvalid property syntax: ${line}"
			set errorMsg "While reading ${fname}\n\nInvalid property syntax: ${line}.\n"
		    } else {
			set propertyName  [string trim [lindex $splittedList 0]] 
			set propertyValue [string trim [lindex $splittedList 1]]
			dict set thisPlugin ${propertyName} ${propertyValue}
		    }
		}
	    }
	    catch { close ${fname} }
	}
	if { ${errorMsg} != "" } {
	    puts "Warning: ${errorMsg}"
	}
	if { [dict exists ${thisPlugin} script] } {
	    lappend pluginInfo ${thisPlugin}
	} else {
	    puts "Warning: script is not defined in $fname.  Not loading it."
	}
    }
    SharedData_setMiscData PLUGINS ${pluginInfo}
}

proc SharedData_init {} {
   SharedData_initColors

   tsv::array set misc [ list \
   COMMON_MUTEX [ thread::mutex create ] \
   CANVAS_BOX_WIDTH 90 \
   CANVAS_X_START 40 \
   CANVAS_Y_START 40 \
   CANVAS_BOX_HEIGHT 43 \
   CANVAS_PAD_X 30 \
   CANVAS_PAD_Y 15 \
   CANVAS_PAD_TXT_X 4 \
   CANVAS_PAD_TXT_Y 23 \
   CANVAS_SHADOW_OFFSET 5 \
   LOOP_OVAL_SIZE 15 \
   SHOW_ABORT_TYPE true \
   SHOW_EVENT_TYPE true \
   SHOW_INFO_TYPE true \
   SHOW_SYSINFO_TYPE true \
   MSG_CENTER_BELL_TRIGGER 15 \
   MSG_CENTER_USE_BELL true \
   MSG_CENTER_FOCUS_GRAB true \
   FONT_BOLD "-*-*-bold-r-normal--11-*-*-*-p-*-iso8859-10" \
   FONT_SIZE 10 \
   FONT_NAME "" \
   FONT_TASK "" \
   FONT_LABEL "" \
   FONT_NAME_SIZE 10 \
   FONT_TASK_SIZE 10 \
   FONT_LABEL_SIZE 10 \
   FONT_NAME_STYLE "normal" \
   FONT_TASK_STYLE "normal" \
   FONT_LABEL_STYLE "normal" \
   FONT_NAME_SLANT "roman" \
   FONT_TASK_SLANT "roman" \
   FONT_LABEL_SLANT "roman" \
   FONT_NAME_UNDERL 0 \
   FONT_TASK_UNDERL 0 \
   FONT_LABEL_UNDERL 0 \
   DEBUG_TRACE 0 \
   FLOW_SCALE 1 \
   AUTO_LAUNCH true \
   AUTO_MSG_DISPLAY true \
   AUTO_MSG_DISPLAY true \
   SUBMIT_POPUP true \
   NODE_DISPLAY_PREF normal \
   COLLAPSE_DISABLED_NODES false \
   STARTUP_DONE false \
   XFLOW_EXP_LABEL_SIZE 25 \
   OVERVIEW_MODE false \
   DEFAULT_CONSOLE "konsole -e" \
   TEXT_VIEWER default \
   USER_TMP_DIR default \
   MENU_RELIEF flat \
   TIMING_PROGRESS_REF_LEVEL1 "00:10:00" \
   TIMING_PROGRESS_REF_LEVEL2 "00:15:00" \
   OVERVIEW_CHECK_EXP_IDLE false \
   OVERVIEW_EXP_IDLE_INTERVAL 60 \
   OVERVIEW_EXP_SUBMIT_LATE_INTERVAL 15 \
   OVERVIEW_EXP_IDLE_THRESHOLD 60 \
   OVERVIEW_EXP_SUBMIT_LATE_THRESHOLD 60 \
   OVERVIEW_NUM_THREADS 4 \
   OVERVIEW_DATESTAMP_RANGE "8 9" \
   OVERVIEW_SHOW_TOOLBAR true \
   DATESTAMP_VISIBLE_LEN 10 \
   ]

   # SharedData_readProperties
}

proc SharedData_readProperties { {rc_file ""} } {
   global env DEBUG_TRACE
   set DEBUG_TRACE [SharedData_getMiscData DEBUG_TRACE]
   set errorMsg ""
   if { ${rc_file} == "" } {
      set fileName $env(HOME)/.maestrorc
   } else {
      set fileName ${rc_file}
   }

   if { [file exists ${fileName}] } {
      set propertiesFile [open ${fileName} r]
      SharedData_setMiscData "RC_FILE" ${fileName}

      while {[gets ${propertiesFile} line] >= 0 && ${errorMsg} == "" } {
         #puts "SharedData_readProperties processing line: ${line}"
         if { [string index ${line} 0] != "#" && [string length ${line}] > 0 } {
            #puts "SharedData_readProperties found data line: ${line}"
            # the = sign is used to separate between the key and the value.
            # spaces around the values are trimmed
            set splittedList [split ${line} =]

            # if the list does not contain 2 elements, something's not right
            # output the error message
            if { [llength ${splittedList}] != 2 } {
               # error "ERROR: While reading ${fileName}\nInvalid property syntax: ${line}"
               set errorMsg "While reading ${fileName}\n\nInvalid property syntax: ${line}.\n"
            } else {
               set keyFound   [string toupper [string trim [lindex $splittedList 0]]]
               set valueFound [string trim [lindex $splittedList 1]]
               #puts "SharedData_readProperties found key:${keyFound} value:${valueFound}"
               puts "maestrorc preference name:${keyFound} value:${valueFound}"
               SharedData_setMiscData ${keyFound} ${valueFound}
            }
         }
      }
      catch { close ${propertiesFile} }

      # validate maestrorc input if any
      # validate overview_datestamp_range
      set overviewDatestampRange [SharedData_getMiscData OVERVIEW_DATESTAMP_RANGE]
      if { ${overviewDatestampRange} != "" } {
         SharedData_setMiscData OVERVIEW_DATESTAMP_RANGE "8 9"
	 catch {
	    set values     [split ${overviewDatestampRange} -]
	    set startIndex [lindex ${values} 0]
	    set endIndex   [lindex ${values} 1]
	    if { ${startIndex} > -1 && ${endIndex} < 15 } {
               SharedData_setMiscData OVERVIEW_DATESTAMP_RANGE "${startIndex} ${endIndex}"
	    }
	 }
      }

      # validate timing progress values
      SharedData_validateTimingProgress

      if { ${errorMsg} != "" } {
         error "ERROR: ${errorMsg}"
      }
   }
}
