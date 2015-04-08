require 'irc-socket'
require 'openssl'
require 'irc_parser'

irc = IRCSocket.new('kornbluth.freenode.net', 7000, true)
irc.connect
joined = false
message_mode = false

if irc.connected?
	irc.nick 'djfkadm'
	irc.user('djfkadm', 0, "*", 'ff')

	while line = irc.read
		# Join channel after motd
		if line.split[1] == '376'
			irc.join '#haselwurzel'
			joined = true
		end
		msg = IRCParser.parse_raw("#{line}\r\n")
		puts "received #{msg[1]} from #{msg[0]} on channel #{msg[2]} with the content #{msg[3]}"
	end
end