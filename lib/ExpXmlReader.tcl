package require tdom
package require struct::record
namespace import ::struct::record::*

# x  is x coord variable used to know where to
#    display next exp
# x  is y coord variable used to know where to
#    display next exp
record define DisplayGroup {
   name
   level {0}
   exp_list {}
   x {0}
   y {0}
   {miny 0}
   {maxy 0}
   {group_y 0}
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
   set nodeName [$xml_node nodeName]
   if { $nodeName == "Group" } {
      set goupName [$xml_node getAttribute name]

      set newLevel $level
      if { $parent_name != "" } {
         set goupName ${parent_name}/${goupName}
         set newLevel [expr $level + 1]
         puts "ExpXmlReader_readGroup goupName:$goupName newLevel:$newLevel"
      } else {
         puts "ExpXmlReader_readGroup goupName:$goupName newLevel:$newLevel"
      }

      # replace / and spaces with _
      set groupRecordName [regsub -all "/" ${goupName} _]
      set groupRecordName [regsub -all " " ${groupRecordName} _ ]
      if { ! [record exists instance $groupRecordName] } {
         DisplayGroup $groupRecordName -name ${goupName} -level $newLevel
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
               puts "exp:$expPath"
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

proc ExpXmlReader_getExpList {} {
   set expList ""
   set displayGroups [record show instances DisplayGroup]
   foreach dispGroup $displayGroups {
      puts "ExpXmlReader_getExpList $dispGroup [$dispGroup cget -exp_list]"
      append expList [$dispGroup cget -exp_list]
   }
   return $expList
}
