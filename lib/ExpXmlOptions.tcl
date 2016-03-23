package require tdom
# sample ExpOptions.xml file
#
#<ExpOptions displayName="HRDPS/West/forecast" shortName="hrdps">
#   <DatestampInfo daily="false"/>
#   <ScheduleInfo sched_type="day_of_week" sched_value="0 1 2 3 4 5 6" />
#   <MonitorInfo auto_launch="false" check_idle="false" idle_threshold="60" submit_late_threshold="15" show_exp="false"/>
#   <SupportInfo executing="Yes" status="All Full Support"/>
#   <TimingProgress ref_level1="00:20:00" ref_level2="00:45:00"/>
#   <Exp hour="00">
#      <TimingInfo ref_start="15:00" ref_end="17:00"/>
#      <SupportInfo executing="Yes" status="Full Support"/>
#   </Exp>
#   <Exp hour="12">
#      <TimingInfo ref_start="21:00" ref_end="22:30"/>
#      <SupportInfo executing="Yes" status="Full Support"/>
#   </Exp>
# </ExpOptions>
#
#
# idle_threshold : threshold value in minutes after which the application will
#                        warn if the exp log file is still idle. 
#                        This is an overwrite at the exp level.
# submit_late_threshold : threshold value in minutes after which the application will warn
#                         if the exp run has still not been launched
# parse the xml file and returns a doc
proc ExpXmlOptions_parse { _xml_file } {
   set doc [dom parse [tDOM::xmlReadFile ${_xml_file}]]
   return ${doc}
}

# when we don't need the doc anymore release it
proc ExpXmlOptions_done { _dom_doc } {
   ${_dom_doc} delete
}

proc ExpXmlOptions_getSupport { _dom_doc _exp_path _exp_name { _exp_hour "" } } {

   # return data
   set results {}

   if { ${_exp_name} != "" } {
      set expName ${_exp_name}
   } else {
      set expName [file tail ${_exp_path}]
   }

   # point to the root element
   set root [${_dom_doc} documentElement root]

   set topXmlNode [${root} selectNodes /ExpOptions]

   set defaultExecStatus No
   set defaultSupportStatus "No Support"
   # get default support for the whole exp
   set supportInfoNode [${topXmlNode} selectNodes ./SupportInfo]
   if { ${supportInfoNode} != "" } {
      set defaultExecStatus [${supportInfoNode} getAttribute executing No]
      set defaultSupportStatus [${supportInfoNode} getAttribute status "No Support"]
   }

   # get the exp hours
   set expHourNodes [${topXmlNode} selectNodes ./Exp]
   foreach expHourNode ${expHourNodes} {
      # get exp hour value
      set expHour [${expHourNode} getAttribute hour ""]
      set expNameHour ${expName}${expHour}
      set supportInfoNode [${expHourNode} selectNodes ./SupportInfo]

      # get support Info for specific exp
      if { ${supportInfoNode} != "" } {
         set executingStatus [${supportInfoNode} getAttribute executing No]
         set supportStatus [${supportInfoNode} getAttribute status "No Support"]
         lappend results [list ${expNameHour} ${executingStatus} ${supportStatus}]
      } else {
         # assign default values
         lappend results [list ${expNameHour} ${defaultExecStatus} ${defaultSupportStatus}]
      }
   }
   return ${results}
}
proc ExpXmlOptions_getTimingProgress { _dom_doc } {

   # point to the root element
   set root [${_dom_doc} documentElement root]

   # retrieve the Exp elements
   # if exp_name is set, we filter it
   # if not set get all exps from the document
   set query "/ExpOptions/TimingProgress"
   set timingProgressNode [${root} selectNodes ${query}]
   set results {}
   if { ${timingProgressNode} != "" } {
      set ref_level1 [${timingProgressNode} getAttribute ref_level1]
      set ref_level2 [${timingProgressNode} getAttribute ref_level2]
      ::log::log debug "ExpXmlOptions_getTimingProgress ref_level1:$ref_level1 ref_level2:$ref_level2"
      set results [list ${ref_level1} ${ref_level2}]
   }
   ::log::log debug "ExpXmlOptions_getTimingProgress results:$results"

   return ${results}
}
proc ExpXmlOptions_getRefTimings { _dom_doc } {

   # point to the root element
   set root [${_dom_doc} documentElement root]

   # retrieve the Exp elements
   # if exp_name is set, we filter it
   # if not set get all exps from the document
   set query "/ExpOptions/Exp/TimingInfo"

   set timingInfoNodes [${root} selectNodes ${query}]
   set results {}
   foreach timingInfoNode ${timingInfoNodes} {
      set expNode [${timingInfoNode} parentNode]
      set expHour [${expNode} getAttribute hour ${expNode}]
      set start [${timingInfoNode} getAttribute ref_start]
      set end [${timingInfoNode} getAttribute ref_end]
      # puts "ExpXmlOptions_getRefTimings ${expHour} ${start} ${end}"
      lappend results [list ${expHour} ${start} ${end}]
   }
   return ${results}
}

proc ExpXmlOptions_getDisplayName { _dom_doc _exp_path } {
   set root [${_dom_doc} documentElement root]

   set defaultDisplayName [file tail ${_exp_path}]

   # retrieve the Exp elements
   # if exp_name is set, we filter it
   # if not set get all exps from the document
   set query "/ExpOptions"

   set rootNode [${root} selectNodes ${query}]
   if { ${rootNode} != "" && [llength ${rootNode}] == 1 } {
      set defaultDisplayName [${rootNode} getAttribute displayName ${defaultDisplayName}]
   }

   return ${defaultDisplayName}
}

proc ExpXmlOptions_getShortName { _dom_doc _exp_path } {
   set root [${_dom_doc} documentElement root]

   set defaultShortName [file tail ${_exp_path}]

   # retrieve the Exp elements
   # if exp_name is set, we filter it
   # if not set get all exps from the document
   set query "/ExpOptions"

   set rootNode [${root} selectNodes ${query}]
   if { ${rootNode} != "" && [llength ${rootNode}] == 1 } {
      set defaultShortName [${rootNode} getAttribute shortName ${defaultShortName}]
   }

   return ${defaultShortName}
}

proc ExpXmlOptions_getAutoLaunch { _dom_doc _exp_path } {
   set autoLaunchValue true
   set root [${_dom_doc} documentElement root]

   set query "/ExpOptions/MonitorInfo"
   set monitorInfoNode [${root} selectNodes ${query}]
   if { ${monitorInfoNode} != "" } {
      set autoLaunchValue [${monitorInfoNode} getAttribute auto_launch true]
   }
   return ${autoLaunchValue}
}

proc ExpXmlOptions_getShowExp { _dom_doc _exp_path } {
   set showExpValue true
   set root [${_dom_doc} documentElement root]

   set query "/ExpOptions/MonitorInfo"
   set monitorInfoNode [${root} selectNodes ${query}]
   if { ${monitorInfoNode} != "" } {
      set showExpValue [${monitorInfoNode} getAttribute show_exp true]
   }
   return ${showExpValue}
}

proc ExpXmlOptions_getCheckIdle { _dom_doc _exp_path } {
   set checkIdleValue true
   set root [${_dom_doc} documentElement root]

   set query "/ExpOptions/MonitorInfo"
   set monitorInfoNode [${root} selectNodes ${query}]
   if { ${monitorInfoNode} != "" } {
      set checkIdleValue  [${monitorInfoNode} getAttribute check_idle true]
   }
   return ${checkIdleValue}
}

proc ExpXmlOptions_getIdleThreshold { _dom_doc _exp_path } {
   set idleThresholdValue ""
   set root [${_dom_doc} documentElement root]

   set query "/ExpOptions/MonitorInfo"
   set monitorInfoNode [${root} selectNodes ${query}]
   if { ${monitorInfoNode} != "" } {
      set idleThresholdValue  [${monitorInfoNode} getAttribute idle_threshold ""]
   }
   return ${idleThresholdValue}
}

proc ExpXmlOptions_getSubmitLateThreshold { _dom_doc _exp_path } {
   set submitLateThresholdValue ""
   set root [${_dom_doc} documentElement root]

   set query "/ExpOptions/MonitorInfo"
   set monitorInfoNode [${root} selectNodes ${query}]
   if { ${monitorInfoNode} != "" } {
      set submitLateThresholdValue  [${monitorInfoNode} getAttribute submit_late_threshold ""]
   }
   return ${submitLateThresholdValue}
}

proc ExpXmlOptions_getScheduleInfoType { _dom_doc _exp_path } {
   set type DAY_OF_WEEK
   set root [${_dom_doc} documentElement root]

   set query "/ExpOptions/ScheduleInfo"
   set scheduleInfoNode [${root} selectNodes ${query}]
   if { ${scheduleInfoNode} != "" } {
      set type [string toupper [${scheduleInfoNode} getAttribute sched_type]]
   }
   return ${type}
}

proc ExpXmlOptions_getScheduleInfoValue { _dom_doc _exp_path } {
   # default executes every day of the week
   set value "0 1 2 3 4 5 6"
   set root [${_dom_doc} documentElement root]

   set query "/ExpOptions/ScheduleInfo"
   set scheduleInfoNode [${root} selectNodes ${query}]
   if { ${scheduleInfoNode} != "" } {
      set value [${scheduleInfoNode} getAttribute sched_value]
   }
   return ${value}
}

# does the exp uses daily datestamps or others like reforecast (historical datestamps)
# or reforecast_stats (future datestamps)
# default is daily datestamp = true
proc ExpXmlOptions_getDatestampInfoDaily { _dom_doc _exp_path } {
   set value true
   set root [${_dom_doc} documentElement root]
   set query "/ExpOptions/DatestampInfo"
   set datestampInfoNode [${root} selectNodes ${query}]
   if { ${datestampInfoNode} != "" } {
      set value [${datestampInfoNode} getAttribute daily true]
   }
   # puts "ExpXmlOptions_getDatestampInfoDaily value:$value"
   return ${value}
}

#global env
#global env
#ExpXmlOptions_read $env(SEQ_EXP_HOME)/ExpOptions.xml
