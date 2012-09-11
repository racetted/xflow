package provide SuiteNode 1.0
package require struct::record
namespace import ::struct::record::*

# canvas_info is a tcl array of
# key: canvas_name
# value: canvas_next_y root_node
namespace eval ::SuiteNode {
   namespace export resetDisplayNextY \
      removeDisplayFromSuite setDisplayNextY getDisplayNextY \
      setDisplayRoot getDisplayRoot
}

# active_log empty means we monitor the current exp datestamp log
# active_log not empy means the user is in view history mode
# exp_log is used to hold the exp log last viewed by the log reader
#              it is used to know if the exp log has switched to a new one.
# last_status_info  { status datestamp date time } example { begin 20090726000000 20100908 08:12:43 }
# overview_display_info { startx starty endx endy }
# canvas_info { next_y root_node max_x max_y }
record define SuiteInfo {
   suite_name
   suite_path
   root_node
   {canvas_info {}}
   {node_mapping {}}
   {exp_log ""}
   {overview_after_id ""}
   {overview_group_record ""}
}

proc ::SuiteNode::formatName { suite_path } {
   set formatValue [regsub -all "/" ${suite_path} _]
   set formatValue [regsub -all {[\.]} ${formatValue} _]
   
   return $formatValue
}

proc ::SuiteNode::formatSuiteRecord { suite_path } {
   set formatValue [regsub -all "/" ${suite_path} _]
   set formatValue [regsub -all {[\.]} ${formatValue} _]
   
   return SuiteInfo.$formatValue
}

proc ::SuiteNode::getSuiteRecordFromPath { suite_path } {
   set suiteRecords [record show instance SuiteInfo]
   foreach suiteRecord $suiteRecords {
      if { [$suiteRecord cget suite_path] == $suite_path } {
         return $suiteRecord
      }
   }
   return ""
}

proc ::SuiteNode::resetDisplayNextY { suite canvas } {
   setDisplayNextY $suite $canvas 40
}

proc ::SuiteNode::resetDisplayData { suite canvas } {
   array set canvasList [$suite cget -canvas_info]
   if { [info exists canvasList($canvas)] } {
      set canvasInfo $canvasList($canvas)
      set canvasInfo [lreplace $canvasInfo 0 0 40]
      set canvasInfo [lreplace $canvasInfo 2 2 40]
      set canvasInfo [lreplace $canvasInfo 3 3 40]
      set canvasList($canvas) ${canvasInfo}
      $suite configure -canvas_info [array get canvasList]
   }
}

proc ::SuiteNode::initDisplay { suite canvas } {
   array set canvasList [$suite cget -canvas_info]
   if { ! [info exists canvasList($canvas)] } {
      set canvasList($canvas) [list 40 "/[${suite} cget -suite_name]" 40 40]
      $suite configure -canvas_info [array get canvasList]
   }
}

proc ::SuiteNode::removeDisplayFromSuite { suite canvas } {
   array set canvasList [$suite cget -canvas_info]
   array unset canvasList $canvas
   $suite configure -canvas_info [array get canvasList]
}

proc ::SuiteNode::setDisplayData { suite canvas next_y max_x max_y } {

   ::SuiteNode::initDisplay $suite $canvas
   array set canvasList [$suite cget -canvas_info]
   set canvasInfo $canvasList($canvas)
   if { [expr ${next_y} > [lindex $canvasInfo 0]] } {
      set canvasInfo [lreplace $canvasInfo 0 0 $next_y]
   }

   if { [expr ${max_x} > [lindex $canvasInfo 2]] } {
      set canvasInfo [lreplace $canvasInfo 2 2 $max_x]
   }

   if { [expr ${max_y} > [lindex $canvasInfo 3]] } {
      set canvasInfo [lreplace $canvasInfo 3 3 $max_y]
   }

   set canvasList($canvas) ${canvasInfo}
   $suite configure -canvas_info [array get canvasList]
}

# $suite is the name of a SuiteInfo record
proc ::SuiteNode::setDisplayNextY { suite canvas value } {
   ::SuiteNode::initDisplay $suite $canvas
   array set canvasList [$suite cget -canvas_info]
   set canvasInfo $canvasList($canvas)
   set canvasList($canvas) [lreplace $canvasInfo 0 0 $value]
   $suite configure -canvas_info [array get canvasList]
}

proc ::SuiteNode::getDisplayNextY {suite canvas} {
   ::SuiteNode::initDisplay $suite $canvas
   array set canvasList [$suite cget -canvas_info]
   set canvasInfo $canvasList($canvas)
   return [lindex $canvasInfo 0]
}

proc ::SuiteNode::getDisplayMaximumX {suite canvas} {
   ::SuiteNode::initDisplay $suite $canvas
   array set canvasList [$suite cget -canvas_info]
   set canvasInfo $canvasList($canvas)
   return [lindex $canvasInfo 2]
}

proc ::SuiteNode::getDisplayMaximumY {suite canvas} {
   ::SuiteNode::initDisplay $suite $canvas
   array set canvasList [$suite cget -canvas_info]
   set canvasInfo $canvasList($canvas)
   return [lindex $canvasInfo 3]
}

proc ::SuiteNode::setDisplayRoot { suite canvas value} {
   ::SuiteNode::initDisplay $suite $canvas
   array set canvasList [$suite cget -canvas_info]
   set canvasInfo $canvasList($canvas)
   set canvasInfo [lreplace $canvasInfo 1 1 $value]
   set canvasList($canvas) $canvasInfo
   $suite configure -canvas_info [array get canvasList]
}

proc ::SuiteNode::getDisplayRoot { suite canvas } {
   ::SuiteNode::initDisplay $suite $canvas
   array set canvasList [$suite cget -canvas_info]
   set canvasInfo $canvasList($canvas)
   return [lindex $canvasInfo 1]
}

proc ::SuiteNode::getCanvasList { suite } {
   set canvasList {}
   if { [$suite cget -canvas_info] != "" } {
      foreach {canvas info} [$suite cget -canvas_info] {
         lappend canvasList $canvas
      }
   }

   return $canvasList
}

proc ::SuiteNode::addFlowNodeMapping { suite real_node flow_node } {
   array set nodeMapping [$suite cget -node_mapping]
   set nodeMapping($real_node) $flow_node
   $suite configure -node_mapping [array get nodeMapping]
}

proc ::SuiteNode::getFlowNodeMapping { suite real_node } {
   array set nodeMapping [$suite cget -node_mapping]
   if { [info exists nodeMapping($real_node)] } {
      set flowNode $nodeMapping($real_node)
   } else {
      # if the flow node mapping does not exists, it means that
      # it is the same as the real node.
      set flowNode $real_node
   }
   return $flowNode
}

proc ::SuiteNode::getActiveDatestamp { suite } {
   if { [${suite} cget -exp_log] != "" } {
      set logFileName [${suite} cget -exp_log]
      set startIndex [expr [string last / ${logFileName}] + 1]
      set endIndex [expr [string last _ ${logFileName}] - 1]
      return [string range ${logFileName} ${startIndex} ${endIndex}]
   }
}

# example ::SuiteNode::setStatusInfo $suite begin "20100707000000 20100929 19:05:13"
proc ::SuiteNode::getDatestamps { suite } {
   global StatusInfo
   if { [info globals StatusInfo] == "" } {
      return ""
   }

   array set datestamps {}
   if { [dict exists $StatusInfo ${suite} statuses] } {
      array set datestamps [dict get $StatusInfo ${suite} statuses]
   }
   set values [array names datestamps]
   return [array names datestamps]
}

proc ::SuiteNode::setStatusInfo { suite datestamp status status_info } {
   global StatusInfo
   dict set StatusInfo ${suite} statuses ${datestamp} ${status} ${status_info}
}

proc ::SuiteNode::getStatusInfo { suite datestamp status } {
   global StatusInfo
   set value ""
   if { [info exists StatusInfo] && [dict exists $StatusInfo ${suite} statuses ${datestamp} ${status}] } {
      set value [dict get $StatusInfo ${suite} statuses ${datestamp} ${status}]
   }
   return $value
}

proc ::SuiteNode::removeStatusDatestamp { suite datestamp } {
   puts "::SuiteNode::removeStatusDatestamp $suite $datestamp"
   global StatusInfo
   if { [info globals StatusInfo] == "" } {
      puts "::SuiteNode::removeStatusDatestamp returns empty StatusInfo"
      return ""
   }

   if { [dict exists $StatusInfo ${suite} statuses ${datestamp}] } {
      puts "::SuiteNode::removeStatusDatestamp dict unset StatusInfo ${suite} statuses ${datestamp}"
      dict unset StatusInfo ${suite} statuses ${datestamp}
   }
}

proc ::SuiteNode::test {} {
   global StatusInfo
   dict values $StatusInfo
}

# returns the status date & time as an integer value
# empty string is returned if no value is found
proc ::SuiteNode::getStatusClockValue { suite datestamp status } {
   set value ""
   set statusInfo [::SuiteNode::getStatusInfo ${suite} ${datestamp} ${status}]
   set dateTime "[lindex ${statusInfo} 0] [lindex ${statusInfo} 1]"
   if { [string length ${dateTime}] > 1} {
      set value [clock scan "${dateTime}"]
   }
   proc out {} {
      array set infoList [$suite cget -status_info]
      set value ""
      if { [info exists infoList(${status})] } {
         set statusInfo $infoList(${status})
         set dateTime "[lindex ${statusInfo} 1] [lindex ${statusInfo} 2]"
         if { [string length ${dateTime}] > 1} {
            set value [clock scan "${dateTime}"]
         }
      }
   }
   return ${value}
}

# gives the date & time in seconds that should be
# used to compare with the overview grid limits
# if the start time is greater than current time && 
# end reference time (hh::mm) is prior to current time, 
# return previous day value for the start time
# else return today's value value
proc ::SuiteNode::getStartRelativeClockValue { ref_start_time ref_end_time } {
   set currentDateTime [clock seconds]
   set currentTime [clock format ${currentDateTime} -format "%H:%M" -gmt 1]
   set startDateTime [clock scan ${ref_start_time}]
   set endDateTime [clock scan ${ref_end_time}]
   if { ${startDateTime} > ${currentDateTime} && ${endDateTime} < ${currentDateTime} } {
      set value [clock add ${startDateTime} -24 hours ]
   } else {
      set value ${startDateTime}
   }

   return ${value}
}


proc ::SuiteNode::setLastStatusInfo { suite datestamp status date time } {
   # if the status is beginx and the suite already has a begin value... I don't
   # store the begin time.. this means that it is a ripple effect and I don't want
   # the overview box to be moved to the new time...
   if { ${status} == "beginx" } {
      if { [::SuiteNode::getStatusInfo ${suite} ${datestamp} begin ] == "" } {
         ::SuiteNode::setStatusInfo ${suite} ${datestamp} begin "${date} ${time}"
      }
      ::SuiteNode::setStatusInfo ${suite} ${datestamp} last begin
      # ${suite} configure -last_status begin
   } else {
      ::SuiteNode::setStatusInfo ${suite} ${datestamp} ${status} "${date} ${time}"   
      ::SuiteNode::setStatusInfo ${suite} ${datestamp} last ${status}
      # ${suite} configure -last_status ${status}
   }
}

proc ::SuiteNode::getLastStatus { suite datestamp } {
   #set value [${suite} cget -last_status]
   set value [::SuiteNode::getStatusInfo ${suite} ${datestamp} last]
   if { ${value} == "" } {
      set value init
   }
   return  ${value}
}

proc ::SuiteNode::getLastStatusDatestamp { suite } {
   set lastStatus [${suite} cget -last_status]
   set statusInfo [::SuiteNode::getStatusInfo ${suite} ${lastStatus}]
   set value [lindex ${statusInfo} 0]

   return  ${value}
}

proc ::SuiteNode::getLastStatusTime { suite datestamp } {

   set lastStatus [::SuiteNode::getStatusInfo ${suite} ${datestamp} last]
   set statusInfo [::SuiteNode::getStatusInfo ${suite} ${datestamp} ${lastStatus}]
   set value [lindex ${statusInfo} 1]
   return  ${value}
}

proc ::SuiteNode::getStartTime { suite datestamp } {
   set statusInfo [::SuiteNode::getStatusInfo ${suite} ${datestamp} begin]
   set value [lindex ${statusInfo} 1]
   return ${value}
}

proc ::SuiteNode::getEndTime { suite datestamp } {
   set statusInfo [::SuiteNode::getStatusInfo ${suite} ${datestamp} end]
   set value [lindex ${statusInfo} 1]
   return ${value}
}

# not sure what to do with this for now
# returns true if the suite is in init state,
# has no reference start time and end time.
# I must put it somewhere on the canvas...
# so for now they are parked at the start of 
# my time grid in the overview and must not be time
# shifted.
proc ::SuiteNode::isHomeless {suite datestamp} {
   set value false
   if { [::SuiteNode::getLastStatus ${suite} ${datestamp}] == "init" &&
        [SharedData_getExpTimings [${suite} cget -suite_path]] == "" } {
      set value true
   }

   return ${value}
}
