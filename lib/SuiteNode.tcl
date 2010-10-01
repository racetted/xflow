package provide SuiteNode 1.0
package require struct::record
namespace import ::struct::record::*

# canvas_info is a tcl array of
# key: canvas_name
# value: canvas_next_y root_node
namespace eval ::SuiteNode {
   namespace export getSuiteRecord resetDisplayNextY \
      removeDisplayFromSuite setDisplayNextY getDisplayNextY \
      setDisplayRoot getDisplayRoot
}

# active_log empty means we monitor the current exp datestamp log
# active_log not empy means the user is in view history mode
# exp_log is used to hold the exp log last viewed by the log reader
#              it is used to know if the exp log has switched to a new one.
# last_status_info  { status datestamp date time } example { begin 20090726000000 20100908 08:12:43 }
# overview_display_info { startx starty endx endy }
record define SuiteInfo {
   suite_name
   suite_path
   root_node
   ref_start { "" }
   ref_end { "" }
   type
   {canvas_info {}}
   {node_mapping {}}
   bg
   {read_interval 4000}
   {read_offset 0}
   {active_log ""}
   {exp_log ""}
   {overview_display_info {}}
   {overview_after_id ""}
   {overview_group_record ""}
   {status_info {init { "" "" "" }}}
   {last_status {init} }

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

proc ::SuiteNode::getSuiteRecord { canvas } {
   set splitList [split $canvas .]
   set suiteName [lindex $splitList 2]
   set suiteRecord SuiteInfo.$suiteName

   return $suiteRecord
}

proc ::SuiteNode::resetDisplayNextY { suite canvas } {
   setDisplayNextY $suite $canvas 40
}

proc ::SuiteNode::initDisplay { suite canvas } {
   array set canvasList [$suite cget -canvas_info]
   if { ! [info exists canvasList($canvas)] } {
      set suiteRecord [getSuiteRecord $canvas]
      set canvasList($canvas) [list 40 "/[$suiteRecord cget -suite_name]"]
      $suite configure -canvas_info [array get canvasList]
   }
}

proc ::SuiteNode::removeDisplayFromSuite { suite canvas } {
   array set canvasList [$suite cget -canvas_info]
   array unset canvasList $canvas
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
   foreach {canvas info} [$suite cget -canvas_info] {
      lappend canvasList $canvas
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

proc ::SuiteNode::setOverviewInfo { suite startx starty endx endy } {
   set value "$startx $starty $endx $endy"
   $suite configure -overview_display_info $value
}

proc ::SuiteNode::getOverviewInfo { suite } {
   return [$suite cget -overview_display_info]
}

proc ::SuiteNode::getOverviewInfoStartx { suite } {
   return [lindex [$suite cget -overview_display_info] 0]
}

proc ::SuiteNode::getOverviewInfoStarty { suite } {
   return [lindex [$suite cget -overview_display_info] 1]
}

proc ::SuiteNode::getOverviewInfoEndx { suite } {
   return [lindex [$suite cget -overview_display_info] 2]
}

proc ::SuiteNode::getOverviewInfoEndy { suite } {
   return [lindex [$suite cget -overview_display_info] 3]
}

# the status_info is an array of where the key is
# the status name and the info contains "datestamp date time"
# example "::SuiteNode::getStatusInfo $suite begin" might return
# "20100707000000 20100929 19:05:13"
# an empty string is returned if no info
proc ::SuiteNode::getStatusInfo { suite status } {
   array set infoList [$suite cget -status_info]
   set statusInfo ""
   if { [info exists infoList(${status})] } {
      set statusInfo $infoList(${status})
   }
   return ${statusInfo}
}

# example ::SuiteNode::setStatusInfo $suite begin "20100707000000 20100929 19:05:13"
proc ::SuiteNode::setStatusInfo { suite status status_info } {
   puts "::SuiteNode::setStatusInfo $suite $status $status_info"
   array set infoList [$suite cget -status_info]
   set statusInfo ""
   set infoList(${status}) ${status_info}
   if { ${status} == "init" } {
      set infoList(begin) { "" "" "" }
      set infoList(end) { "" "" "" }
      set infoList(abort) { "" "" "" }
   } elseif { ${status} == "begin" } {
      set infoList(end) { "" "" "" }
      set infoList(abort) { "" "" "" }
   }

   ${suite} configure -status_info [array get infoList]
   ${suite} configure -last_status ${status}
}

# returns the status date & time as an integer value
# empty string is returned if no value is found
proc ::SuiteNode::getStatusClockValue { suite status } {
   array set infoList [$suite cget -status_info]
   set value ""
   if { [info exists infoList(${status})] } {
      set statusInfo $infoList(${status})
      set dateTime "[lindex ${statusInfo} 1] [lindex ${statusInfo} 2]"
      if { [string length ${dateTime}] > 1} {
         set value [clock scan "${dateTime}"]
      }
   }
   return ${value}
}

proc ::SuiteNode::setLastStatusInfo { suite status datestamp date time } {
   ::SuiteNode::setStatusInfo ${suite} ${status} "${datestamp} ${date} ${time}"   
   ${suite} configure -last_status ${status}
}

proc ::SuiteNode::getLastStatus { suite } {
   set value [${suite} cget -last_status]
   return  ${value}
}

proc ::SuiteNode::getLastStatusDateTime { suite } {
   set lastStatus [${suite} cget -last_status]
   set statusInfo [::SuiteNode::getStatusInfo ${suite} ${lastStatus}]
   set value [lrange ${statusInfo} 1 2]

   return  ${value}
}

proc ::SuiteNode::getLastStatusTime { suite } {

   set lastStatus [${suite} cget -last_status]
   set statusInfo [::SuiteNode::getStatusInfo ${suite} ${lastStatus}]
   set value [lindex ${statusInfo} 2]

   # if the value is empty, it likely means that we're
   # dealing with an empty new log file so we return the start time
   if { ${value} == "" } {
       if { [lindex ${statusInfo} 0] == "init" &&
            [${suite} cget -ref_start] != "" } {
         set value "[${suite} cget -ref_start]"
       }
   }
   return  ${value}
}

proc ::SuiteNode::getStartTime { suite } {
   array set infoList [$suite cget -status_info]
   set value ""
   if { [info exists infoList(begin)] } {
      set statusInfo $infoList(begin)
      set value [lindex ${statusInfo} 2]
   }
   return ${value}
}

proc ::SuiteNode::getEndTime { suite } {
   array set infoList [$suite cget -status_info]
   set value ""
   if { [info exists infoList(end)] } {
      set statusInfo $infoList(end)
      set value [lindex ${statusInfo} 2]
   }
   return ${value}
}

# not sure what to do with this for now
# returns true if the suite is in init state,
# has no reference start time and end time.
# I must put it somewhere on the canvas...
# so for now they are parked at the the start of 
# my time grid in the overview and must not be time
# shifted.
proc ::SuiteNode::isHomeless {suite} {
   set value false
   if { [::SuiteNode::getLastStatus ${suite}] == "init" &&
        [${suite} cget -ref_start] == "" } {
      set value true
   }

   return ${value}
}
