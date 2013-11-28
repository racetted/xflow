package require Thread

# This file contains the info of FlowNodes, the nodes that appears in the flow
# The info is mainly stored in two shared structures. It uses tsv shared structures so that
# the information can be shared between the overview main thread, the msg center main thread and
# the experiment datestamp thread that monitors the nodelogger log files.
#
# The firs data structure SharedFlowNode_${exp_path}_${datestamp}  stores the static information of a flow with respect to
# a datestamp: the flow information (submits relation, node types, loop data, etc)
# The second one ${exp_path}_${datestamp}_runtim stores the dynamic information for each node 
# i.e. current status, begin time, abort time, etc.
#
# generic argument:
# exp_path: full path of the experiment i.e. SEQ_EXP_HOME
# node: the flow node as seen in xflow i.e. the submit path and not the container path
# datestamp: the full datestamp in format yyyymmddhh0000

# creates a new node. Mainly called by FlowXml when parsing the flow.xml file.
# submitter: flow node path of the node that submits the new node
# type: one of task, family, module, npass_task, loop
proc SharedFlowNode_createNode { exp_path node datestamp submitter type } {
   # puts "SharedFlowNode_createNode $exp_path $node $submitter $type"
   tsv::keylset SharedFlowNode_${exp_path}_${datestamp} ${node} name [file tail ${node}] type ${type} submitter ${submitter} loops {} submits {} \
      catchup 4 memory 120M cpu 1 queue "" work_unit 0

   if { {$type} == "module" } {
      SharedData_addExpModule ${exp_path} ${node} ${datestamp}
   }
}

# remove the datestamp completely... This is called to cleanup data for a datestamp that is not viewed anymore
#
proc SharedFlowNode_removeDatestamp { exp_path datestamp } {
   ::log::log notice "SharedFlowNode_removeDatestamp ${exp_path} ${datestamp}"

   ::log::log notice "SharedFlowNode_removeDatestamp tsv::unset SharedFlowNode_${exp_path}_${datestamp}_runtime"
   catch { tsv::unset SharedFlowNode_${exp_path}_${datestamp}_runtime }
   ::log::log notice "SharedFlowNode_removeDatestamp tsv::unset SharedFlowNode_${exp_path}_${datestamp}_runtime DONE"

   ::log::log notice "SharedFlowNode_removeDatestamp tsv::unset SharedFlowNode_${exp_path}_${datestamp}"
   catch { tsv::unset SharedFlowNode_${exp_path}_${datestamp} }

   ::log::log notice "SharedFlowNode_removeDatestamp tsv::unset SharedFlowNode_${exp_path}_${datestamp} DONE"
   ::log::log notice "SharedFlowNode_removeDatestamp ${exp_path} ${datestamp} DONE"
}

# this is a generic attribute accessor for the SharedFlowNode_${exp_path}_${datestamp} data structure
proc SharedFlowNode_getGenericAttribute { exp_path node datestamp attr_name } {
   set value ""
   catch {
      set value [tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node} ${attr_name}]
   }
   return ${value}
}

# this is a generic attribute setter for the SharedFlowNode_${exp_path}_${datestamp} data structure
proc SharedFlowNode_setGenericAttribute { exp_path node datestamp attr_name attr_value } {
   tsv::keylset SharedFlowNode_${exp_path}_${datestamp} ${node} ${attr_name} ${attr_value}
}

proc SharedFlowNode_isNodeExist { exp_path node datestamp } {
   set isExist false
   if { [tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node}] != "" } {
      set isExist true
   }
   return ${isExist}
}

proc SharedFlowNode_getNodeType { exp_path node datestamp } {
   tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node} type
}

proc SharedFlowNode_getSubmitter { exp_path node datestamp } {
   tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node} submitter
}

proc SharedFlowNode_getName { exp_path node datestamp } {
   tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node} name
}

proc SharedFlowNode_getQueue { exp_path node datestamp } {
   tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node} queue
}

proc SharedFlowNode_getNodeSubmits { exp_path node datestamp } {
   tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node} submits
}

proc SharedFlowNode_getWorkUnit { exp_path node datestamp } {
   tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node} work_unit
}

# sets the loop info for a loop node
# loop_type is one of default, loopset
# start is an integer value that is the start index of the loop
# step is an integer value that is the step between two iterations
# end is an integer value that is the end index of the loop
# set is an integer value that is the number of concurrent iterations for the loop
proc SharedFlowNode_setLoopData { exp_path node datestamp loop_type start step end set } {
   tsv::keylset SharedFlowNode_${exp_path}_${datestamp} ${node} loop_type ${loop_type} start ${start} step ${step} end ${end} set ${set}
}

# adds a loop to the current container
# it is an ordered list of full loop nodes path
proc SharedFlowNode_addLoop { exp_path node datestamp new_loop } {

   set currentList [tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node} loops]
   if { ${currentList} != "" && [lsearch ${currentList} ${new_loop}] != -1 } {
      return
   }

   tsv::keylset SharedFlowNode_${exp_path}_${datestamp} ${node} loops [linsert ${currentList} 0 ${new_loop}]
}

proc SharedFlowNode_getLoops { exp_path node datestamp } {
   # puts "SharedFlowNode_getLoops exp_path:${exp_path} node:${node} datestamp:${datestamp}"
   tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node} loops
}

proc SharedFlowNode_hasLoops { exp_path node datestamp } {
   set loopList [SharedFlowNode_getLoops ${exp_path} ${node} ${datestamp}]
   if { [llength $loopList] > 0 } {
      return 1
   }
   return 0
}

proc SharedFlowNode_getSubmits { exp_path node datestamp } {
   tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node} submits
}

proc SharedFlowNode_getSubmitPosition { exp_path node datestamp } {
   set submitter [tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node} submitter]
   set returnValue 0
   if { ${submitter} != "" } {
      set submits [SharedFlowNode_getSubmits ${exp_path} ${submitter} ${datestamp}]
      if { [expr [llength ${submits}] > 1] } {
         set nodeName [tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node} name]
         set returnValue [lsearch ${submits} ${nodeName}]
         if { [expr ${returnValue} == -1] } {
            set returnValue 0
         }
      }
   }

   return ${returnValue}
}

# get the submit node at position x, the first submission is at position 0
proc SharedFlowNode_getSubmitAtPosition { exp_path node datestamp {position end} } {

   set child ""
   catch {
      set currentList [tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node} submits]
      set child [lindex ${currentList} ${position}]
   }
   return ${child}
}

# takes the flow node as input and returns the sequencer node as output
proc SharedFlowNode_getSequencerNode { exp_path node datestamp } {
   set containerNode [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} container]
   set nodeLeaf [file tail ${node}]
   if {  $containerNode != "" } {
      set realNode $containerNode/$nodeLeaf
   } else {
      set realNode /$nodeLeaf
   }
   return $realNode
}

# search the _node tree down to find which node submits the given node
# If the submitter node is not the _node itself, it will only
# go down nodes that are of type task_node or npt nodes... because you cannot
# submit a node that belongs to another container than your own.
# _node is full path of the node to begin search on i.e. /exp_root/my_container
# _submitted_node is the xml node name of the submitted node
proc SharedFlowNode_searchSubmitNode { exp_path node datestamp submitted_node } {
   set currentList [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} submits]
   set value ""
   if { ${currentList} != "" } {
      if { [lsearch ${currentList} ${submitted_node}] != -1 } {
         set value ${node}
         set foundNode ${node}
      } else {
         foreach childName ${currentList} {
            set childSubmitNode ${node}/${childName}
	    ::log::log debug "SharedFlowNode_searchSubmitNode submitted_node:${submitted_node} childSubmitNode:${childSubmitNode}"
	    if { [SharedFlowNode_isNodeExist ${exp_path} ${childSubmitNode} ${datestamp}] == true } {
               set childeSubmitNodeType [SharedFlowNode_getNodeType ${exp_path} ${childSubmitNode} ${datestamp}]
               if { ${childeSubmitNodeType} == "task" || ${childeSubmitNodeType} == "npass_task" } {
                  set value [SharedFlowNode_searchSubmitNode ${exp_path} ${node}/${childName} ${datestamp} ${submitted_node}]
                  if { ${value} != "" } {
                     set foundNode ${node}/${childName}
                     break
                  }
               }
            } else {
	       # the node does not exists if we have not parsed the definition of the node yet 
	       # (the parsing of the submit might have been done though)
	       ::log::log debug "SharedFlowNode_searchSubmitNode submitted_node:${submitted_node} bypassing childSubmitNode:${childSubmitNode}"
	    }
         }
      }
   }
   return ${value}
}

# search the node uptree & returns the path of the node that
# is of type task
# returns empty string if not found
proc SharedFlowNode_searchForTask { exp_path flow_node datestamp } {
   set value ""
   if { $flow_node != "" } {
      if { [SharedFlowNode_getGenericAttribute ${exp_path} ${flow_node} ${datestamp} type] == "task" } {
         set value $flow_node
      } else {
         set value [SharedFlowNode_searchForTask ${exp_path} [SharedFlowNode_getGenericAttribute ${exp_path} ${flow_node} ${datestamp} submitter] ${datestamp}]
      }
   }

   return $value
}

# search uptree for submitter indexed containers (loop and switching nodes) and add it to the
# current node
proc SharedFlowNode_searchSubmitLoops { exp_path node datestamp src_node } {
   if { $node != "" } {
      set nodeType [SharedFlowNode_getNodeType  ${exp_path} ${node} ${datestamp}]
      if { ${nodeType} == "loop" || ${nodeType} == "switch_case" } {
         SharedFlowNode_addLoop ${exp_path} ${src_node} ${datestamp} ${node}
      }
      SharedFlowNode_searchSubmitLoops ${exp_path} [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} submitter] ${datestamp} $src_node
   }
}

proc SharedFlowNode_findNodes { exp_path node datestamp search_value match_case results_output } {
   upvar #0 ${results_output} myOutput

   set matchCaseFlag "-nocase"

   if { ${match_case} == 1 } { set matchCaseFlag "" }
   if { [eval string match ${matchCaseFlag} \"*${search_value}*\" [file tail ${node}]] == 1 } {
      lappend myOutput ${node}
   }

   foreach submitName [SharedFlowNode_getSubmits ${exp_path} ${node} ${datestamp}] {
      SharedFlowNode_findNodes ${exp_path} ${node}/${submitName} ${datestamp} ${search_value} ${match_case} ${results_output}
   }
}

# returns a list of all extensions belonging to the
# current loop node
proc SharedFlowNode_getLoopExtensions { exp_path node datestamp } {
   set extensions {}
   switch [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} loop_type]] {
      loopset -
      default {
         set start [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} start]
         set step [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} step]
         set setValue [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} setValue]
         set end [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} end]
         set count $start
         while { [expr $count <= $end] } {
            lappend extensions $count
            set count [expr $count + $step]
         }
      }
   }

   return $extensions
}

# get parent loop extension
proc SharedFlowNode_getParentLoopExt { exp_path node datestamp } {
   set parentExt ""
   set count 0
   set isLatest 0
   set loopList [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} loops]

   foreach loopNode $loopList {
      set currentExt [SharedFlowNode_getCurrentExt ${exp_path} ${node} ${datestamp}]
      
      if { ${loopNode} == ${node} } {
         break
      }
      if { $current == "latest" } {
         set parentExt latest
      } else {
         if { $count == 0 } {
            set parentExt "${currentExt}"
         } else {
            set parentExt "${parentExt}${currentExt}"
         }
      }
      incr count
   }
   return ${parentExt}
}

# verifies if the flow.xml of each module has changed compared to the last time
# the module was loaded. Returns true if the flow has been modified,
# otherwise returns false
proc SharedFlowNode_isFlowModified { exp_path datestamp } {
   set modules [SharedData_getExpModules ${exp_path} ${datestamp}]
   set isModified false
   foreach module ${modules} {
      set moduleName [SharedFlowNode_getName ${exp_path} ${module} ${datestamp}]
      set loadTime [SharedFlowNode_getGenericAttribute ${exp_path} ${module} ${datestamp} load_time]
      set flowFile ${exp_path}/modules/${moduleName}/flow.xml
      set flowModTime [file mtime ${flowFile}]
      if { ${loadTime} != "" && ${flowModTime} > ${loadTime} } {
         set isModified true
         ::log::log notice "SharedFlowNode_isFlowModified ${exp_path} ${module} ${datestamp} ${flowFile} has been modified"
         break
      }
   }
   return ${isModified}
}

# loop_args = "outer_Loop=2,inner_Loop=3"
# returns +2+3 if node exists
#
# returns "" on errors
proc SharedFlowNode_getLoopExtFromLoopArgs { exp_path node datestamp loop_args } {
   if { [SharedFlowNode_isNodeExist ${exp_path} ${node} ${datestamp}] == false } {
      puts "ERROR: retrieving loop... node ${node} does not exists!"
      return ""
   }

   set nodeType [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} type]

   # get parent loop containers
   set loops [SharedFlowNode_getLoops ${exp_path} ${node} ${datestamp}]

   # remove = sign and comma from arg values.. out of this
   # I get a list of [loop_one value_one loop_two value_two]
   set splittedLoopArgs [join [split [split ${loop_args} = ] , ]]

   # validate loop arg values
   set count 0
   foreach splittedLoopArg ${splittedLoopArgs} {
      # the loop names is at odd indexes
      if { [expr ${count} % 2] == 1 } {
         # even position, go to next
         incr count
      } else {
         set found false
	 # validate the argument loop is found in the list of parent loops
         foreach loopNode ${loops} {
            if { [file tail ${loopNode}] == ${splittedLoopArg} } {
	       set found true
	    }
         }

         # check if argument belongs to nptask
         if { ${found} == false && ${nodeType} == "npass_task" && [file tail ${node}] == ${splittedLoopArg} } {
	    set found true
	 }

         # if not found, outputs an error and return
         if { ${found} == false } {
            puts "ERROR: Invalid loop argument: ${splittedLoopArg}"
	    return ""
         }

         incr count
      }
   }

   # get the iterations in order in case the loop arguments are in the wrong loop order
   set loopExt ""
   foreach loopNode ${loops} {
      set foundIndex [lsearch ${splittedLoopArgs} [file tail ${loopNode}]]
      if { ${foundIndex} != -1 } {
         set loopExt ${loopExt}+[lindex ${splittedLoopArgs} [expr $foundIndex + 1]]
      }
   }
   if { ${nodeType} == "npass_task" } {
      set foundIndex [lsearch ${splittedLoopArgs} [file tail ${node}]]
      if { ${foundIndex} != -1 } {
         set loopExt ${loopExt}+[lindex ${splittedLoopArgs} [expr $foundIndex + 1]]
      }
   }

   return ${loopExt}
}

################################################################################################3
#
# The part here relates to runtime status for nodes running within a datestamp value
# It stores information for each node with respects to the canvas where the node appears.
# The info stored includes whether the node is collapsed or not, the display coordinates,
# the current status of the node, the time for each status, etc
#
################################################################################################3

# clears all the runtime data and display infos for all nodes
proc SharedFlowNode_clearAllNodes { exp_path datestamp } {
   catch { tsv::unset SharedFlowNode_${exp_path}_${datestamp}_runtime }
}

proc SharedFlowNode_initNodeDatestamp { exp_path node datestamp {force false} } {
   set nodeType [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} type]
   if { [tsv::names SharedFlowNode_${exp_path}_${datestamp}_runtime] == "" || [tsv::keylget  SharedFlowNode_${exp_path}_${datestamp}_runtime ${node}] == ""} {
      # the dislpays_infos is only iniated once throught he init
      tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} display_infos {}
   } else {
      # delete all member keys
      foreach key [tsv::keylkeys SharedFlowNode_${exp_path}_${datestamp}_runtime ${node}] {
         if { [string first latest_member_ ${key}] != -1 } {
            tsv::keyldel SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} ${key}
         }
      }
   }

   tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} statuses {} current latest
   tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} latest_member ""

   if { ${nodeType} == "npass_task" || ${nodeType} == "loop" } {
      tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} max_ext_value 5
   }
   set nodeType [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} type]
   if { ${nodeType} == "switch_case" && 
        [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} switching_type] == "datestamp_hour" && ${datestamp} != "" } {
      tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} current +[Utils_getHourFromDatestamp ${datestamp}]
   }
   
   if { ${nodeType} == "switch_case" && 
        [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} switching_type] == "day_of_week" && ${datestamp} != "" } {
        tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} current +[Utils_getDayOfWeekFromDatestamp ${datestamp}]
   }

   # puts "SharedFlowNode_initNodeDatestamp done" 
}

proc SharedFlowNode_initNodeDatestampCanvas { exp_path node datestamp canvas {force false} } {
   # puts "SharedFlowNode_initNodeDatestampCanvas $exp_path $node $datestamp $canvas"
   if { [tsv::names SharedFlowNode_${exp_path}_${datestamp}_runtime] == "" || [tsv::keylget  SharedFlowNode_${exp_path}_${datestamp}_runtime ${node}] == ""} {
      SharedFlowNode_initNodeDatestamp ${exp_path} ${node} ${datestamp} ${force}
   }
   array set displayInfoList [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} display_infos]
   if { ! [info exists displayInfoList($canvas)] || ${force} == true } {
      set displayInfoList($canvas) {0 0 0 0 0 0 0 0 40}
      tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} display_infos "[array get displayInfoList]"
   }
}

proc SharedFlowNode_resetAllStatus { exp_path node datestamp {is_recursive 0} } {
   SharedFlowNode_initNodeDatestamp ${exp_path} ${node} ${datestamp}
   if { ${is_recursive} } {
      set submits [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} submits]
      if { ${submits} != "" } {
         foreach submitName ${submits} {
            set submitNode ${node}/${submitName}
            SharedFlowNode_resetAllStatus  ${exp_path} ${submitNode} ${datestamp} 1
         }
      }
   }
}

# returns the max extension value for a node that contains extensions or indexes
# such as a loop node or an npass_task node. This is mainly used for display purpose
# in xflow
proc SharedFlowNode_getMaxExtValue { exp_path node datestamp } {
   set value ""
   if { [tsv::keylget  SharedFlowNode_${exp_path}_${datestamp}_runtime ${node}] != "" } {
      set value [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} max_ext_value]
   }
   return ${value}
}

# returns the current iteration/index/extension selected by the user
# for a loop or npass_task node
proc SharedFlowNode_getCurrentExt { exp_path node datestamp } {
   set value ""
   if { [tsv::keylget  SharedFlowNode_${exp_path}_${datestamp}_runtime ${node}] != "" } {
      set value [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} current]
   }
   return ${value}
}

# sets the current iteration for the loop or npass_task node
# the value must be in the format +${iteration_value} i.e. +1 or +1+000000018
proc SharedFlowNode_setCurrentExt { exp_path node datestamp value } {
   tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} current ${value}
}

# returns the latest iteration that was modified
# The return value is in the form of the setCurrentExt format
# The is mainly used to know what iteration value to display when the user
# has selected the "latest" iteration i.e. view the latest modified iteration
proc SharedFlowNode_getLatestExt { exp_path node datestamp } {
   set value ""
   if { [tsv::keylget  SharedFlowNode_${exp_path}_${datestamp}_runtime ${node}] != "" } {
      set nodeType [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} type]

      if { ${nodeType} == "npass_task" } {
         set parentExt [SharedFlowNode_getParentLoopExt ${exp_path} ${node} ${datestamp}]
	 if { ${parentExt} != "" && ${parentExt} != "latest" } {
	      set latestMemberKey latest_member_${parentExt}
              if { [SharedFlowNode_isRuntimeKeyExist ${exp_path} ${node} ${datestamp} ${latestMemberKey}] == true }  {
	         set value [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} ${latestMemberKey}]
	      }
	 } else {
            set value [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} latest_member]
	 }
      } else {
         set value [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} latest_member]
      }
   }
   return ${value}
}

proc SharedFlowNode_isRuntimeKeyExist {  exp_path node datestamp key } {
   set found false
   catch {
      set keys [tsv::keylkeys SharedFlowNode_${exp_path}_${datestamp}_runtime ${node}]
      if { [lsearch -exact ${keys} ${key}] != -1 } {
         set found true
      }
   }
   return ${found}
}

# see getMaxExtValue
proc SharedFlowNode_setMaxExtValue { exp_path node datestamp max_ext_value } {
   tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} max_ext_value ${max_ext_value}
}

# retrieves the status for a given member iteration
# This is a generic procedure that is used even for node that are not part of
# loops... In that case the member value is simply an empty string
# For nodes that are part of loops or npass_task nodes, the member can either be the
# member value i.e. +1 or +00000036 or the value "latest".
proc SharedFlowNode_getMemberStatus { exp_path node datestamp member } {
   set value "init"

      # puts "tsv::exists SharedFlowNode_${exp_path}_${datestamp}_runtime ${node}? [tsv::exists SharedFlowNode_${exp_path}_${datestamp}_runtime ${node}]"
   if { [tsv::exists SharedFlowNode_${exp_path}_${datestamp}_runtime ${node}] == 1 } {
      set values {init}
      # puts "tsv::keylkeys SharedFlowNode_${exp_path}_${datestamp}_runtime ${node}? [tsv::keylkeys SharedFlowNode_${exp_path}_${datestamp}_runtime ${node}]"
      if { $member == "" } {
         set member "null"
      }
      # get the latest member 
      if { $member == "latest" } {
         set member [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} latest_member]
      }
      catch {
         array set statuses [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} statuses]
         if { [info exists statuses($member)] } {
            set values $statuses($member)
         }
      }
      set value [lindex ${values} 0]
   }

   return $value
}

# sets the status of a node. Generic procedure used for all type of nodes
# called by LogReader
# difference between status orig_status:
# status=end, begin
# orig_status=end or endx, begin or beginx
proc SharedFlowNode_setMemberStatus { exp_path node datestamp member status orig_status timestamp {is_recursive false} } {
   # puts "SharedFlowNode_setMemberStatus ${exp_path} ${node} ${datestamp} ${member} ${status}"
   if { [tsv::names SharedFlowNode_${exp_path}_${datestamp}_runtime] == "" || [tsv::keylget  SharedFlowNode_${exp_path}_${datestamp}_runtime ${node}] == ""} {
      # puts "SharedFlowNode_setMemberStatus SharedFlowNode_initNodeDatestamp"
      SharedFlowNode_initNodeDatestamp ${exp_path} ${node} ${datestamp} 
   }

   set nodeType [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} type]
   if { ${nodeType} == "npass_task" || ${nodeType} == "loop" } {
      set currentMax [SharedFlowNode_getMaxExtValue ${exp_path} ${node} ${datestamp}]
      set newMax [string length [lindex [split ${member} +] end ] ]
      if { ${newMax} > ${currentMax} } {
         SharedFlowNode_setMaxExtValue  ${exp_path} ${node} ${datestamp} ${newMax}
      }
   }

   if { ${nodeType} == "npass_task"} {
      SharedFlowNode_setNptMemberStatus ${exp_path} ${node} ${datestamp} ${member} ${status} ${timestamp}
   } else {

      array set statuses [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} statuses]

      if { $member == "" } {
         set member null
         set statuses(null) "${status} ${timestamp}"
      } else {
         if { ${status} == "init" } {
            if { [info exists statuses($member)] } {
               # reset the exact member match
               unset statuses($member)
            }
            # reset all members that are part of the same iteration
            set resetList [array get statuses ${member}+*]
            foreach {item value} ${resetList} {
               unset statuses($item)
            }
         } else {
            set statuses($member) "${status} ${timestamp}"
	    if { ${nodeType} == "loop"} {
	       # for loops, the latest_member stores the value of the whole loop.
	       # for inn   # how many parent loops do I have
               set nofParentLoops [llength [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} loops]]
               # how many index separator do I have from the given member
               set nofSeparators [expr [llength [split ${member} +]] - 1]

               if { ${nofParentLoops} > 1 && [expr ${nofParentLoops} - 1] == ${nofSeparators} } {
                  tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} latest_member $member
               }
	    } else {
               tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} latest_member $member
	    }
         }
      }
      set values [array get statuses]
      tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} statuses "${values}"
   }

   SharedFlowNode_setStatInfo ${exp_path} ${node} ${datestamp} ${member} ${orig_status} ${timestamp}

   if { ${is_recursive} } {
      set submits [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} submits]
      if { ${submits} != "" } {
         foreach submitName ${submits} {
            set submitNode ${node}/${submitName}
            SharedFlowNode_setMemberStatus ${exp_path} ${submitNode} ${datestamp} ${member} ${status} ${orig_status} ${timestamp} 1
         }
      }
   }
}

# add to statistic info list... calculation of exec time
proc SharedFlowNode_setStatInfo { exp_path node datestamp member status timestamp } {
   array set statsinfo {}
   # puts "SharedFlowNode_setStatInfo node:$node member:$member status:$status timestamp:$timestamp "

   catch { array set statsinfo [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} stats_info] }

   if { ${status} != "submit" && [info exists statsinfo($member)] } {
         set memberInfoList $statsinfo($member)
         set foundIndex [lsearch ${memberInfoList} ${status}]

         # for containers, we keep the first endx, if an endx is found, don't save the new one
         if { ! [string match "*task" [SharedFlowNode_getNodeType ${exp_path} ${node} ${datestamp}]] 
              && ${status} == "endx" && ${foundIndex} != -1 } {
            # puts "SharedFlowNode_setStatInfo node:$node member:$member container endx already found: not updating..."
            # puts "SharedFlowNode_setStatInfo node:$node member:$member $memberInfoList"
	    return
         }

         if { ${foundIndex} == -1 } {
            # status is new, store the new status
	    # puts "SharedFlowNode_setStatInfo node:$node member:$member new status:$status"
            lappend memberInfoList ${status} ${timestamp}
         } else {
            # update status with new info
	    switch ${status} {
	       begin {
	          # delete any abort or end status
	          set abortIndexes [ lreverse [lsearch -all ${memberInfoList} abort]]
	          # puts "node:$node member:$member abortIndexes:$abortIndexes"
	          foreach deleteIndex ${abortIndexes} {
	             set memberInfoList [lreplace  ${memberInfoList} ${deleteIndex} ${deleteIndex}]
	          }
	          set endIndexes [lreverse [lsearch -all ${memberInfoList} end]]
	          # puts "node:$node member:$member endIndexes:$endIndexes"
	          foreach deleteIndex ${endIndexes} {
	             set memberInfoList [lreplace  ${memberInfoList} ${deleteIndex} ${deleteIndex}]
	          }
	       }
	       default {
	       }
	    }
            set memberInfoList [lreplace ${memberInfoList} ${foundIndex} [expr ${foundIndex} + 1] ${status} ${timestamp}]
         }
         set statsinfo($member) ${memberInfoList}
         # puts "node:$node member:$member memberInfoList:$memberInfoList"
   } else {
      # puts "SharedFlowNode_setStatInfo node:$node member:$member initialising..."
      # initialise status
      array set statsinfo {}
      set statsinfo($member) [list ${status} ${timestamp}]
   }
   # puts "SharedFlowNode_setStatInfo node:$node member:$member set statsinfo:[array get statsinfo]"
   tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} stats_info "[array get statsinfo]"
}

# for loop, member could be the member iteration (+24) or "all" for the
# status of the loop itself
# for non loop nodes, member is "null"
proc SharedFlowNode_getStatInfo { exp_path node datestamp member } {
   # puts "SharedFlowNode_getStatInfo exp_path:$exp_path node:$node datestamp:$datestamp member:$member"
   set result ""
   if { ${member} == "" } {
      set member null
   }
   if { [tsv::keylkeys SharedFlowNode_${exp_path}_${datestamp}_runtime ${node}] != "" } {
      array set statsinfo [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} stats_info]
      if { [info exists statsinfo($member)] } {
         set result $statsinfo($member)
      }
   }
   return ${result}
}

proc SharedFlowNode_getExecTime { exp_path node datestamp member } {
   # puts "SharedFlowNode_getExecTime exp_path:$exp_path node:$node datestamp:$datestamp member:$member"
   if { ${member} == "" } {
      set member null
   }
   set execTime ""
   set timestampFormat {%Y%m%d.%H:%M:%S}
   set timeDisplayFormat {%H:%M:%S}
   set beginStatus begin
   if { [string match "*task" [SharedFlowNode_getNodeType ${exp_path} ${node} ${datestamp}]] } {
      # tasks node
      set endStatus end
   } else {
      # container node
      set endStatus endx
   }

   if { [SharedFlowNode_getMemberStatus ${exp_path} ${node} ${datestamp} ${member}] == "end" && 
        [tsv::keylkeys SharedFlowNode_${exp_path}_${datestamp}_runtime ${node}] != "" } {
      array set statsinfo [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} stats_info]
      if { [info exists statsinfo($member)] } {
         set memberInfoList $statsinfo($member)
         set beginIndex [lsearch -exact ${memberInfoList} ${beginStatus}]
         set endIndex [lsearch -exact ${memberInfoList} ${endStatus}]
	 if { ${beginIndex} != -1 && ${endIndex} != -1 } {
	    set beginTime [lindex ${memberInfoList} [expr ${beginIndex} + 1]]
	    set endTime [lindex ${memberInfoList} [expr ${endIndex} + 1]]
	    set execTimeString [expr [clock scan ${endTime} -format ${timestampFormat}] -  [clock scan ${beginTime} -format ${timestampFormat}] ]
	    set execTime [clock format ${execTimeString} -timezone :UTC -format ${timeDisplayFormat}]
	 }
      }
   }
   return ${execTime}
}

proc SharedFlowNode_isStatsInfoExists {  exp_path node datestamp } {
   set isExists false
   catch {
      set keys [tsv::keylkeys SharedFlowNode_${exp_path}_${datestamp}_runtime ${node}]
      if { [lsearch ${keys} stats_info] != -1 } {
         set isExists true
      }
   }
   return ${isExists}
}

proc SharedFlowNode_getBeginTime { exp_path node datestamp member } {
   if { ${member} == "" } {
      set member null
   }
   set beginTime ""
   set timestampFormat {%Y%m%d.%H:%M:%S}
   set timeDisplayFormat {%H:%M:%S}
   set beginStatus begin

   set currentStatus [SharedFlowNode_getMemberStatus ${exp_path} ${node} ${datestamp} ${member}]
   if { ${currentStatus} == "submit" || ${currentStatus} == "init" || ${currentStatus} == "wait" || ${currentStatus} == "discret" } {
	return ""
   }

   if { [SharedFlowNode_isStatsInfoExists ${exp_path} ${node} ${datestamp}] == true } {
      array set statsinfo [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} stats_info]
      if { [info exists statsinfo($member)] } {
         set memberInfoList $statsinfo($member)
         set beginIndex [lsearch -exact ${memberInfoList} ${beginStatus}]
	 if { ${beginIndex} != -1 } {
	    set beginTimeValue [lindex ${memberInfoList} [expr ${beginIndex} + 1]]
	    set beginTimeString [clock scan ${beginTimeValue} -format ${timestampFormat}]
	    set beginTime [clock format ${beginTimeString} -format ${timeDisplayFormat}]
	 }
      }
   }
   return ${beginTime}
}

proc SharedFlowNode_getEndTime { exp_path node datestamp member } {
   if { ${member} == "" } {
      set member null
   }
   set endTime ""
   set timestampFormat {%Y%m%d.%H:%M:%S}
   set timeDisplayFormat {%H:%M:%S}
   if { [string match "*task" [SharedFlowNode_getNodeType ${exp_path} ${node} ${datestamp}]] } {
      # tasks node
      set endStatus end
   } else {
      # container node
      set endStatus endx
   }

   if { [SharedFlowNode_getMemberStatus ${exp_path} ${node} ${datestamp} ${member}] == "end" && 
        [tsv::keylkeys SharedFlowNode_${exp_path}_${datestamp}_runtime ${node}] != "" } {
      array set statsinfo [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} stats_info]
      if { [info exists statsinfo($member)] } {
         set memberInfoList $statsinfo($member)
         set endIndex [lsearch -exact ${memberInfoList} ${endStatus}]
	 if { ${endIndex} != -1 } {
	    set endTimeValue [lindex ${memberInfoList} [expr ${endIndex} + 1]]
	    set endTimeString [clock scan ${endTimeValue} -format ${timestampFormat}]
	    set endTime [clock format ${endTimeString} -format ${timeDisplayFormat}]
	 }
      }
   }
   return ${endTime}
}

proc SharedFlowNode_getSubmitDelay { exp_path node datestamp member } {
   if { ${member} == "" } {
      set member null
   }
   set submitDelay ""
   set timestampFormat {%Y%m%d.%H:%M:%S}
   set timeDisplayFormat {%H:%M:%S}
   set submitStatus submit
   set beginStatus begin

   set currentStatus [SharedFlowNode_getMemberStatus ${exp_path} ${node} ${datestamp} ${member}]
   if { ${currentStatus} == "submit" || ${currentStatus} == "init" || ${currentStatus} == "wait" || ${currentStatus} == "discret" } {
	return ""
   }

   if { [SharedFlowNode_isStatsInfoExists ${exp_path} ${node} ${datestamp}] == true } {
      array set statsinfo [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} stats_info]
      if { [info exists statsinfo($member)] } {
         set memberInfoList $statsinfo($member)
         set beginIndex [lsearch -exact ${memberInfoList} ${beginStatus}]
         set submitIndex [lsearch -exact ${memberInfoList} ${submitStatus}]
	 if { ${beginIndex} != -1 && ${submitIndex} != -1 } {
	    set submitTime [lindex ${memberInfoList} [expr ${submitIndex} + 1]]
	    set beginTime [lindex ${memberInfoList} [expr ${beginIndex} + 1]]
	    set delayTimeString [expr [clock scan ${beginTime} -format ${timestampFormat}] -  [clock scan ${submitTime} -format ${timestampFormat}] ]
	    set submitDelay [clock format ${delayTimeString} -format ${timeDisplayFormat}]
	 }
      }
   }
   return ${submitDelay}
}

proc SharedFlowNode_setNptMemberStatus { exp_path node datestamp member status timestamp {is_recursive false}} {
   ::log::log debug "SharedFlowNode_setNptMemberStatus ${exp_path} $node $member $status"
   if { [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} type] != "npass_task" } {
      return
   }

   if { [tsv::keylkeys SharedFlowNode_${exp_path}_${datestamp}_runtime ${node}] == "" } {
      tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} statuses {}
   }

   array set statuses [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} statuses]

   # how many parent loops do I have
   set nofParentLoops [llength [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} loops]]
   # how many index separator do I have from the given member
   set nofSeparators [expr [llength [split ${member} +]] - 1]

   set parentLoopExt [SharedFlowNode_getParentLoopExt ${exp_path} ${node} ${datestamp}]

   if { ${nofParentLoops} != "" } {
      if { ${nofSeparators} == ${nofParentLoops} && ${status} == "init" } {
         # whole loop iteration
         # need to init all indexes in the npt that matches
         foreach { stored_member status } [array get statuses] {
            if { [string match ${member}+* ${stored_member}] } {
               # removing is same as init... less data
               unset statuses($stored_member)
            }
         }
         catch { unset statuses($member) }
         # reset the latest reference if needed
         set latestMember [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} statuses]

         if { [string match ${member}+* ${latestMember}] } {
            tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} latest_member ""
         }

         set baseExt [SharedFlowNode_getBasePart ${member}]
	 set latestMemberKey latest_member_${baseExt}
         if { [SharedFlowNode_isRuntimeKeyExist ${exp_path} ${node} ${datestamp} ${latestMemberKey}] == true }  {
	    tsv::keyldel SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} ${latestMemberKey}
	 }

      } elseif { [expr ${nofSeparators} > ${nofParentLoops}] } {
         # changing one npt index only
         set statuses($member) "${status} ${timestamp}"
         set baseExt [SharedFlowNode_getBasePart ${member}]
         tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} latest_member $member
	 if { ${baseExt} != "" } {
	    set latestMemberKey latest_member_${baseExt}
            tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} ${latestMemberKey} $member
	 }
      } elseif { [expr ${nofSeparators} < ${nofParentLoops}] } {
         # not for myself
         return
      }
   } else {
      # changing one npt member not part of a loop
      if { ${timestamp} != "" } {
         set statuses($member) "${status} ${timestamp}"
      } else {
         set statuses($member) "${status}"
      }
      tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} latest_member $member
   }
   tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} statuses "[array get statuses]"
}

# returns the list of extensions application for the npass_task_node
# the npass_task may have a list of many values but they might not
# all be visible if the task is running within a loop...
# for instance if the user selects a loop index then only the npass_task values
# that start with that index is relevant
proc SharedFlowNode_getNptExtensions { exp_path node datestamp } {
   set extensions {}
   set loopList [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} loops]
   set loopExt ""
   set isAllLatest true
   set returnedExtensions {}

   array set statuses [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} statuses]
   set extensions [array names statuses]
   foreach ext ${extensions} {
      lappend returnedExtensions [string range ${ext} [expr [string last + ${ext}] + 1]  end]
   }
   set returnedExtensions [lsort -unique ${returnedExtensions}]
   return ${returnedExtensions}
}



################################################################################################3
# The part here relates to display information for nodes in xflow running within a datestamp value
################################################################################################3
proc SharedFlowNode_isCollapsed { exp_path node datestamp canvas } {
   set value 0
   if { [tsv::exists SharedFlowNode_${exp_path}_${datestamp}_runtime ${node}] == 1 } {
      catch {
         array set displayInfoList [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} display_infos]
         if { [info exists displayInfoList($canvas)] } {
            set displayInfo $displayInfoList($canvas)
            set value [lindex $displayInfo 0]
         }
      }
   }
   return $value
}

proc SharedFlowNode_isParentCollapsed { exp_path node datestamp canvas } {
   # puts "SharedFlowNode_isParentCollapsed exp:${exp_path} node:${node} datestamp:${datestamp} "
   if { [tsv::exists SharedFlowNode_${exp_path}_${datestamp}_runtime ${node}] == 0 } {
      return 0
   }

   set submitter [SharedFlowNode_getSubmitter ${exp_path} ${node} ${datestamp} ]
   set value [SharedFlowNode_isCollapsed ${exp_path} ${submitter} ${datestamp} ${canvas}]
   return ${value}
}

proc SharedFlowNode_setCollapsed { exp_path node datestamp canvas value } {
   array set displayInfoList [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} display_infos]
   set displayInfo $displayInfoList($canvas)
   set displayInfo [lreplace $displayInfo 0 0 $value]
   set displayInfoList($canvas) $displayInfo
   tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} display_infos "[array get displayInfoList]"

   set submits [SharedFlowNode_getSubmits ${exp_path} ${node} ${datestamp}]
   foreach submitName ${submits} {
      set submitNode ${node}/${submitName}
      SharedFlowNode_setCollapsed ${exp_path} ${submitNode} ${datestamp} ${canvas} ${value}
   }
}

# if the current node is collapsed,
# searches up the submit parent chain to look for first parent that is collapsed,
# and then sets the collapse value to 0 from the found parent down to every submit child
# returns the first parent found 
# else returns empty string
proc SharedFlowNode_uncollapseBranch { exp_path node datestamp canvas } {
   if { [SharedFlowNode_isCollapsed ${exp_path} ${node} ${datestamp} ${canvas}] == 0 } {
      return ""
   }

   set previousNode ${node}
   set nextNode [tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node} submitter]
   set found false
   while { ${nextNode} != "" && ${found} == false } {
      array set displayInfoList [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${nextNode} display_infos]
      if { [info exists displayInfoList($canvas)] } {
         set displayInfo $displayInfoList($canvas)
         set value [lindex $displayInfo 0]
         if { $value == 0 } {
            set found true ; break
         }
         set previousNode ${nextNode}
         set nextNode [tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${nextNode} submitter]
      }
   }
   SharedFlowNode_setCollapsed ${exp_path} ${previousNode} ${datestamp} ${canvas} 0
   return ${previousNode}
}

proc SharedFlowNode_uncollapseAll { exp_path node datestamp canvas } {
   SharedFlowNode_setCollapsed  ${exp_path} ${node} ${datestamp} ${canvas} 0
}

# values must be a list of {x1 y1 x2 y2 max_x max_y}
proc SharedFlowNode_setDisplayCoords { exp_path node datestamp canvas values } {
   if { [tsv::names SharedFlowNode_${exp_path}_${datestamp}_runtime] == "" || [tsv::keylget  SharedFlowNode_${exp_path}_${datestamp}_runtime ${node}] == ""} {
      SharedFlowNode_initNodeDatestamp ${exp_path} ${node} ${datestamp} 
   }
   array set displayInfoList [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} display_infos]
   if { ! [info exists displayInfoList($canvas)] } {
      SharedFlowNode_initNodeDatestampCanvas ${exp_path} ${node} ${datestamp} ${canvas}
      array set displayInfoList [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} display_infos]
   }

   set displayInfo $displayInfoList($canvas)
   set displayInfo [lreplace $displayInfo 2 7 $values]
   set displayInfoList($canvas) [join $displayInfo]

   tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} display_infos "[array get displayInfoList]"
}

proc SharedFlowNode_setDisplayLimits { exp_path flow_node datestamp canvas } {
   set displayCoords [SharedFlowNode_getDisplayCoords ${exp_path} ${flow_node} ${datestamp} ${canvas}]
   set nodeMaxX [lindex $displayCoords 4]
   set nodeMaxY [lindex $displayCoords 5]
   set currentNode $flow_node
   while { $currentNode != "" } {
      set submitter [tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node} submitter]
      if { ${submitter} == "" } {
         break
      }
      #puts "setDisplayLimits parentNode:$parentNode"
      set parentDispCoords [SharedFlowNode_getDisplayCoords ${exp_path} ${submitter} ${datestamp} ${canvas}]
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
         setDisplayCoords ${submitter} $canvas $parentDispCoords
      }
      set currentNode ${submitter}
   }
}

proc SharedFlowNode_setDisplayY { exp_path node datestamp canvas value } {
   if { [tsv::names SharedFlowNode_${exp_path}_${datestamp}_runtime] == "" || [tsv::keylget  SharedFlowNode_${exp_path}_${datestamp}_runtime ${node}] == ""} {
      SharedFlowNode_initNodeDatestamp ${exp_path} ${node} ${datestamp} 
   }
   # set value for current node to be used by children node
   array set displayInfoList [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} display_infos]
   if { ! [info exists displayInfoList($canvas)] } {
      SharedFlowNode_initNodeDatestampCanvas ${exp_path} ${node} ${datestamp} ${canvas}
      array set displayInfoList [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} display_infos]
   }

   set displayInfo $displayInfoList($canvas)
   set displayInfo [lreplace $displayInfo 8 8 ${value}]
   set displayInfoList($canvas) [join $displayInfo]

   tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} display_infos "[array get displayInfoList]"
}

proc SharedFlowNode_getDisplayY { exp_path node datestamp canvas } {

   array set displayInfoList [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} display_infos]
   set displayInfo $displayInfoList($canvas)
   return [lindex ${displayInfo} 8]
}

proc SharedFlowNode_getDisplayCoords { exp_path node datestamp canvas} {
   array set displayInfoList [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} display_infos]
   set displayInfo $displayInfoList($canvas)
   return [lrange $displayInfo 2 7]
}

proc  SharedFlowNode_setIsRootNode { exp_path node datestamp canvas value} {
   if { [tsv::names SharedFlowNode_${exp_path}_${datestamp}_runtime] == "" || [tsv::keylget  SharedFlowNode_${exp_path}_${datestamp}_runtime ${node}] == ""} {
      SharedFlowNode_initNodeDatestamp ${exp_path} ${node} ${datestamp} 
   }
   array set displayInfoList [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} display_infos]
   if { ! [info exists displayInfoList($canvas)] } {
      SharedFlowNode_initNodeDatestampCanvas ${exp_path} ${node} ${datestamp} ${canvas}
      array set displayInfoList [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} display_infos]
   }
   set displayInfo $displayInfoList($canvas)
   set displayInfo [lreplace $displayInfo 1 1 $value]
   set displayInfoList($canvas) $displayInfo

   tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} display_infos "[array get displayInfoList]"
}

proc  SharedFlowNode_isRootNode { exp_path node datestamp canvas } {
   array set displayInfoList [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} display_infos]
   set displayInfo $displayInfoList($canvas)
   set value [lindex $displayInfo 1]
   return $value
}

proc SharedFlowNode_initNode { exp_path node datestamp canvas} {
   if { [tsv::exists SharedFlowNode_${exp_path}_${datestamp}_runtime ${node}] == 1 } {
      array set displayInfoList [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} display_infos]
   } else {
      array set displayInfoList {}
   }

   if { ! [info exists displayInfoList($canvas)] } {
      # puts "SharedFlowNode_initNode creating canvas:$canvas"
      set displayInfoList($canvas) {0 0 0 0 0 0 0 0 40}
      tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} display_infos "[array get displayInfoList]"
   }
   
}

proc SharedFlowNode_resetNodeStatus { exp_path node datestamp } {
   SharedFlowNode_resetAllStatus ${exp_path} ${node} ${datestamp}
   set submits [SharedFlowNode_getSubmits ${exp_path} ${node} ${datestamp}]
   foreach submitName ${submits} {
      set submitNode ${node}/${submitName}
      SharedFlowNode_resetNodeStatus ${exp_path} ${submitNode} ${datestamp}
   }
}

proc SharedFlowNode_removeDisplayFromNode { exp_path node datestamp canvas {is_recursive 0}} {
   array set displayInfoList [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} display_infos]
   array unset displayInfoList $canvas
   tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} display_infos "[array get displayInfoList]"
   if { $is_recursive } {
      foreach submitName ${submits} {
         set submitNode ${node}/${submitName}
         SharedFlowNode_removeDisplayFromNode ${exp_path} ${submitNode} ${datestamp} ${canvas} 1
      }
   }
}

proc SharedFlowNode_getDisplayList { exp_path node datestamp} {
   array set displayInfoList [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} display_infos]
   return [array names displayInfoList]
}

# returns the extension of the current node based
# on parent loops
proc SharedFlowNode_getNodeExtension { exp_path node datestamp } {
   set extension ""
   set loopList [SharedFlowNode_getLoops ${exp_path} ${node} ${datestamp}]
   set nodeType [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} type]
   if { ${nodeType} == "npass_task" } {
      # current index selection for the nptask
      set nptExtension [SharedFlowNode_getCurrentExt ${exp_path} ${node} ${datestamp}]
      set parentLoopExt [SharedFlowNode_getParentLoopExt ${exp_path} ${node} ${datestamp}]
      if { ${parentLoopExt} == "latest" || ${nptExtension} == "latest" } {
         # get latest if any of selection is latest
         set extension [SharedFlowNode_getLatestExt ${exp_path} ${node} ${datestamp}]
      } else {
         # get npt extension corresponding to loop extension
         set extension ${parentLoopExt}${nptExtension}
      }
   } else {
      if { ${nodeType} == "loop" && [llength ${loopList}] == 1 && [SharedFlowNode_getCurrentExt ${exp_path} ${node} ${datestamp}] == "latest" } {
         # exception case for top loop
         return "all"
      } else {
         foreach loopNode ${loopList} {
            set currentExt [SharedFlowNode_getCurrentExt ${exp_path} ${loopNode} ${datestamp}]
            if { ${currentExt} == "latest" } {
               return [SharedFlowNode_getLatestExt ${exp_path} ${node} ${datestamp}]
            }
            set extension "${extension}[SharedFlowNode_getCurrentExt ${exp_path} ${loopNode} ${datestamp}]"
         }
      }
   }
   return ${extension}
}

# returns the extension text that should be displayed
proc SharedFlowNode_getExtDisplay { exp_path node datestamp loop_ext } {
   set displayValue ""
   set nodeType [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} type]
   if { ${nodeType} == "loop" || ${nodeType} == "npass_task"} {
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

proc SharedFlowNode_getParentLoopExt {exp_path node datestamp} {
   set parentExt ""
   set count 0
   set isLatest 0
   set loopList [SharedFlowNode_getLoops ${exp_path} ${node} ${datestamp}]

   foreach loopNode $loopList {
      set currentExt [SharedFlowNode_getCurrentExt ${exp_path} ${loopNode} ${datestamp}]
      if { ${loopNode} == ${node} } {
         break
      }
      if { ${currentExt} == "latest" } {
         set parentExt latest
      } else {
         if { $count == 0 } {
            set parentExt "${currentExt}"
         } else {
            set parentExt "${parentExt}${currentExt}"
         }
      }
      incr count
   }
   return ${parentExt}
}

proc SharedFlowNode_getIndexValue { value } {
   set returnValue $value
   if { [string first "+" $value] == 0 } {
      catch { set returnValue [string range $value 1 end] }
   }
   return $returnValue
}

proc SharedFlowNode_getLoopInfo { exp_path loop_node datestamp } {
   set txt ""
   switch [SharedFlowNode_getGenericAttribute ${exp_path} ${loop_node} ${datestamp} loop_type] {
      default {
         set start [SharedFlowNode_getGenericAttribute ${exp_path} ${loop_node} ${datestamp} start]
         set step [SharedFlowNode_getGenericAttribute ${exp_path} ${loop_node} ${datestamp} step]
         set setValue [SharedFlowNode_getGenericAttribute ${exp_path} ${loop_node} ${datestamp} set]
         set end [SharedFlowNode_getGenericAttribute ${exp_path} ${loop_node} ${datestamp} end]
         set txt "\[${start},${end},${step},${setValue}\]"
      }
   }

   return $txt
}

proc SharedFlowNode_getNodeFromDisplayFormat { node_with_ext } {
   set newNodeName ${node_with_ext}
   set firstSepIndex [string first "+" ${node_with_ext}]
   if { [expr ${firstSepIndex} != -1] } {
      set newNodeName [string range ${node_with_ext} 0 [expr ${firstSepIndex} - 1]]
   }
   return ${newNodeName}
}

# returns +123 from node+123
# return "" if no index
proc SharedFlowNode_getExtFromDisplayFormat { node_with_ext } {
   set extValue ""
   set firstSepIndex [string first "+" ${node_with_ext}]
   if { [expr ${firstSepIndex} != -1] } {
      set extValue [string range ${node_with_ext} ${firstSepIndex} end]
   }
   return ${extValue}
}

proc SharedFlowNode_getLoopTooltip { exp_path loop_node datestamp } {
   set tooltipTxt ""
   if { [SharedFlowNode_getGenericAttribute ${exp_path} ${loop_node} ${datestamp} type] == "loop" } {
      set start [SharedFlowNode_getGenericAttribute ${exp_path} ${loop_node} ${datestamp} start]
      set step [SharedFlowNode_getGenericAttribute ${exp_path} ${loop_node} ${datestamp} step]
      set setValue [SharedFlowNode_getGenericAttribute ${exp_path} ${loop_node} ${datestamp} set]
      set end [SharedFlowNode_getGenericAttribute ${exp_path} ${loop_node} ${datestamp} end]

      set tooltipTxt "\[start=${start},end=${end},step=${step},set=${setValue}\]"
   }
   return ${tooltipTxt}
}

# returns the node extension that should be used
# for listings
# user should have chosen an extension or all
# loops should be "latest"
proc SharedFlowNode_getListingNodeExtension { exp_path current_node datestamp {full_loop "0"} } {
   set extension ""
   set count 0
   set latestCount 0
   set loopList [SharedFlowNode_getLoops ${exp_path} ${current_node} ${datestamp}]
   set numberOfLoops [llength $loopList]
   if { [SharedFlowNode_getNodeType ${exp_path} ${current_node} ${datestamp}] == "npass_task" } {
      set currentNptExt [SharedFlowNode_getCurrentExt ${exp_path} ${current_node} ${datestamp}]
      set extension ${currentNptExt}

      if { ${loopList} != "" } {
         set parentLoopExt [SharedFlowNode_getParentLoopExt ${exp_path} ${current_node} ${datestamp}]
         if { ${parentLoopExt} == "latest" } {
            if { ${currentNptExt} != "latest" } {
               # npt index cannot be selected if parent loop is on latest
               return "-1"
            }
            set extension [SharedFlowNode_getLatestExt ${exp_path} ${current_node} ${datestamp}]
         } else {
            if { ${currentNptExt} == "latest" } {
               # npt cannot be latest if parent loop is not latest
               return "-1"
            } else {
               set extension ${parentLoopExt}${currentNptExt}
            }
         }
      } else {
         if { ${currentNptExt} == "latest" } {
            set extension [SharedFlowNode_getLatestExt ${exp_path} ${current_node} ${datestamp}]
         }
      }
   } else {
      foreach loopNode $loopList {
         incr count
         set currentExt [SharedFlowNode_getCurrentExt ${exp_path} ${loopNode} ${datestamp}]
         # this part is only for loop nodes
         if { ${full_loop} == "1" && $count == $numberOfLoops } {
            set currentExt ""
         }
         if { $currentExt == "latest" } {
            incr latestCount
            set latestExt [SharedFlowNode_getLatestExt ${exp_path} ${loopNode} ${datestamp}]
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
         set extension [SharedFlowNode_getLatestExt ${exp_path} ${current_node} ${datestamp}]
         if { $extension == "all" } {
            set extension ""
         }
      }
   }

   return $extension
}

# returns the input arguments as expected by the
# sequencer for loop arguments
# it builds the loop arguments for all loops
# contained in the node loops attribute
# 
# exts sample: +2+4 for outer_loop index +2 and inner loop index +4
proc SharedFlowNode_getLoopArgs { exp_path node datestamp exts} {
   set args ""
   set count 0
   set loopList [SharedFlowNode_getLoops ${exp_path} ${node} ${datestamp}]
   if { ${exts} != "" } {
      set exts [split ${exts} +]
      set exts [lrange ${exts} 1 end]
   }
   if { [llength $loopList] > 0 } {
      foreach loopNode $loopList {
         if { ${exts} == "" } {
	    # retrieve from xflow selection
            set currentExt [SharedFlowNode_getCurrentExt ${exp_path} ${loopNode} ${datestamp}]
	 } else {
	    # get from given list
            set currentExt [lindex ${exts} ${count}]
	 }
         if { ${currentExt} == "latest" } {
            return ""
	 } elseif { ${currentExt} != "" } {
            # remove the + sign before extension
            set currentExt [string trim ${currentExt} +]
            set nodeName [SharedFlowNode_getName ${exp_path} ${loopNode} ${datestamp}]
            if { $count == 0 } {
               set args "-l ${nodeName}=${currentExt}"
            } else {
               set args "${args},${nodeName}=${currentExt}"
            }
         }
         incr count
      }
   }
   return $args
}

# npass_index argument is used when user is provided manual
# the index value at submission time
proc SharedFlowNode_getNptArgs { exp_path node datestamp {loop_index ""} {npass_index ""} } {
   set args ""

   set parentLoopArgs [SharedFlowNode_getLoopArgs ${exp_path} ${node} ${datestamp} ${loop_index}]
   if { ${parentLoopArgs} != "" } {
      set parentLoopArgs "${parentLoopArgs},"
   } elseif { [SharedFlowNode_hasLoops ${exp_path} ${node} ${datestamp}] } {
      return "-1"
   } else {
      set parentLoopArgs "-l "
   }

   set nodeName [SharedFlowNode_getName ${exp_path} ${node} ${datestamp}]
   if { ${npass_index} != "" } {
      # if npass_index is passed use it...
      # means user has provided it manually
      set args "${parentLoopArgs}${nodeName}=[string trim ${npass_index} +]"
   } else {
      set currentExt [SharedFlowNode_getCurrentExt ${exp_path} ${node} ${datestamp}]
      if { ${currentExt} == "latest" } {
         set args "-1"
         return $args
      } else {
         # remove the + sign before extension
         set currentExt [string trim ${currentExt} +]
         set args "${parentLoopArgs}${nodeName}=${currentExt}"
      }
   }

   return $args
}

proc SharedFlowNode_getParentLoopArgs { exp_path node datestamp } {
   set args ""
   set count 0
   set isLatest 0
   set loopList [SharedFlowNode_getLoops ${exp_path} ${node} ${datestamp}]

   if { [llength $loopList] > 1 } {
      foreach loopNode $loopList {
         set currentExt [SharedFlowNode_getCurrentExt ${exp_path} ${loopNode} ${datestamp}]
         if { $node != $loopNode && ${currentExt} == "latest" } {
            set args "-1"
            return $args
         } else {
            # remove the + sign before extension
            if { $node == ${loopNode} } {
               break
            }
            set currentExt [string range ${currentExt} 1 end]
            set nodeName [SharedFlowNode_getName ${exp_path} ${loopNode} ${datestamp}]
            if { $count == 0 } {
               set args "-l ${nodeName}=${currentExt}"
            } else {
               set args "${args},${nodeName}=${currentExt}"
            }
         }
         incr count
      }
   }
   return $args
}

# input +2+3 returns +2
# input +2+3+4 returns +2+3
# input +2 returns ""
proc SharedFlowNode_getBasePart { value } {
   set returnVal ""
   switch [llength [split ${value} +]] {
      0 -
      2 {
         set returnVal ""
      }

      default {
         set returnVal [string range ${value} 0 [expr [string last + ${value}] - 1]]
      }
   }

   return ${returnVal}
}

# this function is used to know whether we should redisplay
# a node branch when an update to a node is detected from
# the exp log file. To minimize the number of updates done
# at the gui level, only changes that affects the visibility
# of nodes are being redrawned. For instance, if you are viewing a loop iteration
# of 1 and updates are on another iteration, the data is updated but the gui is not
proc SharedFlowNode_isRefreshNeeded { exp_path flow_node datestamp current_ext } {
   ::log::log debug "SharedFlowNode_isRefreshNeeded $exp_path $flow_node $datestamp current_ext:$current_ext"
   set refreshNeeded true
   set nodeType [SharedFlowNode_getNodeType ${exp_path} ${flow_node} ${datestamp}]
   if { [SharedFlowNode_getLoops ${exp_path} ${flow_node} ${datestamp}] != "" } {
      # if the current is either a loop node or part of a loop container,
      # I will only call a redraw on the flow if current update affects the display
      set parentLoopExt [SharedFlowNode_getParentLoopExt ${exp_path} ${flow_node} ${datestamp}]
      # nodeExt is the value of the current loop and any parent loop
      set nodeExt [SharedFlowNode_getNodeExtension ${exp_path} ${flow_node} ${datestamp}]

      switch ${nodeType} {
         loop {
            # current is the value of current loop listbox selection
            set currentLoopSelection [SharedFlowNode_getCurrentExt ${exp_path} ${flow_node} ${datestamp}]
            if { ${parentLoopExt} == "" || ${parentLoopExt} != "latest" } {
               if { ${currentLoopSelection} != "latest" && ${nodeExt} != ${current_ext} } {
                  # we don't refresh the current update if the user is currently viewing
                  # a specific iteration and the update is not on that iteration
                  set refreshNeeded false
               }
            }
	 }
         npass_task {
            # current is the value of current listbox selection
            set currentIterationSelection [SharedFlowNode_getCurrentExt ${exp_path} ${flow_node} ${datestamp}]
            if { ${parentLoopExt} != "latest" && ${currentIterationSelection} == "latest" } {
	       # parent loop is latest, so only update if npt iteration belongs to parent loop
	       if { [string first ${parentLoopExt} ${current_ext}] != 0 } {
                  set refreshNeeded false
	       }
	    } elseif { ${parentLoopExt} == "" || ${parentLoopExt} != "latest" } {
               if { ${currentIterationSelection} != "latest" && ${nodeExt} != ${current_ext} } {
                  # we don't refresh the current update if the user is currently viewing
                  # a specific iteration and the update is not on that iteration
                  set refreshNeeded false
               }
            }
	 }
         default {
            # non indexed nodes part of a loop container
            if { ${parentLoopExt} != "latest" && ${nodeExt} != ${current_ext} } {
               set refreshNeeded false
            }
         }
      }
   }
   ::log::log debug "SharedFlowNode_isRefreshNeeded $flow_node ${current_ext} refreshed? ${refreshNeeded}"
   return ${refreshNeeded}
}

# change from node+123 to node[123]
proc SharedFlowNode_convertToDisplayFormat { node_with_ext } {
   set firstSepIndex [string first "+" ${node_with_ext}]
   set newNodeName ${node_with_ext}
   if { [expr ${firstSepIndex} != -1] } {
      set newNodeName [string replace ${node_with_ext} ${firstSepIndex} ${firstSepIndex} "\["]
      set newNodeName "${newNodeName}\]"
   }
   return ${newNodeName}
}

# change node[123] back to node+123
proc SharedFlowNode_convertFromDisplayFormat { node_with_ext } {
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

proc SharedFlowNode_setSwitchingData { exp_path node datestamp switching_type } {
   tsv::keylset SharedFlowNode_${exp_path}_${datestamp} ${node} switching_type ${switching_type}
}

proc SharedFlowNode_getSwitchingInfo { exp_path node datestamp } {
   set value ""
   if { [SharedFlowNode_getNodeType  ${exp_path} ${node} ${datestamp}] == "switch_case" } {
      set switchType [tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node} switching_type]
      switch ${switchType} {
         datestamp_hour {
	    set hour [Utils_getHourFromDatestamp ${datestamp}]
	    # set value "\[dshour-${hour}\]"
	    set value "\[dshour]"
         }
         day_of_week {
	    # set value "\[dshour-${hour}\]"
	    set value "\[dow]"
	 }
	 default {
	 }
      }
   }
   return ${value}
}

proc SharedFlowNode_printNode { exp_path node datestamp {print_child false} } {
   puts "---------------------------------------------------------"
   puts "node:${node}"
   puts "---------------------------------------------------------"
   foreach key [tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node}] {
      puts "   ${key}:[tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node} ${key}]"
   }
   if { ${datestamp} != "" } {
      SharedFlowNode_printNodeStatus ${exp_path} ${node} ${datestamp}
   }

   if { ${print_child} == true } {
      foreach child [tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node} submits] {
         SharedFlowNode_printNode ${exp_path} ${node}/${child} ${datestamp} ${print_child}
      }
   }
}

proc SharedFlowNode_printNodeStatus  { exp_path node datestamp} {
   puts "   @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
   if { [tsv::keylget  SharedFlowNode_${exp_path}_${datestamp} ${node}] != "" } {
      set nodeType [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} type]
      array set statuses [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} statuses]
      foreach { member status } [array get statuses] {
         puts "   member:${member} status:${status}"
      }
      if { ${nodeType} == "npass_task" || ${nodeType} == "loop" } {
         puts "   max_ext_value:[tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} max_ext_value]"
         puts "   current:[tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} current]"
         puts "   latest:[tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} latest_member]"
      }
      if { [SharedFlowNode_hasLoops ${exp_path} ${node} ${datestamp}] } {
         puts "   latest:[tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} latest_member]"
      }
   }
}

proc SharedFlowNode_printNodeMembers { exp_path node datestamp } {
   if { [tsv::keylget  SharedFlowNode_${exp_path}_${datestamp} ${node}] != "" } {
      set nodeType [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} type]
      array set statuses [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} statuses]
      array set statsinfo [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} stats_info]
      if { [SharedFlowNode_getLoops ${exp_path} ${node} ${datestamp}] != "" } {
         foreach { member } [lsort -integer [array names statuses]] {
            puts "   member:${member} status:$statuses($member) stats_info:$statsinfo($member)"
         }
      } else {
         foreach { member status } [array get statuses] {
            puts "   status:${status}"
         }
      }
   }
}
