require 'rubygems'
require 'bundler/setup'
require 'cinch'
require 'time'
require 'sequel'
require 'nacl'
require 'securerandom'
require 'sqlite3'
require 'digest'
require 'base64'

$dbpath = "sqlite://test.db"

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
    puts 'virtual message'

  end
  end
end

class DatabaseBox  # todo: rewrite DatabaseBox to be a more generic accessor for databases
  attr_reader :messages_ds  # make dataset readable
  def initialize
    # check if database was used before, otherwise generate what we need
    @DB
    @messages_ds
    @keys_ds

    #if !File.exist?(File.basename($dbpath))
      setup_message_database
      setup_key_database
    #end

    @DB = Sequel.connect($dbpath)
    @messages_ds = @DB[:messages]  # create dataset for messages
    @keys_ds = @DB[:keys]  # create dataset for keys
  end

  def write_message_to_database(timestamp, client, private, sender, message, attachment, nonce, key_id)
    # write the message from the client application to the database
    @messages_ds.insert(:time => timestamp, :client => client, :private => private, :sender => sender, :message => message, :attachment => attachment, :nonce => nonce, :key_id =>key_id)
  end

  def read_messages_by_id(message_id, key_id)
    # searches for the message with id = message_id and key_id = key_id
    @messages_ds.where(:id=>message_id).where(:key_id => key_id)  # outputs an array of messages
  end

  def register_key (description, host, private_key, public_key)
    @keys_ds.insert(:description => description, :host => host, :private_key => private_key, :public_key => public_key, :revoked => false)
  end

  def revoke_key(public_key)
    @keys_ds.where(:public_key=>Base64.encode64(public_key)).update(:revoked=>true)
    puts @keys_ds.where(:public_key=>public_key).to_a
  end

  def output_host_keypair
    found_keypairs = @keys_ds.exclude(:private_key=>nil).exclude(:revoked=>true).to_a
    if found_keypairs.length < 1
      # no keypair found. have to generate one
      # todo: generate keypair
      # crypto = CryptoBox.new  # todo: put host key generation somewhere else where it makes sense and is executed not just by accident
      # public_key, private_key = crypto.generate_keypair
      # register_key('host', '127.0.0.1', private_key, public_key)
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
      String :client  # client (hazewood_irc, juforum_xmpp...)
      TrueClass :private  # true if the message is private (for IRC, e.g.)
      String :sender  # client specific sender of the message
      String :message  # message; only to use if it's clear that it's just a string!
      File :attachment  # to save images and complete emails
      String :nonce  # place to save the nonce used for authenticated encryption
      Integer :key_id  # references to the id of the key database for public_key
    end
    @messages_ds = @DB[:message]  # dataset creation
    @DB.disconnect
  end

  def setup_key_database
    # sets up the key table and the nonce database
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

class EncryptedAdapter
  def initialize

  end

  def write_encrypted_message(timestamp, client, private_bool, sender, message, attachment)
    # a drop-in encryption-enabling wrapper for DatabaseBox
    # encrypts every message's sender, message and attachments with every single pubkey in the key database
    database = DatabaseBox.new
    crypto = CryptoBox.new
    database.output_all_keys.each do |public_key|
      nonce = crypto.generate_nonce
      enc_sender = Base64.encode64(crypto.encrypt_sting(sender, public_key[0], nonce))
      enc_message = Base64.encode64(crypto.encrypt_sting(message, public_key[0], nonce))
      enc_attachment = Base64.encode64(crypto.encrypt_sting(attachment, public_key[0], nonce))
      database.write_message_to_database(timestamp, client, private_bool, enc_sender, enc_message, enc_attachment, Base64.encode64(nonce), public_key[1])
      # @messages_ds.insert(:time => timestamp, :client => client, :private => private_bool, :sender => enc_sender, :message => enc_message, :attachment => enc_attachment, :nonce => Base64.encode64(nonce), :key_id => public_key[1]) 
    end
  end

  def read_encrypted_message_by_id(message_id, key_id)
    # no use case for server application since the server has no need to decrypt messages, but may be
    # useful for client applications; server host key is just for signing messages
    # reads the database for messages where :id == message_id & :public_key == public_key are true
    # found_messages = @messages_ds.where(:id=>message_id).where(:key_id=>key_id).to_a  # outputs an array of messages
    db = DatabaseBox.new
    cb = CryptoBox.new
    found_messages = db.read_messages_by_id(message_id, key_id).to_a[0]  # since database ids are unique it should only output one dataset
    time = found_messages[:time]
    client =  = found_messages[:client]
    private = found_messages[:private]
    enc_sender = Base64.decode64(found_messages[:sender])
    enc_message = Base64.decode64(found_messages[:message])
    enc_attachment = Base64.decode64(found_messages[:attachment])
    nonce = Base64.decode64(found_messages[:nonce])

    sender = cb.decrypt_string(enc_sender, sender_key, nonce)
    message = cb.decrypt_string(enc_message, sender_key, nonce)
    attachment = cb.decrypt_string(enc_attachment, sender_key, nonce)
    {'time' => time, 'client' => client, 'private' => private, 'sender' => sender, 'message' => message, 'attachment'=>attachment}  # returns a hash of the decrypted message
  end

end

class CryptoBox
  # attr_writer :private_key, :public_key
  attr_accessor :private_key, :public_key
  def initialize
    database = DatabaseBox.new
    pub, priv = database.output_host_keypair
    if pub == nil and priv == nil
      pub_key, priv_key = generate_keypair
      database.register_key('host', '127.0.0.1', Base64.encode64(priv_key), Base64.encode64(pub_key))
      puts 'no host key present, generated new ones'
    else
      pub_key, priv_key = database.output_host_keypair
    end

    @public_key = pub_key
    @private_key = priv_key
  end

  def testing_generate_receiving_keypair
    db = DatabaseBox.new
    pub, priv = NaCl.crypto_box_keypair
    db.register_key('example description', 'horst', nil, Base64.encode64(pub))
  end

  def generate_keypair
    @public_key, @private_key = NaCl.crypto_box_keypair
  end

  def generate_nonce
    SecureRandom.random_bytes(NaCl::BOX_NONCE_LENGTH)
  end

  def encrypt_sting(string_to_encrypt, receiver_key, nonce)
    NaCl.crypto_box(string_to_encrypt, nonce, receiver_key, @private_key)
  end

  def decrypt_string(string_to_decrypt, sender_key, nonce)
    NaCl.crypto_box_open(string_to_decrypt, nonce, sender_key, @private_key)
  end

end
