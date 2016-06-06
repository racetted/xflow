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

proc Sequencer_getExpRootNodeInfo { exp_path } {
   set seqExec "[SharedData_getMiscData SEQ_BIN]/nodeinfo"

   set cmd "export SEQ_EXP_HOME=$exp_path; ${seqExec} -f root | cut -d \"=\" -f2"
   set rootNode [exec ksh -c ${cmd}]
   return ${rootNode}
}

proc Sequencer_runCommandWithWindow { exp_path datestamp parent_top command title position args } {
   global env
   regsub -all " " [file tail $command] _ tmpfile
   set id [clock seconds]
   set tmpdir $env(TMPDIR)
   set tmpfile "${tmpdir}/${tmpfile}_${id}"
   Sequencer_runCommand ${exp_path} ${datestamp} ${tmpfile} "${command} [join ${args}]"
   TextEditor_createWindow "$title" ${tmpfile} ${position} ${parent_top}
   catch {[exec rm -f ${tmpfile}}
}

proc Sequencer_runSubmit { exp_path datestamp parent_top command title position args } {
   global env
   global SUBMIT_POPUP
   regsub -all " " [file tail $command] _ tmpfile
   set id [clock seconds]
   set tmpdir $env(TMPDIR)
   set tmpfile "${tmpdir}/${tmpfile}_${id}"
   Sequencer_runCommand ${exp_path} ${datestamp} ${tmpfile} "${command} [join ${args}]"
   ::log::log notice "${command} [join ${args}]"
   if { ${SUBMIT_POPUP} != false } {
      TextEditor_createWindow "$title" ${tmpfile} ${position} ${parent_top}
   }
   catch {[exec rm -f ${tmpfile}}
}

proc Sequencer_runCommand { exp_path datestamp out_file command } {

   set prefix "export SEQ_EXP_HOME=${exp_path}"
   if { ${datestamp} != "" } {
      set prefix "$prefix; export SEQ_DATE=${datestamp}"
   }

   set remote_host [ SharedData_getMiscData REMOTE_HOST ]

   if { $remote_host != "" } {
      # Send command through ssh pipe
      set remote_user [ SharedData_getMiscData REMOTE_USER ]
      if { $remote_user != "" } {
         set remote_user "-l $remote_user"
      }
      set maestro_shortcut "$::env(SEQ_MAESTRO_SHORTCUT)"
      set prefix "${prefix}; export SEQ_MAESTRO_SHORTCUT=\\\"$maestro_shortcut\\\";$maestro_shortcut"
      set cmd "${prefix}; echo \\\"### ${command}\\\"; $command"
      set remote_cmd "echo \"${cmd}\" | ssh ${remote_host} ${remote_user} > ${out_file} 2>&1"
      puts "Running remote command $remote_cmd"
      catch { eval [exec ksh -c $remote_cmd] }
      ::log::log debug "Sequencer_runCommand ksh -c $remote_cmd"
   } else {
      # Send command on local shell
      set cmd "${prefix}; echo \"### ${command}\" > ${out_file}; $command >> $out_file 2>&1"
      catch { eval [ exec ksh -c $cmd ] }
      ::log::log debug "Sequencer_runCommand ksh -c $cmd"
   }
}
