require 'irc-socket'
require 'openssl'
require 'irc_parser'
require 'thread'

server = 'kornbluth.freenode.net'
port = 7000
nick = 'muhasdjf'

def receiver
  puts 'started receiver'
  while line = irc.read
    # Join channel after motd
    if line.split[1] == '376'
      irc.join '#haselwurzel'
      joined = true
    end
    msg = IRCParser.parse_raw("#{line}\r\n")
    if msg[1].eql? 'JOIN'
      # connected to channel
      puts 'joined!'
    elsif msg[1].eql? 'PRIVMSG'
      # got message
      # puts "received message from #{msg[0]} on #{msg[2][0]} with the content #{msg[2][1]}"
      puts "sender nick: #{msg[0]}"
      sender_nick = msg[0].split('!~')[0]
      receiving_channel = msg[2][0]
      message = msg[2][1]

      if receiving_channel.eql? nick
        puts "received private message on #{server} from #{sender_nick}: #{message}"
      else
        puts "#{sender_nick} wrote on #{receiving_channel}: #{message}"
      end
    end
  end
end

def sender
  # i'm sending sth
  puts 'sending'
end
puts 'before connecting'
irc = IRCSocket.new(server, port, true)
irc.connect
puts 'connected'
joined = false
message_mode = false

if irc.connected?
  puts 'hl3 confirmed'
	irc.nick nick
	irc.user(nick, 0, "*", 'ff')

  receiving = Thread.new do
    loop do
      puts 'im a receiver'
    end
  end

  # sending = Thread.new{sender()}

end