#!/data/bowmore/afsisul/apps/bin/tclsh8.5
package require struct::record
package require tdom
package require log

proc FlowXml_parse { xml_file exp_path datestamp parent_flow_node } {
   if [ catch { set xmlSrc [exec cat $xml_file] } ] {
      error "FlowXml_parse XML Document Not Found: $xml_file"
      return
   }
   FlowXml_parseModule $xmlSrc $exp_path ${datestamp} $parent_flow_node 
}


proc FlowXml_getSubmits { exp_path datestamp flow_node xml_node } {
   set submits [$xml_node selectNodes SUBMITS]
   set flowSubmits ""
   #puts "FlowXml_getSubmits ${exp_path} ${flow_node}"
   foreach submit $submits {
      set flowSubmitName [$submit getAttribute sub_name ""]
      lappend flowSubmits $flowSubmitName
   }
   #puts "FlowXml_getSubmits ${exp_path} ${flow_node} flowSubmits:${flowSubmits}"
   SharedFlowNode_setGenericAttribute ${exp_path} ${flow_node} ${datestamp} submits ${flowSubmits}
}

# retrieve the dependencies for the node
# "testsuite/bg_check/primary -6 job complete testsuite n/a"
proc FlowXml_getDeps { exp_path datestamp flow_node xml_node } {
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
   #puts "FlowXml_getSubmits flowChildren:$flowChildren"
   SharedFlowNode_setGenericAttribute ${exp_path} ${flow_node} ${datestamp} deps ${depValues}
}

proc FlowXml_createNodeFromXml { exp_path datestamp parent_flow_node xml_node } {
   set FlowNodeTypeMap {   TASK "FlowTask task"
                           FAMILY "FlowFamily family"
                           LOOP "FlowLoop loop"
                           CASE_ITEM "FlowOutlet outlet"
                           CASE "FlowCase case"
                           MODULE "FlowModule module"
                           NPASS_TASK "FlowNpassTask npass_task"
                       }

   set xmlNodeName [$xml_node nodeName]
   set nodeName [$xml_node getAttribute name ""]
   # I need to get the node that has a submit to this node. It is not
   # necessarily the xml parent node that is effectively the flow parent
   # node
   ::log::log debug "FlowXml_createNodeFromXml() parent_flow_node:$parent_flow_node nodeName:$nodeName"
   set actualFlowParent [SharedFlowNode_searchSubmitNode ${exp_path} $parent_flow_node ${datestamp} $nodeName]
   set newFlowDirname $actualFlowParent/$nodeName
   set flowCreateCmd [lindex [string map $FlowNodeTypeMap $xmlNodeName] 0]
   set flowType [lindex [string map $FlowNodeTypeMap $xmlNodeName] 1]
   #puts "FlowXml_createNodeFromXml() newFlowDirname:$newFlowDirname"
   SharedFlowNode_createNode ${exp_path} ${newFlowDirname} ${datestamp} ${actualFlowParent} ${flowType}
   if { ${xmlNodeName} == "MODULE" } {
      SharedFlowNode_setGenericAttribute ${exp_path} ${newFlowDirname} ${datestamp} load_time [clock seconds]
   }
   # I'm storing the closest container of the node
   set parentContainer "[SharedFlowNode_getGenericAttribute ${exp_path} ${actualFlowParent} ${datestamp} container]"
   set parentName "[SharedFlowNode_getGenericAttribute ${exp_path} ${actualFlowParent} ${datestamp} name]"
   set parentType [SharedFlowNode_getGenericAttribute ${exp_path} ${actualFlowParent} ${datestamp} type]
   ::log::log debug "FlowXml_createNodeFromXml() parentContainer:$parentContainer parentName:$parentName type:$flowType parentType:${parentType}"
   if { [string match "*task" ${parentType} ] } {
      SharedFlowNode_setGenericAttribute ${exp_path} ${newFlowDirname} ${datestamp} container "$parentContainer"
   } else {
      if { ${parentContainer} == "" } {
         SharedFlowNode_setGenericAttribute ${exp_path} ${newFlowDirname} ${datestamp} container "/${parentName}"
      } else {
         SharedFlowNode_setGenericAttribute ${exp_path} ${newFlowDirname} ${datestamp} container "${parentContainer}/${parentName}"
      }
   }

   # if one of my parent node in the flow is of type task, I also need to store a mapping
   # of the real node to the flow node. A real node is the value that is required by the
   # sequencer API.
   if { [SharedFlowNode_searchForTask ${exp_path} $actualFlowParent ${datestamp}] != "" } {
      if { [string match "*task" ${parentType} ] } {
         SharedData_addExpNodeMapping ${exp_path} ${datestamp} $parentContainer/$nodeName $newFlowDirname
      } else {
         SharedData_addExpNodeMapping ${exp_path} ${datestamp} $parentContainer/$parentName/$nodeName $newFlowDirname
      }
   }
   
   # I'm storing the list of parent loops if there are any
   SharedFlowNode_searchSubmitLoops ${exp_path} $newFlowDirname ${datestamp} $newFlowDirname

   set newParentNode $newFlowDirname
   FlowXml_getSubmits ${exp_path} ${datestamp} $newFlowDirname $xml_node
   FlowXml_getDeps ${exp_path} ${datestamp} $newFlowDirname $xml_node
   ::log::log debug "FlowXml_createNodeFromXml() done returning newParentNode:$newParentNode"
   return $newParentNode
}

# there is a distinction between the xml node used by tdom
# and the flow_node record defined by the current application
# parent_flow_node refers to a FlowNode record instance
# current_xml_node refers to a tdom node instance
# 
proc FlowXml_parseNode { exp_path datestamp parent_flow_node current_xml_node } {

   global env
   set xmlNodeName [$current_xml_node nodeName]
   ::log::log debug "FlowXml_parseNode: exp_path:$exp_path parent_flow_node=$parent_flow_node xmlNodeName=$xmlNodeName"
   set parseChild 1
   set parentFlowNode $parent_flow_node
   set newParentNode ""
   # defaults to 0
   set workUnitMode 0
   if { [$current_xml_node nodeType] == "ELEMENT_NODE" } {
      # this line bombs if not element i.e. comments for instance
      set workUnitMode [$current_xml_node getAttribute work_unit 0]
   }
   switch $xmlNodeName {
      "TASK" -
      "NPASS_TASK" -
      "CASE_ITEM" -
      "FAMILY" {
         set newParentNode [FlowXml_createNodeFromXml ${exp_path}  ${datestamp} $parent_flow_node $current_xml_node]
      }
      "MODULE" { 
	      set nodeName [$current_xml_node getAttribute name]
         set newXmlFile ${exp_path}/modules/$nodeName/flow.xml
         ::log::log debug "FlowXml_parseNode:: newXmlFile = $newXmlFile"
         set newParentNode [FlowXml_createNodeFromXml ${exp_path} ${datestamp} $parent_flow_node $current_xml_node]
         ::log::log debug "FlowXml_parseNode FlowXml_parse $newXmlFile ${exp_path} $newParentNode"
         FlowXml_parse $newXmlFile ${exp_path} ${datestamp} $newParentNode
         set parseChild 0
      }
      "LOOP" {
         set newParentNode [FlowXml_createNodeFromXml ${exp_path}  ${datestamp} $parent_flow_node $current_xml_node]
         set start [$current_xml_node getAttribute start "1"]
         set step [$current_xml_node getAttribute step "1"]
         set setValue [$current_xml_node getAttribute "set" "1"]
         set end [$current_xml_node getAttribute end "1"]
         set type default
         if { $setValue != "" } {
            set type loopset
         }
         SharedFlowNode_setLoopData ${exp_path} ${newParentNode} ${datestamp} ${type} ${start} ${step} ${end} ${setValue}
      }
      "CASE" {
         # set newParentNode [FlowXml_createNodeFromXml ${exp_path} $parent_flow_node $current_xml_node]
         # set evalScript [$current_xml_node getAttribute exec_script]
         # $newParentNode configure -eval_exec $evalScript
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
   if { $newParentNode != "" } {
      set parentFlowNode $newParentNode
      SharedFlowNode_setGenericAttribute ${exp_path} ${newParentNode} ${datestamp} work_unit ${workUnitMode}
   }
   # do I need to go down further?
   if { ${parseChild} == 1 } {
      if { [$current_xml_node hasChildNodes] && $parseChild == 1 } {
         set xmlChildren [$current_xml_node childNodes]
         foreach xmlChild $xmlChildren {
            FlowXml_parseNode ${exp_path} ${datestamp} $parentFlowNode $xmlChild
         }
      }
   }
}

proc FlowXml_parseModule { xml_data exp_path datestamp parent_flow_node } {
   ::log::log debug "FlowXml_parseModule exp_path:$exp_path parent_flow_node:$parent_flow_node"
   # puts "FlowXml_parseModule exp_path:$exp_path parent_flow_node:$parent_flow_node"
   # First you parse the XML, the result is held in token d.
   set xml_data [string trim $xml_data] ;# v2.6 barfed w/o this
   
   set doc [dom parse $xml_data ]
   set rootNode [$doc documentElement]
   
   # get the top node of the xml tree
   set topXmlNode [$rootNode selectNodes /MODULE]
   set recordName [$topXmlNode getAttribute name]
   # defaults to 0
   set workUnitMode [$topXmlNode getAttribute work_unit 0]

   if { $parent_flow_node == "" } {
      set suiteName [$topXmlNode getAttribute name]
      set recordName "/$suiteName"
      SharedData_setExpRootNode ${exp_path} ${datestamp} ${recordName}
      # create the top node of our flow tree
      if { [SharedFlowNode_isNodeExist ${exp_path} ${recordName} ${datestamp}] == false } {
         SharedFlowNode_createNode ${exp_path} $recordName ${datestamp} "" module
         SharedFlowNode_setGenericAttribute ${exp_path} ${recordName} ${datestamp} load_time [clock seconds]
      }
   } else {
      set recordName $parent_flow_node
   }
   SharedFlowNode_setGenericAttribute ${exp_path} ${recordName} ${datestamp} work_unit ${workUnitMode}
   FlowXml_getSubmits ${exp_path} ${datestamp} $recordName $topXmlNode
   # recursively parse the children nodes of the xml tree
   if { [$topXmlNode hasChildNodes] } {
      set xmlChildren [$topXmlNode childNodes]
      foreach xmlChild $xmlChildren {
         FlowXml_parseNode ${exp_path} ${datestamp} $recordName $xmlChild
      }
   }

   $doc delete
}

