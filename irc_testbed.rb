require 'irc-socket'

irc = IRCSocket.new('irc.freenode.org', 7000, true)
irc.connect

if irc.connected?
  irc.nick 'Happybot'
  irc.user('Happybot', 0, "*", 'The probably most happy logger alive')

  while line = irc.read
    # Join channel after motd
    if line.split[1] == '376'
      irc.join '#hazewood'
    end

    puts "received: #{line}"
  end
end