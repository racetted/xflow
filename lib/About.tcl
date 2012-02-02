proc About_show { parent } {
   global env
   set topW .abouttop
   destroy ${topW}
   toplevel ${topW}
   Utils_positionWindow ${topW} ${parent} 
   wm title ${topW} "About Xflow"

   # create text widget
   set scrolledW [ScrolledWindow ${topW}.sw]
   set textW [text ${scrolledW}.txt -wrap word -height 15 -relief flat -width 75]

   ${scrolledW} setwidget ${textW}

   ${textW} tag configure BOLD_TXT -font TkHeadingFont
   set xflowVersion "unknown"
   if { [info exists env(SEQ_XFLOW_VERSION)] } {
      set xflowVersion $env(SEQ_XFLOW_VERSION)
   }
   ${textW} insert end "Xflow version ${xflowVersion}" BOLD_TXT

   set utilsVersion "unknown"
   if { [info exists env(SEQ_UTILS_VERSION)] } {
      set utilsVersion $env(SEQ_UTILS_VERSION)
   }
   ${textW} insert end "\n\nMaestro utilities version ${utilsVersion}" BOLD_TXT

   set seqVersion "unknown"
   if { [info exists env(SEQ_MAESTRO_VERSION)] } {
      set seqVersion $env(SEQ_MAESTRO_VERSION)
   }
   ${textW} insert end "\n\nMaestro sequencer version ${seqVersion}" BOLD_TXT

   ${textW} insert end "\n\nMaestro documentation:\n" BOLD_TXT

   # should create an app properties file in next version
   set docUrl "https://wiki.cmc.ec.gc.ca/wiki/Maestro"

   #font create MyUnderlinedFont
   #set defaultCfg [font configure TkDefaultFont]
   #eval font configure MyUnderlinedFont ${defaultCfg}
   #font configure MyUnderlinedFont -underline true
   #set docLabel [label ${textW}.doc_label -font MyUnderlinedFont -text ${docUrl} -fg blue]
   set docLabel [label ${textW}.doc_label -text ${docUrl} -fg blue]
   ${textW} window create end -window ${docLabel}

   bind ${docLabel} <Double-Button-1> [list Utils_goBrowser ${docUrl}]
    
   ${textW} configure -state disabled
   pack ${scrolledW} -fill both -expand yes -padx 5 -pady 5 -ipadx 2 -ipady 2
   #wm geometry ${topW} =400x200
}

