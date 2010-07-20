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
record define SuiteInfo {
   suite_name
   suite_path
   ref_start { "" }
   ref_end { "" }
   start_time { "" }
   end_time { "" }
   last_status { "init" }
   last_status_time { "00:00" }
   type
   {canvas_info {}}
   {node_mapping {}}
   bg
   {read_interval 4000}
   {read_offset 0}
   {active_log ""}
   {exp_log ""}
}

proc ::SuiteNode::formatName { suite_path } {
   set formatValue [regsub -all "/" ${suite_path} _]
   set formatValue [regsub -all {[\.]} ${formatValue} _]
   
   return $formatValue
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

