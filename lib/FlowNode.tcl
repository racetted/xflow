package provide FlowNodes 1.0
package require struct::record
namespace import ::struct::record::*

#
# statuses: is an array that contains the status of 
# the node or nodes when it's part of a loop for instance.
#
# display_infos: is an array that contains references to canvas where
# this node is located; this node can appear in different canvases
# the array is a hashtable where the key is the canvas and the value is
# "is_collapsed(1 or 0) is_root(1 or 0) x1 y1 x2 y2 max_x max_y children_next_y"
#
# ext: this is used to store the current extension for loop members.
#      ext="" means node is not part of loop
#      ext="default" means we display the last updated member
#      ext=$member means we only display the value of a specific member
#
# latest: is used to store latest ext update of the node
# in case current attribute is set to latest
# type: for now can be
#       family, loop, case
# family :is a dirname reference to the
#          closest family container
# ex: global/assimilation/00
#
# deps: holds dependency data
# it is a tcl array of key/value
# key: dependency_path_name ex: testsuite/bg_check/primary
# value: "dependency_hour dependency_type dependency_status suitename username"
# example:" -6 job complete testsuite n/a"
# "n/a" must be set if the data member has no value
# "
record define FlowNode {
   name
   parent
   family
   container
   {loops {} }
   {statuses {} }
   {latest ""}
   {children ""}
   {display_infos {}}
   {type family}
   {deps {}}
}

record define FlowFamily {
   {record FlowNode flow}
   {record_type "FlowFamily"}
}

record define FlowModule {
   {record FlowNode flow}
   {record_type "FlowModule"}
}

#   catchup
#   cpu
#   host
#   memory
#   mpi
#   queue
#   wallclock
record define FlowTask {
   {record FlowNode flow}
   {record_type "FlowTask"}
   {catchup 4}
   {cpu 1}
   {machine dorval-ib}
   {queue null}
   {wallclock 3}
   {memory 40M}
   {mpi 0}
}

# loop_type can be default , date, or set
# a default has a start,step,end
# i.e. start=0, step=1, end=10
# a set fas a finite list of items
# loop_type can be default, loopset
# i.e. {1 a b c 2}
#
record define FlowLoop {
   {record FlowNode flow}
   {loop_type default}
   start
   step
   end
   {current "latest"}
   {sets ""}
   {record_type "FlowLoop"}
}

record define FlowCase {
   {record FlowNode flow}
   eval_exec
   {record_type "FlowCase"}
}

record define FlowOutlet {
   {record FlowNode flow}
   {record_type "FlowOutlet"}
}

record define FlowNpassTask {
   {record FlowNode flow}
   {record_type "FlowNpassTask"}
   {current "latest"}
   {catchup 4}
   {cpu 1}
   {machine dorval-ib}
   {queue null}
   {wallclock 3}
   {memory 40M}
   {mpi 0}
}

namespace eval ::FlowNodes {
   namespace export addToChildren remFromChildren searchChildren \
      getSequencerNode searchForFamily uncollapseAll
   variable families
}

# return the node that should be passed to the sequencer package API
proc ::FlowNodes::getSequencerNode { node } {
   set containerNode [$node cget -flow.container]
   set nodeLeaf [$node cget -flow.name]
   if {  $containerNode != "" } {
      set realNode $containerNode/$nodeLeaf
   } else {
      set realNode /$nodeLeaf
   }
   return $realNode
}

# canvases widgets in the application have the following pattern:
# .something.${suite_name}.canvas
# example0: .tabs.regional.canvas
# example1: .toplevel_regional_assimilation.regional.canvas
# example1: .toplevel_overview_regional_assimilation.regional.canvas
#
# node has to start with the form overview/${suite}
proc ::FlowNodes::getSuiteFromOverview { node } {
   set splitValues [split $node /]
   return [lindex $splitValues 1]
}

# node has to start with the form overview/${suite}
# strips overview/ from the node name
proc ::FlowNodes::getNodeFromOverview { node } {
   return [string range $node [expr [string first / $node] + 1] end]
}

proc ::FlowNodes::isNodeFromOverview { node } {

   return [string match overview/* $node]
}

# adds a new child to the list of children
# will not do anything if the child is already there
# node has to be FlowFamily FlowTask FlowLoop, etc but
# not FlowNode
proc ::FlowNodes::addToChildren { node new_child  {position end} } {
   #puts "addToChildren called"
   set currentList [$node cget -flow.children]
   if { $currentList != "" && [lsearch $currentList $new_child] != -1 } {
      return
   }

   $node configure -flow.children [linsert $currentList $position $new_child]
}

proc ::FlowNodes::remFromChildren { node new_child } {
   #puts "remFromChildren called"
   set currentList [$node cget -flow.children]
   if { $currentList != "" } {
      set foundIndex [lsearch $currentList $new_child]
      if { $foundIndex != -1 } {
         $node configure -flow.children [lreplace $currentList $foundIndex $foundIndex]
      }
   }
}

# returns the display position of the node withing it's parent 
proc ::FlowNodes::getPosition { node } {
   set parentNode [${node} cget flow.parent]
   set returnValue 0
   if { ${parentNode} != "" } {
      set childList [${parentNode} cget -flow.children]
      if { [expr [llength ${childList}] > 1] } {
         set nodeName [${node} cget flow.name]
         set returnValue [lsearch ${childList} ${nodeName}]
         if { [expr ${returnValue} == -1] } {
            set returnValue 0
         }
      }
   }

   return ${returnValue}
}

# search the node subtree & returns the path of the node that contains a specific child
# returns "" if not found
proc ::FlowNodes::searchForChild { node child } {
   #puts "searchForChild called node:$node child:$child"
   set currentList [$node cget -flow.children]
   set value ""
   if { $currentList != "" } {
      if { [lsearch $currentList $child] != -1 } {
         set value $node
         set foundNode $node
      } else {
         foreach childName $currentList {
            set value [searchForChild $node/$childName $child]
            if { $value != "" } {
               set foundNode $node/$childName
               break
            }
         }
      }
   }
   if { $value != "" } {
      #puts "searchForChild found in $foundNode"
   }
   return $value
}

# search the node uptree & returns the path of the node that
# is of type family
# throw an error if not found
proc ::FlowNodes::searchForFamily { flow_node } {
   #puts "searchForFamily $flow_node"

   set value ""

   if { [$flow_node cget -flow.type] == "family" } {
      set value $flow_node
   } else {
      set value [searchForFamily [$flow_node cget -flow.parent]]
   }

   #puts "searchForFamily $flow_node value:$value"
   if { $value == "" } {
      error "Couldn't locate the closest family node for $flow_node"
   }
   return $value
}

# search the node uptree & returns the path of the node that
# is of type task
# returns empty string if not found
proc ::FlowNodes::searchForTask { flow_node } {
   #puts "searchForTask $flow_node"
   set value ""
   if { $flow_node != "" } {
      if { [$flow_node cget -flow.type] == "task" } {
         set value $flow_node
      } else {
         set value [searchForTask [$flow_node cget -flow.parent]]
      }
   }

   return $value
}

proc ::FlowNodes::addToFamilyList { new_family_node } {
   variable families 
   if { ! [info exists families] } {
      set families $new_family_node
   } else {
      if { [lsearch $families $new_family_node] == -1 } {
         set families [linsert $families 0 $new_family_node]
      }
   }
}

proc ::FlowNodes::printFamilyList {} {
   variable families
   #puts "::FlowNodes::printFamilyList()"
   foreach family $families {
      #puts "family:$family"
   }
}

proc ::FlowNodes::uncollapseAll { node canvas } {
   #puts "::FlowNodes::uncollapseAll node:$node canvas:$canvas"
   if { ![info exists displayInfoList($canvas)] } {
      ::FlowNodes::initNode $node $canvas
   }
   setCollapsed $node $canvas 0
   set currentList [$node cget -flow.children]
   if { $currentList != "" } {
      foreach childName $currentList {
         set childNode $node/$childName
         uncollapseAll $childNode $canvas
      }
   }
}

proc ::FlowNodes::isCollapsed { node canvas } {
   array set displayInfoList [$node cget -flow.display_infos]
   set displayInfo $displayInfoList($canvas)
   set value [lindex $displayInfo 0]
   return $value
}

proc ::FlowNodes::setCollapsed { node canvas value } {
   #puts "::FlowNodes::setCollapsed node:$node canvas:$canvas value:$value"
   array set displayInfoList [$node cget -flow.display_infos]
   set displayInfo $displayInfoList($canvas)
   set displayInfo [lreplace $displayInfo 0 0 $value]
   set displayInfoList($canvas) $displayInfo
   #puts "displayInfo:$displayInfo"
   #puts "array info: [array get displayInfoList]"
   $node configure -flow.display_infos [array get displayInfoList]

   #puts "array info after: [$node cget -flow.display_infos]"

}

# values must be a list of {x1 y1 x2 y2 max_x max_y}
proc ::FlowNodes::setDisplayCoords { node canvas values } {
   #puts "::FlowNodes::setDisplayCoords node:$node canvas:$canvas value:$values"
   array set displayInfoList [$node cget -flow.display_infos]
   set displayInfo $displayInfoList($canvas)
   set displayInfo [lreplace $displayInfo 2 7 $values]
   set displayInfoList($canvas) [join $displayInfo]
   $node configure -flow.display_infos [array get displayInfoList]

   #puts "setDisplayCoords array info after: [$node cget -flow.display_infos]"
}

proc ::FlowNodes::setDisplayLimits { flow_node canvas } {
   set displayCoords [getDisplayCoords $flow_node $canvas]
   set nodeMaxX [lindex $displayCoords 4]
   set nodeMaxY [lindex $displayCoords 5]
   set currentNode $flow_node
   while { $currentNode != "" } {
      set parentNode [$currentNode cget -flow.parent]
      if { $parentNode == "" } {
         break
      }
      #puts "setDisplayLimits parentNode:$parentNode"
      set parentDispCoords [getDisplayCoords $parentNode $canvas]
      set parentMaxX [lindex $parentDispCoords 4]
      set parentMaxY [lindex $parentDispCoords 5]

      set isChanged 0
      if { $nodeMaxX  > $parentMaxX } {
         set parentDispCoords [lreplace $parentDispCoords 4 4 $nodeMaxX]
         set isChanged 0
      }

      if { $nodeMaxY  > $parentMaxY } {
         set parentDispCoords [lreplace $parentDispCoords 5 5 $nodeMaxY]
         set isChanged 0
      }
      
      if { $isChanged } {
         setDisplayCoords $parentNode $canvas $parentDispCoords
      }
      set currentNode $parentNode
   }
}

proc ::FlowNodes::setDisplayY { flow_node canvas value } {
   # set value for current node to be used by children node
   array set displayInfoList [${flow_node} cget -flow.display_infos]
   set displayInfo $displayInfoList($canvas)
   set displayInfo [lreplace $displayInfo 8 8 ${value}]
   set displayInfoList($canvas) [join $displayInfo]
   ${flow_node} configure -flow.display_infos [array get displayInfoList]

}

proc ::FlowNodes::getDisplayY { flow_node canvas } {

   array set displayInfoList [${flow_node} cget -flow.display_infos]
   set displayInfo $displayInfoList($canvas)
   return [lindex ${displayInfo} 8]
}

proc ::FlowNodes::getDisplayCoords { node canvas} {
   array set displayInfoList [$node cget -flow.display_infos]
   set displayInfo $displayInfoList($canvas)
   return [lrange $displayInfo 2 7]
}

proc ::FlowNodes::setIsRootNode { node canvas value} {
   array set displayInfoList [$node cget -flow.display_infos]
   set displayInfo $displayInfoList($canvas)
   set displayInfo [lreplace $displayInfo 1 1 $value]
   set displayInfoList($canvas) $displayInfo
   $node configure -flow.display_infos [array get displayInfoList]
}

proc ::FlowNodes::isRootNode { node canvas } {
   array set displayInfoList [$node cget -flow.display_infos]
   set displayInfo $displayInfoList($canvas)
   set value [lindex $displayInfo 1]
   return $value
}

proc ::FlowNodes::initNode { node canvas} {
   # puts "::FlowNodes::initNode node:$node canvas:$canvas"
   array set displayInfoList [$node cget -flow.display_infos]
   if { ! [info exists displayInfoList($canvas)] } {
      # puts "::FlowNodes::initNode creating canvas:$canvas"
      set displayInfoList($canvas) {1 0 0 0 0 0 0 0 40}
      $node configure -flow.display_infos [array get displayInfoList]
   }
   
}

proc ::FlowNodes::resetNodeStatus { node } {
   ::FlowNodes::resetAllStatus $node init
   set childList [$node cget -flow.children]
   if { $childList != "" } {
      foreach childName $childList {
         set childNode $node/$childName
         ::FlowNodes::resetNodeStatus $childNode
      }
   }
}

proc ::FlowNodes::removeDisplayFromNode { node canvas {is_recursive 0}} {
   #puts "::FlowNodes::initNode node:$node canvas:$canvas"
   array set displayInfoList [$node cget -flow.display_infos]
   array unset displayInfoList $canvas
   $node configure -flow.display_infos [array get displayInfoList]
   if { $is_recursive } {
      set childList [$node cget -flow.children]
      if { $childList != "" } {
         foreach childName $childList {
            set childNode $node/$childName
            removeDisplayFromNode $childNode $canvas 1
         }
      }
   }
}

proc ::FlowNodes::getDisplayList { node } {
   array set displayInfoList [$node cget -flow.display_infos]
   return [array names displayInfoList]
}

proc ::FlowNodes::setMemberStatus { node member new_status {timestamp ""} {is_recursive 0} } {
   if { [$node cget -flow.type] == "npass_task"} {
      ::FlowNodes::setNptMemberStatus ${node} ${member} ${new_status} ${timestamp}
   } else {

      array set statusList [$node cget -flow.statuses]
   
      if { $member == "" } {
         set statusList(null) $new_status
      } else {
         if { ${new_status} == "init" } {
            if { [info exists statusList($member)] } {
               unset statusList($member)
            }
         } else {
            if { ${timestamp} != "" } {
               set statusList($member) "${new_status} ${timestamp}"
            } else {
               set statusList($member) "${new_status}"
            }
         }
         $node configure -flow.latest $member
      }
      
      $node configure -flow.statuses [array get statusList]
   }

   if { $is_recursive } {
      set childList [$node cget -flow.children]
      if { $childList != "" } {
         foreach childName $childList {
            set childNode $node/$childName
            ::FlowNodes::setMemberStatus $childNode $member $new_status ${timestamp} 1
         }
      }
   }
}

proc ::FlowNodes::resetAllStatus { node new_status {is_recursive 0} } {
   ${node} configure -flow.latest ""
   catch { ${node} configure -flow.current "" }
   if { [$node cget -flow.type] == "npass_task"} {
      # for npass_task, we need to empty all the indexes
      $node configure -flow.statuses {}
   } else {
      array set statusList [$node cget -flow.statuses]
      foreach { member status } [$node cget -flow.statuses] {
         set statusList($member) $new_status
      }
      $node configure -flow.statuses [array get statusList]
   }

   if { $is_recursive } {
      set childList [$node cget -flow.children]
      if { $childList != "" } {
         foreach childName $childList {
            set childNode $node/$childName
            ::FlowNodes::resetAllStatus $childNode $new_status 1
         }
      }
   }
}

proc ::FlowNodes::getMemberStatus { node member } {
   set values "init"
   if { $member == "" } {
      set member "null"
   }
   # get the latest member 
   if { $member == "latest" } {
      set member [$node cget -flow.latest]
   }
   array set statusList [$node cget -flow.statuses]
   if { [info exists statusList($member)] } {
      set values $statusList($member)
   }
   set value [lindex ${values} 0]
   return $value
}

# returns the extension text that should be displayed
proc ::FlowNodes::getExtDisplay { node loop_ext } {
   set displayValue ""
   if { [$node cget -flow.type] == "loop" || [$node cget -flow.type] == "npass_task"} {
      if { $loop_ext == "all" || $loop_ext == "latest" } {
         return ""
      }
   }

   if { $loop_ext != "" } {
      if { $loop_ext != "latest" } {
         set displayValue "\[$loop_ext\]"
         # replace the first _ by [
         set displayValue [string replace $loop_ext 0 0 \[]
         # add ] at the end
         set displayValue "${displayValue}]"
         # replace any _ by ][
         set displayValue [string map {_ \]\[} $displayValue]
      } else {
         set displayValue "\[\]"
      }
   }

   return $displayValue
}

# adds a loop to the current container
# it is an ordered list of loop nodes
proc ::FlowNodes::addLoop { current_node loop_node } {
   #puts "::FlowNodes::addLoop adding loop: loop_node to node:$current_node"
   set loopList [$current_node cget -flow.loops]
   set loopList [linsert $loopList 0 $loop_node]
   $current_node configure -flow.loops $loopList
}

# search uptree for parent loops and add it to the
# current node
proc ::FlowNodes::searchParentLoops { node src_node } {
   if { $node != "" } {
      if { [$node cget -flow.type] == "loop" } {
         ::FlowNodes::addLoop $src_node $node
      }
      searchParentLoops [$node cget -flow.parent] $src_node
   }
}

# returns the extension of the current node based
# on parent loops
proc ::FlowNodes::getNodeExtension { current_node } {
   set extension ""
   set loopList [$current_node cget -flow.loops]
   if { [${current_node} cget -flow.type] == "npass_task" } {
      # current index selection for the nptask
      set nptExtension "[${current_node} cget -current]"
      set parentLoopExt [::FlowNodes::getParentLoopExt ${current_node}]
      if { ${parentLoopExt} == "latest" || ${nptExtension} == "latest" } {
         # get latest if any of selection is latest
         set extension [${current_node} cget -flow.latest]
      } else {
         # get npt extension corresponding to loop extension
         set extension ${parentLoopExt}${nptExtension}
      }
   } else {
      foreach loopNode $loopList {
         set currentExt [${loopNode} cget -current]
         if { $currentExt == "latest" } {
            return [$current_node cget -flow.latest]
         }
         set extension "${extension}[${loopNode} cget -current]"
      }
   }
   return $extension
}

# returns 1 if the node requires a display refresh
# returns 0 if not
proc ::FlowNodes::isDisplayUpdate { current_node updated_ext } {
   DEBUG "::FlowNodes::isDisplayUpdate current_node:$current_node updated_ext:$updated_ext"
   set extension ""
   if { [${current_node} cget -flow.type] == "npass_task" } {
      set extension [${current_node} cget -current]
      if { ${extension} == "latest" } {
         set extension "*"
      }
   } else {
      set loopList [${current_node} cget -flow.loops]
      foreach loopNode ${loopList} {
         set currentExt [${loopNode} cget -current]
         if { ${currentExt} == "latest" } {
            set currentExt "*"
         }
         set extension "${extension}${currentExt}"
      }
   }
   DEBUG "::FlowNodes::isDisplayUpdate extension:$extension updated_ext:$updated_ext"

   return [string match "${extension}" ${updated_ext}]
}

# returns the node extension that should be used
# for listings
# user should have chosen an extension or all
# loops should be "latest"
proc ::FlowNodes::getListingNodeExtension { current_node {full_loop "0"} } {
   set extension ""
   set count 0
   set latestCount 0
   set loopList [$current_node cget -flow.loops]
   set numberOfLoops [llength $loopList]
   if { [${current_node} cget -flow.type] == "npass_task" } {
      set currentNptExt [${current_node} cget -current]
      if { ${loopList} != "" } {
         set parentLoopExt [::FlowNodes::getParentLoopExt ${current_node}]
         if { ${parentLoopExt} == "latest" } {
            if { ${currentNptExt} != "latest" } {
               # npt index cannot be selected if parent loop is on latest
               return "-1"
            }
            set extension [${current_node} cget -flow.latest]
         } else {
            if { ${currentNptExt} == "latest" } {
               # npt cannot be latest if parent loop is not latest
               return "-1"
            } else {
               set extension ${parentLoopExt}${currentNptExt}
            }
         }
      }
   } else {
      foreach loopNode $loopList {
         incr count
         set currentExt [${loopNode} cget -current]
         # this part is only for loop nodes
         if { ${full_loop} == "1" && $count == $numberOfLoops } {
            set currentExt ""
         }
         if { $currentExt == "latest" } {
            incr latestCount
            set latestExt [${loopNode} cget -flow.latest]
            if { $latestExt == "all" } {
               set currentExt ""
            } else {
               set currentExt $latestExt
            }
         }
         # the all extension is used for loop nodes to store
         # the status of the loop node as a whole
         set extension "${extension}${currentExt}"
      }
      if { $latestCount != 0 && $latestCount != [llength $loopList] } {
         # user has a mix of latest and loop index, can't figure out
         # which one to use send an error
         set extension "-1"
      } elseif { $latestCount != 0 } {
         # user is on latest mode, get the latest for the current node
         set extension [${current_node} cget -flow.latest]
         if { $extension == "all" } {
            set extension ""
         }
      }
   }

   return $extension
}

# returns the loop info text that should be displayed
proc ::FlowNodes::getLoopInfo { loop_node } {
   set txt ""
   switch [$loop_node cget -loop_type] {
      default {
         set start [$loop_node cget -start]
         set step [$loop_node cget -step]
         set setValue [$loop_node cget -sets]
         set end [$loop_node cget -end]
         if { $setValue == "" } {
            set txt "\[${start},${end},${step}\]"
         } else {
            set txt "\[${start},${end},${setValue}\]"
         }
      }
   }

   return $txt
}

# returns a list of all extensions belonging to the
# current loop node
proc ::FlowNodes::getLoopExtensions { loop_node } {
   set extensions {}
   switch [$loop_node cget -loop_type] {
      default {
         set start [$loop_node cget -start]
         set step [$loop_node cget -step]
         set setValue [$loop_node cget -sets]
         if { $setValue != "" } {
            set step 1
         }
         set end [$loop_node cget -end]
         set count $start
         while { [expr $count <= $end] } {
            lappend extensions $count
            set count [expr $count + $step]
         }
      }
   }

   return $extensions
}

# returns the input arguments as expected by the
# sequencer for loop arguments
# it builds the loop arguments for all loops
# contained in the node loops attribute
proc ::FlowNodes::getLoopArgs { node } {
   set args ""
   set count 0
   #set isLatest 0
   set loopList [${node} cget -flow.loops]
   if { [llength $loopList] > 0 } {
      foreach loopNode $loopList {
         set current [${loopNode} cget -current]
         if { $current == "latest" } {
            #set isLatest 1
            return ""
            break
         } else {
            # remove the + sign before extension
            set current [string range $current 1 end]
            set nodeName [${loopNode} cget -flow.name]
            if { $count == 0 } {
               set args "-l ${nodeName}=${current}"
            } else {
               set args "${args},${nodeName}=${current}"
            }
         }
         incr count
      }
   }
   return $args
}

proc ::FlowNodes::hasLoops { node } {
   set loopList [${node} cget -flow.loops]
   if { [llength $loopList] > 0 } {
      return 1
   }
   return 0
}

# strips separator from real index value 
# for instance +001 will return 001
proc ::FlowNodes::getIndexValue { value } {
   set returnValue $value
   if { [string first "+" $value] == 0 } {
      catch { set returnValue [string range $value 1 end] }
   }
   return $returnValue
}

# get parent loop extension
proc ::FlowNodes::getParentLoopExt { node } {
   set parentExt ""
   set count 0
   set isLatest 0
   set loopList [${node} cget -flow.loops]

   foreach loopNode $loopList {
      set current [${loopNode} cget -current]
      if { ${loopNode} == ${node} } {
         break
      }
      if { $current == "latest" } {
         set parentExt latest
      } else {
         if { $count == 0 } {
            set parentExt "${current}"
         } else {
            set parentExt "${parentExt}${current}"
         }
      }
      incr count
   }
   return ${parentExt}
}

proc ::FlowNodes::getParentLoopArgs { node } {
   set args ""
   set count 0
   set isLatest 0
   set loopList [${node} cget -flow.loops]

   if { [llength $loopList] > 1 } {
      foreach loopNode $loopList {
         set current [${loopNode} cget -current]
         if { $node != $loopNode && $current == "latest" } {
            set args "-1"
            return $args
         } else {
            # remove the + sign before extension
            if { $node == ${loopNode} } {
               break
            }
            set current [string range $current 1 end]
            set nodeName [${loopNode} cget -flow.name]
            if { $count == 0 } {
               set args "-l ${nodeName}=${current}"
            } else {
               set args "${args},${nodeName}=${current}"
            }
         }
         incr count
      }
   }
   return $args
}

# npass_index argument is used when user is provided manual
# the index value at submission time
proc ::FlowNodes::getNptArgs { node {npass_index ""} } {
   set args ""

   set parentLoopArgs [::FlowNodes::getLoopArgs  ${node}]
   if { ${parentLoopArgs} != "" } {
      set parentLoopArgs "${parentLoopArgs},"
   } elseif { [::FlowNodes::hasLoops $node] } {
      return "-1"
   } {
      set parentLoopArgs "-l "
   }

   set nodeName [${node} cget -flow.name]
   if { ${npass_index} != "" } {
      # if npass_index is passed use it...
      # means user has provided it manually
      set args "${parentLoopArgs}${nodeName}=${npass_index}"
   } else {
      set current [${node} cget -current]
      if { $current == "latest" } {
         set args "-1"
         return $args
      } else {
         # remove the + sign before extension
         set current [string range $current 1 end]
         set args "${parentLoopArgs}${nodeName}=${current}"
      }
   }

   return $args
}

# returns the list of extensions application for the npass_task_node
# the npass_task may have a list of many values but they might not
# all be visible if the task is running within a loop...
# for instance if the user selects a loop index then only the npass_task values
# that start with that index is relevant
proc ::FlowNodes::getNptExtensions { npt_node } {
   set extensions {}
   set loopList [${npt_node} cget -flow.loops]
   set loopExt ""
   set isAllLatest true
   set returnedExtensions {}

   array set extensionArray [${npt_node} cget -flow.statuses]
   set extensions [array names extensionArray]
   foreach ext ${extensions} {
      lappend returnedExtensions [string range ${ext} [expr [string last + ${ext}] + 1]  end]
   }
   set returnedExtensions [lsort -unique ${returnedExtensions}]
   return ${returnedExtensions}
}

proc ::FlowNodes::setNptMemberStatus { node member new_status {timestamp ""} } {
   DEBUG "::FlowNodes::setNptMemberStatus  $node $member $new_status" 5
   if { [$node cget -flow.type] != "npass_task" } {
      return
   }

   # check if we are setting one member index only
   # or more

   # how many parent loops do I have
   set nofParentLoops [llength [${node} cget -flow.loops]]

   # how many index separator do I have from the given member
   set nofSeparators [expr [llength [split ${member} +]] - 1]
   array set statusList [$node cget -flow.statuses]

   if { ${nofParentLoops} != "" } {
      if { ${nofSeparators} == ${nofParentLoops} && ${new_status} == "init" } {
         # whole loop iteration
         # need to init all indexes in the npt that matches
         foreach { stored_member status } [array get statusList] {
            puts "comparing ${member}+ ${stored_member}"
            if { [string match ${member}+* ${stored_member}] } {
               # removing is same as init... less data
               puts "removing $stored_member"
               unset statusList($stored_member)
            }
         }
         catch { unset statusList($member) }
         # reset the latest reference if needed
         if { [string match ${member}+* [${node} cget -flow.latest]] } {
            $node configure -flow.latest ""
         }
      } elseif { [expr ${nofSeparators} > ${nofParentLoops}] } {
         # changing one npt index only
         if { ${timestamp} != "" } {
            set statusList($member) "${new_status} ${timestamp}"
         } else {
            set statusList($member) "${new_status}"
         }
         $node configure -flow.latest $member
      } elseif { [expr ${nofSeparators} < ${nofParentLoops}] } {
         # not for myself
         return
      }
   } else {
      # changing one npt member not part of a loop
      if { ${timestamp} != "" } {
         set statusList($member) "${new_status} ${timestamp}"
      } else {
         set statusList($member) "${new_status}"
      }
      $node configure -flow.latest $member
   }

   $node configure -flow.statuses [array get statusList]
}

# change from node+123 to node[123]
proc ::FlowNodes::convertToDisplayFormat { node_with_ext } {
   set firstSepIndex [string first "+" ${node_with_ext}]
   set newNodeName ${node_with_ext}
   if { [expr ${firstSepIndex} != -1] } {
      set newNodeName [string replace ${node_with_ext} ${firstSepIndex} ${firstSepIndex} "\["]
      set newNodeName "${newNodeName}\]"
   }
   return ${newNodeName}
}

# change node[123] back to node+123
proc ::FlowNodes::convertFromDisplayFormat { node_with_ext } {
   set lastSepIndex [string last "\]" ${node_with_ext}]
   set firstSepIndex [string first "\[" ${node_with_ext}]
   set newNodeName ${node_with_ext}
   if { [expr ${lastSepIndex} != -1] } {
      set newNodeName [string range ${node_with_ext} 0 end-1]
      if { [expr ${firstSepIndex} != -1] } {
         set newNodeName [string replace ${newNodeName} ${firstSepIndex} ${firstSepIndex} "+"]
      }
   }
   return ${newNodeName}
}

# returns node from node+123
proc ::FlowNodes::getNodeFromDisplayFormat { node_with_ext } {
   set newNodeName ${node_with_ext}
   set firstSepIndex [string first "+" ${node_with_ext}]
   if { [expr ${firstSepIndex} != -1] } {
      set newNodeName [string range ${node_with_ext} 0 [expr ${firstSepIndex} - 1]]
   }
   return ${newNodeName}
}

# returns +123 from node+123
# return "" if no index
proc ::FlowNodes::getExtFromDisplayFormat { node_with_ext } {
   set extValue ""
   set firstSepIndex [string first "+" ${node_with_ext}]
   if { [expr ${firstSepIndex} != -1] } {
      set extValue [string range ${node_with_ext} ${firstSepIndex} end]
   }
   return ${extValue}
}

# if extension is +1+2+3
# slice 0 will return +1
# slice 1 will return +1+2
# slice 2 will return +1+2+3
proc ::FlowNodes::getExtLeftSlice { extension slice } {
   set extValue ""
   set splittedValues [split ${extension} +]
   if { [llength ${splittedValues}] <= 2 } {
      return ${extension}
   }
   set splittedValues [lrange ${splittedValues} 1 end]
   if { ${slice} >= [llength ${splittedValues}] } {
      return ${extension}
   }

   set count 0
   while { ${count} <= ${slice} } {
      set extValue ${extValue}+[lindex ${splittedValues} ${count}]
      incr count
   }
   return ${extValue}
}

# if extension is +1+2+3
# index 0 will return +1
# index 1 will return +2
# index 2 will return +3
# index lower than 0 returns ""
# index higher than 2 returns ""

proc ::FlowNodes::getExtAtIndex { extension index } {
   set extValue ""
   set splittedValues [split ${extension} +]
   if { $index < 0 } {
      return ""
   }

   if { [llength ${splittedValues}] <= 2 } {
      return ""
   }

   set splittedValues [lrange ${splittedValues} 1 end]

   if { ${index} >= [llength ${splittedValues}] } {
      return ""
   }

   set extValue +[lindex ${splittedValues} ${index}]
   return ${extValue}
}

