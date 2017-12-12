proc Sequencer_getExpRootNodeInfo { exp_path } {
   set seqExec "nodeinfo"

   set cmd "export SEQ_EXP_HOME=$exp_path; ${seqExec} -f root | cut -d \"=\" -f2"
   set rootNode [exec -ignorestderr ksh -c ${cmd}]
   return ${rootNode}
}

proc Sequencer_runCommandWithWindow { exp_path datestamp parent_top command title position run_remote args } {
   global env
   regsub -all " " [file tail $command] _ tmpfile
   set id [clock seconds]
   set tmpdir $env(TMPDIR)
   set tmpfile "${tmpdir}/${tmpfile}_${id}"
   Sequencer_runCommand ${exp_path} ${datestamp} ${tmpfile} "${command} [join ${args}]" ${run_remote}
   TextEditor_createWindow "$title" ${tmpfile} ${position} ${parent_top}
   catch {[exec -ignorestderr rm -f ${tmpfile}]}
}

proc Sequencer_runSubmit { exp_path datestamp parent_top command title position run_remote  args {Id "null"} {list_item "null"}} {
   global env SUBMIT_POPUP POPUP_ACTIVATION_COUNTER 
  
   regsub -all " " [file tail $command] _ tmpfile
   switch ${Id} {
          null     {set id [clock seconds]}
          default  {set id ${Id}}
   }
   set id [clock seconds]
   set tmpdir $env(TMPDIR)
   set tmpfile "${tmpdir}/${tmpfile}_${id}"

   Sequencer_runCommand ${exp_path} ${datestamp} ${tmpfile} "${command} [join ${args}]" ${run_remote} ${list_item}
   ::log::log notice "${command} [join ${args}]"
   # Utils_logFileContent notice ${tmpfile}
   switch ${Id} {
        null      { if { ${SUBMIT_POPUP} != false} {
                     TextEditor_createWindow "$title" ${tmpfile} ${position} ${parent_top}
                     catch {[exec -ignorestderr rm -f ${tmpfile}]}
                    }
                }
        default { if { ${SUBMIT_POPUP} != false && ${list_item} == "true"} {
                    set POPUP_ACTIVATION_COUNTER(${tmpfile}) 0
                    Utils_Editor_Activation "$title" ${tmpfile} ${position} ${parent_top}
                  }
                }
   }
}
################################################################################
# Runs a command through a local shell or through a remote shell via an ssh
# pipe.
################################################################################
proc Sequencer_runCommand { exp_path datestamp out_file command run_remote {list_item "null"}} {
   global env LISTJOB_TO_SUB

   if { ${datestamp} != "" } {
      set prefix "export SEQ_DATE=${datestamp}"
   } else {
      set prefix ""
   }

   set remote_host [ SharedData_getMiscData REMOTE_HOST ]
   if { $remote_host != "" && ${run_remote} > 0 } {
      # Send command through ssh pipe
      set remote_user [ SharedData_getMiscData REMOTE_USER ]
      if { $remote_user != "" } {
         set remote_user "-l $remote_user"
      }

      # Get user home (local and remote)
      set remote_home [SharedData_getMiscData REMOTE_HOME ]
      set local_home [SharedData_getMiscData LOCAL_HOME ]

      # Take local experiment home, and substitute the substring $local_home for
      # the string $remote_home to get the remote exp home.
      set length [ expr [ string length $local_home ] - 1 ]
      set relative_exp_home [string replace $exp_path 0 $length ""]
      # Note that doing
      #    set remote_exp_home [string replace $exp_path 0 $length $remote_home]
      # is less robust because if local_home has a trailing slash and remote_home
      # doesn't, then there we would have an end result of
      # /users/dor/afsi/phcDocuments/Experiences/sample where there should be a
      # slash between "phc" and "Documents". This way:
      set remote_exp_home "${remote_home}/${relative_exp_home}"
      # we only run the risc of having two consecutive slashes which is OK for
      # the OS.
      set prefix "$prefix; export SEQ_EXP_HOME=${remote_exp_home}"

      # Add maestro shortcut to command
      set maestro_shortcut "$::env(SEQ_MAESTRO_SHORTCUT)"
      set prefix "${prefix}; export SEQ_MAESTRO_SHORTCUT=\\\"$maestro_shortcut\\\";$maestro_shortcut"

      # Put the command together with the prefix
      set cmd "${prefix}; echo \\\"### ${command}\\\"; $command"
    }  
    switch  ${list_item} {
        null    {  if { $remote_host != "" && ${run_remote} > 0} {
                   # Construct the remote command by echoing the command through an ssh pipe.
                   # set remote_cmd "echo \"${cmd}\" | ssh ${remote_host} ${remote_user} > ${out_file} 2>&1"
                   set remote_cmd "echo \"${cmd}" | ssh ${remote_host} ${remote_user} > ${out_file}"
                   puts "Running remote command $remote_cmd"
                   catch { eval [exec -ignorestderr ksh -c $remote_cmd] }
                   ::log::log debug "Sequencer_runCommand ksh -c $remote_cmd"
                 } else {
                   # Send command on local shell
                   set prefix "$prefix;export SEQ_EXP_HOME=${exp_path}"
                   # set cmd "${prefix}; echo \"### ${command}\" > ${out_file}; $command >> $out_file 2>&1"
                   set cmd "${prefix}; echo \"### ${command}\" > ${out_file}; $command >> $out_file"
                   catch { eval [exec -ignorestderr ksh -c $cmd]}
                   ::log::log debug "Sequencer_runCommand ksh -c $cmd"
                 }
               }    
       default { if { $remote_host != "" && ${run_remote} > 0} {
                   lappend LISTJOB_TO_SUB "`echo \"${cmd}\" | ssh ${remote_host} ${remote_user} >> ${out_file}`"
                   if {$list_item == "true"} {
                      catch { eval [exec -ignorestderr $env(SEQ_XFLOW_BIN)/submit_listcmd -l ${LISTJOB_TO_SUB} -o ${out_file} &]}
                      ::log::log debug "Sequencer_runCommand ksh -c $LISTJOB_TO_SUB"
                    }
                 } else {
                   # Send command on local shell
                   set prefix "$prefix;export SEQ_EXP_HOME=${exp_path}"
                   lappend LISTJOB_TO_SUB "`${prefix}; echo \"### ${command}\" >> ${out_file}; $command >> $out_file `"
                   if {$list_item == "true"} {
                      catch { eval [exec -ignorestderr $env(SEQ_XFLOW_BIN)/submit_listcmd -l ${LISTJOB_TO_SUB} -o ${out_file} &]}
                      ::log::log debug "Sequencer_runCommand ksh -c $LISTJOB_TO_SUB"
                   }
                 }
               }
    }
     
}

