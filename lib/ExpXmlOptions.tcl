#!/home/binops/afsi/ssm/domain2/tcl-tk_8.5.7_linux26-i686/bin/wish8.5
package require tdom

# parse the xml file and returns a doc
proc ExpXmlOptions_parse { xml_file } {
   set doc [dom parse [tDOM::xmlReadFile ${xml_file}]]
   return ${doc}
}

# when we don't need the doc anymore release it
proc ExpXmlOptions_done { dom_doc } {
   ${dom_doc} delete
}

# get the support information, requires a doc document
# returned from the ExpXmlOptions_parse
# it returns a list 
# {exp_name SupportExec SupportStatus exp_name SupportExec SupportStatus}
proc ExpXmlOptions_getSupport { dom_doc {exp_name ""} } {

   #set d [dom parse [tDOM::xmlReadFile ${xml_file}]]

   # point to the root element
   set root [${dom_doc} documentElement root]

   # retrieve the Exp elements
   # if exp_name is set, we filter it
   # if not set get all exps from the document
   set query "/ExpOptions/Exp"
   if { ${exp_name} != "" } {
      append query "\[@name='${exp_name}'\]"
   }

   set expNodes [${root} selectNodes ${query}]
   set results {}
   foreach expNode ${expNodes} {
      #puts "ExpXmlConfig_read exp: [${expNode} getAttribute name]"
      lappend results [${expNode} getAttribute name]
      # retrieve the SupportExec
      set supportExec [${expNode} selectNodes {string(SupportExec)}]
      lappend results ${supportExec}
      # retrieve the SupportStatus
      set supportStatus [${expNode} selectNodes {string(SupportStatus)}]
      lappend results ${supportStatus}
   }
   return ${results}
}

#global env
#ExpXmlOptions_read $env(SEQ_EXP_HOME)/ExpOptions.xml