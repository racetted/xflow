package require tdom
package require struct::record
namespace import ::struct::record::*

# x  is x coord variable used to know where to
#    display next exp
# x  is y coord variable used to know where to
#    display next exp
proc out {} {
record define DisplayGroup {
   name
   level {0}
   parent ""
   exp_list {}
   x {0}
   y {0}
   {maxy 0}
}
}

# reads an xml file for a list of folders
# containing experiment paths.
proc ExpXmlReader_readExperiments { xml_file } {
   set xmlFile $xml_file
   if [ catch { set xmlSrc [exec cat $xmlFile] } ] {
      puts "XML Document Not Found: $xmlFile"
      return
   }

   # First you parse the XML, the result is held in token d.
   set xmlSrc [string trim $xmlSrc] ;# v2.6 barfed w/o this
   set d [dom parse $xmlSrc]

   # point to the root element
   set folders [$d getElementsByTagName GroupList]

   set level 0
   # get the list of Group
   set children [$folders childNodes]
   foreach child $children {
      set childName [$child nodeName]
      if { $childName == "Group" } {
         set goupName [$child getAttribute name]
         ExpXmlReader_readGroup $child "" $level
      }
   }
}

proc ExpXmlReader_readGroup { xml_node parent_name level} {
   global DISPLAY_GROUPS

   set nodeName [$xml_node nodeName]
   if { $nodeName == "Group" } {
      set goupName [$xml_node getAttribute name]

      set newLevel $level
      if { $parent_name != "" } {
         set goupName ${parent_name}/${goupName}
         set newLevel [expr $level + 1]
         ::log::log debug "ExpXmlReader_readGroup goupName:$goupName newLevel:$newLevel"
      } else {
         ::log::log debug "ExpXmlReader_readGroup goupName:$goupName newLevel:$newLevel"
      }

      # replace / and spaces with _
      set groupRecordName [regsub -all "/" ${goupName} _]
      set groupRecordName [regsub -all " " ${groupRecordName} _ ]
      if { ! [record exists instance $groupRecordName] } {
         set recordId [DisplayGroup $groupRecordName -name ${goupName} -level $newLevel -parent ${parent_name} -x 0 -y 0 -maxy 0]
	 lappend DISPLAY_GROUPS ${recordId}
         if { ${parent_name} != "" } {
            DisplayGrp_insertGroup ${parent_name} ${recordId}
         }
      }

      set childs [$xml_node childNodes]
      if { $childs == "" } {
         # puts "ExpXmlReader_readGroup group name:$goupName no child"
         # DisplayGroup $goupName -name $goupName -level $newLevel
      } else {
         foreach child $childs {
            set childName [$child nodeName]
            if { $childName == "Exp" } {
               set firstChild [$child firstChild]
               set expPath [$firstChild nodeValue]
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
   #set displayGroups [record show instances DisplayGroup]
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
