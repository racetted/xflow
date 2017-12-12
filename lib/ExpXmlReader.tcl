package require tdom
package require struct::record
namespace import ::struct::record::*

# reads an xml file for a list of folders
# containing experiment paths.
proc ExpXmlReader_readExperiments { xml_file } {
   global DISPLAY_GROUPS
   set xmlFile $xml_file
   if [ catch { set xmlSrc [exec -ignorestderr cat $xmlFile] } ] {
      puts "XML Document Not Found: $xmlFile"
      return
   }

   # First you parse the XML, the result is held in token d.
   set xmlSrc [string trim $xmlSrc] ;# v2.6 barfed w/o this
   set d [dom parse $xmlSrc]

   # point to the root element
   set folders [$d getElementsByTagName GroupList]

   set labelValue [${folders} getAttribute label ""]
   set labelBgValue [${folders} getAttribute label_bg ""]
   
   SharedData_setMiscData WINDOWS_LABEL ${labelValue}
   SharedData_setMiscData WINDOWS_LABEL_BG ${labelBgValue}

   set level 0
   # get the list of Group
   set children [$folders childNodes]
   foreach child $children {
      set childName [$child nodeName]
      if { $childName == "Group" } {
         ExpXmlReader_readGroup $child "" $level
      }
   }
}

proc ExpXmlReader_readGroup { xml_node parent_name level} {
   global DISPLAY_GROUPS
   set nodeName [$xml_node nodeName]
   if { $nodeName == "Group" } {
      set groupName [$xml_node getAttribute name]
      set groupDname ${groupName}

      set newLevel $level
      if { $parent_name != "" } {
         set groupDname ${parent_name}/${groupName}
         set newLevel [expr $level + 1]
      }
      ::log::log debug "ExpXmlReader_readGroup groupName:$groupName newLevel:$newLevel"

      # replace / and spaces with _
      set groupRecordName [regsub -all "/" ${groupDname} _]
      set groupRecordName [regsub -all " " ${groupRecordName} _ ]
      if { ! [record exists instance $groupRecordName] } {
         set recordId [DisplayGroup $groupRecordName -name ${groupName} -dname ${groupDname} -level $newLevel -parent ${parent_name} -x 0 -y 0 -max_y 0]
         lappend DISPLAY_GROUPS ${recordId}
         if { ${parent_name} != "" } {
            DisplayGrp_insertGroup ${parent_name} ${recordId}
         }
      }

      set childs [$xml_node childNodes]
      if { $childs == "" } {
         # puts "ExpXmlReader_readGroup group name:$groupName no child"
         # DisplayGroup $groupName -dname $groupName -level $newLevel
      } else {
         foreach child $childs {
            set childName [$child nodeName]
            if { $childName == "Exp" } {
               set firstChild [$child firstChild]
               set expPath [$firstChild nodeValue]
               # ExpXmlReader_addExp $groupRecordName [exec true_path $expPath]
               ExpXmlReader_addExp $groupRecordName $expPath
               ::log::log debug "exp:$expPath"
            } elseif { $childName == "Group" } {
               ExpXmlReader_readGroup $child $groupRecordName $newLevel
            }
         }
      }
   }
}

proc ExpXmlReader_addExp {group_name exp_path} {
   set expList [$group_name cget -exp_list]
   if { [lsearch $expList $exp_path] == -1 } {
      lappend expList $exp_path
      $group_name configure -exp_list $expList
   }
}

proc ExpXmlReader_getGroups {} {
   global DISPLAY_GROUPS
   if { [info exists DISPLAY_GROUPS] } {
      return ${DISPLAY_GROUPS}
   }
   return ""
}

proc ExpXmlReader_getExpList {} {
   set expList ""
   set displayGroups [ExpXmlReader_getGroups]

   foreach dispGroup $displayGroups {
      ::log::log debug "ExpXmlReader_getExpList $dispGroup [$dispGroup cget -exp_list]"
      append expList [$dispGroup cget -exp_list]
   }
   return $expList
}

global env
if { ! [record exists record DisplayGroup] } {
   # puts "ExpXmlReader sourcing DisplayGrp.tcl"
   source ${lib_dir}/DisplayGrp.tcl
}
