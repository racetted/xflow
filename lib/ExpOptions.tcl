package require tablelist

proc ExpOptions_showSupportCallback { _exp_path _datestamp parent_widget } {

   set hour ""
   if { ${_datestamp} != "" } {
      set hour [Utils_getHourFromDatestamp ${_datestamp}]
   }
   ExpOptions_showSupport ${_exp_path} ${hour} ${parent_widget}
}

# show support info from xml file
#
# for now the xml is quite small so I don't
# bother storing anything in memory...
# the xml file is simply parse everything the
# functionality is called
proc ExpOptions_showSupport { _exp_path _hour _parent_widget } {
   puts "ExpOptions_showSupport exp_path:${_exp_path} hour:${_hour}"
   package require tablelist
   global env supportData
   #set optionsFile ${exp_path}/ExpOptions.xml
   set expName [file tail ${_exp_path}]
   set supportData {}
   set parentCode ""
   set supportData [SharedData_getExpSupportInfo ${_exp_path}]
   set topW .support_top

   destroy ${topW}

   Utils_positionWindow [toplevel ${topW}] ${_parent_widget}
   wm title ${topW} "Experiment Support Info"
   wm geometry ${topW} =400x200

   set rowFgColor [SharedData_getColor MSG_CENTER_NORMAL_FG]
   set headerBgColor black
   set headerFgColor [SharedData_getColor DEFAULT_HEADER_FG]
   set stripeBgColor [SharedData_getColor MSG_CENTER_STRIPE_BG]
   set normalBgColor [SharedData_getColor MSG_CENTER_NORMAL_BG]

   set defaultAlign center
   set columns [list 0 "Exp" ${defaultAlign} \
                     0 "Executing" ${defaultAlign} \
                     0 "Support Status" ${defaultAlign} ]
   set tableW ${topW}.support_table
   set yscrollW ${topW}.support_sy
   set xscrollW ${topW}.support_sx

   tablelist::tablelist ${tableW} -columns ${columns} \
      -arrowcolor white -spacing 1 -resizablecolumns 1 \
      -stretch all -relief flat -labelrelief flat -showseparators 0 -borderwidth 0 -listvariable  supportData \
      -bg ${normalBgColor} -fg ${rowFgColor} \
      -labelcommand tablelist::sortByColumn -labelbg ${headerBgColor} \
      -labelfg ${headerFgColor} -labelpady 5 \
      -labelfont TkHeadingFont -labelbd 1 -labelrelief raised \
      -stripebg ${stripeBgColor} \
      -yscrollcommand [list ${yscrollW} set] -xscrollcommand [list ${xscrollW} set]

   ${tableW} columnconfigure 2 -wrap 1 -maxwidth 25
   # search the data for the given hour and highlight it
   # set selectedRow [${tableW} searchcolumn 0 ${expName}${_hour}]
   # if { ${selectedRow} != -1 } {
   #   ${tableW} selection clear active
   #   ${tableW} selection set ${selectedRow}
   #   ${tableW} see active
   # }

   # creating scrollbars
   scrollbar ${yscrollW} -command [list ${tableW} yview]
   scrollbar ${xscrollW} -command [list ${tableW} xview] -orient horizontal
   ::autoscroll::autoscroll ${yscrollW}
   ::autoscroll::autoscroll ${xscrollW}

   set buttonFrame [frame ${topW}.button_Frame]
   set closeButton [button ${buttonFrame}.close_button -text Close -command [list destroy ${topW}]]

   grid ${tableW} -row 0 -column 0 -sticky nsew -padx 2 -pady 2
   grid ${yscrollW} -row 0 -column 1 -sticky nsew -padx 2 -pady 2
   grid ${xscrollW} -row 1 -sticky ew

   grid ${closeButton} -padx { 2 2 } -pady 5 -sticky e
   grid ${buttonFrame} -row 2 -column 0 -padx 5 -sticky e

   grid columnconfigure ${topW} 0 -weight 1
   # grid columnconfigure ${topW} 1 -weight 1

   grid rowconfigure ${topW} 0 -weight 1
   grid rowconfigure ${topW} 1 -weight 1
}

proc ExpOptions_getDisplayName { _exp_path } {
   set displayName [SharedData_getExpDisplayName ${_exp_path}]

   return ${displayName}
}

proc ExpOptions_getShortName { _exp_path } {
   set shortName [SharedData_getShortName ${_exp_path}]

   return ${shortName}
}

proc ExpOptions_getCheckIdle { _exp_path } {
   set shortName [SharedData_getExpCheckIdle ${_exp_path}]

   return ${shortName}
}

# returns list with start_time and end_time as {start_time end_time}
# returns empty string if timings cannot be read
proc ExpOptions_getRefTimings { _exp_path _hour } {
   #set optionsFile ${_exp_path}/ExpOptions.xml
   set foundRefTimings ""
   set refTimings [SharedData_getExpTimings ${_exp_path}]
   # set hour [Utils_getHourFromDatestamp ${_datestamp}]
   
   set foundIndex [lsearch -exact -index 0 ${refTimings} ${_hour}]
   if { ${foundIndex} != -1 } {
      set foundRefTimings [lrange [lindex ${refTimings} ${foundIndex}] 1 2]
   }
   return ${foundRefTimings}
}

proc ExpOptions_read { _exp_path } {

   set optionsFile ${_exp_path}/ExpOptions.xml
   if { [file exists ${optionsFile}] } {
      set domDoc [ExpXmlOptions_parse ${optionsFile}]

      # get the display name
      set displayName [ExpXmlOptions_getDisplayName ${domDoc} ${_exp_path}]

      # get the short name
      set shortName [ExpXmlOptions_getShortName ${domDoc} ${_exp_path}]

      # get reference timings
      set refTimings [ExpXmlOptions_getRefTimings ${domDoc}]
      # get reference timings progress
      set refTimingsProgres [ExpXmlOptions_getTimingProgress ${domDoc}]
      # get support info
      set supportData [ExpXmlOptions_getSupport ${domDoc} ${_exp_path} ${shortName}]

      # get auto launch info
      set autoLaunchValue [ExpXmlOptions_getAutoLaunch ${domDoc} ${_exp_path}]

      # get show exp info
      set showExpValue [ExpXmlOptions_getShowExp ${domDoc} ${_exp_path}]

      set checkIdleValue [ExpXmlOptions_getCheckIdle ${domDoc} ${_exp_path}]
      set idleThresholdValue [ExpXmlOptions_getIdleThreshold ${domDoc} ${_exp_path}]
      set submitLateThresholdValue [ExpXmlOptions_getSubmitLateThreshold ${domDoc} ${_exp_path}]

      set scheduleType [ExpXmlOptions_getScheduleInfoType ${domDoc} ${_exp_path}]
      set scheduleValue [ExpXmlOptions_getScheduleInfoValue ${domDoc} ${_exp_path}]
      set isDailyDatestamp [ExpXmlOptions_getDatestampInfoDaily ${domDoc} ${_exp_path}]

      # close xml doc
      ExpXmlOptions_done ${domDoc}


      # store data
      SharedData_setExpDisplayName ${_exp_path} ${displayName}
      SharedData_setExpTimings ${_exp_path} ${refTimings}
      SharedData_setExpTimingProgress ${_exp_path} ${refTimingsProgres}
      SharedData_validateTimingProgress ${_exp_path}
      SharedData_setExpShortName ${_exp_path} ${shortName}
      SharedData_setExpSupportInfo ${_exp_path} ${supportData}
      SharedData_setExpAutoLaunch ${_exp_path} ${autoLaunchValue}
      SharedData_setExpShowExp ${_exp_path} ${showExpValue}
      SharedData_setExpCheckIdle ${_exp_path} ${checkIdleValue}
      SharedData_setExpIdleThreshold ${_exp_path} ${idleThresholdValue}
      SharedData_setExpSubmitLateThreshold ${_exp_path} ${submitLateThresholdValue}
      SharedData_setExpScheduleType ${_exp_path} ${scheduleType}
      SharedData_setExpScheduleValue ${_exp_path} ${scheduleValue}
      SharedData_setExpIsDailyDatestamp ${_exp_path} ${isDailyDatestamp}
   } else {
      SharedData_setExpDisplayName ${_exp_path} [file tail ${_exp_path}]
      SharedData_setExpShortName ${_exp_path} [file tail ${_exp_path}]
      SharedData_setExpScheduleType ${_exp_path} "DAY_OF_WEEK"
      SharedData_setExpScheduleValue ${_exp_path} "0 1 2 3 4 5 6"
      SharedData_setExpIsDailyDatestamp ${_exp_path} true
   }
}

# displays the list of maestroe executables with a short description
