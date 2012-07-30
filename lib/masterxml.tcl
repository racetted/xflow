#!/data/bowmore/afsisul/apps/bin/tclsh8.5
package require struct::record
package require tdom
package require FlowNodes

proc readMasterfile { xml_file suite_path parent_flow_node suite } {
   if [ catch { set xmlSrc [exec cat $xml_file] } ] {
      error "readMasterfile XML Document Not Found: $xml_file"
      return
   }
   parseModuleMasterfile $xmlSrc $suite_path $parent_flow_node $suite 
}


proc getSubmits { flow_node xml_node } {
   set submits [$xml_node selectNodes SUBMITS]
   set flowChildren ""
   foreach submit $submits {
      set flowSubmitName [$submit getAttribute sub_name ""]
      lappend flowChildren $flowSubmitName
   }
   #puts "getSubmits flowChildren:$flowChildren"
   $flow_node configure -flow.children $flowChildren
}

# retrieve the dependencies for the node
# "testsuite/bg_check/primary -6 job complete testsuite n/a"
proc getDeps { flow_node xml_node } {
   set xmlDepNodes [$xml_node selectNodes DEPENDS]
   set depValues {}
   foreach depNode $xmlDepNodes {
      set depName [$depNode getAttribute dep_name "n/a"]
      set depPath [$depNode getAttribute path "."]
      set depHour [$depNode getAttribute hour "n/a"]
      set depType [$depNode getAttribute type "n/a"]
      set depStatus [$depNode getAttribute status "n/a"]
      set depSuite [$depNode getAttribute suite "n/a"]
      set depUser [$depNode getAttribute user "n/a"]
      set depKey ${depPath}/${depName}
      set depValue "$depHour $depType $depStatus $depSuite $depUser"
      #set depValues($depKey) $depValue
      lappend depValues $depKey
      lappend depValues $depValue
   }

   #set depValues { key0 value0 key1 value1 key2 value2 }
   #puts "getSubmits flowChildren:$flowChildren"
   $flow_node configure -flow.deps $depValues
}

proc createNodeFromXml { suite parent_flow_node xml_node } {
   set FlowNodeTypeMap {   TASK "FlowTask task"
                           FAMILY "FlowFamily family"
                           LOOP "FlowLoop loop"
                           CASE_ITEM "FlowOutlet outlet"
                           CASE "FlowCase case"
                           MODULE "FlowModule module"
                           NPASS_TASK "FlowNpassTask npass_task"
                           SUPER_TASK "FlowSuperTask super_task"
                       }

   set xmlNodeName [$xml_node nodeName]
   set nodeName [$xml_node getAttribute name ""]
   # I need to get the node that has a submit to this node. It is not
   # necessarily the xml parent node that is effectively the flow parent
   # node
   DEBUG "createNodeFromXml() parent_flow_node:$parent_flow_node nodeName:$nodeName xmlNodeName:${xmlNodeName}" 5
   set actualFlowParent [::FlowNodes::searchSubmitNode $parent_flow_node $nodeName]
   set newFlowDirname $actualFlowParent/$nodeName
   set flowCreateCmd [lindex [string map $FlowNodeTypeMap $xmlNodeName] 0]
   set flowType [lindex [string map $FlowNodeTypeMap $xmlNodeName] 1]
   #puts "createNodeFromXml() newFlowDirname:$newFlowDirname"
   if { ! [record exists instance $newFlowDirname] } {
      $flowCreateCmd $newFlowDirname
   }
   $newFlowDirname configure -flow.name $nodeName -flow.type $flowType -flow.parent $actualFlowParent
   if { ${xmlNodeName} == "MODULE" } {
      $newFlowDirname configure -load_time [clock seconds]
   }

   # I'm storing the closest container of the node
   set parentContainer "[$actualFlowParent cget -flow.container]"
   set parentName "[$actualFlowParent cget -flow.name]"
   DEBUG "createNodeFromXml() parentContainer:$parentContainer parentName:$parentName type:$flowType parentType:[$actualFlowParent cget -flow.type]" 5
   set parentType [$actualFlowParent cget -flow.type]
   if { [string match "*task" ${parentType} ] } {
      $newFlowDirname configure -flow.container "$parentContainer"
   } else {
      if { ${parentContainer} == "" } {
         $newFlowDirname configure -flow.container "/${parentName}"
      } else {
         $newFlowDirname configure -flow.container "${parentContainer}/${parentName}"
      }
   }

   # if one of my parent node in the flow is of type task, I also need to store a mapping
   # of the real node to the flow node. A real node is the value that is required by the
   # sequencer API.
   if { [::FlowNodes::searchForTask $actualFlowParent] != "" } {
      if { [string match "*task" ${parentType} ] } {
         ::SuiteNode::addFlowNodeMapping $suite $parentContainer/$nodeName $newFlowDirname
      } else {
         ::SuiteNode::addFlowNodeMapping $suite $parentContainer/$parentName/$nodeName $newFlowDirname
      }
   }
   
   # I'm storing the list of parent loops if there are any
   ::FlowNodes::searchParentLoops $newFlowDirname $newFlowDirname

   #puts "createNodeFromXml parent:$actualFlowParent container name: [$newFlowDirname cget -flow.container]"
   set newParentNode $newFlowDirname
   getSubmits $newFlowDirname $xml_node
   getDeps $newFlowDirname $xml_node
   return $newParentNode
}

# there is a distinction between the xml node used by tdom
# and the flow_node record defined by the current application
# parent_flow_node refers to a FlowNode record instance
# current_xml_node refers to a tdom node instance
# 
proc parseXmlNode { suite parent_flow_node current_xml_node } {

   global env
   set xmlNodeName [$current_xml_node nodeName]
   DEBUG "parseXmlNode: suite:$suite parent_flow_node=$parent_flow_node xmlNodeName=$xmlNodeName" 5
   set parseChild 1
   set parentFlowNode $parent_flow_node
   set newParentNode ""
   # defaults to 0
   set workUnitMode [$current_xml_node getAttribute work_unit 0] 

   switch $xmlNodeName {
      "TASK" -
      "NPASS_TASK" -
      "CASE_ITEM" -
      "FAMILY" {
         set newParentNode [createNodeFromXml $suite $parent_flow_node $current_xml_node]
      }
      "MODULE" { 
         set suiteName [$suite cget -suite_name]
         set nodeName [$current_xml_node getAttribute name]
         set newXmlFile [$suite cget -suite_path]/modules/$nodeName/flow.xml
         DEBUG "ParseXmlNode:: suite_path: [$suite cget -suite_path]"  5
         DEBUG "ParseXmlNode:: newXmlFile = $newXmlFile"  5
         set newParentNode [createNodeFromXml $suite $parent_flow_node $current_xml_node]
         readMasterfile $newXmlFile [$suite cget -suite_path] $newParentNode $suite
         set parseChild 0
      }
      "LOOP" {
         set newParentNode [createNodeFromXml $suite $parent_flow_node $current_xml_node]
         set start [$current_xml_node getAttribute start "1"]
         set step [$current_xml_node getAttribute step "1"]
         set setValue [$current_xml_node getAttribute "set" "1"]
         set end [$current_xml_node getAttribute end "1"]
         set type default
         if { $setValue != "" } {
            set type loopset
         }
         $newParentNode configure -loop_type $type -start $start -step $step -end $end \
                     -set $setValue
      }
      "CASE" {
         set newParentNode [createNodeFromXml $suite $parent_flow_node $current_xml_node]
         set evalScript [$current_xml_node getAttribute exec_script]
         $newParentNode configure -eval_exec $evalScript
      }
      "DEPENDS_ON" -
      "SUBMITS" -
      "ABORT_ACTION" -
      "#text" -
      "#comment" {
         set parseChild 0
      }
      default {
         puts "got UNSUPPORTED child name: $xmlNodeName"
         set parseChild 0
      }
   }
   if { ${parseChild} == 1 } {
      if { $newParentNode != "" } {
         set parentFlowNode $newParentNode
         ${newParentNode} configure -flow.work_unit ${workUnitMode}
      }
      if { [$current_xml_node hasChildNodes] && $parseChild == 1 } {
         set xmlChildren [$current_xml_node childNodes]
         foreach xmlChild $xmlChildren {
            parseXmlNode $suite $parentFlowNode $xmlChild
         }
      }
   }
}

proc parseModuleMasterfile { xml_data suite_path parent_flow_node suite_record } {
   DEBUG "parseModuleMasterfile suite_path:$suite_path parent_flow_node:$parent_flow_node" 4
   # First you parse the XML, the result is held in token d.
   set xml_data [string trim $xml_data] ;# v2.6 barfed w/o this
   
   set doc [dom parse $xml_data ]
   set rootNode [$doc documentElement]
   
   # get the top node of the xml tree
   set topXmlNode [$rootNode selectNodes /MODULE]
   set recordName [$topXmlNode getAttribute name]
   # defaults to 0
   set workUnitMode [$topXmlNode getAttribute work_unit 0] 
   # DEBUG "parseModuleMasterfile suite_record:$suite_record recordName:${recordName} workUnitMode:${workUnitMode}" 5
   
   set suiteRecord [::SuiteNode::formatSuiteRecord $suite_path]
   if { $parent_flow_node == "" } {
      set suiteName [$topXmlNode getAttribute name]
      if { ! [record exists instance $suiteRecord] } {
         DEBUG "parseModuleMasterfile $suiteRecord does not exists" 5
         SuiteInfo $suiteRecord
      }
      set recordName "/$suiteName"
      $suiteRecord configure -type "user" -suite_name $suiteName -suite_path $suite_path -root_node ${recordName}
      SharedData_setSuiteData ${suite_path} ROOT_NODE ${recordName}
      # create the top node of our flow tree
      if { ! [record exists instance ${recordName}] } {
         FlowModule $recordName
         $recordName configure -load_time [clock seconds] 
      }
      $recordName configure -flow.name $suiteName -flow.type module -flow.family $recordName
   } else {
      DEBUG "parseModuleMasterfile suite_record:$suite_record" 5
      set suiteName [$suite_record cget -suite_name]
      set recordName $parent_flow_node
      DEBUG "parseModuleMasterfile suiteName:$suiteName" 5
   }
   $recordName configure  -flow.work_unit ${workUnitMode}

   getSubmits $recordName $topXmlNode
   # recursively parse the children nodes of the xml tree
   if { [$topXmlNode hasChildNodes] } {
      set xmlChildren [$topXmlNode childNodes]
      foreach xmlChild $xmlChildren {
         parseXmlNode $suiteRecord $recordName $xmlChild
      }
   }

   $doc delete
}

# for testing
if { [info exists argv] && [llength $argv] == 1 } {
   readMasterfile [lindex $argv 0]
}
