proc Sequencer_getPath {} {
   global env
   if { [info exists env(SEQ_BIN)] } {
      return $env(SEQ_BIN)
   }
   set sequencerPath ""
   catch { set sequencerPath [exec which maestro] }
   if { $sequencerPath == "" } {
      FatalError . "Application Error" "SEQ_BIN not set. Cannot find sequencer binaries path!"
   }
   return [file dirname $sequencerPath]
}

proc Sequencer_getUtilsPath {} {
   global env
   if { [info exists env(SEQ_UTILS_BIN)] } {
      return $env(SEQ_UTILS_BIN)
   }
   set utilsPath ""
   catch { set utilsPath [exec which nodetracer] }
   if { $utilsPath == "" } {
      FatalError . "Application Error" "SEQ_UTILS_BIN not set. Cannot find sequencer utilities path!"
   }
   return [file dirname $utilsPath]
}

proc Sequencer_runCommand { suite_path command title args } {
   global env
   regsub -all " " [file tail $command] _ tmpfile
   set id [clock seconds]
   set tmpdir $env(TMPDIR)
   set tmpfile "${tmpdir}/${tmpfile}$id"
   set cmd "export SEQ_EXP_HOME=$suite_path;$command [join $args] > $tmpfile 2>&1"
   DEBUG "Sequencer_runCommand ksh -c $cmd" 5
   catch { eval [exec ksh -c $cmd]}
   create_text_window "$title" $tmpfile top .
   catch {[exec rm -f $tmpfile]}
}