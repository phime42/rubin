require 'rubygems'
require 'bundler/setup'
require 'cinch'
require 'time'
require 'sequel'
require 'rbnacl/libsodium'
require 'sqlite3'
require 'digest'
require 'base64'
require 'socket'

$dbpath = "sqlite://test.db"

##
# manages the startup of all bots and clients
class Starter
  def initialize
    db = DatabaseBox.new
    db.output_all_clients.each do |x|
      if x[:type].eql? 'irc'
        puts "now listening to #{x[:channel]} on #{x[:host]}"
        RelayChat.new(x[:nick], x[:realname], x[:host], x[:channel])
      puts x[:host]
      elsif x[:type].eql? 'email'
        # do something pretty with email
      elsif x[:type].eql? 'xmpp'
        # do something pretty with xmpp
      end
    end
  end
end

##
# Plugin for cinch IRC bot, a framework which is used to provide IRC capabilities
class Logger
  include Cinch::Plugin

  listen_to :private,    :method => :register_private_message
  listen_to :disconnect, :method => :disco
  listen_to :channel,    :method => :register_public_message

  def initialize(*args)
    super
    @short_format = "%Y-%m-%d"
    @long_format = "%Y-%m-%d %H:%M:%S"
  end

  def disco(*)
    puts 'got disconnected'
  end

  # registers a public message on the channel
  def register_public_message(message)
    adapter = EncryptedAdapter.new
    adapter.write_encrypted_message(Time.new, message.channel.to_s, false, message.user.name, message.message, 'nil')
  end

  def register_private_message(message)
    adapter = EncryptedAdapter.new
    # puts message.server.methods
    adapter.write_encrypted_message(Time.new, "PM by #{message.user.name}", true, message.user.name, message.message, 'nil')  # todo: get the server url / channel for proper linking
    #puts "#{Time.new} #{message.user.name} whispers: #{message.message}"
  end

end

class RelayChat
  def initialize(nick, realname, server, channels)
    bot = Cinch::Bot.new do
    configure do |c|
      c.nick = nick
      c.realname = realname
      c.server = server
      c.channels = [channels]
      c.plugins.plugins = [Logger]
    end
    end
    bot.start

    def send_message(nick, recipient)
      # sends a private message to the desired nick
      # TODO: implement message sending
      message.reply('stw')
    end
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

  def testing_get_private_key_out_of_description(key_id)
    # long method name should make it perfectly clear: this is strictly for testing and UNSAFE!
    @keys_ds.where(:id=>key_id).to_a[0][:description]
  end

  def output_all_clients
    # reads the client table and outputs all clients as an array
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


  def write_message_to_database(timestamp, client, private, sender, message, attachment, key_id)
    # write the message from the client application to the database
    @messages_ds.insert(:time => timestamp, :client => client, :private => private, :sender => sender, :message => message, :attachment => attachment, :key_id =>key_id)
  end

  def read_messages_by_id(message_id, key_id)
    # searches for the message with id = message_id and key_id = key_id
    mo = @messages_ds.where(:id => message_id)#.where(:key_id => key_id)  # outputs an array of messages
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

  # Generates a new NaCl keypair
  # also sets the @public_key and @private_key instance variables
  # Due to the switch to RbNaCl a seperate handling of the messenge's nonce is no longer needed!
  def generate_keypair
    keypair = RbNaCl::PrivateKey.generate
    @private_key = keypair
    @public_key = keypair.private
    @public_key, @private_key
  end

  # Encrypts a given string with the given pubkey, signed with the host keypair
  def host_encrypt_string(string_to_encrypt, receiver_public_key)
    RbNaCl::SimpleBox.from_keypair(receiver_public_key, @private_key).encrypt(string_to_encrypt)
  end

  # Encrypts a given string with the given receiver public key and signs the message with a given private key
  def encrypt_string(string_to_encrypt, sender_private_key, receiver_public_key)
    RbNaCl::SimpleBox.from_keypair(receiver_public_key, sender_private_key).encrypt(string_to_encrypt)
  end

end