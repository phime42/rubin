require 'rubygems'
require 'bundler/setup'
require 'time'
require 'sequel'
require 'json'
require 'rbnacl/libsodium'
require 'sqlite3'
require 'digest'
require 'base64'
require 'socket'
require 'irc-socket'
require 'irc_parser'
require 'thread'


$dbpath = "sqlite://test.db"


##
# manages the startup of all bots and clients
class Starter
  def initialize  # note: for each plugin call (network-plugin, irc-plugin...: start a new thread!)
    services_to_start = []
    db = DatabaseBox.new
    db.output_all_clients.each do |x|
      if x[:type].eql? 'irc'
        irc_queue = Queue.new
        services_to_start << Thread.new {
          puts "connecting to #{x[:channel]} on #{x[:host]}..."
          host = x[:host].split(':')[1].split('//')[1]  # http://irc.freenode.org:7000 --> irc.freenode.org
          port = x[:host].split(':')[2]
          channel = x[:channel]
          nick = x[:nick]
          RelayChat.new(host, port, channel, nick).connect
        }
      elsif x[:type].eql? 'email'
        # do something pretty with email
      elsif x[:type].eql? 'xmpp'
        # do something pretty with xmpp
      end
    end
    services_to_start.each{ |t| t.join }
  end
end


##
# This module opens an IRC connection and saves all the raw irc data to the database
class RelayChat
  def initialize(server, port, channel, nick)
    @server = server
    @port = port
    @channel = channel
    @nick = nick
  end

  # connects to the given irc channel
  def connect
    irc = IRCSocket.new(@server, @port, true)
    irc.connect

    if irc.connected?
      irc.nick @nick
      irc.user(@nick, 0, "*", @nick)

      sending = Thread.new {
        # this thread waits for a message sent by the user and sends it to the irc channel of this instance
        }

      receiving = Thread.new {
        # this thread reads messages from this instance's irc and writes them to the database
        while line = irc.read
          if line.split[1] == '376'
            irc.join @channel
          end
          # puts line  # reactivate if a detailed unfiltered output of the irc server messages is desired
          msg = IRCParser.parse_raw("#{line}\r\n")
          if msg[1].eql? 'JOIN'
            # connected to channel
            puts "joined channel #{@channel}@#{@server}"
          elsif msg[1].eql? 'PRIVMSG'
            sender_nick = msg[0].split('!~')[0]  # strips off client and IP
            receiving_channel = msg[2][0]
            message = msg[2][1]

            adapter = EncryptedAdapter.new
            if receiving_channel.eql? @nick
              # received private message
              adapter.write_encrypted_message(Time.new, "#{@channel.split('#')[1]}@#{@server}", true, sender_nick, message, 'nil')
            else
              adapter.write_encrypted_message(Time.new, "#{@channel.split('#')[1]}@#{@server}", false, sender_nick, message, 'nil')
            end
          end
        end
      }

      [sending, receiving].each{ |t| t.join }

    end
  end

  def send_to_channel(message)
  end

  def send_to_user(user, message)
  end

end

class DatabaseBox  # OPTIMIZE: rewrite this class to be more ordered and suitable for general use
  attr_reader :messages_ds, :keys_ds # make dataset readable
  def initialize
    # check if database was used before, otherwise generate what we need
    @DB
    @messages_ds
    @keys_ds
    @clients_ds

    setup_message_database
    setup_key_database
    setup_client_database

    @DB = Sequel.connect($dbpath)
    @messages_ds = @DB[:messages]  # create dataset for messages
    @keys_ds = @DB[:keys]  # create dataset for keys
    @clients_ds = @DB[:clients]
  end

  # reads the client table and outputs all clients as an array
  def output_all_clients
    client_array = []
    @clients_ds.to_a.each do |element|
      client_array << element
    end
    client_array
  end

  def register_new_client(description, host, type, nick, realname, channel)
    if @clients_ds.where(:host=>host).where(:channel=>channel).to_a.length.eql? 0  # do not load configuration if a config with same channel and same server already exists
      @clients_ds.insert(:description=>description, :host=>host, :type=>type, :nick=>nick, :realname=>realname, :channel=>channel)
    end
  end

  # write the message from the client application to the database
  def write_message_to_database(timestamp, client, private, sender, message, attachment, key_id)
    @messages_ds.insert(:time => timestamp, :client => client, :private => private, :sender => sender, :message => message, :attachment => attachment, :key_id =>key_id)
  end

  # searches for the message with id = message_id and key_id = key_id
  def output_message_by_id(message_id, key_id)
    message = @messages_ds.where(:id => message_id).to_a[0]  # outputs a message
    database_key_id = message[:key_id]
    if database_key_id.eql?(key_id.to_i)
      message
    else
      nil
    end
  end

  def output_all_message_ids_by_key_id(key_id)
    # outputs all key-ids available for the given key_id
    # lets the client decide which messages he wants to download and saves time and resources
    # todo: implement ranges ("the last 1000 messages that are for me etc")
    message_id_output_array = []
    @messages_ds.where(:key_id => key_id).to_a.each do |element|
      message_id_output_array << element[:id]
    end
    message_id_output_array
  end

  def output_new_message_ids(key_id, message_id)
    # outputs an array of every message id bigger than the given message_id
    message_id_output_array = []
    @messages_ds.where(:key_id => key_id).to_a.each do |element|
      if (element[:id] > message_id)  # todo: substitute with direct sequel query
        message_id_output_array << element[:id]
      end
    end
    message_id_output_array
  end

  def output_message_by_days(key_id, days)
    # queries the database for a certain range of days since today
  end

  def register_key (description, host, private_key, public_key)
    @keys_ds.insert(:description => description, :host => host, :private_key => private_key, :public_key => public_key, :revoked => false)
  end

  def revoke_key(public_key, key_id)
    if !public_key.nil?
      @keys_ds.where(:public_key=>Base64.encode64(public_key)).update(:revoked=>true)
    end
    if !key_id.nil?
      @keys_ds.where(:id => key_id).update(:revoked=>true)
    end
  end

  def output_host_keypair
    found_keypairs = @keys_ds.exclude(:private_key=>nil).exclude(:revoked=>true).to_a
    if found_keypairs.length < 1
      # no keypair found. have to generate one
      # todo: generate keypair
      # crypto = CryptoBox.new  # todo: put host key generation somewhere else where it makes sense and is executed not just by accident
      [nil, nil]
    elsif found_keypairs.length == 1
      # exactly one keypair found. returning it
      [Base64.decode64(found_keypairs[0][:public_key]), Base64.decode64(found_keypairs[0][:private_key])]
    elsif found_keypairs.length > 1
      # there's more than one valid hostkey in the database. something went terribly wrong
      # todo: think about handling it; maybe delete every host key present
      # todo: implement helpful logging
      puts 'there is more then one valid host key present, database corrupt. data breach?'
    end
  end

  def output_host_public_key
    public_key, private_key = self.output_host_keypair
    public_key
  end

  def output_all_keys
    pubkey_array = []
    found_keys = @keys_ds.where(:revoked=>false).where(:private_key=>nil).to_a
    found_keys.each do |element|
      pubkey_array << [Base64.decode64(element[:public_key]), element[:id]]
    end
    pubkey_array
  end

  def check_for_revocation(key_id)
    # takes a key_id and looks it up in the keystore database table. Returns true if revoked, false if not revoked
    key_hash = @keys_ds.where(:id=>key_id).to_a
    key_hash[0][:revoked]
  end

  private

  def hash_key(public_key)
    Base64.encode64(Digest::SHA256.digest public_key)
  end

  def setup_message_database
    @DB = Sequel.sqlite
    @DB = Sequel.connect($dbpath)
    @DB.create_table? :messages do
      primary_key :id  # wtf
      Datetime :time  # time when the message was received
      String :client  # client (IRC XYZ)
      TrueClass :private  # true if the message is private (for IRC, e.g.)
      String :sender  # client specific sender of the message
      String :message  # message; only to use if it's clear that it's just a string!
      File :attachment  # to save images and complete emails
      Integer :key_id  # references to the id of the key database for public_key
    end
    @messages_ds = @DB[:message]  # dataset creation
    @DB.disconnect
  end

  def setup_client_database
    # the client database holds information about the various information sources (read: clients) that the
    # server should be take into account
    @DB = Sequel.sqlite
    @DB = Sequel.connect($dbpath)
    @DB.create_table? :clients do
      primary_key :id  # id
      String :description  # description of client
      String :host  # contains url / whatever of the host
      String :type  # contains desired type of connection (only 'irc' is supported by now!)
      String :nick  # irc only
      String :realname  # irc only
      String :channel  # maybe someday multiple channels; one for now. irc only
    end
  end

  # sets up the key database table
  def setup_key_database
    @DB = Sequel.sqlite
    @DB = Sequel.connect($dbpath)
    @DB.create_table? :keys do
      primary_key :id  # id
      String :description  # description of the respective key
      String :host  # contains url / whatever of the host
      String :private_key  # only contains a value if it's a local private key, otherwise nil
      String :public_key  # contains public key of respectiv host
      TrueClass :revoked  # false if the key is revoked
    end
  end
end

class EncryptedAdapter
  def initialize
    # no initialization needed so far
  end

  def write_encrypted_message(timestamp, client, private_bool, sender, message, attachment)
    # a drop-in encryption-enabling wrapper for DatabaseBox
    # encrypts every message's sender, message and attachments with every single pubkey in the key database
    database = DatabaseBox.new
    crypto = CryptoBox.new
    database.output_all_keys.each do |public_key|  # todo: not capable of multiple clients; ATM every message is encrypted for every pubkey known to the database
      enc_sender = Base64.encode64(crypto.host_encrypt_string(sender, public_key[0]))
      enc_message = Base64.encode64(crypto.host_encrypt_string(message, public_key[0]))
      enc_attachment = Base64.encode64(crypto.host_encrypt_string(attachment, public_key[0]))
      database.write_message_to_database(timestamp, client, private_bool, enc_sender, enc_message, enc_attachment, public_key[1])
    end
  end

end

##
# The class CryptoBox poses as a generic adapter for cryptographic services. It uses the NaCl library by djb as backend.
# Ruby binding is provided by RbNaCl by Tony Arcieri

class CryptoBox
  def initialize
    database = DatabaseBox.new
    pub, priv = database.output_host_keypair
    if pub == nil and priv == nil
      # apparently, there is no host keypair available, so a new one has to be generated, but not without snitching
      puts 'No host keypair available, have to generate a new one! Possible temper alert!'
      new_pub, new_priv = generate_keypair
      database.register_key('host', '127.0.0.1', Base64.encode64(new_priv), Base64.encode64(new_pub))
    else
      @public_key = pub
      @private_key = priv
    end
  end

  # Generates a keypair in order to receive messages. For testing only.
  def testing_generate_receiving_keypair
    db = DatabaseBox.new
    pub, priv = generate_a_keypair
    db.register_key('example description', 'horst', nil, Base64.encode64(pub))
  end

  # Generates a new NaCl keypair
  # also sets the @public_key and @private_key instance variables
  # Due to the switch to RbNaCl a seperate handling of the messenge's nonce is no longer needed!
  def generate_keypair
    keypair = RbNaCl::PrivateKey.generate
    @private_key = keypair
    @public_key = keypair.public_key
    return @public_key, @private_key
  end

  # Generates a new NaCl keypair, but does not touch instance variables.
  def generate_a_keypair
    keypair = RbNaCl::PrivateKey.generate
    private_key = keypair
    public_key = keypair.public_key
    return public_key, private_key
  end

  # Encrypts a given string with the given pubkey, signed with the host keypair
  def host_encrypt_string(string_to_encrypt, receiver_public_key)
    RbNaCl::SimpleBox.from_keypair(receiver_public_key, @private_key).encrypt(string_to_encrypt)
  end

  # Encrypts a given string with the given receiver public key and signs the message with a given private key
  def encrypt_string(string_to_encrypt, sender_private_key, receiver_public_key)
    RbNaCl::SimpleBox.from_keypair(receiver_public_key, sender_private_key).encrypt(string_to_encrypt)
  end

  # Decrypts a given string with the given receiver private key and
  # checks the signature of the message with a given public key

  def decrypt_string(string_to_decrypt, receiver_private_key, sender_public_key)
    RbNaCl::SimpleBox.from_keypair(sender_public_key, receiver_private_key).decrypt(string_to_decrypt)
  end

end



# db = DatabaseBox.new
# puts db.output_messages_by_id(10,3)