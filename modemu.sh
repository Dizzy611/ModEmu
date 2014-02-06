#!/bin/bash
# DO NOT CHANGE THE ABOVE! This will not run in sh or dash or whatever your
# preferred shell is, this is very VERY bash specific code.
#
# ModEmu v0.7d: Master fork.
# I'm a silly hayes modem emulator!
# Requirements:
#    bash 4.0 or newer! Associative arrays be here.
#    slirp 1.0.17-7 or newer, preferably patched with atduck's fakeip patch
#    (package for amd64 available as slirp 1.0.17-8~dm1 locally)
#    cut
#    awk
#    sed
#    curl & whois (optional)
#    crc32 (debian package libarchive-zip-perl)
#    fauxgetty (included)
#    Bravery! This is very much an alpha.
#

#
# TODOs:
#
# 1:Definable negotation time for -q and -r (see TODO note later in script)
#
# 2:Patch to slirp to recognize +++(1 sec pause) as equivalent to
# 0(pause)0(pause)0(pause)0(pause)0(pause) for clean hangups. Currently you'll
# have to kill slirp after the PPP session terminates on the client side to get
# proper hangup behavior.
#
# 3:Turn -t into a proper login prompt, possibly just by calling login, though
# due to the ill-defined nature of the "terminal" provided by socat, I'm
# worried that won't work. Maybe one of the various versions of getty would
# though?
# ^ Partially handled through -T but this requires this script to be called
# from root, which may be a security risk.
#
# 4:Is ATI19 safe to use for a shut off command? Pretty sure nothing queries
# that high for diagnostics...
#
# 5:Maybe, MAYBE provide an option that will aplay some provided ringing and
# canned negotiation noise samples to make things even more authentic? :P
#

#
# Declarations and defaults.
#
declare -A options
rate=19200
interface=eth0
echo_mode=0

# These probably aren't necessary, but safety first.
options[t]=0
options[s]=0
options[r]=0
options[b]=0
options[q]=0
options[T]=0

# Turn this on to echo the result every time an option is checked.
OPTION_DEBUG=0

# Turn this on to use a line feed as well as a CR with each result code. Some things like this, others don't. Useful for cleaner interactive debugging.
LINE_FEED=1

# Script variables, mostly for ATInn usage.
version=0.7d
prcode=M07
script=$(readlink -f $0)
crc=`crc32 $script`
# These variables are currently unused, but getting in the habit of marking modem state is not a bad thing. mode C is command mode, mode D is data mode.
offhook=0
mode=C
mkdir -p ~/.modemu

function command_exists {
    type "$1" &> /dev/null ;
}
function check_option {
    if [[ $OPTION_DEBUG == 1 ]]
    then
      echo "Checking option -$1: ${options[$1]}"
    fi
    retval=${options[$1]}

    #Silly return values and their being the opposite of the way booleans work
    #elsewhere.
    if [[ $retval == 1 ]]
    then
      return 0
    else
      return 1
    fi
}

function slow_mode {
    if check_option s
    then
      sleep 0.2
    fi
}

function mecho {
    slow_mode
    if check_option l
    then
      echo "$@" >> ~/.modemu/log
    fi
    echo -n -e "$@\r"
    if [[ $LINE_FEED == 1 ]]
    then
      echo
    fi
}
function script_help {
    # This took way too long to write :P But it's pretty!
    echo
    echo "  modemu.sh v0.2                                                       "
    echo "  Hayes Semicompatible Modem Emulator                                  "
    echo "                                                                       "
    echo "  Usage: modemu.sh [OPTION...] [RATE]                                  "
    echo "                                                                       "
    echo "  Valid options:                                                       "
    echo "  -t: Force terminal mode. Run a shell as the current user. Dangerous! "
    echo "      Please be aware of the security risks. If TERM is not set, will  "
    echo "      be set to vt100. Will not allow you to 'dial' as root.           "
    echo "                                                                       "
    echo "  -T: Force Real Terminal mode. WARNING: Requires root and may be      "
    echo "      insecure. Runs 'fauxgetty' (a provided script) to provide a      "
    echo "      'nearly real' login terminal. If TERM is not set, will be set to "
    echo "      vt100. Will not ratelimit, so make sure com0com or whatever      "
    echo "      you're using is set to 'emulate baud' for best experience.       "
    echo "                                                                       "
    echo "  -p: Force SLiRP/PPP mode. The former default. Will not allow you to  "
    echo "      'dial' as root.                                                  "
    echo "                                                                       "
    echo "  -s: Slow mode. Wait 2/10ths of a second before replying, simulating  "
    echo "      the low speed of a serial-connected modem.                       "
    echo "                                                                       "
    echo "  -r: Ring mode. Ring 3 times with one second between each ring and    "
    echo "      then an additional 3 seconds to simulate a fast negotiation      "
    echo "      before connecting. Combine with slow mode for authenticity.      "
    echo "                                                                       "
    echo "  -q: Quiet ring mode. Like ring mode but silent. Waits 6 seconds and  "
    echo "      then reports CONNECT. More accurately emulates earlier modems    "
    echo "      that only provide RING messages in an ATA situation.             "
    echo "                                                                       "
    echo "  -b=[interface]: Report the address of this interface as the host     "
    echo "                  address to slirp. By default, we scan eth0.          "
    echo "                                                                       "
    echo "  -c: Turn off country detection for ATI15. Falls over to US.          "
    echo "                                                                       "
    echo "  -l: Logging mode, log all input and output to ~/.modemu/log          "
    echo "                                                                       "
    echo "  -h/-?/--help: Print this help message.                               "
    echo "                                                                       "
    echo "  Defaults are 19200 baud, fast mode, no ring, and eth0 interface.     "
    echo "  By default, the number dialed determines the mode. If it begins with "
    echo "  1, ppp mode it used. If it begins with 2, terminal mode is used. If  "
    echo "  it begins with 3, Real Terminal mode is used. If for some reason your"
    echo "  dialer can't deal with numbers in these formats, that's what the     "
    echo "  force modes are for.                                                 "
    echo
}

function real_term {
  if [ -z "$TERM" ]
  then
    export TERM="vt100"
  fi
  if [ "$(id -u)" != "0" ]
  then
    mecho "ERROR: Real Terminal mode requires root!"
    mode=C
    mecho "NO CARRIER"
  else
    mecho "Please exit terminal before hanging up. Login/bash will not handle +++"
    BAUD=$rate fauxgetty
    mode=C
    mecho "NO CARRIER"
  fi
}

function simple_term {
  if [ -z "$TERM" ]
  then
    export TERM="vt100"
  fi
  if [ "$(id -u)" == "0" ]
  then
    mecho "ERROR: Not permitting you to run a simple shell as root!"
    mode=C
    mecho "NO CARRIER"
  else
    mecho "Please exit bash before hanging up! Bash will not handle +++"
    bash
    mode=C
    mecho "NO CARRIER"
  fi
}
function slirp_cslip {
  if [ "$(id -u)" == "0" ]
  then
    mecho "ERROR: Not permitting you to run slirp as root. See man slirp."
    mode=C
    mecho "NO CARRIER"
  else
    interface_ip=`/sbin/ifconfig $interface | grep 'inet addr:' | cut -d: -f2 | awk '{ print $1}'`
    if [ -z "$interface_ip" ]
    then
      mecho "WARN: Interface IP not found. Defaulting to localhost."
      interface_ip=127.0.0.1 # You generally do not want this! You
                                # shouldn't be running slirp if you don't
                                # have a network connected.
    fi
    slirp compress "baudrate $rate" "host addr $interface_ip"
    mode=C
    mecho "NO CARRIER"
  fi
}
function slirp_slip {
  if [ "$(id -u)" == "0" ]
  then
    mecho "ERROR: Not permitting you to run slirp as root. See man slirp."
    mode=C
    mecho "NO CARRIER"
  else
    interface_ip=`/sbin/ifconfig $interface | grep 'inet addr:' | cut -d: -f2 | awk '{ print $1}'`
    if [ -z "$interface_ip" ]
    then
      mecho "WARN: Interface IP not found. Defaulting to localhost."
      interface_ip=127.0.0.1 # You generally do not want this! You
                                # shouldn't be running slirp if you don't
                                # have a network connected.
    fi
    slirp nocompress "baudrate $rate" "host addr $interface_ip"
    mode=C
    mecho "NO CARRIER"
  fi
}
function slirp_ppp {
  if [ "$(id -u)" == "0" ]
  then
    mecho "ERROR: Not permitting you to run slirp as root. See man slirp."
    mode=C
    mecho "NO CARRIER"
  else
    interface_ip=`/sbin/ifconfig $interface | grep 'inet addr:' | cut -d: -f2 | awk '{ print $1}'`
    if [ -z "$interface_ip" ]
    then
      mecho "WARN: Interface IP not found. Defaulting to localhost."
      interface_ip=127.0.0.1 # You generally do not want this! You
                               # shouldn't be running slirp if you don't
                               # have a network connected.
    fi
    slirp ppp "baudrate $rate" "host addr $interface_ip"
    mode=C
    mecho "NO CARRIER"
  fi
}

function ATI { # FIXME: Most of these are guesswork based on very vague descriptions! Also, 19 is nonstandard.
    case "$1" in
    "0") # Product code, 3 characters on Hayes, 4 digits on USR, string model and speed on GSM... We're going with Hayes here.
       mecho $prcode
       ;;
    "1" | "12") # 1 is ROM Checksum, or "Predefined checksum", depending who you ask, 12 is more definitely ROM checksum.
       mecho $crc
       ;;
    "2" | "3" | "5" | "6" | "7" | "8" | "9" | "10" | "11") # FIXME: Undefined??? Reserve for future use???
       mecho "OK"
       ;;
    "4") # OEM String
       mecho "ModEmu v$version, copyright (c)2014 Dylan J Morrison, all rights reserved. Licensed under the ISC license."
       ;;
    "13") # FIXME: RC Version Number??? Assuming ROM version?
       mecho "v$version"
       ;;
    "14") # Firmware version. So, same as above???
       mecho "v$version"
       ;;
    "15") # Country. Oh boy. Don't want to add more dependencies, so making this optional and default to US.
       if command_exists curl
       then
         if command_exists whois
         then
           if ! check_option c
           then
             mecho `whois $(curl -s ifconfig.me) | awk 'tolower($1) ~ /^country:/ { print $2 }'`
           else
             mecho "US"
           fi
         else
           mecho "US"
         fi
       else
         mecho "US"
       fi
       ;;
    "16" | "17" | "18") # GSM related stuff.
       mecho "ERROR"
       ;;
    "19") # Our little hack, because well, we need a way to turn it off, and we don't exactly have a power switch.
       mecho "ModEmu is turning off..."
       mecho "OK"
       exit 0
       ;;
    esac
}

# generic option parser. Sets flags based on - variables, passes
# anything that doesn't have a dash to the baudrate as long as it's
# a number, otherwise prints help and quits.
for var in "$@"
do
  if [[ "$var" == '-h' ]] || [[ "$var" == '--help' ]] || [[ "$var" == '-?' ]]
  then
    script_help
    exit 0
  fi
  if [[ $var == -b* ]]
  then
    interface=`echo $var | cut -b 4-`
    options[b]=1
  elif [[ $var == -* ]]
  then
    option=`echo $var | cut -b 2-`
    options[$option]=1
  else
    re='^[0-9]+$'
    if ! [[ $var =~ $re ]]
    then
      echo "ERROR: Expected baud rate but didn't get numbers. Do you know what "
      echo "       you're doing? Printing help and quitting.                   "
      script_help
      exit 1
    else
      rate=$var
    fi
  fi
done

while true
do
  if [[ $echo_mode == 1 ]]
  then
    read atcommand
  else
    read -s atcommand
  fi
  if check_option l
  then
    echo $atcommand >> ~/.modemu/log
  fi
  if [[ $atcommand == \+\+\+* ]] # We're a TIES modem, because read can't do delay checking.
  then
    mode=C
    atcommand=`echo $atcommand | cut -b 4-`
  fi
  if [[ $atcommand == ATD* ]]
  then
    type=`echo $atcommand | cut -b 4`
    echo $type
    if [[ "$type" == "P" || "$type" == "T" ]]
    then
      if check_option r
      then
        sleep 1
        mecho "RING"
        sleep 1
        mecho "RING"
        sleep 1
        mecho "RING"
        # TODO: Provide an option to define negotiation time that works with
        #       both -r and -q. Use it here.
        sleep 3 #negotiation time (bee bee bee boo boo boo bee-beep!)
      elif check_option q
      then
        sleep 3 #ring time
        # TODO: See above.
        sleep 3 #negotiation time
      fi
      mecho "CONNECT $rate"
      mode=D
      if check_option t
      then
        simple_term
      elif check_option T
      then
        real_term
      elif check_option p
      then
        slirp_ppp
      else
        number=`echo $atcommand | cut -b 5`
        if [[ $number == 1 ]]
        then
          slirp_ppp
        elif [[ $number == 2 ]]
        then
          simple_term
        elif [[ $number == 3 ]]
        then
          real_term
        else
          mode=C
          mecho "NO CARRIER"
        fi
      fi
    else
      mecho "ERROR"
    fi
  elif [[ $atcommand == ATI* ]]
  then
    ATI `echo $atcommand | cut -b 4-`
  elif [[ $atcommand == ATE* ]]
  then
    echo_mode=`echo $atcommand | cut -b 4-`
    mecho "OK"
  elif [[ $atcommand == ATH0 ]]
  then
    offhook=0
    mecho "NO CARRIER"
  elif [[ $atcommand == ATH1 ]]
  then
    offhook=1
    mecho "OK"
  elif [[ $atcommand == ATH2 ]]
  then
    offhook=2
    mecho "OK"
  else
      mecho "OK"
  fi
done
