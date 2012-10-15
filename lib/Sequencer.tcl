proc Sequencer_getPath {} {
   global env
   if { [info exists env(SEQ_BIN)] } {
      return $env(SEQ_BIN)
   }
   set sequencerPath ""
   catch { set sequencerPath [exec which maestro] }
   if { $sequencerPath == "" } {
      Utils_fatalError . "Application Error" "SEQ_BIN not set. Cannot find sequencer binaries path!"
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
      Utils_fatalError . "Application Error" "SEQ_UTILS_BIN not set. Cannot find sequencer utilities path!"
   }
   return [file dirname $utilsPath]
}

proc Sequencer_runCommandWithWindow { exp_path datestamp parent_top command title position args } {
   global env
   regsub -all " " [file tail $command] _ tmpfile
   set id [clock seconds]
   set tmpdir $env(TMPDIR)
   set tmpfile "${tmpdir}/${tmpfile}_${id}"
   Sequencer_runCommand ${exp_path} ${datestamp} ${tmpfile} "${command} [join ${args}]"
   create_text_window "$title" ${tmpfile} ${position} ${parent_top}
   catch {[exec rm -f ${tmpfile}}
}

proc Sequencer_runCommandLogAndWindow { exp_path datestamp parent_top command title position args } {
   global env
   regsub -all " " [file tail $command] _ tmpfile
   set id [clock seconds]
   set tmpdir $env(TMPDIR)
   set tmpfile "${tmpdir}/${tmpfile}_${id}"
   Sequencer_runCommand ${exp_path} ${datestamp} ${tmpfile} "${command} [join ${args}]"
   ::log::log notice "${command} [join ${args}]"
   Utils_logFileContent notice ${tmpfile}
   create_text_window "$title" ${tmpfile} ${position} ${parent_top}
   catch {[exec rm -f ${tmpfile}}
}

proc Sequencer_runCommand { exp_path datestamp out_file command } {
   # if { [Utils_validateRealDatestamp ${datestamp}] == false } {
   #  error "Invalid datestamp"
   # }
   if { ${datestamp} != "" } {
      set cmd "export SEQ_EXP_HOME=$exp_path;export SEQ_DATE=${datestamp}; print \"### ${command}\" > ${out_file}; $command >> ${out_file} 2>&1"
   } else {
      set cmd "export SEQ_EXP_HOME=$exp_path;print \"### ${command}\" > ${out_file}; $command >> ${out_file} 2>&1"
   }
   ::log::log debug "Sequencer_runCommand ksh -c $cmd"
   catch { eval [exec ksh -c $cmd]}
}