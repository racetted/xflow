#!/home/binops/afsi/ssm/domain2/tcl-tk_8.5.7_linux26-i686/bin/wish8.5
package require tdom
# sample ExpOptions.xml file
#
#<ExpOptions displayName="HRDPS/West/forecast">
#   <SupportInfo executing="Yes" status="All Full Support"/>
#   <Exp hour="00">
#      <TimingInfo ref_start="15:00" ref_end="17:00"/>
#      <SupportInfo executing="Yes" status="Full Support"/>
#   </Exp>
#   <Exp hour="12">
#      <TimingInfo ref_start="21:00" ref_end="22:30"/>
#      <SupportInfo executing="Yes" status="Full Support"/>
#   </Exp>
# </ExpOptions>
#

# parse the xml file and returns a doc
proc ExpXmlOptions_parse { _xml_file } {
   set doc [dom parse [tDOM::xmlReadFile ${_xml_file}]]
   return ${doc}
}

# when we don't need the doc anymore release it
proc ExpXmlOptions_done { _dom_doc } {
   ${_dom_doc} delete
}

proc ExpXmlOptions_getSupport { _dom_doc _exp_path _exp_name { _exp_hour "" } } {

   # return data
   set results {}

   if { ${_exp_name} != "" } {
      set expName ${_exp_name}
   } else {
      set expName [file tail ${_exp_path}]
   }

   # point to the root element
   set root [${_dom_doc} documentElement root]

   set topXmlNode [${root} selectNodes /ExpOptions]

   set defaultExecStatus No
   set defaultSupportStatus "No Support"
   # get default support for the whole exp
   set supportInfoNode [${topXmlNode} selectNodes ./SupportInfo]
   if { ${supportInfoNode} != "" } {
      set defaultExecStatus [${supportInfoNode} getAttribute executing No]
      set defaultSupportStatus [${supportInfoNode} getAttribute status "No Support"]
   }

   # get the exp hours
   set expHourNodes [${topXmlNode} selectNodes ./Exp]
   foreach expHourNode ${expHourNodes} {
      # get exp hour value
      set expHour [${expHourNode} getAttribute hour ""]
      set expNameHour ${expName}${expHour}
      set supportInfoNode [${expHourNode} selectNodes ./SupportInfo]

      # get support Info for specific exp
      if { ${supportInfoNode} != "" } {
         set executingStatus [${supportInfoNode} getAttribute executing No]
         set supportStatus [${supportInfoNode} getAttribute status "No Support"]
         lappend results [list ${expNameHour} ${executingStatus} ${supportStatus}]
      } else {
         # assign default values
         lappend results [list ${expNameHour} ${defaultExecStatus} ${defaultSupportStatus}]
      }
   }
   return ${results}
}

proc ExpXmlOptions_getRefTimings { _dom_doc } {

   # point to the root element
   set root [${_dom_doc} documentElement root]

   # retrieve the Exp elements
   # if exp_name is set, we filter it
   # if not set get all exps from the document
   set query "/ExpOptions/Exp/TimingInfo"

   set timingInfoNodes [${root} selectNodes ${query}]
   set results {}
   foreach timingInfoNode ${timingInfoNodes} {
      set expNode [${timingInfoNode} parentNode]
      set expHour [${expNode} getAttribute hour ${expNode}]
      set start [${timingInfoNode} getAttribute ref_start]
      set end [${timingInfoNode} getAttribute ref_end]
      # puts "ExpXmlOptions_getRefTimings ${expHour} ${start} ${end}"
      lappend results [list ${expHour} ${start} ${end}]
   }
   return ${results}
}

proc ExpXmlOptions_getRefTimings___ { _dom_doc _exp_hour } {

   # point to the root element
   set root [${_dom_doc} documentElement root]

   # retrieve the Exp elements
   # if exp_name is set, we filter it
   # if not set get all exps from the document
   set query "/ExpOptions/Exp\[@hour='${_exp_hour}'\]/TimingInfo"

   set expNodes [${root} selectNodes ${query}]
   set results {}
   foreach timingInfo ${expNodes} {
      set start [${timingInfo} getAttribute ref_start]
      lappend results ${start}
      set end [${timingInfo} getAttribute ref_end]
      lappend results ${end}
   }
      # get timingInfo
      #set timingInfoNode [${expHourNode} selectNodes ./TimingInfo]
      #if { ${timingInfoNode} != "" } {
      #   set refStart [${timingInfoNode} getAttribute ref_start]
      #   set refEnd [${timingInfoNode} getAttribute ref_end]
      #   puts "ExpXmlOptions_getSupport2 expHour:${expHour} refStart:${refStart} refEnd:${refEnd}"
      #}

   return ${results}
}

proc ExpXmlOptions_getDisplayName { _dom_doc _exp_path } {
   set root [${_dom_doc} documentElement root]

   set defaultDisplayName [file tail ${_exp_path}]

   # retrieve the Exp elements
   # if exp_name is set, we filter it
   # if not set get all exps from the document
   set query "/ExpOptions"

   set rootNode [${root} selectNodes ${query}]
   if { ${rootNode} != "" && [llength ${rootNode}] == 1 } {
      set defaultDisplayName [${rootNode} getAttribute displayName ${defaultDisplayName}]
   }

   return ${defaultDisplayName}
}

proc ExpXmlOptions_getShortName { _dom_doc _exp_path } {
   set root [${_dom_doc} documentElement root]

   set defaultShortName [file tail ${_exp_path}]

   # retrieve the Exp elements
   # if exp_name is set, we filter it
   # if not set get all exps from the document
   set query "/ExpOptions"

   set rootNode [${root} selectNodes ${query}]
   if { ${rootNode} != "" && [llength ${rootNode}] == 1 } {
      set defaultShortName [${rootNode} getAttribute shortName ${defaultShortName}]
   }

   return ${defaultShortName}
}

#global env
#ExpXmlOptions_read $env(SEQ_EXP_HOME)/ExpOptions.xml