   ModEmu v0.7d: Master fork.
   I'm a silly hayes modem emulator!

   Requirements:
     bash 4.0 or newer! Associative arrays be here.
     slirp 1.0.17-7 or newer, preferably patched with atduck's fakeip patch
       (package for amd64 available as slirp 1.0.17-8~dm1 locally)
     cut
     awk
     sed
     curl & whois (optional)
     crc32 (debian package libarchive-zip-perl)
     fauxgetty (included)
     Bravery! This is very much an alpha.

  Usage: modemu.sh [OPTION...] [RATE]

  Valid options:
  -t: Force terminal mode. Run a shell as the current user. Dangerous!
      Please be aware of the security risks. If TERM is not set, will
      be set to vt100. Will not allow you to 'dial' as root.

  -T: Force Real Terminal mode. WARNING: Requires root and may be
      insecure. Runs 'fauxgetty' (a provided script) to provide a
      'nearly real' login terminal. If TERM is not set, will be set to
      vt100. Will not ratelimit, so make sure com0com or whatever
      you're using is set to 'emulate baud' for best experience.

  -p: Force SLiRP/PPP mode. The former default. Will not allow you to
      'dial' as root.

  -s: Slow mode. Wait 2/10ths of a second before replying, simulating
      the low speed of a serial-connected modem.

  -r: Ring mode. Ring 3 times with one second between each ring and
      then an additional 3 seconds to simulate a fast negotiation
      before connecting. Combine with slow mode for authenticity.

  -q: Quiet ring mode. Like ring mode but silent. Waits 6 seconds and
      then reports CONNECT. More accurately emulates earlier modems
      that only provide RING messages in an ATA situation.

  -b=[interface]: Report the address of this interface as the host
                  address to slirp. By default, we scan eth0.

  -c: Turn off country detection for ATI15. Falls over to US.

  -l: Logging mode, log all input and output to ~/.modemu/log

  -h/-?/--help: Print this help message.

  Defaults are 19200 baud, fast mode, no ring, and eth0 interface.
  By default, the number dialed determines the mode. If it begins with
  1, ppp mode it used. If it begins with 2, terminal mode is used. If
  it begins with 3, Real Terminal mode is used. If for some reason your
  dialer can't deal with numbers in these formats, that's what the
  force modes are for.


  TODOs:

  1:Definable negotation time for -q and -r (see TODO note later in script)

  2:Patch to slirp to recognize +++(1 sec pause) as equivalent to
  0(pause)0(pause)0(pause)0(pause)0(pause) for clean hangups. Currently you'll
  have to kill slirp after the PPP session terminates on the client side to get
  proper hangup behavior.

  3:Turn -t into a proper login prompt, possibly just by calling login, though
  due to the ill-defined nature of the "terminal" provided by socat, I'm
  worried that won't work. Maybe one of the various versions of getty would
  though?
  ^ Partially handled through -T but this requires this script to be called
  from root, which may be a security risk.

  4:Is ATI19 safe to use for a shut off command? Pretty sure nothing queries
  that high for diagnostics...

  5:Maybe, MAYBE provide an option that will aplay some provided ringing and
  canned negotiation noise samples to make things even more authentic? :P
