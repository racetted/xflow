
package require Thread

################################################################################
# Reads output of tsvinfo from stdout into a TSV keyed list.  The output is for
# the specified experiment and relative to the specified datestamp.
################################################################################
proc TsvInfo_loadData { exp_path datestamp } {

   # Launch the binary and collect it's output
   # Note: the datestamp will need to be used.
   set data_list [exec tsvinfo -t stdout -e $exp_path -d $datestamp]

   # Read the content of the file into a keyed list.
   tsv::keylset the_shared_var the_keyed_list {*}$data_list

}

################################################################################
# Retrie information from a node specified by $nodeName (sequencer name) and
# subkey. like loop.start or resources.cpu
################################################################################
proc TsvInfo_getNodeInfo { nodeName subkey } {
   return [tsv::keylget the_shared_var the_keyed_list $nodeName.$subkey]
}

################################################################################
# Same as getNodeInfo, but puts the value associated with the key into a
# variable specified by the caller.
################################################################################
proc TsvInfo_getInfoPlus { nodeName subkey retvar_name } {

   upvar $retvar_name retvar
   return [tsv::keylget the_shared_var the_keyed_list $nodeName.$subkey retvar]
}

################################################################################
# Used to check if a node has a given subkey.  Returns 1 if the subkey exists
# and 0 if it doesn't.
################################################################################
proc TsvInfo_haskey { nodeName subkey } {
   return [tsv::keylget the_shared_var the_keyed_list $nodeName.$subkey {}]
}

################################################################################
# Kept from SharedFlowNode_getLoopInfo
# Splits definitions on different lines:
# 1:2:3:4,5:6:7:8 
# becomes
# 1:2:3:4
# 5:6:7:8
################################################################################
proc TsvInfo_formatExpression { expression } {
   set definitions [split $txt ","]
   set txt ""
   foreach def $definitions {
      append txt $def "\n"
   }

   # removes the newline after the last definition
   string range $txt 0 end-2
   return $txt
}

################################################################################
# Constructs the text that goes under the name of a loop widget
# For regular loops, it is [a,b,c,d] where a = start, b = end, c = step, d =
# set.
# For expression loops it is [expr], the expression string in brackets.
################################################################################
proc TsvInfo_getLoopInfo { exp_path loop_node datestamp } {
   set seq_node [SharedFlowNode_getSequencerNode $exp_path $loop_node $datestamp]
   # set loop_type [TsvInfo_getNodeInfo $loop_node loop.type]
   # switch $loop_type {
   if { [TsvInfo_haskey $seq_node loop.expression] } {
      set expression [TsvInfo_getNodeInfo $seq_node loop.expression]
      # set text to either expression on one line or one def per line.
      set txt "\[$expression\]"
      # set txt [TsvInfo_formatExpression $expression]
   } else {
      set start [TsvInfo_getNodeInfo $seq_node loop.start]
      set end [TsvInfo_getNodeInfo $seq_node loop.end]
      set step [TsvInfo_getNodeInfo $seq_node loop.step]
      set set_val [TsvInfo_getNodeInfo $seq_node loop.set]

      # set txt "\[${start},${end},${step},${set_val}\]"
      set txt "\[${start},${end},${step},${set_val}\]"
   }
   # }
   return $txt
}
