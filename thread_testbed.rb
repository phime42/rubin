require 'thread'
require 'irc-socket'
require 'irc_parser'
require 'openssl'
require_relative 'classes.rb'


class TestingRelayChat
  def initialize(server, port, channel, nick)
    @server = server
    @port = port
    @channel = channel
    @nick = nick

  end

  # connects to the given irc channel
    irc = IRCSocket.new(@server, @port, true)
    puts 'connecting'
    irc.connect

    if irc.connected?
      irc.nick @nick
      irc.user(@nick, 0, "*", @nick)
      puts 'connected'
      # start thread before teh reading lock begins
      Thread.new {
        puts 'foo'
        sleep 1
      }.join
    end


      while line = irc.read
        if line.split[1] == '376'
          irc.join @channel
        end

        msg = IRCParser.parse_raw("#{line}\r\n")
        if msg[1].eql? 'JOIN'
          # connected to channel
          puts "joined channel #{@channel}@#{@server}"
        elsif msg[1].eql? 'PRIVMSG'
          sender_nick = msg[0].split('!~')[0]  # strips off client and IP
          receiving_channel = msg[2][0]
          message = msg[2][1]

          # adapter = EncryptedAdapter.new
          if receiving_channel.eql? @nick
            # received private message
            # adapter.write_encrypted_message(Time.new, "irc@#{@server}", true, sender_nick, message, 'nil')
          else
            # adapter.write_encrypted_message(Time.new, "irc@#{@server}", false, sender_nick, message, 'nil')
          end
        end
      end
end



TestingRelayChat.new('kornbluth.freenode.net', 7000, '#haselholz', 'sdgfaddqeu').connect