# this is essentially a wrapper class around the tcl clock functionality
# It allows manipulation of clock values by adding a delta value to
# the values returned by the following tcl clock commands:
# "seconds", "milliseconds", "microseconds"
# How to use from client:
#
# source ClockWrapper.tcl
# package require ClockWrapper
# the alias will transfer all clock commands to the ClockWrapper
# interp alias {} ::clock {} ::ClockWrapper
# ::ClockWrapper::setDelta "7 hour"
# ::ClockWrapper::setDelta "-5 hour"
# ::ClockWrapper::setDelta "0 second"
#
package provide ClockWrapper 1.0
namespace eval ::ClockWrapper {
   namespace ensemble create
   namespace export add clicks format microseconds milliseconds scan seconds

   variable deltaTime "0 seconds"

proc ::ClockWrapper::add { args } {
   return [eval ::tcl::clock::add ${args}]
}

proc ::ClockWrapper::clicks { args } {
   return [eval ::tcl::clock::clicks ${args}]
}

proc ::ClockWrapper::microseconds {} {
   variable deltaTime
   set clockNow [eval ::tcl::clock::microseconds]
   return [eval ::tcl::clock::add ${clockNow} ${deltaTime}]
}

proc ::ClockWrapper::milliseconds {} {
   variable deltaTime
   set clockNow [eval ::tcl::clock::milliseconds]
   return [eval ::tcl::clock::add ${clockNow} ${deltaTime}]
}

proc ::ClockWrapper::seconds {} {
   variable deltaTime
   # puts "::ClockWrapper::seconds"
   set clockNow [eval ::tcl::clock::seconds]
   return [eval ::tcl::clock::add ${clockNow} ${deltaTime}]
}

proc ::ClockWrapper::scan { args } {
   return [eval ::tcl::clock::scan ${args}]
}

proc ::ClockWrapper::format { args } {
   return [eval ::tcl::clock::format ${args}]
}

proc ::ClockWrapper::setDelta { delta } {
   variable deltaTime
   set deltaTime ${delta}
}

proc ::ClockWrapper::getDelta {} {
   variable deltaTime
   return ${deltaTime}
}

}
